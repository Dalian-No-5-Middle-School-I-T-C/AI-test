import {
  ApiChatMessage,
  AppSettings,
  Conversation,
  DisplayMessage,
  StreamResult,
  ToolCall,
} from '../model/ChatModels';
import { cancelActiveRequest, createMessageId, streamChatCompletion, buildApiMessages } from './DeepSeekService';
import { executeToolCalls } from './ToolExecutor';
import { storageService } from './StorageService';

export interface ChatStreamUpdate {
  reasoningContent: string;
  content: string;
  toolCalls: ToolCall[];
  isStreaming: boolean;
}

export interface ChatCallbacks {
  onStreamUpdate: (update: ChatStreamUpdate) => void;
  onMessageAdded: (message: DisplayMessage) => void;
  onConversationUpdated: (conversation: Conversation) => void;
  onError: (message: string) => void;
  onLoadingChange: (loading: boolean) => void;
}

const MAX_TOOL_ROUNDS = 5;

function displayToApiMessages(messages: DisplayMessage[]): ApiChatMessage[] {
  const result: ApiChatMessage[] = [];
  for (const msg of messages) {
    if (msg.role === 'user') {
      result.push({ role: 'user', content: msg.content });
    } else if (msg.role === 'assistant') {
      const apiMsg: ApiChatMessage = { role: 'assistant', content: msg.content || '' };
      const hasToolCalls = msg.toolCalls !== undefined && msg.toolCalls.length > 0;
      if (hasToolCalls && msg.reasoningContent) {
        apiMsg.reasoning_content = msg.reasoningContent;
      }
      if (hasToolCalls) {
        apiMsg.tool_calls = msg.toolCalls;
      }
      result.push(apiMsg);
    } else if (msg.role === 'tool') {
      result.push({
        role: 'tool',
        content: msg.content,
        tool_call_id: msg.toolCallId ?? '',
        name: msg.toolName ?? '',
      });
    }
  }
  return result;
}

function generateTitle(firstUserMessage: string): string {
  const trimmed = firstUserMessage.trim();
  if (trimmed.length <= 20) {
    return trimmed;
  }
  return trimmed.substring(0, 20) + '...';
}

class ChatManager {
  private conversation: Conversation | null = null;
  private isLoading: boolean = false;
  private abortFlag: boolean = false;

  getConversation(): Conversation | null {
    return this.conversation;
  }

  isRequestLoading(): boolean {
    return this.isLoading;
  }

  async loadConversation(id: string): Promise<Conversation | null> {
    const all = await storageService.getConversations();
    const found = all.find((c) => c.id === id);
    if (found) {
      this.conversation = found;
      await storageService.setCurrentConversationId(id);
    }
    return found ?? null;
  }

  async createNewConversation(): Promise<Conversation> {
    const conv: Conversation = {
      id: createMessageId(),
      title: '新对话',
      messages: [],
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    this.conversation = conv;
    await storageService.setCurrentConversationId(conv.id);
    return conv;
  }

  async ensureConversation(): Promise<Conversation> {
    if (this.conversation) {
      return this.conversation;
    }
    const currentId = await storageService.getCurrentConversationId();
    if (currentId) {
      const loaded = await this.loadConversation(currentId);
      if (loaded) {
        return loaded;
      }
    }
    return await this.createNewConversation();
  }

  private async persistConversation(): Promise<void> {
    if (!this.conversation) {
      return;
    }
    const all = await storageService.getConversations();
    const idx = all.findIndex((c) => c.id === this.conversation!.id);
    this.conversation.updatedAt = Date.now();
    if (idx >= 0) {
      all[idx] = this.conversation;
    } else {
      all.unshift(this.conversation);
    }
    await storageService.saveConversations(all);
  }

  cancelRequest(): void {
    this.abortFlag = true;
    cancelActiveRequest();
    this.isLoading = false;
  }

  async sendMessage(
    userText: string,
    settings: AppSettings,
    callbacks: ChatCallbacks,
  ): Promise<void> {
    if (this.isLoading) {
      return;
    }

    const conv = await this.ensureConversation();
    this.abortFlag = false;
    this.isLoading = true;
    callbacks.onLoadingChange(true);

    const userMsg: DisplayMessage = {
      id: createMessageId(),
      role: 'user',
      content: userText,
      reasoningContent: '',
    };
    conv.messages.push(userMsg);
    callbacks.onMessageAdded(userMsg);

    if (conv.title === '新对话') {
      conv.title = generateTitle(userText);
    }

    await this.persistConversation();

    let apiMessages = buildApiMessages(displayToApiMessages(conv.messages));

    try {
      for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
        if (this.abortFlag) {
          break;
        }

        const streamMsg: DisplayMessage = {
          id: createMessageId(),
          role: 'assistant',
          content: '',
          reasoningContent: '',
          toolCalls: [],
          isStreaming: true,
        };
        conv.messages.push(streamMsg);
        callbacks.onMessageAdded(streamMsg);

        const result = await this.runStreamRound(apiMessages, settings, streamMsg, callbacks);

        streamMsg.isStreaming = false;
        streamMsg.content = result.content;
        streamMsg.reasoningContent = result.reasoningContent;
        streamMsg.toolCalls = result.toolCalls.length > 0 ? result.toolCalls : undefined;

        if (!streamMsg.content && !streamMsg.reasoningContent &&
          (!streamMsg.toolCalls || streamMsg.toolCalls.length === 0)) {
          streamMsg.content = '未收到模型回复，请检查 API Key、模型名称或网络连接。';
        }

        if (this.abortFlag) {
          conv.messages.pop();
          break;
        }

        if (result.toolCalls.length === 0) {
          break;
        }

        const toolResults = executeToolCalls(result.toolCalls);
        for (const tc of result.toolCalls) {
          const toolMsg: DisplayMessage = {
            id: createMessageId(),
            role: 'tool',
            content: toolResults.get(tc.id) ?? '{}',
            reasoningContent: '',
            toolCallId: tc.id,
            toolName: tc.function.name,
          };
          conv.messages.push(toolMsg);
          callbacks.onMessageAdded(toolMsg);
        }

        apiMessages = buildApiMessages(displayToApiMessages(conv.messages));
      }

      await this.persistConversation();
      callbacks.onConversationUpdated(conv);
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : '未知错误';
      callbacks.onError(errMsg);
      await this.persistConversation();
      callbacks.onConversationUpdated(conv);
    } finally {
      this.isLoading = false;
      callbacks.onLoadingChange(false);
    }
  }

  private runStreamRound(
    apiMessages: ApiChatMessage[],
    settings: AppSettings,
    streamMsg: DisplayMessage,
    callbacks: ChatCallbacks,
  ): Promise<StreamResult> {
    return streamChatCompletion(apiMessages, settings, {
      onReasoning: (text: string) => {
        streamMsg.reasoningContent += text;
        callbacks.onStreamUpdate({
          reasoningContent: streamMsg.reasoningContent,
          content: streamMsg.content,
          toolCalls: streamMsg.toolCalls ?? [],
          isStreaming: true,
        });
      },
      onContent: (text: string) => {
        streamMsg.content += text;
        callbacks.onStreamUpdate({
          reasoningContent: streamMsg.reasoningContent,
          content: streamMsg.content,
          toolCalls: streamMsg.toolCalls ?? [],
          isStreaming: true,
        });
      },
      onToolCallsUpdate: (toolCalls: ToolCall[]) => {
        streamMsg.toolCalls = toolCalls;
        callbacks.onStreamUpdate({
          reasoningContent: streamMsg.reasoningContent,
          content: streamMsg.content,
          toolCalls: toolCalls,
          isStreaming: true,
        });
      },
      onDone: (_finishReason: string) => {
        callbacks.onStreamUpdate({
          reasoningContent: streamMsg.reasoningContent,
          content: streamMsg.content,
          toolCalls: streamMsg.toolCalls ?? [],
          isStreaming: false,
        });
      },
      onError: (message: string) => {
        callbacks.onError(message);
      },
    });
  }

  async deleteConversation(id: string): Promise<void> {
    const all = await storageService.getConversations();
    const filtered = all.filter((c) => c.id !== id);
    await storageService.saveConversations(filtered);
    if (this.conversation?.id === id) {
      this.conversation = null;
      await storageService.setCurrentConversationId('');
    }
  }

  setConversation(conv: Conversation): void {
    this.conversation = conv;
  }

  clearCurrentConversation(): void {
    this.conversation = null;
  }
}

export const chatManager = new ChatManager();
