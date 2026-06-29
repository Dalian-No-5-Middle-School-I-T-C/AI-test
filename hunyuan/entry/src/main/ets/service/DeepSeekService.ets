// DeepSeekService.ets - DeepSeek API 服务层（ArkTS 严格模式最终版）
import http from '@ohos.net.http';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  ChatMessage, MessageRole, ToolCallItem, ToolDefinition, ToolCallResult,
  ToolFunctionDef, ToolParameters, ToolProperties
} from '../model/ChatModels';

const BASE_URL: string = 'https://api.deepseek.com/chat/completions';

/**
 * 流式输出回调接口
 */
export interface StreamCallbacks {
  onReasoning?: (text: string) => void;
  onContent?: (text: string) => void;
  onToolCall?: (toolCalls: ToolCallItem[]) => void;
  onDone?: () => void;
  onError?: (err: string) => void;
}

/**
 * API 消息格式（对应 DeepSeek messages 参数）
 */
export interface ApiMessage {
  role: string;
  content: string;
  tool_calls?: ToolCallItem[];
}

/**
 * API 请求体格式
 */
export interface ApiRequestBody {
  model: string;
  messages: ApiMessage[];
  stream: boolean;
  thinking?: { type: string };
  reasoning_effort?: string;
  tools?: ToolDefinition[];
  tool_choice?: string;
}

/**
 * SSE 解析辅助：按 key 取字符串
 */
function getStr(obj: Object, key: string): string {
  const val: Object | undefined = (obj as Record<string, Object>)[key];
  if (val === undefined || val === null) return '';
  return String(val);
}

/**
 * SSE 解析辅助：按 key 取对象数组
 */
function getObjArr(obj: Object, key: string): Object[] {
  const val: Object | undefined = (obj as Record<string, Object>)[key];
  if (val instanceof Array) return val as Object[];
  return [];
}

/**
 * DeepSeek API 服务
 */
export class DeepSeekService {
  private apiKey: string = '';

  setApiKey(key: string): void {
    this.apiKey = key;
  }

  getApiKey(): string {
    return this.apiKey;
  }

  /**
   * 流式聊天请求（SSE）
   */
  async chatStream(
    messages: ChatMessage[],
    model: string,
    thinkingEnabled: boolean,
    reasoningEffort: string,
    callbacks: StreamCallbacks,
    tools?: ToolDefinition[]
  ): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (reason: Object) => void) => {
      const httpRequest: http.HttpRequest = http.createHttp();
      const body: string = this.buildRequestBody(messages, model, thinkingEnabled, reasoningEffort, tools, true);

      let buffer: string = '';
      let requestFailed: boolean = false;

      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        if (requestFailed) return;
        const chunk: string = this.arrayBufferToString(data);
        buffer = buffer + chunk;
        const lines: string[] = buffer.split('\n');
        buffer = lines.pop() || '';
        for (const line of lines) {
          this.handleSSELine(line, callbacks);
        }
      });

      httpRequest.on('dataEnd', () => {
        if (requestFailed) return;
        if (buffer.trim()) {
          this.handleSSELine(buffer, callbacks);
        }
        httpRequest.destroy();
        if (callbacks.onDone) callbacks.onDone();
        resolve();
      });

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`,
        'Accept': 'text/event-stream',
      };

      // requestInStream 回调签名：(err: BusinessError, data: number) => void
      // data 是请求 ID（number），不是 HttpResponse
      try {
        httpRequest.requestInStream(BASE_URL, {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: body,
          expectDataType: http.HttpDataType.STRING,
        }, (err: BusinessError, data: number) => {
          if (err) {
            requestFailed = true;
            httpRequest.destroy();
            const msg: string = `请求失败: ${err.code} ${err.message}`;
            if (callbacks.onError) callbacks.onError(msg);
            reject(new Error(msg));
          }
          // data 是请求 ID，非零表示成功发起
        });
      } catch (e) {
        requestFailed = true;
        if (callbacks.onError) callbacks.onError(`请求异常: ${(e as Error).message}`);
        reject(e as Error);
      }
    });
  }

  /**
   * 非流式聊天请求
   */
  async chatNonStream(
    messages: ChatMessage[],
    model: string,
    thinkingEnabled: boolean,
    reasoningEffort: string,
    tools?: ToolDefinition[]
  ): Promise<ChatMessage> {
    return new Promise<ChatMessage>((resolve: (value: ChatMessage) => void, reject: (reason: Object) => void) => {
      const httpRequest: http.HttpRequest = http.createHttp();
      const body: string = this.buildRequestBody(messages, model, thinkingEnabled, reasoningEffort, tools, false);

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`,
      };

      httpRequest.request(BASE_URL, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
      }, (err: BusinessError, data: http.HttpResponse) => {
        httpRequest.destroy();
        if (err) {
          reject(new Error(`请求失败: ${err.code} ${err.message}`));
          return;
        }
        if (data.responseCode !== 200) {
          reject(new Error(`API 错误 ${data.responseCode}: ${data.result}`));
          return;
        }
        try {
          const result: Object = JSON.parse(data.result as string);
          const assistantMsg: ChatMessage = this.parseNonStreamResponse(result);
          resolve(assistantMsg);
        } catch (e) {
          reject(new Error(`解析响应失败: ${(e as Error).message}`));
        }
      });
    });
  }

  /**
   * 处理单条 SSE 行
   */
  private handleSSELine(line: string, callbacks: StreamCallbacks): void {
    const trimmed: string = line.trim();
    if (!trimmed.startsWith('data:')) {
      return;
    }

    const dataStr: string = trimmed.substring(5).trim();
    if (dataStr === '[DONE]') {
      return;
    }

    try {
      const chunk: Object = JSON.parse(dataStr);
      const choices: Object[] = getObjArr(chunk, 'choices');
      if (!choices || choices.length === 0) return;

      const choice: Object = choices[0];
      const delta: Object | undefined = (choice as Record<string, Object>)['delta'];

      if (delta) {
        const reasoningText: string = getStr(delta, 'reasoning_content');
        if (reasoningText && callbacks.onReasoning) {
          callbacks.onReasoning(reasoningText);
        }

        const contentText: string = getStr(delta, 'content');
        if (contentText && callbacks.onContent) {
          callbacks.onContent(contentText);
        }

        const toolCallsRaw: Object = (delta as Record<string, Object>)['tool_calls'];
        if (toolCallsRaw && callbacks.onToolCall) {
          // 将原始 Object[] 转换为 ToolCallItem[]
          const toolCallsArr: Object[] = toolCallsRaw instanceof Array ? toolCallsRaw as Object[] : [];
          const converted: ToolCallItem[] = this.convertToToolCallItems(toolCallsArr);
          callbacks.onToolCall(converted);
        }
      }
    } catch {
      // 忽略无法解析的行
    }
  }

  /**
   * 将 Object[] 转换为 ToolCallItem[]（ArkTS 无 any 类型时的安全转换）
   */
  private convertToToolCallItems(raw: Object[]): ToolCallItem[] {
    const result: ToolCallItem[] = [];
    for (const item of raw) {
      const id: string = getStr(item, 'id');
      const type: string = getStr(item, 'type');
      const funcObj: Object | undefined = (item as Record<string, Object>)['function'];
      const funcName: string = funcObj ? getStr(funcObj, 'name') : '';
      const funcArgs: string = funcObj ? getStr(funcObj, 'arguments') : '';
      const tci: ToolCallItem = {
        id: id,
        type: type,
        function: {
          name: funcName,
          arguments: funcArgs,
        },
      };
      result.push(tci);
    }
    return result;
  }

  /**
   * 构建请求体（使用显式接口 ApiRequestBody）
   */
  private buildRequestBody(
    messages: ChatMessage[],
    model: string,
    thinkingEnabled: boolean,
    reasoningEffort: string,
    tools?: ToolDefinition[],
    stream: boolean = false
  ): string {
    const apiMessages: ApiMessage[] = messages.map((m: ChatMessage): ApiMessage => {
      const msg: ApiMessage = {
        role: m.role.toString(),
        content: m.content,
      };
      if (m.tool_calls && m.tool_calls.length > 0) {
        msg.tool_calls = m.tool_calls;
      }
      return msg;
    });

    const body: ApiRequestBody = {
      model: model,
      messages: apiMessages,
      stream: stream,
    };

    if (thinkingEnabled) {
      body.thinking = { type: 'enabled' };
      body.reasoning_effort = reasoningEffort;
    } else {
      body.thinking = { type: 'disabled' };
    }

    if (tools && tools.length > 0) {
      body.tools = tools;
      body.tool_choice = 'auto';
    }

    return JSON.stringify(body);
  }

  /**
   * 解析非流式响应
   */
  private parseNonStreamResponse(response: Object): ChatMessage {
    const choices: Object[] = getObjArr(response, 'choices');
    if (!choices || choices.length === 0) {
      throw new Error('无效的 API 响应：无 choices');
    }

    const choice: Object = choices[0];
    const msg: Object | undefined = (choice as Record<string, Object>)['message'];

    const content: string = msg ? getStr(msg, 'content') : '';
    const reasoning: string = msg ? getStr(msg, 'reasoning_content') : '';

    let toolCalls: ToolCallItem[] | undefined = undefined;
    if (msg) {
      const tcRaw: Object = (msg as Record<string, Object>)['tool_calls'];
      if (tcRaw instanceof Array && tcRaw.length > 0) {
        toolCalls = this.convertToToolCallItems(tcRaw as Object[]);
      }
    }

    return {
      id: this.generateId(),
      role: MessageRole.Assistant,
      content: content,
      reasoning_content: reasoning,
      tool_calls: toolCalls,
      timestamp: Date.now(),
    };
  }

  /**
   * ArrayBuffer 转 string（手动循环，ArkTS 兼容）
   */
  private arrayBufferToString(buffer: ArrayBuffer): string {
    const uint8: Uint8Array = new Uint8Array(buffer);
    let result: string = '';
    for (let i: number = 0; i < uint8.length; i++) {
      result = result + String.fromCharCode(uint8[i]);
    }
    return result;
  }

  /**
   * 生成唯一 ID
   */
  private generateId(): string {
    return Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
  }
}

/**
 * 工具调用处理器 - 使用 namespace 模式避免 this 问题
 */
export namespace ToolExecutor {
  /**
   * 获取当前手机系统时间工具
   */
  export function getSystemTime(): string {
    const now: Date = new Date();
    const year: number = now.getFullYear();
    const month: string = String(now.getMonth() + 1).padStart(2, '0');
    const day: string = String(now.getDate()).padStart(2, '0');
    const hours: string = String(now.getHours()).padStart(2, '0');
    const minutes: string = String(now.getMinutes()).padStart(2, '0');
    const seconds: string = String(now.getSeconds()).padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
  }

  /**
   * 执行工具调用，返回结果消息列表
   */
  export function executeToolCalls(toolCalls: ToolCallItem[]): ToolCallResult[] {
    const results: ToolCallResult[] = [];
    for (const tc of toolCalls) {
      const funcName: string = tc.function ? tc.function.name : '';
      let resultContent: string = '';
      if (funcName === 'get_system_time') {
        resultContent = ToolExecutor.getSystemTime();
      } else {
        resultContent = `未知工具: ${funcName}`;
      }
      const tcr: ToolCallResult = {
        role: 'tool',
        content: resultContent,
        tool_call_id: tc.id,
      };
      results.push(tcr);
    }
    return results;
  }

  /**
   * 获取工具定义列表（传给 API）
   */
  export function getToolDefinitions(): ToolDefinition[] {
    const params: ToolParameters = {
      type: 'object',
      properties: new ToolProperties(),
      required: [],
    };

    const funcDef: ToolFunctionDef = {
      name: 'get_system_time',
      description: '获取当前手机系统的日期和时间',
      parameters: params,
    };

    const toolDef: ToolDefinition = {
      type: 'function',
      function: funcDef,
    };

    return [toolDef];
  }
}
