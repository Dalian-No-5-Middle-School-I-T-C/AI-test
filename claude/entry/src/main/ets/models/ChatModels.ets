// 数据模型定义

// 思考深度档位
export type ReasoningEffort = 'high' | 'max';

// 模型 ID
export type ModelId = 'deepseek-v4-flash' | 'deepseek-v4-pro';

// 消息角色
export type MessageRole = 'system' | 'user' | 'assistant' | 'tool';

// 工具调用结构（OpenAI 兼容格式）
export interface ToolCallFunction {
  name: string;
  arguments: string;
}

export interface ToolCall {
  id: string;
  type: string; // 通常为 "function"
  function: ToolCallFunction;
}

// 发送给 API 的单条消息（请求体格式）
export interface ApiMessage {
  role: MessageRole;
  content: string;
  // assistant 消息可能携带工具调用
  tool_calls?: ToolCall[];
  // tool 消息需要回填对应的调用 id
  tool_call_id?: string;
}

// UI 展示用的消息（包含思考内容、流式状态等）
@Observed
export class ChatMessage {
  id: string;
  role: MessageRole;
  // 正式回答内容
  content: string;
  // 思考过程内容
  reasoning: string;
  // 是否处于流式生成中
  streaming: boolean;
  // 思考是否展开显示
  reasoningExpanded: boolean;
  // 是否发生错误
  isError: boolean;
  // 工具调用记录（用于展示与回传）
  toolCalls: ToolCall[];
  // tool 角色消息对应的调用 id
  toolCallId: string;
  // 工具调用的可读描述（仅 UI 展示）
  toolLabel: string;
  // 创建时间戳
  timestamp: number;

  constructor(role: MessageRole, content: string) {
    this.id = `${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    this.role = role;
    this.content = content;
    this.reasoning = '';
    this.streaming = false;
    this.reasoningExpanded = true;
    this.isError = false;
    this.toolCalls = [];
    this.toolCallId = '';
    this.toolLabel = '';
    this.timestamp = Date.now();
  }
}

// 一段对话会话
export interface Conversation {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messages: SerializableMessage[];
}

// 可序列化的消息（持久化用，不含运行时瞬态字段）
export interface SerializableMessage {
  id: string;
  role: MessageRole;
  content: string;
  reasoning: string;
  isError: boolean;
  toolCalls: ToolCall[];
  toolCallId: string;
  toolLabel: string;
  timestamp: number;
}

// 应用设置
export interface AppSettings {
  apiKey: string;
  model: ModelId;
  thinkingEnabled: boolean;
  reasoningEffort: ReasoningEffort;
}

export const DEFAULT_SETTINGS: AppSettings = {
  apiKey: '',
  model: 'deepseek-v4-pro',
  thinkingEnabled: true,
  reasoningEffort: 'high'
};

export const SYSTEM_PROMPT: string = 'You are a helpful assistant. 你是一个有帮助的助手，请使用中文回答用户问题。';

// 序列化 / 反序列化辅助
export function toSerializable(msg: ChatMessage): SerializableMessage {
  return {
    id: msg.id,
    role: msg.role,
    content: msg.content,
    reasoning: msg.reasoning,
    isError: msg.isError,
    toolCalls: msg.toolCalls,
    toolCallId: msg.toolCallId,
    toolLabel: msg.toolLabel,
    timestamp: msg.timestamp
  };
}

export function fromSerializable(s: SerializableMessage): ChatMessage {
  const msg = new ChatMessage(s.role, s.content);
  msg.id = s.id;
  msg.reasoning = s.reasoning;
  msg.isError = s.isError;
  msg.toolCalls = s.toolCalls ?? [];
  msg.toolCallId = s.toolCallId ?? '';
  msg.toolLabel = s.toolLabel ?? '';
  msg.timestamp = s.timestamp;
  msg.reasoningExpanded = false;
  return msg;
}
