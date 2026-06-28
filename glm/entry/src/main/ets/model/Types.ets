export type Role = 'system' | 'user' | 'assistant' | 'tool';

export type ThinkingType = 'enabled' | 'disabled';

export type ReasoningEffort = 'high' | 'max';

export type ModelId = 'deepseek-v4-flash' | 'deepseek-v4-pro';

export interface AppSettings {
  apiKey: string;
  model: ModelId;
  thinkingType: ThinkingType;
  reasoningEffort: ReasoningEffort;
  systemPrompt: string;
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

export interface ToolFunctionDef {
  name: string;
  description: string;
  parameters: Record<string, Object>;
}

export interface ToolDef {
  type: string;
  function: ToolFunctionDef;
}

export interface ApiMessage {
  role: string;
  content?: string;
  tool_calls?: ToolCall[];
  tool_call_id?: string;
}

export interface ThinkingConfig {
  type: string;
}

export interface ChatRequestBody {
  model: string;
  messages: ApiMessage[];
  stream: boolean;
  thinking?: ThinkingConfig;
  reasoning_effort?: string;
  tools?: ToolDef[];
  tool_choice?: string;
}

export interface StreamCallbacks {
  onReasoning: (chunk: string) => void;
  onContent: (chunk: string) => void;
  onToolCalls: (toolCalls: ToolCall[]) => void;
  onDone: () => void;
  onError: (message: string) => void;
}

export interface HistoryItem {
  id: string;
  role: string;
  content: string;
  reasoningContent: string;
  isToolCall: boolean;
  toolCalls: ToolCall[];
  toolCallId: string;
  isError: boolean;
  timestamp: number;
}

@Observed
export class ChatMessage {
  id: string;
  role: string;
  content: string;
  reasoningContent: string;
  isThinking: boolean;
  isToolCall: boolean;
  toolCalls: ToolCall[];
  toolCallId: string;
  isError: boolean;
  timestamp: number;

  constructor(id: string, role: string, content: string) {
    this.id = id;
    this.role = role;
    this.content = content;
    this.reasoningContent = '';
    this.isThinking = false;
    this.isToolCall = false;
    this.toolCalls = [];
    this.toolCallId = '';
    this.isError = false;
    this.timestamp = Date.now();
  }
}

export function genId(): string {
  return Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
}
