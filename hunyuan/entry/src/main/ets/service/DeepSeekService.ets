// DeepSeekService.ets - DeepSeek API 服务层（ArkTS 严格模式最终版）
import http from '@ohos.net.http';
import { BusinessError } from '@kit.BasicServicesKit';
import util from '@ohos.util';
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
  tool_call_id?: string;
}

/**
 * thinking 配置（对应 DeepSeek thinking 参数）
 */
export class ThinkingConfig {
  type: string = 'enabled';

  constructor(type: string) {
    this.type = type;
  }
}

/**
 * API 请求体格式
 */
export interface ApiRequestBody {
  model: string;
  messages: ApiMessage[];
  stream: boolean;
  thinking?: ThinkingConfig;
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
 * 采用非流式请求，拿到完整回复后一次性回调 onContent
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
   * 聊天请求（非流式，直接返回完整内容）
   */
  async chat(
    messages: ChatMessage[],
    model: string,
    thinkingEnabled: boolean,
    reasoningEffort: string,
    callbacks: StreamCallbacks,
    tools?: ToolDefinition[]
  ): Promise<void> {
    const httpRequest: http.HttpRequest = http.createHttp();
    const body: string = this.buildRequestBody(messages, model, thinkingEnabled, reasoningEffort, tools);

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.apiKey}`,
    };

    try {
      const data: http.HttpResponse = await httpRequest.request(BASE_URL, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
      });
      httpRequest.destroy();

      if (data.responseCode !== 200) {
        const errMsg: string = `API 错误 ${data.responseCode}: ${data.result}`;
        if (callbacks.onError) callbacks.onError(errMsg);
        return;
      }

      const result: Object = JSON.parse(data.result as string);
      const choices: Object[] = getObjArr(result, 'choices');
      if (!choices || choices.length === 0) {
        if (callbacks.onError) callbacks.onError('无效的 API 响应：无 choices');
        return;
      }

      const choice: Object = choices[0];
      const msgObj: Object | undefined = (choice as Record<string, Object>)['message'];
      const content: string = msgObj ? getStr(msgObj, 'content') : '';
      const reasoning: string = msgObj ? getStr(msgObj, 'reasoning_content') : '';

      // 回调思考内容
      if (reasoning && callbacks.onReasoning) {
        callbacks.onReasoning(reasoning);
      }

      // 回调正文内容（一次性传出全文）
      if (content && callbacks.onContent) {
        callbacks.onContent(content);
      }

      // 检查是否有工具调用
      if (msgObj) {
        const tcRaw: Object = (msgObj as Record<string, Object>)['tool_calls'];
        if (tcRaw instanceof Array && tcRaw.length > 0) {
          const toolCalls: ToolCallItem[] = this.convertToToolCallItems(tcRaw as Object[]);
          if (callbacks.onToolCall) callbacks.onToolCall(toolCalls);
        }
      }

      if (callbacks.onDone) callbacks.onDone();

    } catch (e) {
      httpRequest.destroy();
      const errMsg: string = `请求失败: ${(e as Error).message}`;
      if (callbacks.onError) callbacks.onError(errMsg);
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
    const apiMessages: ApiMessage[] = [];
    for (const m of messages) {
      const msg: ApiMessage = {
        role: m.role.toString(),
        content: m.content,
      };
      if (m.tool_calls && m.tool_calls.length > 0) {
        msg.tool_calls = m.tool_calls;
      }
      if (m.tool_call_id && m.tool_call_id.length > 0) {
        msg.tool_call_id = m.tool_call_id;
      }
      apiMessages.push(msg);
    }

    const body: ApiRequestBody = {
      model: model,
      messages: apiMessages,
      stream: false,
    };

    if (thinkingEnabled) {
      body.thinking = new ThinkingConfig('enabled');
      body.reasoning_effort = reasoningEffort;
    } else {
      body.thinking = new ThinkingConfig('disabled');
    }

    if (tools && tools.length > 0) {
      body.tools = tools;
      body.tool_choice = 'auto';
    }

    return JSON.stringify(body);
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
