// DeepSeek 流式聊天客户端（自实现 HTTP + SSE 解析，不依赖 OpenAI SDK）
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ApiMessage, ModelId, ReasoningEffort, ToolCall } from '../models/ChatModels';
import { ToolDef } from '../tools/Tools';

const BASE_URL: string = 'https://api.deepseek.com/chat/completions';

// 流式回调接口
export interface StreamCallbacks {
  // 收到一段思考内容增量
  onReasoning: (delta: string) => void;
  // 收到一段正式回答内容增量
  onContent: (delta: string) => void;
  // 流结束，回传完整的工具调用（如有）
  onDone: (toolCalls: ToolCall[]) => void;
  // 出错
  onError: (message: string) => void;
}

// 请求参数
export interface ChatRequestParams {
  apiKey: string;
  model: ModelId;
  messages: ApiMessage[];
  thinkingEnabled: boolean;
  reasoningEffort: ReasoningEffort;
  tools: ToolDef[];
}

// ---- 用于解析增量 tool_calls 的内部累积结构 ----
interface ToolCallAccumulator {
  id: string;
  type: string;
  name: string;
  arguments: string;
}

// SSE delta 中的 function 片段
interface DeltaFunction {
  name?: string;
  arguments?: string;
}

interface DeltaToolCall {
  index?: number;
  id?: string;
  type?: string;
  function?: DeltaFunction;
}

interface DeltaObject {
  content?: string;
  reasoning_content?: string;
  tool_calls?: DeltaToolCall[];
}

interface ChoiceObject {
  delta?: DeltaObject;
  finish_reason?: string;
}

interface StreamChunk {
  choices?: ChoiceObject[];
}

// 构造请求体
interface ThinkingConfig {
  type: string;
}

function buildRequestBody(params: ChatRequestParams): string {
  // 使用 Record 动态拼装，便于条件性加入字段
  const body: Record<string, Object> = {};
  body['model'] = params.model;
  body['messages'] = params.messages;
  body['stream'] = true;
  body['tools'] = params.tools;

  if (params.thinkingEnabled) {
    const thinking: ThinkingConfig = { type: 'enabled' };
    body['thinking'] = thinking;
    body['reasoning_effort'] = params.reasoningEffort;
  } else {
    const thinking: ThinkingConfig = { type: 'disabled' };
    body['thinking'] = thinking;
  }
  return JSON.stringify(body);
}

// 单次请求的会话状态。每次 streamChat 创建一个独立实例，
// 这样嵌套的多轮请求（工具调用后续写）互不干扰，
// 一轮的清理不会误伤另一轮的 http 请求。
class StreamSession {
  request: http.HttpRequest;
  cb: StreamCallbacks;
  buffer: string = '';
  toolAcc: Map<number, ToolCallAccumulator> = new Map();
  finished: boolean = false;
  cancelled: boolean = false;
  decoder: util.TextDecoder;
  // 是否收到过任何正文 / 思考增量（用于判断本轮是否真的产出了内容）
  sawContent: boolean = false;
  sawReasoning: boolean = false;
  // 完整原始响应文本（用于在静默失败时把服务端的真实报错暴露出来）
  rawBody: string = '';
  // 本轮发送的请求体（用于诊断：静默失败时回看实际发了什么）
  requestBody: string = '';

  constructor(request: http.HttpRequest, cb: StreamCallbacks) {
    this.request = request;
    this.cb = cb;
    this.decoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
  }
}

export class DeepSeekService {
  // 当前活跃的会话（仅用于 cancel）；新一轮会覆盖旧引用
  private session: StreamSession | null = null;

  // 取消正在进行的流
  cancel(): void {
    const s = this.session;
    if (s) {
      s.cancelled = true;
      this.destroyRequest(s);
    }
  }

  // 发起流式聊天
  streamChat(params: ChatRequestParams, cb: StreamCallbacks): void {
    const request = http.createHttp();
    const session = new StreamSession(request, cb);
    this.session = session;

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${params.apiKey}`,
      'Accept': 'text/event-stream'
    };

    const body: string = buildRequestBody(params);
    session.requestBody = body;

    // 流式数据回调
    request.on('dataReceive', (data: ArrayBuffer) => {
      if (session.cancelled) {
        return;
      }
      const chunk: string = this.decodeChunk(session, data);
      // 累积原始响应（用于静默失败时暴露服务端真实报错）
      session.rawBody += chunk;
      session.buffer += chunk;
      this.processBuffer(session);
    });

    // 流结束回调
    request.on('dataEnd', () => {
      if (session.cancelled) {
        return;
      }
      this.finalize(session);
    });

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      readTimeout: 120000,
      connectTimeout: 30000
    };

    request.requestInStream(BASE_URL, options).then((statusCode: number) => {
      if (session.cancelled) {
        this.destroyRequest(session);
        return;
      }
      // 非 2xx：requestInStream 不一定有响应体回调，需手动处理错误
      if (statusCode < 200 || statusCode >= 300) {
        if (!session.finished) {
          session.finished = true;
          this.destroyRequest(session);
          const raw: string = session.rawBody.trim();
          const detail: string = raw.length > 0 ? `\n响应体: ${raw}` : '';
          session.cb.onError(`请求失败，HTTP 状态码: ${statusCode}。${detail}\n\n[本轮请求体] ${session.requestBody}`);
        }
      }
    }).catch((err: Object) => {
      if (session.cancelled) {
        this.destroyRequest(session);
        return;
      }
      if (!session.finished) {
        session.finished = true;
        this.destroyRequest(session);
        session.cb.onError(`网络请求异常: ${this.errToString(err)}`);
      }
    });
  }

  // 处理缓冲区中完整的 SSE 行
  private processBuffer(session: StreamSession): void {
    let newlineIndex: number = session.buffer.indexOf('\n');
    while (newlineIndex !== -1) {
      let line: string = session.buffer.substring(0, newlineIndex);
      session.buffer = session.buffer.substring(newlineIndex + 1);
      // 去除可能的 \r
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      this.handleLine(session, line.trim());
      // finalize 之后停止继续处理
      if (session.finished) {
        return;
      }
      newlineIndex = session.buffer.indexOf('\n');
    }
  }

  // 处理单行 SSE
  private handleLine(session: StreamSession, line: string): void {
    if (line.length === 0) {
      return;
    }
    if (!line.startsWith('data:')) {
      return;
    }
    const payload: string = line.substring(5).trim();
    if (payload === '[DONE]') {
      this.finalize(session);
      return;
    }
    this.parseChunk(session, payload);
  }

  // 解析单个 JSON chunk
  private parseChunk(session: StreamSession, payload: string): void {
    let chunk: StreamChunk;
    try {
      chunk = JSON.parse(payload) as StreamChunk;
    } catch (e) {
      // 不完整或非 JSON 行，忽略
      return;
    }
    const choices: ChoiceObject[] | undefined = chunk.choices;
    if (!choices || choices.length === 0) {
      return;
    }
    const delta: DeltaObject | undefined = choices[0].delta;
    if (!delta) {
      return;
    }
    // 思考内容
    if (delta.reasoning_content !== undefined && delta.reasoning_content !== null) {
      session.sawReasoning = true;
      session.cb.onReasoning(delta.reasoning_content);
    }
    // 正式内容
    if (delta.content !== undefined && delta.content !== null) {
      session.sawContent = true;
      session.cb.onContent(delta.content);
    }
    // 工具调用增量
    if (delta.tool_calls && delta.tool_calls.length > 0) {
      this.accumulateToolCalls(session, delta.tool_calls);
    }
  }

  // 累积工具调用增量片段
  private accumulateToolCalls(session: StreamSession, deltas: DeltaToolCall[]): void {
    for (const d of deltas) {
      const idx: number = d.index ?? 0;
      let acc: ToolCallAccumulator | undefined = session.toolAcc.get(idx);
      if (!acc) {
        acc = { id: '', type: 'function', name: '', arguments: '' };
        session.toolAcc.set(idx, acc);
      }
      if (d.id) {
        acc.id = d.id;
      }
      if (d.type) {
        acc.type = d.type;
      }
      if (d.function) {
        if (d.function.name) {
          acc.name += d.function.name;
        }
        if (d.function.arguments) {
          acc.arguments += d.function.arguments;
        }
      }
    }
  }

  // 结束流，组装 tool_calls 并回调。
  // 关键顺序：先销毁本会话的请求，再触发 onDone —— 因为 onDone 可能同步
  // 发起下一轮 streamChat，若顺序颠倒会把下一轮的新请求误销毁。
  private finalize(session: StreamSession): void {
    if (session.finished) {
      return;
    }
    session.finished = true;

    const toolCalls: ToolCall[] = [];
    // 收集 index 并升序输出
    const indices: number[] = [];
    session.toolAcc.forEach((_acc: ToolCallAccumulator, key: number) => {
      indices.push(key);
    });
    indices.sort((a: number, b: number) => a - b);
    for (const i of indices) {
      const acc: ToolCallAccumulator | undefined = session.toolAcc.get(i);
      if (acc && acc.name.length > 0) {
        toolCalls.push({
          id: acc.id.length > 0 ? acc.id : `call_${i}_${Date.now()}`,
          type: acc.type.length > 0 ? acc.type : 'function',
          function: {
            name: acc.name,
            arguments: acc.arguments.length > 0 ? acc.arguments : '{}'
          }
        });
      }
    }

    // 先清理本轮请求资源，再回调
    this.destroyRequest(session);

    // 静默失败检测：既无内容、无思考、也无工具调用 —— 通常是 API 返回了
    // 非流式的错误响应（如 400/401 的 JSON），其内容不是 data: 行而被忽略。
    // 把原始响应体作为错误抛出，避免界面无任何反馈。
    if (toolCalls.length === 0 && !session.sawContent && !session.sawReasoning) {
      const raw: string = session.rawBody.trim();
      const msg: string = raw.length > 0
        ? `服务端返回了非预期内容：${raw}\n\n[本轮请求体] ${session.requestBody}`
        : '服务端未返回任何内容（空响应）。请检查模型 ID、思考参数与网络。';
      session.cb.onError(msg);
      return;
    }

    session.cb.onDone(toolCalls);
  }

  // 销毁指定会话的 http 请求（只动它自己的 request）
  private destroyRequest(session: StreamSession): void {
    try {
      session.request.off('dataReceive');
      session.request.off('dataEnd');
      session.request.destroy();
    } catch (e) {
      // 忽略
    }
  }

  // ArrayBuffer (UTF-8) -> string
  // 使用会话级解码器 + stream 模式，正确拼接跨分片的多字节字符（如中文）
  private decodeChunk(session: StreamSession, buf: ArrayBuffer): string {
    return session.decoder.decodeToString(new Uint8Array(buf), { stream: true });
  }

  private errToString(err: Object): string {
    try {
      return JSON.stringify(err);
    } catch (e) {
      return 'unknown error';
    }
  }
}
