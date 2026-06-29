// ChatModels.ets - 数据模型定义（ArkTS 严格模式最终版）
/**
 * 聊天消息角色（字符串枚举，值与 DeepSeek API 一致）
 */
export enum MessageRole {
  System = 'system',
  User = 'user',
  Assistant = 'assistant',
  Tool = 'tool'
}

/**
 * ToolCallItem 中的 function 字段
 */
export interface ToolCallItemFunction {
  name: string;
  arguments: string;
}

/**
 * 工具调用项（API 返回）
 */
export interface ToolCallItem {
  id: string;
  type: string;
  function: ToolCallItemFunction;
}

/**
 * 单条聊天消息
 */
export interface ChatMessage {
  id: string;
  role: MessageRole;
  content: string;
  reasoning_content?: string;
  tool_calls?: ToolCallItem[];
  tool_call_id?: string;
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
  parameters: ToolParameters;
}

/**
 * 工具参数定义
 */
export interface ToolParameters {
  type: string;
  properties: ToolProperties;
  required: string[];
}

/**
 * 工具属性（用 class 包装，ArkTS 严格模式要求对象字面量对应显式类/接口）
 */
export class ToolProperties {
  constructor() {}
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
