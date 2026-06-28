export type ChatRole = 'system' | 'user' | 'assistant' | 'tool';
export type ModelId = 'deepseek-v4-flash' | 'deepseek-v4-pro';
export type ReasoningEffort = 'high' | 'max';

export interface ToolFunctionCall { name: string; arguments: string; }
export interface ToolCall { id: string; type: 'function'; function: ToolFunctionCall; }
export interface ChatMessage {
  role: ChatRole;
  content: string;
  reasoning?: string;
  toolCalls?: ToolCall[];
  toolCallId?: string;
  name?: string;
  createdAt: number;
}
export interface Conversation { id: string; title: string; updatedAt: number; messages: ChatMessage[]; }
export interface AppSettings { apiKey: string; model: ModelId; thinkingEnabled: boolean; reasoningEffort: ReasoningEffort; }

export const DEFAULT_SETTINGS: AppSettings = {
  apiKey: '', model: 'deepseek-v4-pro', thinkingEnabled: true, reasoningEffort: 'high'
};

export interface ToolParameters { type: 'object'; properties: Record<string, string>; required: string[]; }
export interface ToolFunction { name: string; description: string; parameters: ToolParameters; }
export interface ToolDefinition { type: 'function'; function: ToolFunction; }
export const TIME_TOOL: ToolDefinition = {
  type: 'function',
  function: {
    name: 'get_current_system_time',
    description: 'Get the current date and time from the user phone system.',
    parameters: { type: 'object', properties: {}, required: [] }
  }
};

function pad(value: number): string { return value < 10 ? '0' + value.toString() : value.toString(); }

export function executeTool(name: string): string {
  if (name !== 'get_current_system_time') return JSON.stringify({ error: 'Unknown tool: ' + name });
  const now: Date = new Date();
  const value: string = now.getFullYear().toString() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate()) +
    ' ' + pad(now.getHours()) + ':' + pad(now.getMinutes()) + ':' + pad(now.getSeconds());
  return JSON.stringify({ local_time: value, timestamp_ms: now.getTime() });
}
