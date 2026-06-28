// 持久化存储：设置 + 会话历史
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSettings, DEFAULT_SETTINGS, Conversation, ModelId, ReasoningEffort } from '../models/ChatModels';

const STORE_NAME: string = 'deepseek_chat_store';
const KEY_SETTINGS: string = 'app_settings';
const KEY_CONVERSATIONS: string = 'conversations';

// 单例式存储管理
export class Storage {
  private static store: preferences.Preferences | null = null;

  // 初始化（在 Ability/页面启动时调用一次）
  static async init(context: common.UIAbilityContext): Promise<void> {
    if (Storage.store) {
      return;
    }
    const options: preferences.Options = { name: STORE_NAME };
    Storage.store = await preferences.getPreferences(context, options);
  }

  private static ensure(): preferences.Preferences {
    if (!Storage.store) {
      throw new Error('Storage 未初始化，请先调用 Storage.init()');
    }
    return Storage.store;
  }

  // ---- 设置 ----
  static async loadSettings(): Promise<AppSettings> {
    const store = Storage.ensure();
    const raw = await store.get(KEY_SETTINGS, '') as string;
    if (!raw) {
      return {
        apiKey: DEFAULT_SETTINGS.apiKey,
        model: DEFAULT_SETTINGS.model,
        thinkingEnabled: DEFAULT_SETTINGS.thinkingEnabled,
        reasoningEffort: DEFAULT_SETTINGS.reasoningEffort
      };
    }
    try {
      const parsed = JSON.parse(raw) as AppSettings;
      return {
        apiKey: parsed.apiKey ?? '',
        model: (parsed.model ?? DEFAULT_SETTINGS.model) as ModelId,
        thinkingEnabled: parsed.thinkingEnabled ?? DEFAULT_SETTINGS.thinkingEnabled,
        reasoningEffort: (parsed.reasoningEffort ?? DEFAULT_SETTINGS.reasoningEffort) as ReasoningEffort
      };
    } catch (e) {
      return {
        apiKey: DEFAULT_SETTINGS.apiKey,
        model: DEFAULT_SETTINGS.model,
        thinkingEnabled: DEFAULT_SETTINGS.thinkingEnabled,
        reasoningEffort: DEFAULT_SETTINGS.reasoningEffort
      };
    }
  }

  static async saveSettings(settings: AppSettings): Promise<void> {
    const store = Storage.ensure();
    await store.put(KEY_SETTINGS, JSON.stringify(settings));
    await store.flush();
  }

  // ---- 会话历史 ----
  static async loadConversations(): Promise<Conversation[]> {
    const store = Storage.ensure();
    const raw = await store.get(KEY_CONVERSATIONS, '') as string;
    if (!raw) {
      return [];
    }
    try {
      const list = JSON.parse(raw) as Conversation[];
      return list ?? [];
    } catch (e) {
      return [];
    }
  }

  static async saveConversations(list: Conversation[]): Promise<void> {
    const store = Storage.ensure();
    await store.put(KEY_CONVERSATIONS, JSON.stringify(list));
    await store.flush();
  }
}
