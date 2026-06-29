// ChatModels.ets - 数据模型定义（ArkTS 严格模式兼容）
/**
 * 聊天消息角色
 */
export enum MessageRole {
  System = 'system',
  User = 'user',
  Assistant = 'assistant',
  Tool = 'tool'
}

/**
 * 工具调用项（API 返回）
 */
export interface ToolCallItem {
  id: string;
  type: string;
  function: {
    name: string;
    arguments: string;
  };
}

/**
 * 单条聊天消息
 */
export interface ChatMessage {
  role: MessageRole;
  content: string;
  reasoning_content?: string;
  tool_calls?: ToolCallItem[];
  id: string;
  timestamp: number;
}

/**
 * 会话（一次对话）
 */
export interface Conversation {
  id: string;
  title: string;
  messages: ChatMessage[];
  model: string;
  thinkingEnabled: boolean;
  reasoningEffort: string;
  createdAt: number;
  updatedAt: number;
}

/**
 * 工具定义中的 function 字段
 */
export interface ToolFunctionDef {
  name: string;
  description: string;
  parameters: Record<string, Object>;
}

/**
 * 工具定义（传给 API）
 */
export interface ToolDefinition {
  type: string;
  function: ToolFunctionDef;
}

/**
 * 设置项
 */
export interface AppSettings {
  apiKey: string;
  model: string;
  thinkingEnabled: boolean;
  reasoningEffort: string;
}

/**
 * 工具调用结果（传给 API）
 */
export interface ToolCallResult {
  role: string;
  content: string;
  tool_call_id: string;
}
