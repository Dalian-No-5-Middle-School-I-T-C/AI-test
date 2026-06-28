export enum MessageRole {
  SYSTEM = 'system',
  USER = 'user',
  ASSISTANT = 'assistant',
  TOOL = 'tool'
}

export interface ToolCallFunction {
  name: string;
  arguments: string;
}

export interface ToolCall {
  id: string;
  type: string;
  function: ToolCallFunction;
}

export interface ChatMessage {
  id: string;
  role: MessageRole;
  content: string;
  thinkingContent?: string;
  timestamp: number;
  toolCallId?: string;
  toolName?: string;
  toolCalls?: ToolCall[];
}

export interface ToolParamProperty {
  type?: string;
  description?: string;
}

export interface ToolParameters {
  type: string;
  properties: Record<string, ToolParamProperty>;
  required: string[];
}

export interface ToolFunctionDef {
  name: string;
  description: string;
  parameters: ToolParameters;
}

export interface ToolDefinition {
  type: string;
  function: ToolFunctionDef;
}

export interface ChatSession {
  id: string;
  title: string;
  messages: ChatMessage[];
  model: string;
  reasoningEffort: string;
  thinkingEnabled: boolean;
  createdAt: number;
  updatedAt: number;
}

export interface ToolCallInfo {
  id: string;
  type: string;
  functionName: string;
  functionArguments: string;
}

export interface ApiMessage {
  role: string;
  content: string;
  tool_call_id?: string;
  tool_calls?: ToolCall[];
}

export interface DeltaContent {
  thinking?: string;
  content?: string;
  tool_calls?: ToolCallDeltaItem[];
}

export interface ToolCallDeltaItem {
  index?: number;
  id?: string;
  type?: string;
  function?: ToolCallDeltaFunction;
}

export interface ToolCallDeltaFunction {
  name?: string;
  arguments?: string;
}

export interface SSEChoice {
  delta?: DeltaContent;
  finish_reason?: string;
}

export interface SSEResponse {
  choices?: SSEChoice[];
  error?: SSEError;
}

export interface SSEError {
  message: string;
  type?: string;
}
