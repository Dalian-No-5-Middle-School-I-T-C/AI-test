// ChatModels.ets - 数据模型定义（ArkTS 兼容版）
import { ESObject } from '@ohos.arkts.lang';

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
 * 单条聊天消息
 */
export interface ChatMessage {
  role: MessageRole;
  content: string;
  reasoning_content?: string;
  tool_calls?: ESObject[];
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
 * 工具定义（传给 API）
 */
export interface ToolDefinition {
  type: string;
  function: {
    name: string;
    description: string;
    parameters: Object;
  };
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
