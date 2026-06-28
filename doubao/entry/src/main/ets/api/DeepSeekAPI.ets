import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  AppSettings,
  ChatMessage,
  ToolCall,
  TIME_TOOL,
  ToolDefinition
} from '../model/ChatModels';

export interface StreamCallbacks {
  onContent: (delta: string) => void;
  onThinking: (delta: string) => void;
  onToolCall: (index: number, toolCall: ToolCall) => void;
  onDone: () => void;
  onError: (error: string) => void;
}

interface ThinkingConfig {
  type: string;
}

interface HttpHeaders {
  'Content-Type': string;
  'Authorization': string;
  'Accept': string;
}

interface ApiFuncPart {
  name: string;
  arguments: string;
}

interface ApiToolCall {
  index?: number;
  id?: string;
  type?: string;
  function?: ApiFuncPart;
}

interface ApiToolCallMsg {
  id: string;
  type: string;
  function: ApiFuncPart;
}

interface ApiMessage {
  role: string;
  content: string;
  tool_calls?: ApiToolCallMsg[];
  tool_call_id?: string;
}

interface RequestBody {
  model: string;
  messages: ApiMessage[];
  stream: boolean;
  tools: ToolDefinition[];
  thinking: ThinkingConfig;
  reasoning_effort?: string;
}

interface DeltaContent {
  reasoning_content?: string;
  content?: string;
  tool_calls?: ApiToolCall[];
}

interface DeltaChoiceItem {
  delta: DeltaContent;
}

interface DeltaChoice {
  choices: DeltaChoiceItem[];
}

interface ApiErrorDetail {
  message?: string;
}

interface ApiErrorResponse {
  error?: ApiErrorDetail;
}

export class DeepSeekAPI {
  private settings: AppSettings;
  private buffer: string = '';
  private toolCallsMap: Map<number, ToolCall> = new Map();
  private httpRequest: http.HttpRequest | null = null;
  private errorBuffer: string = '';
  private statusOk: boolean = true;

  constructor(settings: AppSettings) {
    this.settings = settings;
  }

  updateSettings(settings: AppSettings): void {
    this.settings = settings;
  }

  destroy(): void {
    if (this.httpRequest) {
      try {
        this.httpRequest.destroy();
      } catch (_) {}
      this.httpRequest = null;
    }
  }

  async chatStream(messages: ChatMessage[], callbacks: StreamCallbacks): Promise<void> {
    this.destroy();
    const httpRequest = http.createHttp();
    this.httpRequest = httpRequest;
    this.buffer = '';
    this.errorBuffer = '';
    this.toolCallsMap = new Map();
    this.statusOk = true;
    let done = false;

    const finish = (): void => {
      if (done) return;
      done = true;
      this.destroy();
    };

    const doDone = (): void => {
      if (done) return;
      done = true;
      callbacks.onDone();
      this.destroy();
    };

    const doError = (msg: string): void => {
      if (done) return;
      done = true;
      callbacks.onError(msg);
      this.destroy();
    };

    httpRequest.on('headersReceive', (header: Object) => {
      console.info('DeepSeek API headers received');
    });

    httpRequest.on('dataReceive', (chunk: ArrayBuffer) => {
      const textDecoder = util.TextDecoder.create('utf-8');
      const text = textDecoder.decodeToString(new Uint8Array(chunk));
      if (this.statusOk) {
        this.buffer = this.buffer + text;
        this.processLines(callbacks);
      } else {
        this.errorBuffer = this.errorBuffer + text;
      }
    });

    httpRequest.on('dataEnd', () => {
      if (this.statusOk) {
        if (this.buffer.trim().length > 0) {
          this.parseLine(this.buffer.trim(), callbacks);
        }
        doDone();
      } else {
        let errMsg = '请求失败';
        try {
          if (this.errorBuffer.length > 0) {
            const errResp = JSON.parse(this.errorBuffer) as ApiErrorResponse;
            if (errResp.error && errResp.error.message) {
              errMsg = errResp.error.message;
            }
          }
        } catch (_) {}
        doError(errMsg);
      }
      finish();
    });

    const apiMessages: ApiMessage[] = [];
    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i];
      if (msg.role === 'system' && i > 0) {
        continue;
      }
      const m: ApiMessage = { role: msg.role, content: msg.content };
      if (msg.toolCalls.length > 0) {
        const tcs: ApiToolCallMsg[] = [];
        for (let j = 0; j < msg.toolCalls.length; j++) {
          const tc = msg.toolCalls[j];
          const func: ApiFuncPart = { name: tc.functionName, arguments: tc.functionArgs };
          const tcm: ApiToolCallMsg = { id: tc.id, type: tc.type, function: func };
          tcs.push(tcm);
        }
        m.tool_calls = tcs;
      }
      if (msg.role === 'tool' && msg.toolCallId.length > 0) {
        m.tool_call_id = msg.toolCallId;
      }
      apiMessages.push(m);
    }

    const sysMsg: ApiMessage = {
      role: 'system',
      content: 'You are a helpful assistant. When appropriate, use tools to answer questions.'
    };
    if (apiMessages.length === 0 || apiMessages[0].role !== 'system') {
      apiMessages.unshift(sysMsg);
    }

    const thinkingType: string = this.settings.thinkingEnabled ? 'enabled' : 'disabled';
    const thinking: ThinkingConfig = { type: thinkingType };

    const body: RequestBody = {
      model: this.settings.model,
      messages: apiMessages,
      stream: true,
      tools: [TIME_TOOL],
      thinking: thinking
    };

    if (this.settings.thinkingEnabled) {
      body.reasoning_effort = this.settings.reasoningEffort;
    }

    const url = this.settings.baseUrl + '/chat/completions';
    const headers: HttpHeaders = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + this.settings.apiKey,
      'Accept': 'text/event-stream'
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: JSON.stringify(body),
      connectTimeout: 30000,
      readTimeout: 120000
    };

    try {
      const responseCode: number = await httpRequest.requestInStream(url, options);
      if (responseCode !== 200) {
        this.statusOk = false;
      }
    } catch (e) {
      let msg = '请求失败';
      try {
        const err = e as BusinessErrorLike;
        if (err.message && err.message.length > 0) {
          msg = err.message;
        }
      } catch (_) {}
      doError(msg);
      finish();
    }
  }

  private processLines(callbacks: StreamCallbacks): void {
    let idx: number = this.buffer.indexOf('\n');
    while (idx !== -1) {
      const line = this.buffer.substring(0, idx);
      this.buffer = this.buffer.substring(idx + 1);
      this.parseLine(line.trim(), callbacks);
      idx = this.buffer.indexOf('\n');
    }
  }

  private parseLine(line: string, callbacks: StreamCallbacks): void {
    if (!line.startsWith('data:')) {
      return;
    }
    const data = line.substring(5).trim();
    if (!data || data === '[DONE]') {
      return;
    }

    try {
      const parsed = JSON.parse(data) as DeltaChoice;
      const choiceList = parsed.choices;
      if (!choiceList || choiceList.length === 0) {
        return;
      }
      const choice = choiceList[0];
      const delta = choice.delta;
      if (!delta) {
        return;
      }

      if (delta.reasoning_content && delta.reasoning_content.length > 0) {
        callbacks.onThinking(delta.reasoning_content);
      }
      if (delta.content && delta.content.length > 0) {
        callbacks.onContent(delta.content);
      }
      if (delta.tool_calls) {
        for (let i = 0; i < delta.tool_calls.length; i++) {
          const tc = delta.tool_calls[i];
          const tcIndex: number = (tc.index !== undefined && tc.index !== null) ? tc.index : i;
          let existing = this.toolCallsMap.get(tcIndex);
          if (!existing) {
            const tcId = tc.id || '';
            const tcName = (tc.function && tc.function.name) || '';
            const tcArgs = (tc.function && tc.function.arguments) || '';
            existing = new ToolCall(tcId, tcName, tcArgs);
            this.toolCallsMap.set(tcIndex, existing);
            callbacks.onToolCall(tcIndex, existing);
          } else {
            if (tc.id) existing.id = tc.id;
            if (tc.function && tc.function.name) existing.functionName = existing.functionName + tc.function.name;
            if (tc.function && tc.function.arguments) existing.functionArgs = existing.functionArgs + tc.function.arguments;
          }
        }
      }
    } catch (_) {}
  }
}

interface BusinessErrorLike {
  code?: number;
  message?: string;
}
