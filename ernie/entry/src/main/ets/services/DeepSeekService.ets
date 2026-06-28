import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface DeepSeekConfig {
  apiKey: string;
  model: 'deepseek-v4-flash' | 'deepseek-v4-pro';
  thinkingEnabled: boolean;
  reasoningEffort: 'high' | 'max';
}

export interface StreamCallback {
  onToken: (token: string) => void;
  onThinking: (thinking: string) => void;
  onDone: () => void;
  onError: (error: string) => void;
}

interface ThinkingConfig {
  type: string;
}

interface MsgPart {
  role: string;
  content: string;
}

interface HeaderItem {
  key: string;
  value: string;
}

interface RequestBody {
  model: string;
  messages: Array<MsgPart>;
  stream: boolean;
  thinking: ThinkingConfig;
  reasoning_effort: string;
}

interface SseDelta {
  reasoning_content?: string;
  content?: string;
}

interface SseChoice {
  delta: SseDelta;
}

interface SseResponse {
  choices: SseChoice[];
}

const BASE_URL = 'https://api.deepseek.com';

function makeHeaders(apiKey: string): Array<HeaderItem> {
  return [
    { key: 'Content-Type', value: 'application/json' },
    { key: 'Authorization', value: `Bearer ${apiKey}` }
  ];
}

function buildBody(messages: ChatMessage[], config: DeepSeekConfig): string {
  const thinkingConfig: ThinkingConfig = {
    type: config.thinkingEnabled ? 'enabled' : 'disabled'
  };

  const msgParts: Array<MsgPart> = messages.map((m: ChatMessage): MsgPart => ({ role: m.role, content: m.content }));

  const body: RequestBody = {
    model: config.model,
    messages: msgParts,
    stream: true,
    thinking: thinkingConfig,
    reasoning_effort: config.reasoningEffort,
  };

  return JSON.stringify(body);
}

export class DeepSeekService {
  private httpRequest: http.HttpRequest | null = null;

  async chatStream(
    messages: ChatMessage[],
    config: DeepSeekConfig,
    callback: StreamCallback
  ): Promise<void> {
    const url = `${BASE_URL}/chat/completions`;
    const body = buildBody(messages, config);

    try {
      this.httpRequest = http.createHttp();

      this.httpRequest.request(
        url,
        {
          method: http.RequestMethod.POST,
          header: makeHeaders(config.apiKey),
          extraData: body,
          connectTimeout: 30000,
          readTimeout: 60000,
        },
        (err: BusinessError, data: http.HttpResponse) => {
          if (err) {
            callback.onError(`Request failed: ${err.message}`);
            return;
          }

          if (data.responseCode !== 200) {
            callback.onError(`HTTP ${data.responseCode}: ${data.result}`);
            return;
          }

          this.handleSSEStream(data.result as string, callback);
        }
      );
    } catch (e) {
      callback.onError(`Exception: ${e}`);
    }
  }

  private handleSSEStream(streamData: string, callback: StreamCallback): void {
    const lines = streamData.split('\n');
    let thinkingBuffer = '';

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();
      if (!trimmed || trimmed === 'data: [DONE]') {
        continue;
      }
      if (trimmed.startsWith('data: ')) {
        const jsonStr = trimmed.slice(6);
        if (!jsonStr) continue;

        try {
          const json: SseResponse = JSON.parse(jsonStr);
          const choices = json?.choices;
          if (!choices || choices.length === 0) continue;

          const choice: SseChoice = choices[0];
          const delta: SseDelta = choice?.delta;
          if (!delta) continue;

          if (delta.reasoning_content) {
            thinkingBuffer += delta.reasoning_content;
            if (thinkingBuffer.length > 50 || !delta.content) {
              callback.onThinking(thinkingBuffer);
              thinkingBuffer = '';
            }
          }

          if (delta.content) {
            callback.onToken(delta.content);
          }
        } catch {
          continue;
        }
      }
    }

    if (thinkingBuffer) {
      callback.onThinking(thinkingBuffer);
    }
    callback.onDone();
  }

  async getSystemTime(): Promise<string> {
    const now = new Date();
    return now.toLocaleString('zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false
    });
  }

  destroy(): void {
    if (this.httpRequest) {
      this.httpRequest.destroy();
      this.httpRequest = null;
    }
  }
}

export const deepSeekService = new DeepSeekService();
