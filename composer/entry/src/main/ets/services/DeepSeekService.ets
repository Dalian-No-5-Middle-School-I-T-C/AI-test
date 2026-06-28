import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ChatMessage, ToolCallInfo } from '../models/ChatModels';
import { ToolService, ToolDefinition } from './ToolService';

export interface StreamCallbacks {
  onReasoning: (text: string) => void;
  onContent: (text: string) => void;
  onToolCall: (toolCall: ToolCallInfo) => void;
  onToolResult: (toolCall: ToolCallInfo) => void;
  onComplete: (finalContent: string, finalReasoning: string, toolCalls: ToolCallInfo[]) => void;
  onError: (error: string) => void;
}

interface AccumulatedToolCall {
  id: string;
  type: string;
  functionName: string;
  functionArgs: string;
}

interface ThinkingConfig {
  type: string;
}

interface ApiMessageContent {
  role: string;
  content: string;
  tool_call_id?: string;
  tool_calls?: ApiToolCall[];
}

interface ApiToolCall {
  id: string;
  type: string;
  function: ApiToolCallFunction;
}

interface ApiToolCallFunction {
  name: string;
  arguments: string;
}

interface ChatRequest {
  model: string;
  messages: ApiMessageContent[];
  stream: boolean;
  tools: ToolDefinition[];
  thinking: ThinkingConfig;
  reasoning_effort?: string;
}

export class DeepSeekService {
  private httpRequest: http.HttpRequest | null = null;
  private textDecoder: util.TextDecoder;
  private streamBuffer: string = '';
  private fullReasoning: string = '';
  private fullContent: string = '';
  private accumulatedToolCalls: Map<number, AccumulatedToolCall> = new Map();
  private callbacks: StreamCallbacks | null = null;
  private isCancelled: boolean = false;

  constructor() {
    this.textDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
  }

  cancelStream(): void {
    this.isCancelled = true;
    if (this.httpRequest) {
      try {
        this.httpRequest.off('headerReceive');
        this.httpRequest.off('dataReceive');
        this.httpRequest.off('dataEnd');
        this.httpRequest.destroy();
      } catch (e) {
        // ignore
      }
      this.httpRequest = null;
    }
  }

  async streamChat(
    apiKey: string,
    model: string,
    thinkingEnabled: boolean,
    reasoningEffort: string,
    messages: ChatMessage[],
    callbacks: StreamCallbacks
  ): Promise<void> {
    this.isCancelled = false;
    this.streamBuffer = '';
    this.fullReasoning = '';
    this.fullContent = '';
    this.accumulatedToolCalls = new Map();
    this.callbacks = callbacks;

    let thinkingCfg: ThinkingConfig = {
      type: thinkingEnabled ? 'enabled' : 'disabled'
    };
    let apiMessages = DeepSeekService.buildMessages(messages);
    let tools = ToolService.getToolDefinitions();
    let body: ChatRequest = {
      model: model,
      messages: apiMessages,
      stream: true,
      tools: tools,
      thinking: thinkingCfg
    };
    if (thinkingEnabled) {
      body.reasoning_effort = reasoningEffort;
    }

    this.httpRequest = http.createHttp();

    this.httpRequest.on('headerReceive', (headers: Object) => {
      if (this.isCancelled) {
        return;
      }
    });

    this.httpRequest.on('dataReceive', (chunk: ArrayBuffer) => {
      if (this.isCancelled) {
        return;
      }
      this.processChunk(chunk);
    });

    this.httpRequest.on('dataEnd', () => {
      if (this.isCancelled) {
        return;
      }
      this.finalizeStream();
    });

    try {
      this.httpRequest.requestInStream(
        'https://api.deepseek.com/chat/completions',
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`
          },
          extraData: JSON.stringify(body) as string,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 30000,
          readTimeout: 300000
        },
        (err: Object, data: number) => {
          if (err) {
            if (!this.isCancelled && this.callbacks) {
              let errObj = err as Record<string, Object>;
              let msg = errObj['message'] as string;
              this.callbacks.onError('连接失败: ' + (msg ? msg : '未知错误'));
            }
            this.cleanup();
          }
        }
      );
    } catch (err) {
      if (!this.isCancelled && this.callbacks) {
        this.callbacks.onError('请求失败，请检查 API Key 和网络连接');
      }
      this.cleanup();
    }
  }

  private processChunk(data: ArrayBuffer): void {
    try {
      let text: string;
      if (typeof data === 'string') {
        text = data as string;
      } else {
        text = this.textDecoder.decodeWithStream(new Uint8Array(data), { stream: true });
      }
      this.streamBuffer += text;
      this.parseSSE();
    } catch (e) {
      try {
        let fallback: string = (data as Object).toString();
        if (fallback !== '[object ArrayBuffer]') {
          this.streamBuffer += fallback;
          this.parseSSE();
        }
      } catch (e2) {
        // skip
      }
    }
  }

  private parseSSE(): void {
    let normalized = this.streamBuffer.replace(/\r\n/g, '\n');
    let events = normalized.split('\n\n');
    this.streamBuffer = events.pop() || '';

    for (let i = 0; i < events.length; i++) {
      let event = events[i];
      if (event.trim().length === 0) {
        continue;
      }

      let lines = event.split('\n');
      let dataStr = '';

      for (let j = 0; j < lines.length; j++) {
        let line = lines[j];
        if (line.startsWith('data: ')) {
          dataStr += line.substring(6);
        } else if (line.startsWith('data:')) {
          dataStr += line.substring(5);
        }
      }

      if (dataStr.trim() === '') {
        continue;
      }

      if (dataStr.trim() === '[DONE]') {
        continue;
      }

      this.processDelta(dataStr);
    }
  }

  private processDelta(dataStr: string): void {
    try {
      let parsed = JSON.parse(dataStr) as Record<string, Object>;

      let error = parsed['error'] as Record<string, Object>;
      if (error) {
        let msg = error['message'] as string;
        if (msg && this.callbacks) {
          this.callbacks.onError(msg);
          this.cancelStream();
        }
        return;
      }

      let choices = parsed['choices'] as Object[];

      if (!choices || choices.length === 0) {
        return;
      }

      let choice = choices[0] as Record<string, Object>;
      let delta = choice['delta'] as Record<string, Object>;

      if (!delta) {
        return;
      }

      let reasoningContent = delta['reasoning_content'] as string;
      if (reasoningContent && reasoningContent.length > 0) {
        this.fullReasoning += reasoningContent;
        if (this.callbacks) {
          this.callbacks.onReasoning(reasoningContent);
        }
      }

      let content = delta['content'] as string;
      if (content && content.length > 0) {
        this.fullContent += content;
        if (this.callbacks) {
          this.callbacks.onContent(content);
        }
      }

      let toolCalls = delta['tool_calls'] as Object[];
      if (toolCalls && toolCalls.length > 0) {
        this.processToolCallsDelta(toolCalls);
      }
    } catch (e) {
      // Skip invalid JSON deltas
    }
  }

  private processToolCallsDelta(toolCalls: Object[]): void {
    for (let i = 0; i < toolCalls.length; i++) {
      let tc = toolCalls[i] as Record<string, Object>;
      let index: number = (tc['index'] as number) ?? 0;

      let existing = this.accumulatedToolCalls.get(index);
      if (!existing) {
        existing = {
          id: '',
          type: 'function',
          functionName: '',
          functionArgs: ''
        };
        this.accumulatedToolCalls.set(index, existing);
      }

      let id = tc['id'] as string;
      if (id && id.length > 0) {
        existing.id = id;
      }

      let type = tc['type'] as string;
      if (type && type.length > 0) {
        existing.type = type;
      }

      let func = tc['function'] as Record<string, Object>;
      if (func) {
        let name = func['name'] as string;
        if (name && name.length > 0) {
          existing.functionName = name;
        }
        let args = func['arguments'] as string;
        if (args && args.length > 0) {
          existing.functionArgs += args;
        }
      }
    }
  }

  private finalizeStream(): void {
    if (this.streamBuffer.trim().length > 0) {
      let remaining = this.streamBuffer.replace(/\r\n/g, '\n').trim();
      if (remaining.startsWith('data:')) {
        remaining = remaining.substring(5).trim();
      }
      if (remaining.startsWith('data: ')) {
        remaining = remaining.substring(6).trim();
      }
      if (remaining !== '[DONE]' && remaining.length > 0) {
        this.processDelta(remaining);
      }
    }

    let toolCalls: ToolCallInfo[] = [];
    this.accumulatedToolCalls.forEach((acc: AccumulatedToolCall) => {
      if (acc.id.length > 0) {
        toolCalls.push({
          id: acc.id,
          type: acc.type,
          functionName: acc.functionName,
          functionArgs: acc.functionArgs,
          result: ''
        });
      }
    });

    let cb = this.callbacks;
    let finalContent = this.fullContent;
    let finalReasoning = this.fullReasoning;

    if (this.httpRequest) {
      try {
        this.httpRequest.off('headerReceive');
        this.httpRequest.off('dataReceive');
        this.httpRequest.off('dataEnd');
      } catch (e) {
        // ignore
      }
      this.httpRequest = null;
    }
    this.callbacks = null;

    if (cb) {
      cb.onComplete(finalContent, finalReasoning, toolCalls);
    }
  }

  private cleanup(): void {
    if (this.httpRequest) {
      try {
        this.httpRequest.off('headerReceive');
        this.httpRequest.off('dataReceive');
        this.httpRequest.off('dataEnd');
      } catch (e) {
        // ignore
      }
      this.httpRequest = null;
    }
    this.callbacks = null;
  }

  private static buildMessages(messages: ChatMessage[]): ApiMessageContent[] {
    let result: ApiMessageContent[] = [];
    for (let i = 0; i < messages.length; i++) {
      let msg = messages[i];
      let item: ApiMessageContent = {
        role: msg.role,
        content: msg.content
      };

      if (msg.toolCallId && msg.toolCallId.length > 0) {
        item.tool_call_id = msg.toolCallId;
      }

      if (msg.toolCalls && msg.toolCalls.length > 0 && msg.role === 'assistant') {
        let calls: ApiToolCall[] = [];
        for (let j = 0; j < msg.toolCalls.length; j++) {
          let tc = msg.toolCalls[j];
          let func: ApiToolCallFunction = {
            name: tc.functionName,
            arguments: tc.functionArgs
          };
          calls.push({
            id: tc.id,
            type: tc.type,
            function: func
          });
        }
        item.tool_calls = calls;
      }

      result.push(item);
    }
    return result;
  }
}
