export type ChatRole = 'system' | 'user' | 'assistant' | 'tool';

export interface ChatMessage {
  id: string;
  role: ChatRole;
  content: string;
  reasoningContent?: string;
  toolCalls?: ToolCall[];
  toolCallId?: string;
  isStreaming?: boolean;
  model?: string;
}

export interface ToolCallFunction {
  name: string;
  arguments: string;
}

export interface ToolCall {
  id: string;
  type: 'function';
  function: ToolCallFunction;
  index?: number;
}

export interface Conversation {
  id: string;
  title: string;
  messages: ChatMessage[];
  createTime: number;
  updateTime: number;
  model: string;
  thinkingEnabled: boolean;
  reasoningEffort: 'high' | 'max';
}

export interface DeepSeekMessage {
  role: string;
  content: string;
  reasoning_content?: string;
  tool_calls?: ToolCall[];
  tool_call_id?: string;
  name?: string;
}

export interface ThinkingOptions {
  type: 'enabled' | 'disabled';
}

export interface DeepSeekRequest {
  model: string;
  messages: DeepSeekMessage[];
  stream: boolean;
  thinking?: ThinkingOptions;
  reasoning_effort?: 'high' | 'max';
  tools?: DeepSeekTool[];
}

export interface ToolParameterProperty {
  type: string;
  description: string;
  enum?: string[];
}

export interface TimeToolParameterMap {
  format: ToolParameterProperty;
}

export interface ToolParameters {
  type: string;
  properties: TimeToolParameterMap;
  required: string[];
}

export interface ToolFunction {
  name: string;
  description: string;
  parameters: ToolParameters;
}

export interface DeepSeekTool {
  type: 'function';
  function: ToolFunction;
}

export interface DeepSeekDelta {
  content?: string;
  reasoning_content?: string;
  role?: string;
  tool_calls?: ToolCall[];
}

export interface ChoiceMessage {
  role: string;
  content: string;
  reasoning_content?: string;
  tool_calls?: ToolCall[];
}

export interface DeepSeekChoice {
  index: number;
  delta: DeepSeekDelta;
  finish_reason?: string;
  message?: ChoiceMessage;
}

export interface DeepSeekStreamChunk {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: DeepSeekChoice[];
}

export const AVAILABLE_MODELS: string[] = ['deepseek-v4-pro', 'deepseek-v4-flash'];
