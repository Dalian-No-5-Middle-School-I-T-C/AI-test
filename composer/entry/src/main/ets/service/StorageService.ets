import { preferences } from '@kit.ArkData';
import { AppSettings, Conversation, DEFAULT_SETTINGS } from '../model/ChatModels';

const PREF_NAME = 'deepseek_chat_prefs';
const KEY_API_KEY = 'api_key';
const KEY_MODEL = 'model';
const KEY_THINKING = 'thinking_enabled';
const KEY_EFFORT = 'reasoning_effort';
const KEY_CONVERSATIONS = 'conversations';
const KEY_CURRENT_CONV_ID = 'current_conversation_id';

class StorageService {
  private pref: preferences.Preferences | null = null;
  private initPromise: Promise<void> | null = null;

  init(context: Context): Promise<void> {
    if (this.initPromise !== null) {
      return this.initPromise;
    }
    this.initPromise = preferences.getPreferences(context, PREF_NAME).then((pref) => {
      this.pref = pref;
    });
    return this.initPromise;
  }

  private async ensurePref(): Promise<preferences.Preferences> {
    if (this.initPromise !== null) {
      await this.initPromise;
    }
    if (this.pref === null) {
      throw new Error('StorageService not initialized');
    }
    return this.pref;
  }

  async getSettings(): Promise<AppSettings> {
    const pref = await this.ensurePref();
    const apiKey = await pref.get(KEY_API_KEY, '') as string;
    const model = await pref.get(KEY_MODEL, DEFAULT_SETTINGS.model) as string;
    const thinkingEnabled = await pref.get(KEY_THINKING, DEFAULT_SETTINGS.thinkingEnabled) as boolean;
    const reasoningEffort = await pref.get(KEY_EFFORT, DEFAULT_SETTINGS.reasoningEffort) as string;
    return { apiKey, model, thinkingEnabled, reasoningEffort };
  }

  async saveSettings(settings: AppSettings): Promise<void> {
    const pref = await this.ensurePref();
    await pref.put(KEY_API_KEY, settings.apiKey);
    await pref.put(KEY_MODEL, settings.model);
    await pref.put(KEY_THINKING, settings.thinkingEnabled);
    await pref.put(KEY_EFFORT, settings.reasoningEffort);
    await pref.flush();
  }

  async getConversations(): Promise<Conversation[]> {
    const pref = await this.ensurePref();
    const raw = await pref.get(KEY_CONVERSATIONS, '[]') as string;
    try {
      const list = JSON.parse(raw) as Conversation[];
      return list.sort((a, b) => b.updatedAt - a.updatedAt);
    } catch (_e) {
      return [];
    }
  }

  async saveConversations(conversations: Conversation[]): Promise<void> {
    const pref = await this.ensurePref();
    await pref.put(KEY_CONVERSATIONS, JSON.stringify(conversations));
    await pref.flush();
  }

  async getCurrentConversationId(): Promise<string> {
    const pref = await this.ensurePref();
    return await pref.get(KEY_CURRENT_CONV_ID, '') as string;
  }

  async setCurrentConversationId(id: string): Promise<void> {
    const pref = await this.ensurePref();
    await pref.put(KEY_CURRENT_CONV_ID, id);
    await pref.flush();
  }
}

export const storageService = new StorageService();
