export interface ChatMessage {
  id: string;
  role: string;
  content: string;
  reasoningContent: string;
  toolCalls: ToolCallInfo[];
  toolCallId: string;
  timestamp: number;
}

export interface ToolCallInfo {
  id: string;
  type: string;
  functionName: string;
  functionArgs: string;
  result: string;
}

export interface Conversation {
  id: string;
  title: string;
  messages: ChatMessage[];
  model: string;
  createdAt: number;
  updatedAt: number;
}

export interface ConversationSummary {
  id: string;
  title: string;
  lastMessage: string;
  createdAt: number;
  updatedAt: number;
  model: string;
}
