import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  ChatMessage, ToolCall, ApiMessageItem, ChatRequestBody, ThinkingConfig,
  ToolDefinitionSchema, ToolFunctionSchema
} from '../model/ChatModel';

const API_URL = 'https://api.deepseek.com/chat/completions';

export interface StreamCallbacks {
  onThinking: (text: string) => void;
  onContent: (text: string) => void;
  onToolCall: (toolCalls: Array<ToolCall>) => void;
  onDone: (finishReason: string) => void;
  onError: (error: string) => void;
}

export function buildToolsJson(tools: Array<ToolDefinitionSchema>): string {
  let parts: Array<string> = [];
  for (let i = 0; i < tools.length; i++) {
    let t = tools[i];
    let funcJson = '{"name":"' + t.function.name + '","description":"' +
      t.function.description + '","parameters":' + t.function.parameters + '}';
    parts.push('{"type":"' + t.type + '","function":' + funcJson + '}');
  }
  return '[' + parts.join(',') + ']';
}

export class DeepSeekService {
  private httpRequest: http.HttpRequest | null = null;

  private processSSELine(line: string, callbacks: StreamCallbacks): boolean {
    let trimmed: string = line.trim();
    if (trimmed.length === 0) {
      return false;
    }
    if (!trimmed.startsWith('data: ')) {
      return false;
    }
    let jsonStr: string = trimmed.substring(6);
    if (jsonStr === '[DONE]') {
      callbacks.onDone('stop');
      return true;
    }
    try {
      let parsed: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>;
      let choices: Array<Record<string, Object>> = parsed['choices'] as Array<Record<string, Object>>;
      if (choices && choices.length > 0) {
        let choice: Record<string, Object> = choices[0];
        let delta: Record<string, Object> = choice['delta'] as Record<string, Object>;
        let finishReason: string = choice['finish_reason'] as string;

        if (delta) {
          let reasoningContent: string = delta['reasoning_content'] as string;
          let content: string = delta['content'] as string;
          let toolCallsRaw: Array<Record<string, Object>> =
            delta['tool_calls'] as Array<Record<string, Object>>;

          if (reasoningContent) {
            callbacks.onThinking(reasoningContent);
          }
          if (content) {
            callbacks.onContent(content);
          }
          if (toolCallsRaw) {
            let toolCalls: Array<ToolCall> = [];
            for (let k = 0; k < toolCallsRaw.length; k++) {
              let tc = toolCallsRaw[k];
              let func: Record<string, string> = tc['function'] as Record<string, string>;
              let toolCall = new ToolCall();
              toolCall.id = (tc['id'] as string) || '';
              toolCall.type = (tc['type'] as string) || 'function';
              toolCall.name = func ? (func['name'] || '') : '';
              toolCall.arguments = func ? (func['arguments'] || '') : '';
              toolCalls.push(toolCall);
            }
            callbacks.onToolCall(toolCalls);
          }
        }

        if (finishReason) {
          callbacks.onDone(finishReason);
          return true;
        }
      }
    } catch (e) {
      // skip malformed SSE lines
    }
    return false;
  }

  private processSSEText(text: string, callbacks: StreamCallbacks): boolean {
    let lines: Array<string> = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      let done = this.processSSELine(lines[i], callbacks);
      if (done) {
        return true;
      }
    }
    return false;
  }

  async streamChat(
    apiKey: string,
    model: string,
    messages: Array<ChatMessage>,
    thinkingEnabled: boolean,
    reasoningEffort: string,
    tools: Array<ToolDefinitionSchema> | undefined,
    callbacks: StreamCallbacks
  ): Promise<void> {
    this.httpRequest = http.createHttp();

    let apiMessages: Array<ApiMessageItem> = [];
    for (let i = 0; i < messages.length; i++) {
      let m = messages[i];
      let apiMsg = new ApiMessageItem();
      apiMsg.role = m.role;
      apiMsg.content = m.content;
      if (m.role === 'tool' && m.toolCallId) {
        apiMsg.tool_call_id = m.toolCallId;
      }
      if (m.toolCalls && m.toolCalls.length > 0) {
        let tcs: Array<string> = [];
        for (let j = 0; j < m.toolCalls.length; j++) {
          let tc = m.toolCalls[j];
          tcs.push('{"id":"' + tc.id + '","type":"' + tc.type +
            '","function":{"name":"' + tc.name + '","arguments":' +
            JSON.stringify(tc.arguments) + '}}');
        }
        apiMsg.tool_calls = '[' + tcs.join(',') + ']';
      }
      apiMessages.push(apiMsg);
    }

    let body = new ChatRequestBody();
    body.model = model;
    body.messages = apiMessages;
    if (thinkingEnabled) {
      let thinking = new ThinkingConfig();
      thinking.type = 'enabled';
      body.thinking = thinking;
      body.reasoning_effort = reasoningEffort;
    }
    if (tools && tools.length > 0) {
      body.tools = buildToolsJson(tools);
    }
    let bodyJson: string = body.toJson();

    let reqOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + apiKey
      },
      extraData: bodyJson,
      connectTimeout: 30000,
      readTimeout: 300000,
      usingCache: false
    };

    let buffer: string = '';
    let isDone: boolean = false;
    let receivedViaEvent: boolean = false;

    let wrappedCallbacks: StreamCallbacks = {
      onThinking: (text: string) => {
        receivedViaEvent = true;
        callbacks.onThinking(text);
      },
      onContent: (text: string) => {
        receivedViaEvent = true;
        callbacks.onContent(text);
      },
      onToolCall: (toolCalls: Array<ToolCall>) => {
        receivedViaEvent = true;
        callbacks.onToolCall(toolCalls);
      },
      onDone: (finishReason: string) => {
        isDone = true;
        callbacks.onDone(finishReason);
      },
      onError: (error: string) => {
        callbacks.onError(error);
      }
    };

    this.httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      let text: string;
      try {
        let decoder = util.TextDecoder.create('utf-8');
        text = decoder.decodeWithStream(new Uint8Array(data));
      } catch (e) {
        return;
      }
      buffer += text;

      let lines: Array<string> = buffer.split('\n');
      let lastLine: string | undefined = lines.pop();
      buffer = lastLine !== undefined ? lastLine : '';

      for (let i = 0; i < lines.length; i++) {
        if (isDone) {
          break;
        }
        this.processSSELine(lines[i], wrappedCallbacks);
      }
    });

    this.httpRequest.on('dataEnd', () => {
      if (!isDone && buffer.length > 0) {
        this.processSSELine(buffer, wrappedCallbacks);
        buffer = '';
      }
      if (!isDone) {
        isDone = true;
        callbacks.onDone('stop');
      }
    });

    try {
      let response: http.HttpResponse = await this.httpRequest.request(API_URL, reqOptions);

      if (!isDone && !receivedViaEvent && response.result) {
        let responseText: string = response.result as string;
        if (responseText.length > 0) {
          this.processSSEText(responseText, callbacks);
        }
        if (!isDone) {
          isDone = true;
          callbacks.onDone('stop');
        }
      }
    } catch (err) {
      if (!isDone) {
        let error = err as BusinessError;
        callbacks.onError(error.message || 'Network error');
      }
    }

    if (this.httpRequest) {
      this.httpRequest.destroy();
      this.httpRequest = null;
    }
  }

  cancel(): void {
    if (this.httpRequest) {
      this.httpRequest.destroy();
      this.httpRequest = null;
    }
  }
}

interface BusinessError {
  code: number;
  message: string;
}
