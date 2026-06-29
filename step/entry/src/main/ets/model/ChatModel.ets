export enum UserRole {
  USER = 'user',
  ASSISTANT = 'assistant',
  SYSTEM = 'system',
}

export enum ThinkDepth {
  OFF = 'off',
  HIGH = 'high',
  MAX = 'max',
}

export class Message {
  role: UserRole = UserRole.USER
  content: string = ''
  reasoningContent: string = ''
  reasoningVisible: boolean = false
  timestamp: number = 0
  id: string = ''
}

export class ChatConfig {
  model: string = 'deepseek-v4-flash'
  thinkDepth: ThinkDepth = ThinkDepth.OFF
  apiKey: string = ''
}
