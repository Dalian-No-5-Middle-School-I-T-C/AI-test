import { http } from '@kit.NetworkKit';

export function httpStreamRequest(
  url: string,
  method: http.RequestMethod,
  headers: Record<string, string>,
  body: string,
  onDelta: (content: string) => void,
  onReasoningDelta: (content: string) => void,
  onToolCallDelta: (id: string, name: string, args: string) => void,
  onFinish: (reason: string) => void,
  onError: (errMsg: string) => void
): Promise<void> {
  return new Promise<void>((resolve) => {
    const httpRequest = http.createHttp();
    let finished = false;
    let errorBody: string = '';

    const finishOnce = (): void => {
      if (finished) {
        return;
      }
      finished = true;
      try {
        httpRequest.destroy();
      } catch (e) {
      }
      resolve();
    };

    const handleDelta = (raw: string): void => {
      errorBody += raw;
      SseParser.feed(raw, onDelta, onReasoningDelta, onToolCallDelta, onFinish);
    };

    httpRequest.on('headersReceive', (header) => {
    });

    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      try {
        const chunkStr = bufferToString(data);
        handleDelta(chunkStr);
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        onError(`parse error: ${msg}`);
      }
    });

    httpRequest.on('dataEnd', () => {
      onFinish('stop');
      finishOnce();
    });

    httpRequest.requestInStream(
      url,
      {
        method: method,
        header: headers,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        priority: 1,
        connectTimeout: 60000,
        readTimeout: 120000
      },
      (err: Error, status: number) => {
        if (err) {
          onError(err.message);
          finishOnce();
          return;
        }
        if (status < 200 || status >= 300) {
          onError(`http status ${status}: ${errorBody.substring(0, 500)}`);
          finishOnce();
          return;
        }
        finishOnce();
      }
    );
  });
}

function bufferToString(buf: ArrayBuffer): string {
  const u8 = new Uint8Array(buf);
  let str = '';
  let i = 0;
  while (i < u8.length) {
    const b1 = u8[i];
    if (b1 < 0x80) {
      str += String.fromCharCode(b1);
      i++;
    } else if ((b1 & 0xE0) === 0xC0) {
      const b2 = u8[i + 1];
      str += String.fromCharCode(((b1 & 0x1F) << 6) | (b2 & 0x3F));
      i += 2;
    } else if ((b1 & 0xF0) === 0xE0) {
      const b2 = u8[i + 1];
      const b3 = u8[i + 2];
      str += String.fromCharCode(((b1 & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F));
      i += 3;
    } else if ((b1 & 0xF8) === 0xF0) {
      const b2 = u8[i + 1];
      const b3 = u8[i + 2];
      const b4 = u8[i + 3];
      let cp = ((b1 & 0x07) << 18) | ((b2 & 0x3F) << 12) | ((b3 & 0x3F) << 6) | (b4 & 0x3F);
      cp -= 0x10000;
      str += String.fromCharCode(0xD800 + (cp >> 10));
      str += String.fromCharCode(0xDC00 + (cp & 0x3FF));
      i += 4;
    } else {
      i++;
    }
  }
  return str;
}

class SseParser {
  private static buffer: string = '';

  static reset(): void {
    SseParser.buffer = '';
  }

  static feed(
    raw: string,
    onDelta: (content: string) => void,
    onReasoningDelta: (content: string) => void,
    onToolCallDelta: (id: string, name: string, args: string) => void,
    onFinish: (reason: string) => void
  ): void {
    SseParser.buffer += raw;
    let idx: number;
    while ((idx = SseParser.buffer.indexOf('\n')) >= 0) {
      const line = SseParser.buffer.substring(0, idx);
      SseParser.buffer = SseParser.buffer.substring(idx + 1);
      if (SseParser.buffer.length === 0 && line.trim().length > 0 && line.trim().startsWith('{')) {
        try {
          const obj = JSON.parse(line.trim()) as Object;
          SseParser.handleJson(obj, onDelta, onReasoningDelta, onToolCallDelta, onFinish);
          continue;
        } catch (e) {
        }
      }
      SseParser.handleLine(line, onDelta, onReasoningDelta, onToolCallDelta, onFinish);
    }
  }

  private static handleLine(
    line: string,
    onDelta: (content: string) => void,
    onReasoningDelta: (content: string) => void,
    onToolCallDelta: (id: string, name: string, args: string) => void,
    onFinish: (reason: string) => void
  ): void {
    const trimmed = line.replace(/\r$/, '');
    if (trimmed.length === 0) {
      return;
    }
    if (!trimmed.startsWith('data:')) {
      return;
    }
    const payload = trimmed.substring(5).trim();
    if (payload === '[DONE]') {
      onFinish('done');
      return;
    }
    let json: Object;
    try {
      json = JSON.parse(payload) as Object;
    } catch (e) {
      return;
    }
    SseParser.handleJson(json, onDelta, onReasoningDelta, onToolCallDelta, onFinish);
  }

  private static handleJson(
    json: Object,
    onDelta: (content: string) => void,
    onReasoningDelta: (content: string) => void,
    onToolCallDelta: (id: string, name: string, args: string) => void,
    onFinish: (reason: string) => void
  ): void {
    const asMap = json as Record<string, Object>;
    const choices = asMap['choices'] as Array<Object> | undefined;
    if (!choices || choices.length === 0) {
      return;
    }
    const choice = choices[0] as Record<string, Object>;
    const delta = choice['delta'] as Record<string, Object> | undefined;
    const message = choice['message'] as Record<string, Object> | undefined;
    const source: Record<string, Object> | undefined = delta ? delta : message;
    if (!source) {
      return;
    }
    const reasoning = source['reasoning_content'] as string | undefined;
    if (reasoning && reasoning.length > 0) {
      onReasoningDelta(reasoning);
    }
    let content = source['content'] as string | undefined;
    if ((!content || content.length === 0) && source['text'] !== undefined) {
      content = source['text'] as string;
    }
    if (!content || content.length === 0) {
      const candidates: string[] = ['content', 'text', 'delta', 'message', 'response'];
      for (let i = 0; i < candidates.length; i++) {
        const v = source[candidates[i]] as string | undefined;
        if (typeof v === 'string' && v.length > 0) {
          content = v;
          break;
        }
      }
    }
    if (content && content.length > 0) {
      onDelta(content);
    }
    const toolCalls = source['tool_calls'] as Array<Object> | undefined;
    if (toolCalls && toolCalls.length > 0) {
      for (let i = 0; i < toolCalls.length; i++) {
        const tc = toolCalls[i] as Record<string, Object>;
        const id = (tc['id'] as string) ?? '';
        const fn = (tc['function'] as Record<string, Object>) ?? {};
        const name = (fn['name'] as string) ?? '';
        const args = (fn['arguments'] as string) ?? '';
        onToolCallDelta(id, name, args);
      }
    }
    const finishReason = choice['finish_reason'] as string | undefined;
    if (finishReason) {
      onFinish(finishReason);
    }
  }
}

export function newSseSession(): void {
  SseParser.reset();
}