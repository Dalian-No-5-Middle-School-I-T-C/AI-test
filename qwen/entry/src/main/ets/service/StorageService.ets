import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Conversation } from '../model/ChatModel';

const STORE_NAME = 'dschat_store';

export class AppSettings {
  apiKey: string = '';
  model: string = 'deepseek-v4-pro';
  thinkingEnabled: boolean = true;
  reasoningEffort: string = 'high';
}

export class StorageService {
  static async saveConversations(context: common.UIAbilityContext,
    conversations: Array<Conversation>): Promise<void> {
    let store = await preferences.getPreferences(context, STORE_NAME);
    await store.put('conversations', JSON.stringify(conversations));
    await store.flush();
  }

  static async loadConversations(context: common.UIAbilityContext): Promise<Array<Conversation>> {
    let store = await preferences.getPreferences(context, STORE_NAME);
    let data = await store.get('conversations', '[]') as string;
    return JSON.parse(data) as Array<Conversation>;
  }

  static async saveSettings(context: common.UIAbilityContext,
    settings: AppSettings): Promise<void> {
    let store = await preferences.getPreferences(context, STORE_NAME);
    await store.put('settings', JSON.stringify(settings));
    await store.flush();
  }

  static async loadSettings(context: common.UIAbilityContext): Promise<AppSettings> {
    let store = await preferences.getPreferences(context, STORE_NAME);
    let data = await store.get('settings', '') as string;
    if (data.length === 0) {
      return new AppSettings();
    }
    return JSON.parse(data) as AppSettings;
  }

  static async deleteConversation(context: common.UIAbilityContext, convId: string): Promise<void> {
    let conversations = await StorageService.loadConversations(context);
    let filtered: Array<Conversation> = [];
    for (let i = 0; i < conversations.length; i++) {
      if (conversations[i].id !== convId) {
        filtered.push(conversations[i]);
      }
    }
    await StorageService.saveConversations(context, filtered);
  }
}
