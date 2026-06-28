import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { AppSettings, ChatMessage, TIME_TOOL, ToolCall, ToolDefinition } from '../model/ChatModels';

export interface StreamCallbacks { onReasoning: (text: string) => void; onContent: (text: string) => void; onTool: (name: string) => void; onDone: (toolCalls: ToolCall[]) => void; onError: (message: string) => void; }
interface ApiMessage { role: string; content: string; tool_calls?: ToolCall[]; tool_call_id?: string; name?: string; }
interface ThinkingControl { type: string; }
interface RequestBody { model: string; messages: ApiMessage[]; stream: boolean; tools: ToolDefinition[]; tool_choice: string; thinking: ThinkingControl; reasoning_effort?: string; }

export class DeepSeekService {
  private request: http.HttpRequest | null = null;
  private cancelled: boolean = false;

  stop(): void {
    this.cancelled = true;
    if (this.request !== null) try { this.request.destroy(); } catch (_) {}
  }

  async stream(settings: AppSettings, messages: ChatMessage[], callbacks: StreamCallbacks): Promise<void> {
    this.cancelled = false;
    const request: http.HttpRequest = http.createHttp();
    this.request = request;
    const toolCalls: ToolCall[] = [];
    let buffer: string = '';
    let errorSent: boolean = false;
    let done: boolean = false;
    const finish = (): void => {
      if (done) return;
      done = true;
      if (!this.cancelled && !errorSent) callbacks.onDone(toolCalls);
      try { request.destroy(); } catch (_) {}
      this.request = null;
    };
    const process = (data: string): void => {
      if (data === '[DONE]' || this.cancelled) return;
      try {
        const payload: ESObject = JSON.parse(data) as ESObject;
        const choices: ESObject = payload['choices'];
        if (!Array.isArray(choices) || choices.length === 0) return;
        const choice: ESObject = choices[0] as ESObject;
        const delta: ESObject = choice['delta'] as ESObject;
        if (delta === undefined || delta === null) return;
        const reasoning: ESObject = delta['reasoning_content'];
        if (typeof reasoning === 'string' && (reasoning as string).length > 0) callbacks.onReasoning(reasoning as string);
        const content: ESObject = delta['content'];
        if (typeof content === 'string' && (content as string).length > 0) callbacks.onContent(content as string);
        const rawCalls: ESObject = delta['tool_calls'];
        if (!Array.isArray(rawCalls)) return;
        for (let i = 0; i < rawCalls.length; i++) {
          const raw: ESObject = rawCalls[i] as ESObject;
          const indexRaw: ESObject = raw['index'];
          const index: number = typeof indexRaw === 'number' ? indexRaw as number : i;
          while (toolCalls.length <= index) toolCalls.push({ id: '', type: 'function', function: { name: '', arguments: '' } });
          const call: ToolCall = toolCalls[index];
          const id: ESObject = raw['id'];
          if (typeof id === 'string') call.id = id as string;
          const functionData: ESObject = raw['function'] as ESObject;
          if (functionData === undefined || functionData === null) continue;
          const name: ESObject = functionData['name'];
          if (typeof name === 'string' && (name as string).length > 0) { call.function.name += name as string; callbacks.onTool(call.function.name); }
          const argumentsText: ESObject = functionData['arguments'];
          if (typeof argumentsText === 'string') call.function.arguments += argumentsText as string;
        }
      } catch (_) {}
    };
    const consume = (): void => {
      let boundary: number = buffer.indexOf('\n\n');
      while (boundary >= 0) {
        const event: string = buffer.substring(0, boundary);
        buffer = buffer.substring(boundary + 2);
        const lines: string[] = event.split('\n');
        for (let i = 0; i < lines.length; i++) {
          const line: string = lines[i].trim();
          if (line.startsWith('data:')) process(line.substring(5).trim());
        }
        boundary = buffer.indexOf('\n\n');
      }
    };
    request.on('dataReceive', (chunk: ArrayBuffer) => {
      if (this.cancelled) return;
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      buffer += decoder.decodeToString(new Uint8Array(chunk));
      consume();
    });
    request.on('dataEnd', () => { if (buffer.trim().length > 0) { buffer += '\n\n'; consume(); } finish(); });

    const apiMessages: ApiMessage[] = [];
    apiMessages.push({ role: 'system', content: 'You are a helpful assistant. Use the phone system time tool when the user asks for current time.' });
    for (let i = 0; i < messages.length; i++) {
      const source: ChatMessage = messages[i];
      const item: ApiMessage = { role: source.role, content: source.content };
      if (source.toolCalls !== undefined && source.toolCalls.length > 0) item.tool_calls = source.toolCalls;
      if (source.toolCallId !== undefined) item.tool_call_id = source.toolCallId;
      if (source.name !== undefined) item.name = source.name;
      apiMessages.push(item);
    }
    const thinking: ThinkingControl = { type: settings.thinkingEnabled ? 'enabled' : 'disabled' };
    const body: RequestBody = { model: settings.model, messages: apiMessages, stream: true, tools: [TIME_TOOL], tool_choice: 'auto', thinking: thinking };
    if (settings.thinkingEnabled) body.reasoning_effort = settings.reasoningEffort;
    const headers: Record<string, string> = { 'Content-Type': 'application/json', 'Accept': 'text/event-stream', 'Authorization': 'Bearer ' + settings.apiKey };
    const options: http.HttpRequestOptions = { method: http.RequestMethod.POST, header: headers, extraData: JSON.stringify(body), connectTimeout: 30000, readTimeout: 120000 };
    try { await request.requestInStream('https://api.deepseek.com/chat/completions', options); }
    catch (error) {
      if (!this.cancelled) { errorSent = true; callbacks.onError(error instanceof Error ? error.message : '请求未能发出'); }
      finish();
    }
  }
}
