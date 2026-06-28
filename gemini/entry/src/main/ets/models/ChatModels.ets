export interface ChatMessage {
  id: string;
  role: 'system' | 'user' | 'assistant' | 'tool';
  content: string;
  reasoning_content?: string; // DeepSeek Chain of Thought
  tool_calls?: ToolCall[];
  tool_call_id?: string;
  name?: string;
  timestamp: number;
}

export interface ToolCall {
  id: string;
  type: 'function';
  function: ToolFunction;
}

export interface ToolFunction {
  name: string;
  arguments: string; // JSON string
}

export interface ChatSession {
  id: string;
  title: string;
  messages: ChatMessage[];
  timestamp: number;
}

export interface AppSettings {
  apiKey: string;
  baseUrl: string;
  model: 'deepseek-v4-pro' | 'deepseek-v4-flash';
  thinkingEnabled: boolean;
  reasoningEffort: 'high' | 'max';
  toolsEnabled: boolean;
}
