import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  API_BASE_URL,
  CHAT_COMPLETIONS_PATH,
  DEEPSEEK_SYSTEM_PROMPT
} from '../common/constants';
import {
  ApiMessage,
  ToolDefinition,
  ToolCallInfo,
  ToolCall
} from '../models/ChatModels';
import { ToolService } from './ToolService';

const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });

export class DeepSeekService {
  private apiKey: string;

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  private buildHeaders(): object {
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.apiKey}`,
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    };
  }

  private buildRequestBody(
    model: string,
    messages: ApiMessage[],
    thinkingEnabled: boolean,
    reasoningEffort: string,
    tools: ToolDefinition[]
  ): string {
    const body: Record<string, Object> = {};
    body['model'] = model;
    body['messages'] = messages;
    body['stream'] = true;
    if (thinkingEnabled) {
      body['thinking'] = { type: 'enabled' };
      body['reasoning_effort'] = reasoningEffort;
    }
    if (tools.length > 0) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }
    return JSON.stringify(body);
  }

  streamChat(
    model: string,
    messages: ApiMessage[],
    thinkingEnabled: boolean,
    reasoningEffort: string,
    onThinking: (text: string) => void,
    onContent: (text: string) => void,
    onToolCalls: (toolCalls: ToolCallInfo[]) => void,
    onDone: (finishReason: string) => void,
    onError: (error: string) => void,
    onComplete: () => void
  ): void {
    const tools = ToolService.getToolDefinitions();
    const requestBody = this.buildRequestBody(model, messages, thinkingEnabled, reasoningEffort, tools);
    const url = API_BASE_URL + CHAT_COMPLETIONS_PATH;

    const httpRequest = http.createHttp();
    httpRequest.requestInStream(
      url,
      {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(),
        extraData: requestBody,
        connectTimeout: 30000,
        readTimeout: 120000
      },
      (err: Error, data: http.IncomingResponse) => {
        if (err) {
          onError(`Connection error: ${err.message}`);
          onComplete();
          return;
        }

        let buffer = '';
        let accumulatedToolCalls: Map<number, ToolCallInfo> = new Map();

        data.on('dataReceive', (chunk: ArrayBuffer) => {
          const text = decoder.decodeToString(chunk, { flush: false });
          buffer += text;

          // Check for plain JSON error response (non-SSE)
          if (buffer.startsWith('{') || buffer.startsWith('[')) {
            try {
              const errParsed = JSON.parse(buffer);
              const errObj = errParsed.error;
              if (errObj) {
                const errMsg = errObj.message || JSON.stringify(errObj);
                onError(`API Error: ${errMsg}`);
                return;
              }
            } catch (e) {
              // Not valid JSON, continue with SSE parsing
            }
          }

          const parts = buffer.split('\n');
          buffer = parts.pop() || '';

          for (const part of parts) {
            const line = part.trim();
            if (!line || line.startsWith(':')) {
              continue;
            }
            if (!line.startsWith('data: ')) {
              continue;
            }

            const jsonData = line.slice(6).trim();
            if (jsonData === '[DONE]') {
              continue;
            }

            try {
              const parsed = JSON.parse(jsonData);
              // Check for API error in SSE response
              const parsedErr = parsed.error;
              if (parsedErr) {
                const errMsg = parsedErr.message || JSON.stringify(parsedErr);
                onError(`API Error: ${errMsg}`);
                return;
              }
              const choices = parsed.choices;
              const choice = (choices && choices.length > 0) ? choices[0] : null;
              if (!choice) {
                continue;
              }

              const delta = choice.delta || {};

              const thinkingVal = delta.thinking;
              if (thinkingVal !== undefined && thinkingVal !== null) {
                onThinking(String(thinkingVal));
              }

              const contentVal = delta.content;
              if (contentVal !== undefined && contentVal !== null) {
                onContent(String(contentVal));
              }

              const toolCallsDelta = delta.tool_calls;
              if (toolCallsDelta !== undefined && toolCallsDelta !== null) {
                const toolCallsArr = toolCallsDelta as Array<{
                  index?: number;
                  id?: string;
                  type?: string;
                  function?: {
                    name?: string;
                    arguments?: string;
                  };
                }>;
                for (const tc of toolCallsArr) {
                  const idx = tc.index !== undefined ? tc.index : 0;
                  if (!accumulatedToolCalls.has(idx)) {
                    accumulatedToolCalls.set(idx, {
                      id: tc.id || '',
                      type: tc.type || 'function',
                      functionName: '',
                      functionArguments: ''
                    });
                  }
                  const existing = accumulatedToolCalls.get(idx) as ToolCallInfo;
                  if (tc.id) {
                    existing.id = tc.id;
                  }
                  if (tc.type) {
                    existing.type = tc.type;
                  }
                  if (tc.function) {
                    if (tc.function.name) {
                      existing.functionName += tc.function.name;
                    }
                    if (tc.function.arguments) {
                      existing.functionArguments += tc.function.arguments;
                    }
                  }
                }
              }

              const finishReason = choice.finish_reason;
              if (finishReason) {
                if (finishReason === 'tool_calls' && accumulatedToolCalls.size > 0) {
                  const toolCallList: ToolCallInfo[] = [];
                  for (const tc of accumulatedToolCalls.values()) {
                    toolCallList.push({
                      id: tc.id,
                      type: tc.type,
                      functionName: tc.functionName,
                      functionArguments: tc.functionArguments
                    });
                  }
                  onToolCalls(toolCallList);
                }
                onDone(String(finishReason));
              }
            } catch (e) {
              // skip parse errors for partial lines
            }
          }
        });

        data.on('dataEnd', () => {
          httpRequest.destroy();
          onComplete();
        });

        data.on('dataReceiveError', (err: Error) => {
          onError(`Stream error: ${err.message}`);
          httpRequest.destroy();
          onComplete();
        });
      }
    );
  }
}
