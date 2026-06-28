import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  API_BASE_URL,
  CHAT_COMPLETIONS_PATH
} from '../common/constants';
import {
  ApiMessage,
  ToolDefinition,
  ToolCallInfo,
  SSEResponse,
  SSEChoice,
  DeltaContent,
  ToolCallDeltaItem
} from '../models/ChatModels';
import { ToolService } from './ToolService';

const TEXT_DECODER = util.TextDecoder.create('utf-8', { ignoreBOM: true });

interface ThinkingConfig {
  type: string;
}

interface RequestBody {
  model: string;
  messages: ApiMessage[];
  stream: boolean;
  thinking?: ThinkingConfig;
  reasoning_effort?: string;
  tools?: ToolDefinition[];
  tool_choice?: string;
}

export class DeepSeekService {
  private apiKey: string;

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  private buildHeaders(): Record<string, string> {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + this.apiKey,
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
    const body: RequestBody = {
      model: model,
      messages: messages,
      stream: true
    };
    if (thinkingEnabled) {
      const thinkingObj: ThinkingConfig = { type: 'enabled' };
      body.thinking = thinkingObj;
      body.reasoning_effort = reasoningEffort;
    }
    if (tools.length > 0) {
      body.tools = tools;
      body.tool_choice = 'auto';
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
    const tools: ToolDefinition[] = ToolService.getToolDefinitions();
    const requestBody: string = this.buildRequestBody(model, messages, thinkingEnabled, reasoningEffort, tools);
    const url: string = API_BASE_URL + CHAT_COMPLETIONS_PATH;

    const httpRequest = http.createHttp();

    let buffer: string = '';
    const accumulatedToolCalls: Map<number, ToolCallInfo> = new Map();

    httpRequest.on('dataReceive', (chunk: ArrayBuffer) => {
      const uint8: Uint8Array = new Uint8Array(chunk);
      const text: string = TEXT_DECODER.decodeToString(uint8);
      buffer += text;

      if (buffer.startsWith('{') || buffer.startsWith('[')) {
        try {
          const errParsed: SSEResponse = JSON.parse(buffer) as SSEResponse;
          if (errParsed.error) {
            const errMsg: string = errParsed.error.message || JSON.stringify(errParsed.error);
            onError('API Error: ' + errMsg);
            return;
          }
        } catch (e) {
          // Not valid JSON, continue with SSE parsing
        }
      }

      const parts: string[] = buffer.split('\n');
      buffer = parts.pop() || '';

      for (const part of parts) {
        const line: string = part.trim();
        if (!line || line.startsWith(':')) {
          continue;
        }
        if (!line.startsWith('data: ')) {
          continue;
        }

        const jsonData: string = line.slice(6).trim();
        if (jsonData === '[DONE]') {
          continue;
        }

        try {
          const parsed: SSEResponse = JSON.parse(jsonData) as SSEResponse;
          if (parsed.error) {
            const errMsg: string = parsed.error.message || JSON.stringify(parsed.error);
            onError('API Error: ' + errMsg);
            return;
          }
          const choices: SSEChoice[] | undefined = parsed.choices;
          const choice: SSEChoice | undefined = (choices && choices.length > 0) ? choices[0] : undefined;
          if (!choice) {
            continue;
          }

          const delta: DeltaContent | undefined = choice.delta;

          if (delta) {
            const thinkingVal: string | null | undefined = delta.thinking;
            if (thinkingVal !== undefined && thinkingVal !== null) {
              onThinking(thinkingVal);
            }

            const contentVal: string | null | undefined = delta.content;
            if (contentVal !== undefined && contentVal !== null) {
              onContent(contentVal);
            }

            const toolCallsDelta: ToolCallDeltaItem[] | undefined = delta.tool_calls;
            if (toolCallsDelta !== undefined) {
              for (const tc of toolCallsDelta) {
                const idx: number = tc.index !== undefined ? tc.index : 0;
                if (!accumulatedToolCalls.has(idx)) {
                  const newTc: ToolCallInfo = {
                    id: tc.id || '',
                    type: tc.type || 'function',
                    functionName: '',
                    functionArguments: ''
                  };
                  accumulatedToolCalls.set(idx, newTc);
                }
                const existing: ToolCallInfo = accumulatedToolCalls.get(idx) as ToolCallInfo;
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
          }

          const finishReason: string | undefined = choice.finish_reason;
          if (finishReason !== undefined) {
            if (finishReason === 'tool_calls' && accumulatedToolCalls.size > 0) {
              const toolCallList: ToolCallInfo[] = [];
              for (const tc of accumulatedToolCalls.values()) {
                const info: ToolCallInfo = {
                  id: tc.id,
                  type: tc.type,
                  functionName: tc.functionName,
                  functionArguments: tc.functionArguments
                };
                toolCallList.push(info);
              }
              onToolCalls(toolCallList);
            }
            onDone(finishReason);
          }
        } catch (e) {
          // skip parse errors for partial lines
        }
      }
    });

    httpRequest.on('dataEnd', () => {
      httpRequest.destroy();
      onComplete();
    });

    httpRequest.requestInStream(
      url,
      {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(),
        extraData: requestBody,
        connectTimeout: 15000,
        readTimeout: 60000
      },
      (err: Error, requestId: number) => {
        if (err) {
          onError('Request error: ' + err.message);
          httpRequest.destroy();
          onComplete();
        }
      }
    );
  }
}
