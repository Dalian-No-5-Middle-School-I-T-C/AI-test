export type ChatRole = 'system' | 'user' | 'assistant' | 'tool';

export interface ToolFunction {
  name: string;
  arguments: string;
}

export interface ToolCall {
  id: string;
  type: string;
  function: ToolFunction;
}

export interface ApiChatMessage {
  role: string;
  content?: string;
  reasoning_content?: string;
  tool_calls?: ToolCall[];
  tool_call_id?: string;
  name?: string;
}

export interface DisplayMessage {
  id: string;
  role: ChatRole;
  content: string;
  reasoningContent: string;
  toolCalls?: ToolCall[];
  toolCallId?: string;
  toolName?: string;
  isStreaming?: boolean;
}

export interface Conversation {
  id: string;
  title: string;
  messages: DisplayMessage[];
  createdAt: number;
  updatedAt: number;
}

export interface AppSettings {
  apiKey: string;
  model: string;
  thinkingEnabled: boolean;
  reasoningEffort: string;
}

export interface StreamCallbacks {
  onReasoning: (text: string) => void;
  onContent: (text: string) => void;
  onToolCallsUpdate: (toolCalls: ToolCall[]) => void;
  onDone: (finishReason: string) => void;
  onError: (message: string) => void;
}

export interface StreamResult {
  content: string;
  reasoningContent: string;
  toolCalls: ToolCall[];
  finishReason: string;
}

export const DEFAULT_SETTINGS: AppSettings = {
  apiKey: '',
  model: 'deepseek-v4-pro',
  thinkingEnabled: true,
  reasoningEffort: 'high',
};

export const MODEL_OPTIONS: string[] = [
  'deepseek-v4-pro',
  'deepseek-v4-flash',
];

export const REASONING_EFFORT_OPTIONS: string[] = ['high', 'max'];
