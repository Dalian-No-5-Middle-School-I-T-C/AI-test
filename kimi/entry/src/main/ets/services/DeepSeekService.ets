import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ChatMessage, DeepSeekMessage, DeepSeekRequest, DeepSeekStreamChunk, ThinkingOptions, ToolCall, ToolCallFunction } from '../models/ChatModels';
import { ToolService } from './ToolService';

const BASE_URL = 'https://api.deepseek.com/chat/completions';
const CONNECT_TIMEOUT = 60000;
const READ_TIMEOUT = 120000;

const THINKING_ENABLED_OPTION: ThinkingOptions = { type: 'enabled' };
const THINKING_DISABLED_OPTION: ThinkingOptions = { type: 'disabled' };

export interface StreamCallbacks {
  onStart: () => void;
  onContentDelta: (text: string) => void;
  onReasoningDelta: (text: string) => void;
  onToolCall: (toolCall: ToolCall) => void;
  onToolResult: (toolResult: ChatMessage) => void;
  onComplete: (assistantMessage: ChatMessage) => void | Promise<void>;
  onError: (message: string) => void | Promise<void>;
}

export class DeepSeekService {
  private currentHttpRequest: http.HttpRequest | null = null;

  cancel(): void {
    if (this.currentHttpRequest) {
      this.currentHttpRequest.destroy();
      this.currentHttpRequest = null;
    }
  }

  async sendMessageStream(
    apiKey: string,
    model: string,
    thinkingEnabled: boolean,
    reasoningEffort: 'high' | 'max',
    messages: ChatMessage[],
    callbacks: StreamCallbacks
  ): Promise<void> {
    callbacks.onStart();
    const workingMessages: ChatMessage[] = [...messages];
    await this.runRound(apiKey, model, thinkingEnabled, reasoningEffort, workingMessages, callbacks, 0);
  }

  private async runRound(
    apiKey: string,
    model: string,
    thinkingEnabled: boolean,
    reasoningEffort: 'high' | 'max',
    workingMessages: ChatMessage[],
    callbacks: StreamCallbacks,
    depth: number
  ): Promise<void> {
    if (depth > 5) {
      callbacks.onError('Too many tool call rounds');
      return;
    }

    const requestBody = this.buildRequestBody(model, thinkingEnabled, reasoningEffort, workingMessages);
    const result = await this.streamRequest(apiKey, requestBody);

    if (result.error) {
      callbacks.onError(result.error);
      return;
    }

    const assistantMessage: ChatMessage = {
      id: this.generateId(),
      role: 'assistant',
      content: result.content,
      reasoningContent: result.reasoningContent || undefined,
      toolCalls: result.toolCalls.length > 0 ? result.toolCalls : undefined,
      model: model
    };

    if (result.toolCalls.length > 0) {
      for (const tc of result.toolCalls) {
        callbacks.onToolCall(tc);
      }
      workingMessages.push(assistantMessage);

      for (const tc of result.toolCalls) {
        const toolResultContent = ToolService.executeTool(tc.function.name, tc.function.arguments);
        const toolResult: ChatMessage = {
          id: this.generateId(),
          role: 'tool',
          content: toolResultContent,
          toolCallId: tc.id,
          model: model
        };
        callbacks.onToolResult(toolResult);
        workingMessages.push(toolResult);
      }

      await this.runRound(apiKey, model, thinkingEnabled, reasoningEffort, workingMessages, callbacks, depth + 1);
      return;
    }

    callbacks.onComplete(assistantMessage);
  }

  private buildRequestBody(
    model: string,
    thinkingEnabled: boolean,
    reasoningEffort: 'high' | 'max',
    messages: ChatMessage[]
  ): DeepSeekRequest {
    const requestBody: DeepSeekRequest = {
      model,
      messages: this.buildApiMessages(messages),
      stream: true,
      tools: ToolService.TOOLS
    };

    if (thinkingEnabled) {
      requestBody.thinking = THINKING_ENABLED_OPTION;
      requestBody.reasoning_effort = reasoningEffort;
    } else {
      requestBody.thinking = THINKING_DISABLED_OPTION;
    }

    return requestBody;
  }

  private buildApiMessages(messages: ChatMessage[]): DeepSeekMessage[] {
    const systemMessage: DeepSeekMessage = { role: 'system', content: 'You are a helpful assistant.' };
    const apiMessages: DeepSeekMessage[] = [systemMessage];
    for (const msg of messages) {
      const deepSeekMsg: DeepSeekMessage = {
        role: msg.role,
        content: msg.content
      };
      if (msg.reasoningContent) {
        deepSeekMsg.reasoning_content = msg.reasoningContent;
      }
      if (msg.toolCalls && msg.toolCalls.length > 0) {
        deepSeekMsg.tool_calls = msg.toolCalls;
      }
      if (msg.toolCallId) {
        deepSeekMsg.tool_call_id = msg.toolCallId;
      }
      apiMessages.push(deepSeekMsg);
    }
    return apiMessages;
  }

  private async streamRequest(apiKey: string, requestBody: DeepSeekRequest): Promise<StreamResult> {
    const httpRequest = http.createHttp();
    this.currentHttpRequest = httpRequest;
    const textDecoder = util.TextDecoder.create('utf-8');

    let buffer = '';
    let content = '';
    let reasoningContent = '';
    const toolCallMap: Map<number, ToolCall> = new Map();
    let responseCode: number | undefined = undefined;
    let streamEnded = false;
    let networkError = '';

    return new Promise((resolve, _reject) => {
      const tryResolve = (): void => {
        if (networkError) {
          resolve({ error: networkError, content: '', reasoningContent: '', toolCalls: [] });
          return;
        }
        if (responseCode !== undefined && responseCode !== 200) {
          resolve({ error: `HTTP error: ${responseCode}`, content: '', reasoningContent: '', toolCalls: [] });
          return;
        }
        if (!streamEnded || responseCode === undefined) {
          return;
        }
        resolve({
          error: '',
          content,
          reasoningContent,
          toolCalls: this.mapToolCalls(toolCallMap)
        });
      };

      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        const chunk = textDecoder.decodeWithStream(new Uint8Array(data), { stream: true });
        buffer += chunk;
        const lines = buffer.split('\n');
        buffer = lines.pop() ?? '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed.startsWith('data:')) {
            continue;
          }
          const dataStr = trimmed.slice(5).trim();
          if (dataStr === '[DONE]' || !dataStr) {
            continue;
          }

          try {
            const parsed = JSON.parse(dataStr) as DeepSeekStreamChunk;
            if (parsed.choices && parsed.choices.length > 0) {
              const delta = parsed.choices[0].delta;
              if (delta.content) {
                content += delta.content;
              }
              if (delta.reasoning_content) {
                reasoningContent += delta.reasoning_content;
              }
              if (delta.tool_calls) {
                this.mergeToolCallDeltas(toolCallMap, delta.tool_calls);
              }
            }
          } catch (e) {
            // Ignore malformed JSON in stream
          }
        }
      });

      httpRequest.on('dataEnd', () => {
        this.currentHttpRequest = null;
        streamEnded = true;
        tryResolve();
      });

      httpRequest.requestInStream(BASE_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`,
          'Accept': 'text/event-stream'
        },
        extraData: JSON.stringify(requestBody),
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT
      }).then((code: number) => {
        responseCode = code || -1;
        tryResolve();
      }).catch((err: Error) => {
        this.currentHttpRequest = null;
        networkError = err ? err.message : 'Request failed';
        streamEnded = true;
        tryResolve();
      });
    });
  }

  private mergeToolCallDeltas(map: Map<number, ToolCall>, deltas: ToolCall[]): void {
    for (const delta of deltas) {
      const index = delta.index ?? 0;
      const existing = map.get(index);
      if (!existing) {
        const toolFunction: ToolCallFunction = {
          name: delta.function?.name || '',
          arguments: delta.function?.arguments || ''
        };
        const newToolCall: ToolCall = {
          id: delta.id || '',
          type: (delta.type || 'function') as 'function',
          function: toolFunction
        };
        map.set(index, newToolCall);
      } else {
        if (delta.id) {
          existing.id = delta.id;
        }
        if (delta.function?.name) {
          existing.function.name += delta.function.name;
        }
        if (delta.function?.arguments) {
          existing.function.arguments += delta.function.arguments;
        }
      }
    }
  }

  private mapToolCalls(map: Map<number, ToolCall>): ToolCall[] {
    const result: ToolCall[] = [];
    const keys = Array.from(map.keys()).sort((a, b) => a - b);
    for (const key of keys) {
      result.push(map.get(key)!);
    }
    return result;
  }

  generateId(): string {
    return `${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
  }
}

interface StreamResult {
  error: string;
  content: string;
  reasoningContent: string;
  toolCalls: ToolCall[];
}
