import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  ApiChatMessage,
  AppSettings,
  StreamCallbacks,
  StreamResult,
  ToolCall,
} from '../model/ChatModels';
import { AVAILABLE_TOOLS, ToolDefinition } from './ToolExecutor';

const API_URL = 'https://api.deepseek.com/chat/completions';
const SYSTEM_PROMPT =
  'You are a helpful AI assistant running on a HarmonyOS phone. ' +
  'You can use tools when needed. Be concise and friendly.';

let activeHttpRequest: http.HttpRequest | null = null;

function arrayBufferToString(buffer: ArrayBuffer): string {
  const uint8 = new Uint8Array(buffer);
  let result = '';
  for (let i = 0; i < uint8.length; i++) {
    result += String.fromCharCode(uint8[i]);
  }
  return result;
}

function generateId(): string {
  return `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}

interface DeltaToolFunction {
  name?: string;
  arguments?: string;
}

interface DeltaToolCall {
  index?: number;
  id?: string;
  type?: string;
  function?: DeltaToolFunction;
}

interface StreamDelta {
  role?: string;
  content?: string;
  reasoning_content?: string;
  tool_calls?: DeltaToolCall[];
}

interface StreamChunkChoice {
  index: number;
  delta?: StreamDelta;
  finish_reason?: string | null;
}

interface StreamChunk {
  choices?: StreamChunkChoice[];
}

function mergeToolCallDelta(existing: ToolCall[], delta: DeltaToolCall[]): ToolCall[] {
  const merged: ToolCall[] = [];
  for (let i = 0; i < existing.length; i++) {
    merged.push({
      id: existing[i].id,
      type: existing[i].type,
      function: {
        name: existing[i].function.name,
        arguments: existing[i].function.arguments,
      },
    });
  }

  for (const d of delta) {
    const idx = d.index ?? 0;
    while (merged.length <= idx) {
      merged.push({
        id: '',
        type: 'function',
        function: { name: '', arguments: '' },
      });
    }
    if (d.id) {
      merged[idx].id = d.id;
    }
    if (d.type) {
      merged[idx].type = d.type;
    }
    if (d.function?.name) {
      merged[idx].function.name += d.function.name;
    }
    if (d.function?.arguments) {
      merged[idx].function.arguments += d.function.arguments;
    }
  }
  return merged;
}

function parseSSELine(line: string): StreamChunk | null {
  const trimmed = line.trim();
  if (!trimmed.startsWith('data:')) {
    return null;
  }
  const payload = trimmed.substring(5).trim();
  if (payload === '[DONE]') {
    return null;
  }
  try {
    return JSON.parse(payload) as StreamChunk;
  } catch (_e) {
    return null;
  }
}

function processStreamChunk(
  chunk: StreamChunk,
  state: StreamResult,
  callbacks: StreamCallbacks,
): boolean {
  if (!chunk.choices || chunk.choices.length === 0) {
    return false;
  }
  const choice = chunk.choices[0];
  let isDone = false;

  if (choice.delta?.reasoning_content) {
    state.reasoningContent += choice.delta.reasoning_content;
    callbacks.onReasoning(choice.delta.reasoning_content);
  }
  if (choice.delta?.content) {
    state.content += choice.delta.content;
    callbacks.onContent(choice.delta.content);
  }
  if (choice.delta?.tool_calls && choice.delta.tool_calls.length > 0) {
    state.toolCalls = mergeToolCallDelta(state.toolCalls, choice.delta.tool_calls);
    callbacks.onToolCallsUpdate(state.toolCalls);
  }
  if (choice.finish_reason) {
    state.finishReason = choice.finish_reason;
    isDone = true;
  }
  return isDone;
}

interface ThinkingConfig {
  type: string;
}

interface ChatRequestBody {
  model: string;
  messages: ApiChatMessage[];
  stream: boolean;
  tools: ToolDefinition[];
  thinking?: ThinkingConfig;
  reasoning_effort?: string;
}

function buildRequestBody(
  messages: ApiChatMessage[],
  settings: AppSettings,
): ChatRequestBody {
  const body: ChatRequestBody = {
    model: settings.model,
    messages: messages,
    stream: true,
    tools: AVAILABLE_TOOLS,
  };

  if (settings.thinkingEnabled) {
    body.thinking = { type: 'enabled' };
    body.reasoning_effort = settings.reasoningEffort;
  } else {
    body.thinking = { type: 'disabled' };
  }

  return body;
}

export function buildApiMessages(
  history: ApiChatMessage[],
  includeSystem: boolean = true,
): ApiChatMessage[] {
  const result: ApiChatMessage[] = [];
  if (includeSystem) {
    result.push({ role: 'system', content: SYSTEM_PROMPT });
  }
  for (const msg of history) {
    result.push(msg);
  }
  return result;
}

export function cancelActiveRequest(): void {
  if (activeHttpRequest) {
    try {
      activeHttpRequest.destroy();
    } catch (_e) {
      // ignore
    }
    activeHttpRequest = null;
  }
}

export function streamChatCompletion(
  messages: ApiChatMessage[],
  settings: AppSettings,
  callbacks: StreamCallbacks,
): Promise<StreamResult> {
  return new Promise((resolve, reject) => {
    if (!settings.apiKey || settings.apiKey.trim().length === 0) {
      const errMsg = '请先在设置中填写 API Key';
      callbacks.onError(errMsg);
      reject(new Error(errMsg));
      return;
    }

    cancelActiveRequest();

    const httpRequest = http.createHttp();
    activeHttpRequest = httpRequest;

    const state: StreamResult = {
      content: '',
      reasoningContent: '',
      toolCalls: [],
      finishReason: '',
    };

    let isDone = false;
    let receivedStreamData = false;
    let buffer = '';

    const finish = (): void => {
      if (!isDone) {
        isDone = true;
        callbacks.onDone(state.finishReason);
        activeHttpRequest = null;
        resolve(state);
      }
    };

    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      receivedStreamData = true;
      const text = arrayBufferToString(data);
      buffer += text;

      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';

      for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed === 'data: [DONE]' || trimmed === 'data:[DONE]') {
          finish();
          continue;
        }
        const chunk = parseSSELine(line);
        if (chunk) {
          const chunkDone = processStreamChunk(chunk, state, callbacks);
          if (chunkDone) {
            finish();
          }
        }
      }
    });

    httpRequest.on('dataEnd', () => {
      if (buffer.length > 0) {
        const chunk = parseSSELine(buffer);
        if (chunk) {
          processStreamChunk(chunk, state, callbacks);
        }
      }
      finish();
    });

    const requestBody = buildRequestBody(messages, settings);

    httpRequest.requestInStream(
      API_URL,
      {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${settings.apiKey}`,
          'Accept': 'text/event-stream',
        },
        extraData: JSON.stringify(requestBody),
        connectTimeout: 30000,
        readTimeout: 180000,
      },
      (err: BusinessError, _responseCode: number) => {
        if (err) {
          if (!isDone) {
            isDone = true;
            const errMsg = `网络请求失败: ${err.message}`;
            callbacks.onError(errMsg);
            activeHttpRequest = null;
            reject(new Error(errMsg));
          }
          return;
        }

        if (!receivedStreamData && !isDone) {
          finish();
        }
      },
    );
  });
}

export function createMessageId(): string {
  return generateId();
}
