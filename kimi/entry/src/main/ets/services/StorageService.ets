import { preferences } from '@kit.ArkData';
import { Conversation } from '../models/ChatModels';

const PREF_NAME = 'deepseek_chat_prefs';
const KEY_API_KEY = 'api_key';
const KEY_DEFAULT_MODEL = 'default_model';
const KEY_THINKING_ENABLED = 'thinking_enabled';
const KEY_REASONING_EFFORT = 'reasoning_effort';
const KEY_CONVERSATIONS = 'conversations';
const KEY_CURRENT_CONVERSATION_ID = 'current_conversation_id';

export class StorageService {
  private context: Context;
  private pref: preferences.Preferences | null = null;

  constructor(context: Context) {
    this.context = context;
  }

  private async getPref(): Promise<preferences.Preferences> {
    if (this.pref) {
      return this.pref;
    }
    this.pref = await preferences.getPreferences(this.context, PREF_NAME);
    return this.pref;
  }

  async setApiKey(apiKey: string): Promise<void> {
    const pref = await this.getPref();
    await pref.put(KEY_API_KEY, apiKey);
    await pref.flush();
  }

  async getApiKey(): Promise<string> {
    const pref = await this.getPref();
    const value = await pref.get(KEY_API_KEY, '');
    return value as string;
  }

  async setDefaultModel(model: string): Promise<void> {
    const pref = await this.getPref();
    await pref.put(KEY_DEFAULT_MODEL, model);
    await pref.flush();
  }

  async getDefaultModel(): Promise<string> {
    const pref = await this.getPref();
    const value = await pref.get(KEY_DEFAULT_MODEL, 'deepseek-v4-pro');
    return value as string;
  }

  async setThinkingEnabled(enabled: boolean): Promise<void> {
    const pref = await this.getPref();
    await pref.put(KEY_THINKING_ENABLED, enabled);
    await pref.flush();
  }

  async getThinkingEnabled(): Promise<boolean> {
    const pref = await this.getPref();
    const value = await pref.get(KEY_THINKING_ENABLED, true);
    return value as boolean;
  }

  async setReasoningEffort(effort: 'high' | 'max'): Promise<void> {
    const pref = await this.getPref();
    await pref.put(KEY_REASONING_EFFORT, effort);
    await pref.flush();
  }

  async getReasoningEffort(): Promise<'high' | 'max'> {
    const pref = await this.getPref();
    const value = await pref.get(KEY_REASONING_EFFORT, 'high');
    return (value as string) === 'max' ? 'max' : 'high';
  }

  async setCurrentConversationId(id: string): Promise<void> {
    const pref = await this.getPref();
    await pref.put(KEY_CURRENT_CONVERSATION_ID, id);
    await pref.flush();
  }

  async getCurrentConversationId(): Promise<string> {
    const pref = await this.getPref();
    const value = await pref.get(KEY_CURRENT_CONVERSATION_ID, '');
    return value as string;
  }

  async saveConversations(conversations: Conversation[]): Promise<void> {
    const pref = await this.getPref();
    await pref.put(KEY_CONVERSATIONS, JSON.stringify(conversations));
    await pref.flush();
  }

  async getConversations(): Promise<Conversation[]> {
    const pref = await this.getPref();
    const raw = await pref.get(KEY_CONVERSATIONS, '[]');
    try {
      return JSON.parse(raw as string) as Conversation[];
    } catch (e) {
      return [];
    }
  }

  async deleteConversation(id: string): Promise<void> {
    const conversations = await this.getConversations();
    const filtered = conversations.filter(item => item.id !== id);
    await this.saveConversations(filtered);
  }

  async clearAll(): Promise<void> {
    const pref = await this.getPref();
    await pref.clear();
    await pref.flush();
    this.pref = null;
  }
}
