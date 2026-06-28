import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppSettings, ChatMessage, ToolCall } from '../models/ChatModels';
import { TimeToolDefinition, executeTimeTool } from './TimeTool';

export interface StreamCallbacks {
  onReasoningDelta: (delta: string) => void;
  onContentDelta: (delta: string) => void;
  onToolCallDetected?: (toolName: string) => void;
  onComplete: (fullMessage: ChatMessage) => void;
  onError: (errorMsg: string) => void;
}

export class DeepSeekClient {
  private settings: AppSettings;

  constructor(settings: AppSettings) {
    this.settings = settings;
  }

  public async sendChatStream(
    historyMessages: ChatMessage[],
    callbacks: StreamCallbacks
  ): Promise<void> {
    if (!this.settings.apiKey || this.settings.apiKey.trim() === '') {
      callbacks.onError('API Key is missing. Please configure it in Settings.');
      return;
    }

    // Prepare message payload according to OpenAI/DeepSeek schema
    const apiMessages: Record<string, Object>[] = historyMessages.map(msg => {
      const item: Record<string, Object> = {};
      item['role'] = msg.role;
      item['content'] = msg.content;

      if (msg.reasoning_content !== undefined) {
        item['reasoning_content'] = msg.reasoning_content;
      }
      if (msg.tool_calls !== undefined) {
        item['tool_calls'] = msg.tool_calls as Object[];
      }
      if (msg.tool_call_id !== undefined) {
        item['tool_call_id'] = msg.tool_call_id;
      }
      if (msg.name !== undefined) {
        item['name'] = msg.name;
      }
      return item;
    });

    const requestBody: Record<string, Object> = {};
    requestBody['model'] = this.settings.model;
    requestBody['messages'] = apiMessages;
    requestBody['stream'] = true;
    requestBody['reasoning_effort'] = this.settings.reasoningEffort;

    if (this.settings.thinkingEnabled) {
      const thinkingConfig: Record<string, Object> = {};
      thinkingConfig['type'] = 'enabled';
      requestBody['thinking'] = thinkingConfig;
    } else {
      const thinkingConfig: Record<string, Object> = {};
      thinkingConfig['type'] = 'disabled';
      requestBody['thinking'] = thinkingConfig;
    }

    if (this.settings.toolsEnabled) {
      requestBody['tools'] = [TimeToolDefinition];
    }

    let url = this.settings.baseUrl;
    if (url.endsWith('/')) {
      url = url.slice(0, -1);
    }
    if (!url.endsWith('/chat/completions')) {
      url = `${url}/chat/completions`;
    }

    const httpRequest = http.createHttp();
    const textDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    
    let pendingBufferString = '';
    let accumulatedReasoning = '';
    let accumulatedContent = '';
    let accumulatedToolCalls: ToolCall[] = [];

    httpRequest.on('dataReceive', (chunk: ArrayBuffer) => {
      try {
        const chunkStr = textDecoder.decodeToString(new Uint8Array(chunk));
        pendingBufferString += chunkStr;

        const lines = pendingBufferString.split(/\r?\n/);
        // The last element in lines might be incomplete
        pendingBufferString = lines.pop() || '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed || trimmed.startsWith(':')) {
            continue; // Ignore heartbeat / comment lines
          }
          if (trimmed === 'data: [DONE]') {
            continue;
          }
          if (trimmed.startsWith('data: ')) {
            const jsonStr = trimmed.substring(6);
            try {
              const parsed = JSON.parse(jsonStr) as Record<string, Object>;
              if (parsed && parsed.choices) {
                const choices = parsed.choices as Array<Record<string, Object>>;
                if (choices.length > 0) {
                  const delta = choices[0].delta as Record<string, Object>;
                  if (delta) {
                    // Check reasoning_content
                    if (delta.reasoning_content && typeof delta.reasoning_content === 'string') {
                      accumulatedReasoning += delta.reasoning_content;
                      callbacks.onReasoningDelta(delta.reasoning_content);
                    }
                    // Check content
                    if (delta.content && typeof delta.content === 'string') {
                      accumulatedContent += delta.content;
                      callbacks.onContentDelta(delta.content);
                    }
                    // Check tool_calls
                    if (delta.tool_calls && Array.isArray(delta.tool_calls)) {
                      const tCalls = delta.tool_calls as Array<Record<string, Object>>;
                      for (const tc of tCalls) {
                        const idx = typeof tc.index === 'number' ? tc.index : 0;
                        if (!accumulatedToolCalls[idx]) {
                          accumulatedToolCalls[idx] = {
                            id: (tc.id as string) || '',
                            type: 'function',
                            function: {
                              name: '',
                              arguments: ''
                            }
                          };
                        }
                        if (tc.id) {
                          accumulatedToolCalls[idx].id = tc.id as string;
                        }
                        if (tc.function) {
                          const fn = tc.function as Record<string, Object>;
                          if (fn.name) {
                            accumulatedToolCalls[idx].function.name += fn.name as string;
                            if (callbacks.onToolCallDetected) {
                              callbacks.onToolCallDetected(fn.name as string);
                            }
                          }
                          if (fn.arguments) {
                            accumulatedToolCalls[idx].function.arguments += fn.arguments as string;
                          }
                        }
                      }
                    }
                  }
                }
              }
            } catch (err) {
              console.warn('[DeepSeekClient] Error parsing SSE line chunk:', jsonStr, err);
            }
          }
        }
      } catch (err) {
        console.error('[DeepSeekClient] dataReceive decode error:', JSON.stringify(err));
      }
    });

    httpRequest.on('dataEnd', async () => {
      // Clean up event listeners
      httpRequest.off('dataReceive');
      httpRequest.off('dataEnd');
      httpRequest.destroy();

      // Filter empty slots in tool calls if any
      const validToolCalls = accumulatedToolCalls.filter(tc => tc && tc.id);

      const assistantMessage: ChatMessage = {
        id: `msg_${Date.now()}`,
        role: 'assistant',
        content: accumulatedContent,
        reasoning_content: accumulatedReasoning ? accumulatedReasoning : undefined,
        tool_calls: validToolCalls.length > 0 ? validToolCalls : undefined,
        timestamp: Date.now()
      };

      // Handle automatic tool execution loop
      if (validToolCalls.length > 0) {
        const firstTool = validToolCalls[0];
        if (firstTool.function.name === 'get_current_time') {
          callbacks.onContentDelta('\n\n*⚡ [Executing Tool: get_current_time...]*\n\n');
          
          // Execute tool
          const toolResultStr = executeTimeTool();

          const toolMessage: ChatMessage = {
            id: `msg_${Date.now() + 1}`,
            role: 'tool',
            content: toolResultStr,
            tool_call_id: firstTool.id,
            name: 'get_current_time',
            timestamp: Date.now() + 1
          };

          // Append assistant message and tool response message to history
          const updatedHistory = [...historyMessages, assistantMessage, toolMessage];

          // Re-trigger sendChatStream for the final response
          await this.sendChatStream(updatedHistory, callbacks);
          return;
        }
      }

      callbacks.onComplete(assistantMessage);
    });

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.settings.apiKey}`,
        'Accept': 'text/event-stream'
      },
      extraData: JSON.stringify(requestBody),
      connectTimeout: 60000,
      readTimeout: 60000
    };

    try {
      const resCode = await httpRequest.requestInStream(url, options);
      if (resCode !== 200) {
        httpRequest.off('dataReceive');
        httpRequest.off('dataEnd');
        httpRequest.destroy();
        callbacks.onError(`HTTP Request failed with status code: ${resCode}`);
      }
    } catch (err) {
      httpRequest.off('dataReceive');
      httpRequest.off('dataEnd');
      httpRequest.destroy();
      const bErr = err as BusinessError;
      callbacks.onError(`Network error: ${bErr.message || JSON.stringify(err)}`);
    }
  }
}
