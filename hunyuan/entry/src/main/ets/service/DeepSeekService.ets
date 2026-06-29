// DeepSeekService.ets - DeepSeek API 服务层（ArkTS 兼容版）
import http from '@ohos.net.http';
import { BusinessError } from '@kit.BasicServicesKit';
import { ChatMessage, MessageRole, ToolDefinition, ToolCallResult } from '../model/ChatModels';

const BASE_URL = 'https://api.deepseek.com/chat/completions';

/**
 * 流式输出回调接口
 */
export interface StreamCallbacks {
  onReasoning?: (text: string) => void;
  onContent?: (text: string) => void;
  onToolCall?: (toolCalls: ESObject) => void;
  onDone?: () => void;
  onError?: (err: string) => void;
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
   * 使用 requestInStream 实现真正的流式输出
   */
  async chatStream(
    messages: ChatMessage[],
    model: string,
    thinkingEnabled: boolean,
    reasoningEffort: string,
    callbacks: StreamCallbacks,
    tools?: ToolDefinition[]
  ): Promise<void> {
    return new Promise((resolve, reject) => {
      const httpRequest = http.createHttp();
      const body = this.buildRequestBody(messages, model, thinkingEnabled, reasoningEffort, tools, true);

      let buffer = '';

      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        const chunk = this.arrayBufferToString(data);
        buffer += chunk;
        const lines = buffer.split('\n');
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
        callbacks.onDone?.();
        resolve();
      });

      httpRequest.on('error', (err: BusinessError) => {
        httpRequest.destroy();
        const msg = `网络错误: ${err.code} ${err.message}`;
        callbacks.onError?.(msg);
        reject(new Error(msg));
      });

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`,
        'Accept': 'text/event-stream',
      };

      // requestInStream 正确签名：requestInStream(url: string, options: HttpRequestOptions): void
      try {
        httpRequest.requestInStream(BASE_URL, {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: body,
          expectDataType: http.HttpDataType.STRING,
        });
      } catch (e) {
        callbacks.onError?.(`请求异常: ${(e as Error).message}`);
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
    return new Promise((resolve, reject) => {
      const httpRequest = http.createHttp();
      const body = this.buildRequestBody(messages, model, thinkingEnabled, reasoningEffort, tools, false);

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
          const result = JSON.parse(data.result as string);
          const assistantMsg = this.parseNonStreamResponse(result);
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
    const trimmed = line.trim();
    if (!trimmed.startsWith('data:')) {
      return;
    }

    const dataStr = trimmed.substring(5).trim();
    if (dataStr === '[DONE]') {
      return;
    }

    try {
      const chunk: ESObject = JSON.parse(dataStr);
      const choices = chunk['choices'];
      if (!choices || choices.length === 0) return;

      const choice = choices[0];
      const delta = choice['delta'];

      if (delta && delta['reasoning_content'] && callbacks.onReasoning) {
        callbacks.onReasoning(delta['reasoning_content']);
      }

      if (delta && delta['content'] && callbacks.onContent) {
        callbacks.onContent(delta['content']);
      }

      if (delta && delta['tool_calls'] && callbacks.onToolCall) {
        callbacks.onToolCall(delta['tool_calls']);
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
    const apiMessages: ESObject[] = messages.map(m => {
      const msg: ESObject = {
        role: m.role.toString(),
        content: m.content,
      };
      if (m.tool_calls && m.tool_calls.length > 0) {
        msg['tool_calls'] = m.tool_calls;
      }
      return msg;
    });

    const body: ESObject = {
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
  private parseNonStreamResponse(response: ESObject): ChatMessage {
    const choices = response['choices'];
    if (!choices || choices.length === 0) {
      throw new Error('无效的 API 响应：无 choices');
    }

    const choice = choices[0];
    const msg = choice['message'];
    return {
      id: this.generateId(),
      role: MessageRole.Assistant,
      content: msg ? (msg['content'] || '') : '',
      reasoning_content: msg ? (msg['reasoning_content'] || '') : '',
      tool_calls: msg ? (msg['tool_calls'] || undefined) : undefined,
      timestamp: Date.now(),
    };
  }

  /**
   * ArrayBuffer 转 string（兼容 ArkTS）
   */
  private arrayBufferToString(buffer: ArrayBuffer): string {
    const uint8 = new Uint8Array(buffer);
    let result = '';
    for (let i = 0; i < uint8.length; i++) {
      result += String.fromCharCode(uint8[i]);
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
 */
export class ToolExecutor {
  static getSystemTime(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const seconds = String(now.getSeconds()).padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
  }

  static executeToolCalls(toolCalls: ESObject[]): ToolCallResult[] {
    const results: ToolCallResult[] = [];
    for (const tc of toolCalls) {
      const funcName = tc['function'] ? (tc['function']['name'] || '') : '';
      let resultContent = '';
      if (funcName === 'get_system_time') {
        resultContent = this.getSystemTime();
      } else {
        resultContent = `未知工具: ${funcName}`;
      }
      results.push({
        role: 'tool',
        content: resultContent,
        tool_call_id: tc['id'],
      } as ESObject as ToolCallResult);
    }
    return results;
  }

  static getToolDefinitions(): ToolDefinition[] {
    return [
      {
        type: 'function',
        function: {
          name: 'get_system_time',
          description: '获取当前手机系统的日期和时间',
          parameters: {
            type: 'object',
            properties: {},
            required: [],
          },
        },
      },
    ];
  }
}
