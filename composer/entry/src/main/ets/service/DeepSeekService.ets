import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
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
  const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
  return decoder.decodeToString(new Uint8Array(buffer), { stream: false });
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
  message?: StreamDelta;
  finish_reason?: string | null;
}

interface StreamChunk {
  error?: ApiErrorBody;
  choices?: StreamChunkChoice[];
}

interface ApiErrorBody {
  message?: string;
}

interface ApiErrorResponse {
  error?: ApiErrorBody;
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
): void {
  if (chunk.error?.message) {
    throw new Error(chunk.error.message);
  }
  if (!chunk.choices || chunk.choices.length === 0) {
    return;
  }
  const choice = chunk.choices[0];
  const delta = choice.delta ?? choice.message;

  if (delta?.reasoning_content) {
    state.reasoningContent += delta.reasoning_content;
    callbacks.onReasoning(delta.reasoning_content);
  }
  if (delta?.content) {
    state.content += delta.content;
    callbacks.onContent(delta.content);
  }
  if (delta?.tool_calls && delta.tool_calls.length > 0) {
    state.toolCalls = mergeToolCallDelta(state.toolCalls, delta.tool_calls);
    callbacks.onToolCallsUpdate(state.toolCalls);
  }
  if (choice.finish_reason) {
    state.finishReason = choice.finish_reason;
  }
}

function processSSEText(
  text: string,
  buffer: string,
  state: StreamResult,
  callbacks: StreamCallbacks,
): string {
  let pending = buffer + text;
  const lines = pending.split('\n');
  const remaining = lines.pop() ?? '';

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed === 'data: [DONE]' || trimmed === 'data:[DONE]') {
      continue;
    }
    const chunk = parseSSELine(line);
    if (chunk) {
      processStreamChunk(chunk, state, callbacks);
    }
  }
  return remaining;
}

function parseApiErrorBody(body: string): string {
  try {
    const parsed = JSON.parse(body) as ApiErrorResponse;
    if (parsed.error?.message) {
      return parsed.error.message;
    }
  } catch (_e) {
    // ignore
  }
  if (body.length > 200) {
    return body.substring(0, 200);
  }
  return body;
}

function getResponseBodyString(result: string | Object | ArrayBuffer): string {
  if (typeof result === 'string') {
    return result;
  }
  if (result instanceof ArrayBuffer) {
    return arrayBufferToString(result);
  }
  return JSON.stringify(result);
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

function buildHttpOptions(requestBody: ChatRequestBody, apiKey: string): http.HttpRequestOptions {
  return {
    method: http.RequestMethod.POST,
    header: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
      'Accept': 'text/event-stream',
    },
    extraData: JSON.stringify(requestBody),
    connectTimeout: 30000,
    readTimeout: 180000,
  };
}

function attachStreamListeners(
  httpRequest: http.HttpRequest,
  state: StreamResult,
  callbacks: StreamCallbacks,
  receivedStreamData: StreamFlag,
  lineBuffer: StreamBuffer,
  fail: (message: string) => void,
): void {
  httpRequest.on('dataReceive', (data: ArrayBuffer) => {
    receivedStreamData.value = true;
    try {
      lineBuffer.text = processSSEText(
        arrayBufferToString(data),
        lineBuffer.text,
        state,
        callbacks,
      );
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : '流式解析失败';
      fail(errMsg);
    }
  });

  httpRequest.on('dataEnd', () => {
    if (lineBuffer.text.length > 0) {
      try {
        lineBuffer.text = processSSEText('\n', lineBuffer.text, state, callbacks);
      } catch (e) {
        const errMsg = e instanceof Error ? e.message : '流式解析失败';
        fail(errMsg);
      }
    }
  });
}

class StreamFlag {
  value: boolean = false;
}

class StreamBuffer {
  text: string = '';
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

    const state: StreamResult = {
      content: '',
      reasoningContent: '',
      toolCalls: [],
      finishReason: '',
    };

    let isDone = false;
    const receivedStreamData = new StreamFlag();
    const lineBuffer = new StreamBuffer();
    const requestBody = buildRequestBody(messages, settings);
    const options = buildHttpOptions(requestBody, settings.apiKey);

    const finish = (httpRequest: http.HttpRequest): void => {
      if (!isDone) {
        isDone = true;
        callbacks.onDone(state.finishReason);
        try {
          httpRequest.destroy();
        } catch (_e) {
          // ignore
        }
        if (activeHttpRequest === httpRequest) {
          activeHttpRequest = null;
        }
        resolve(state);
      }
    };

    const fail = (httpRequest: http.HttpRequest, message: string): void => {
      if (!isDone) {
        isDone = true;
        callbacks.onError(message);
        try {
          httpRequest.destroy();
        } catch (_e) {
          // ignore
        }
        if (activeHttpRequest === httpRequest) {
          activeHttpRequest = null;
        }
        reject(new Error(message));
      }
    };

    const httpRequest = http.createHttp();
    activeHttpRequest = httpRequest;
    attachStreamListeners(httpRequest, state, callbacks, receivedStreamData, lineBuffer,
      (message: string) => {
        fail(httpRequest, message);
      });

    httpRequest.request(
      API_URL,
      options,
      (err: BusinessError, resp: http.HttpResponse) => {
        if (isDone) {
          return;
        }
        if (err) {
          fail(httpRequest, `网络请求失败: ${err.message}`);
          return;
        }
        if (resp.responseCode >= 400) {
          const body = resp.result !== undefined ? getResponseBodyString(resp.result) : '';
          fail(httpRequest, `HTTP ${resp.responseCode}: ${parseApiErrorBody(body)}`);
          return;
        }
        if (!receivedStreamData.value && resp.result !== undefined) {
          try {
            const body = getResponseBodyString(resp.result);
            lineBuffer.text = processSSEText(body, lineBuffer.text, state, callbacks);
          } catch (e) {
            const errMsg = e instanceof Error ? e.message : '响应解析失败';
            fail(httpRequest, errMsg);
            return;
          }
        }
        finish(httpRequest);
      },
    );
  });
}

export function createMessageId(): string {
  return generateId();
}
