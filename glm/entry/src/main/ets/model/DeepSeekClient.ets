import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  AppSettings,
  ApiMessage,
  ChatRequestBody,
  StreamCallbacks,
  ToolCall,
  ToolDef,
  ToolCallFunction
} from './Types';
import { SSEParser } from './SSEParser';

const BASE_URL: string = 'https://api.deepseek.com';

export class DeepSeekClient {
  private httpRequest: http.HttpRequest | null = null;
  private cancelled: boolean = false;
  private resolveFn: ((value: void) => void) | null = null;

  streamChat(
    messages: ApiMessage[],
    settings: AppSettings,
    tools: ToolDef[] | null,
    callbacks: StreamCallbacks
  ): Promise<void> {
    return new Promise<void>((resolve) => {
      this.cancelled = false;
      this.resolveFn = resolve;
      const parser: SSEParser = new SSEParser();
      const textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const toolCalls: ToolCall[] = [];
      let done: boolean = false;

      const body: ChatRequestBody = {
        model: settings.model,
        messages: messages,
        stream: true
      };
      if (settings.thinkingType === 'enabled') {
        body.thinking = { type: 'enabled' };
        body.reasoning_effort = settings.reasoningEffort;
      } else {
        body.thinking = { type: 'disabled' };
      }
      if (tools && tools.length > 0) {
        body.tools = tools;
        body.tool_choice = 'auto';
      }
      const bodyStr: string = JSON.stringify(body);

      const complete: () => void = () => {
        if (done) {
          return;
        }
        done = true;
        if (toolCalls.length > 0) {
          callbacks.onToolCalls(toolCalls);
        }
        callbacks.onDone();
      };

      const httpRequest: http.HttpRequest = http.createHttp();
      this.httpRequest = httpRequest;

      let rawBuffer: string = '';

      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        if (this.cancelled) {
          return;
        }
        const chunk: string = textDecoder.decodeWithStream(new Uint8Array(data));
        rawBuffer += chunk;
        parser.feed(chunk, (eventData: string) => {
          if (eventData === '[DONE]') {
            complete();
            return;
          }
          try {
            const obj: Record<string, Object> = JSON.parse(eventData) as Record<string, Object>;
            const choicesVal: Object | undefined = obj['choices'];
            if (!choicesVal) {
              return;
            }
            const choices: Object[] = choicesVal as Object[];
            if (choices.length === 0) {
              return;
            }
            const choice: Record<string, Object> = choices[0] as Record<string, Object>;
            const deltaVal: Object | undefined = choice['delta'];
            if (!deltaVal) {
              return;
            }
            const delta: Record<string, Object> = deltaVal as Record<string, Object>;

            const contentVal: Object | undefined = delta['content'];
            if (contentVal !== undefined && contentVal !== null) {
              callbacks.onContent(contentVal as string);
            }

            const reasoningVal: Object | undefined = delta['reasoning_content'];
            if (reasoningVal !== undefined && reasoningVal !== null) {
              callbacks.onReasoning(reasoningVal as string);
            }

            const tcVal: Object | undefined = delta['tool_calls'];
            if (tcVal) {
              const tcArr: Object[] = tcVal as Object[];
              for (let i = 0; i < tcArr.length; i++) {
                const d: Record<string, Object> = tcArr[i] as Record<string, Object>;
                const idx: number = d['index'] as number;
                const idVal: Object | undefined = d['id'];
                const fnVal: Object | undefined = d['function'];
                let nameStr: string = '';
                let argsStr: string = '';
                if (fnVal) {
                  const fn: Record<string, Object> = fnVal as Record<string, Object>;
                  const n: Object | undefined = fn['name'];
                  if (n) {
                    nameStr = n as string;
                  }
                  const a: Object | undefined = fn['arguments'];
                  if (a) {
                    argsStr = a as string;
                  }
                }
                while (toolCalls.length <= idx) {
                  const fn: ToolCallFunction = { name: '', arguments: '' };
                  toolCalls.push({ id: '', type: 'function', function: fn });
                }
                if (idVal) {
                  toolCalls[idx].id = idVal as string;
                }
                if (nameStr.length > 0) {
                  toolCalls[idx].function.name = nameStr;
                }
                if (argsStr.length > 0) {
                  toolCalls[idx].function.arguments += argsStr;
                }
              }
            }
          } catch (e) {
          }
        });
      });

      const header: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + settings.apiKey,
        'Accept': 'text/event-stream'
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        extraData: bodyStr,
        connectTimeout: 30000,
        readTimeout: 120000
      };

      httpRequest.requestInStream(BASE_URL + '/chat/completions', options,
        (err: BusinessError, responseCode: number) => {
          httpRequest.destroy();
          this.httpRequest = null;
          this.resolveFn = null;

          if (this.cancelled) {
            if (!done) {
              done = true;
              callbacks.onDone();
            }
            resolve();
            return;
          }

          if (err) {
            if (!done) {
              done = true;
              callbacks.onError('网络请求失败: ' + err.message);
            }
            resolve();
            return;
          }

          if (responseCode >= 400) {
            if (!done) {
              done = true;
              let msg: string = '请求失败 (HTTP ' + responseCode + ')';
              try {
                const errObj: Record<string, Object> = JSON.parse(rawBuffer) as Record<string, Object>;
                const errInfo: Object | undefined = errObj['error'];
                if (errInfo) {
                  const info: Record<string, Object> = errInfo as Record<string, Object>;
                  const m: Object | undefined = info['message'];
                  if (m) {
                    msg = m as string;
                  }
                }
              } catch (e) {
              }
              callbacks.onError(msg);
            }
            resolve();
            return;
          }

          complete();
          resolve();
        });
    });
  }

  cancel(): void {
    this.cancelled = true;
    if (this.httpRequest) {
      this.httpRequest.destroy();
      this.httpRequest = null;
    }
    if (this.resolveFn) {
      const fn: (value: void) => void = this.resolveFn;
      this.resolveFn = null;
      fn();
    }
  }
}
