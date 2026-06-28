export type MessageRole = 'system' | 'user' | 'assistant' | 'tool'

export interface FunctionCall {
  name: string
  arguments: string
}

export interface Message {
  id: string
  role: MessageRole
  content: string
  thinking?: string
  timestamp: number
  toolCalls?: ToolCall[]
  toolCallId?: string
}

export interface ToolCall {
  id: string
  type: 'function'
  function: FunctionCall
}

export interface Conversation {
  id: string
  title: string
  messages: Message[]
  createdAt: number
  updatedAt: number
}

export type ModelType = 'deepseek-v4-flash' | 'deepseek-v4-pro'
export type ReasoningEffort = 'high' | 'max'

export interface AppSettings {
  apiKey: string
  model: ModelType
  thinkingEnabled: boolean
  reasoningEffort: ReasoningEffort
  systemPrompt: string
}

export const DEFAULT_SETTINGS: AppSettings = {
  apiKey: '',
  model: 'deepseek-v4-pro',
  thinkingEnabled: true,
  reasoningEffort: 'high',
  systemPrompt: '你是一个有用的AI助手。'
}