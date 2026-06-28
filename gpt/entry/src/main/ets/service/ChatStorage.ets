import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSettings, Conversation, DEFAULT_SETTINGS } from '../model/ChatModels';

const STORE_NAME: string = 'deepchat_data';

export class ChatStorage {
  static async loadSettings(context: common.UIAbilityContext): Promise<AppSettings> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      const text: string = await store.get('settings', '') as string;
      if (text.length > 0) return JSON.parse(text) as AppSettings;
    } catch (_) {}
    return { apiKey: DEFAULT_SETTINGS.apiKey, model: DEFAULT_SETTINGS.model, thinkingEnabled: DEFAULT_SETTINGS.thinkingEnabled, reasoningEffort: DEFAULT_SETTINGS.reasoningEffort };
  }
  static async saveSettings(context: common.UIAbilityContext, settings: AppSettings): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put('settings', JSON.stringify(settings));
    await store.flush();
  }
  static async loadConversations(context: common.UIAbilityContext): Promise<Conversation[]> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      const text: string = await store.get('conversations', '[]') as string;
      return JSON.parse(text) as Conversation[];
    } catch (_) { return []; }
  }
  static async saveConversations(context: common.UIAbilityContext, items: Conversation[]): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put('conversations', JSON.stringify(items));
    await store.flush();
  }
}
