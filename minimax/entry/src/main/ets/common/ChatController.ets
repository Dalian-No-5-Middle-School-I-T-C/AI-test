import {
  AppSettings,
  ChatMessage,
  Conversation,
  newId,
  nowMillis,
  readObject,
  writeObject,
  ToolCall
} from './Storage';

const KEY_SETTINGS = 'settings_v1';
const KEY_CONVERSATIONS = 'conversations_v1';

export class ChatController {
  private static instance: ChatController | null = null;

  static get(): ChatController {
    if (!ChatController.instance) {
      ChatController.instance = new ChatController();
    }
    return ChatController.instance;
  }

  settings: AppSettings = new AppSettings();

  conversations: Conversation[] = [];

  currentConversationId: string = '';

  load(): void {
    const s = readObject<AppSettings>(KEY_SETTINGS, this.settings);
    this.settings = s;
    if (!this.settings.baseUrl || this.settings.baseUrl.length === 0) {
      this.settings.baseUrl = 'https://api.deepseek.com';
    }
    if (this.settings.reasoningEffort !== 'high' && this.settings.reasoningEffort !== 'max') {
      this.settings.reasoningEffort = 'high';
    }
    const list = readObject<Conversation[]>(KEY_CONVERSATIONS, []);
    this.conversations = list;
  }

  saveSettings(): void {
    writeObject(KEY_SETTINGS, this.settings);
  }

  saveConversations(): void {
    writeObject(KEY_CONVERSATIONS, this.conversations);
  }

  getCurrentConversation(): Conversation | null {
    if (this.currentConversationId.length === 0) {
      return null;
    }
    for (let i = 0; i < this.conversations.length; i++) {
      if (this.conversations[i].id === this.currentConversationId) {
        return this.conversations[i];
      }
    }
    return null;
  }

  startNewConversation(): Conversation {
    const c = new Conversation();
    c.id = newId();
    c.title = '新对话';
    c.model = this.settings.model;
    c.thinkingEnabled = this.settings.thinkingEnabled;
    c.reasoningEffort = this.settings.reasoningEffort;
    c.systemPrompt = this.settings.systemPrompt;
    c.createdAt = nowMillis();
    c.updatedAt = nowMillis();
    this.conversations.unshift(c);
    this.currentConversationId = c.id;
    this.saveConversations();
    return c;
  }

  ensureCurrent(): Conversation {
    const cur = this.getCurrentConversation();
    if (cur) {
      return cur;
    }
    return this.startNewConversation();
  }

  setCurrentById(id: string): Conversation | null {
    for (let i = 0; i < this.conversations.length; i++) {
      if (this.conversations[i].id === id) {
        this.currentConversationId = id;
        return this.conversations[i];
      }
    }
    return null;
  }

  deleteConversation(id: string): void {
    const next: Conversation[] = [];
    for (let i = 0; i < this.conversations.length; i++) {
      if (this.conversations[i].id !== id) {
        next.push(this.conversations[i]);
      }
    }
    this.conversations = next;
    if (this.currentConversationId === id) {
      this.currentConversationId = '';
    }
    this.saveConversations();
  }

  clearCurrentMessages(): void {
    const cur = this.getCurrentConversation();
    if (!cur) {
      return;
    }
    cur.messages = [];
    cur.updatedAt = nowMillis();
    this.saveConversations();
  }

  appendMessage(msg: ChatMessage): void {
    const cur = this.ensureCurrent();
    cur.messages.push(msg);
    cur.updatedAt = nowMillis();
    if (cur.title === '新对话' && msg.role === 'user' && msg.content.length > 0) {
      const t = msg.content.replace(/\s+/g, ' ').trim();
      cur.title = t.length > 30 ? t.substring(0, 30) + '…' : t;
    }
    this.saveConversations();
  }

  updateLastAssistant(content: string, reasoning: string, toolCalls: ToolCall[]): void {
    const cur = this.getCurrentConversation();
    if (!cur) {
      return;
    }
    if (cur.messages.length === 0) {
      return;
    }
    const last = cur.messages[cur.messages.length - 1];
    if (last.role !== 'assistant') {
      return;
    }
    last.content = content;
    if (reasoning.length > 0) {
      last.reasoning = reasoning;
    }
    if (toolCalls.length > 0) {
      last.toolCalls = toolCalls;
    }
    cur.updatedAt = nowMillis();
    this.saveConversations();
  }
}

export function maskKey(k: string): string {
  if (k.length <= 8) {
    return '••••';
  }
  return `${k.substring(0, 4)}••••${k.substring(k.length - 4)}`;
}