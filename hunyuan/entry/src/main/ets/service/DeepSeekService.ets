// DeepSeekService.ets - DeepSeek API 服务层（ArkTS 严格模式兼容版）
import http from '@ohos.net.http';
import { BusinessError } from '@kit.BasicServicesKit';
import { ChatMessage, MessageRole, ToolCallItem, ToolDefinition, ToolCallResult } from '../model/ChatModels';

const BASE_URL: string = 'https://api.deepseek.com/chat/completions';

/**
 * 流式输出回调接口
 */
export interface StreamCallbacks {
  onReasoning?: (text: string) => void;
  onContent?: (text: string) => void;
  onToolCall?: (toolCalls: Object) => void;
  onDone?: () => void;
  onError?: (err: string) => void;
}

/**
 * SSE 解析辅助：从 JSON.parse 结果中按 key 取字符串
 */
function getStr(obj: Object, key: string): string {
  const val: Object = (obj as Record<string, Object>)[key];
  if (val === undefined || val === null) return '';
  return String(val);
}

/**
 * SSE 解析辅助：从 JSON.parse 结果中按 key 取对象数组
 */
function getArr(obj: Object, key: string): Object[] {
  const val: Object = (obj as Record<string, Object>)[key];
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
    return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void, reject: (reason?: Object) => void) => {
      const httpRequest: http.HttpRequest = http.createHttp();
      const body: string = this.buildRequestBody(messages, model, thinkingEnabled, reasoningEffort, tools, true);

      let buffer: string = '';

      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        const chunk: string = this.arrayBufferToString(data);
        buffer = buffer + chunk;
        const lines: string[] = buffer.split('\n');
        buffer = lines.pop() || '';
        for (const line of lines) {
          this.handleSSELine(line, callbacks);
        }
      });

      httpRequest.on('dataEnd', () => {
        if (buffer.trim()) {
          this.handleSSELine(buffer, callbacks);
        }
        httpRequest.destroy();
        if (callbacks.onDone) callbacks.onDone();
        resolve();
      });

      // 注意：ArkTS 的 HttpRequest 不支持 'error' 事件
      // 错误处理通过 requestInStream 的回调进行

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`,
        'Accept': 'text/event-stream',
      };

      try {
        httpRequest.requestInStream(BASE_URL, {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: body,
          expectDataType: http.HttpDataType.STRING,
        }, (err: BusinessError, data: http.HttpResponse) => {
          if (err) {
            httpRequest.destroy();
            const msg: string = `请求失败: ${err.code} ${err.message}`;
            if (callbacks.onError) callbacks.onError(msg);
            reject(new Error(msg));
          }
          // 检查 HTTP 状态码
          if (data.responseCode !== 200) {
            httpRequest.destroy();
            const errMsg: string = `API 错误 ${data.responseCode}: ${data.result}`;
            if (callbacks.onError) callbacks.onError(errMsg);
            reject(new Error(errMsg));
          }
        });
      } catch (e) {
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
    return new Promise<ChatMessage>((resolve: (value: ChatMessage | PromiseLike<ChatMessage>) => void, reject: (reason?: Object) => void) => {
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
      const choices: Object[] = getArr(chunk, 'choices');
      if (!choices || choices.length === 0) return;

      const choice: Object = choices[0];
      const delta: Object = (choice as Record<string, Object>)['delta'];

      if (delta) {
        const reasoningText: string = getStr(delta, 'reasoning_content');
        if (reasoningText && callbacks.onReasoning) {
          callbacks.onReasoning(reasoningText);
        }

        const contentText: string = getStr(delta, 'content');
        if (contentText && callbacks.onContent) {
          callbacks.onContent(contentText);
        }

        const toolCalls: Object = (delta as Record<string, Object>)['tool_calls'];
        if (toolCalls && callbacks.onToolCall) {
          callbacks.onToolCall(toolCalls);
        }
      }
    } catch {
      // 忽略无法解析的行
    }
  }

  /**
   * 构建请求体
   */
  private buildRequestBody(
    messages: ChatMessage[],
    model: string,
    thinkingEnabled: boolean,
    reasoningEffort: string,
    tools?: ToolDefinition[],
    stream: boolean = false
  ): string {
    const apiMessages: Record<string, Object>[] = messages.map((m: ChatMessage): Record<string, Object> => {
      const msg: Record<string, Object> = {
        role: m.role.toString(),
        content: m.content,
      };
      if (m.tool_calls && m.tool_calls.length > 0) {
        msg['tool_calls'] = m.tool_calls;
      }
      return msg;
    });

    const body: Record<string, Object> = {
      model: model,
      messages: apiMessages,
      stream: stream,
    };

    if (thinkingEnabled) {
      body['thinking'] = { type: 'enabled' };
      body['reasoning_effort'] = reasoningEffort;
    } else {
      body['thinking'] = { type: 'disabled' };
    }

    if (tools && tools.length > 0) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }

    return JSON.stringify(body);
  }

  /**
   * 解析非流式响应
   */
  private parseNonStreamResponse(response: Object): ChatMessage {
    const choices: Object[] = getArr(response, 'choices');
    if (!choices || choices.length === 0) {
      throw new Error('无效的 API 响应：无 choices');
    }

    const choice: Object = choices[0];
    const msg: Object = (choice as Record<string, Object>)['message'];

    return {
      id: this.generateId(),
      role: MessageRole.Assistant,
      content: msg ? getStr(msg, 'content') : '',
      reasoning_content: msg ? getStr(msg, 'reasoning_content') : '',
      tool_calls: msg ? (msg as Record<string, Object>)['tool_calls'] as ToolCallItem[] | undefined : undefined,
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
 * 工具调用处理器 - 执行本地工具
 * 使用命名空间模式避免 this 问题
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
  export function executeToolCalls(toolCalls: Object[]): ToolCallResult[] {
    const results: ToolCallResult[] = [];
    for (const tc of toolCalls) {
      const funcObj: Object = (tc as Record<string, Object>)['function'];
      const funcName: string = funcObj ? getStr(funcObj, 'name') : '';
      let resultContent: string = '';
      if (funcName === 'get_system_time') {
        resultContent = ToolExecutor.getSystemTime();
      } else {
        resultContent = `未知工具: ${funcName}`;
      }
      results.push({
        role: 'tool',
        content: resultContent,
        tool_call_id: (tc as Record<string, Object>)['id'] as string,
      } as ToolCallResult);
    }
    return results;
  }

  /**
   * 获取工具定义列表（传给 API）
   */
  export function getToolDefinitions(): ToolDefinition[] {
    const params: Record<string, Object> = {
      type: 'object',
      properties: {} as Record<string, Object>,
      required: [] as string[],
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
