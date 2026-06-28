import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSettings, ChatSession } from '../models/ChatModels';

export class PreferencesManager {
  private static readonly PREF_NAME = 'DeepSeekChatPrefs';
  private static readonly KEY_SETTINGS = 'AppSettings';
  private static readonly KEY_SESSIONS = 'ChatSessions';

  private static getPrefs(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PreferencesManager.PREF_NAME });
  }

  static getSettings(context: common.Context): AppSettings {
    const prefs = PreferencesManager.getPrefs(context);
    const defaultSettings: AppSettings = {
      apiKey: '',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-v4-pro',
      thinkingEnabled: true,
      reasoningEffort: 'high',
      toolsEnabled: true
    };

    try {
      const jsonStr = prefs.getSync(PreferencesManager.KEY_SETTINGS, '') as string;
      if (jsonStr) {
        const obj = JSON.parse(jsonStr) as Record<string, Object>;
        if (obj) {
          return {
            apiKey: (obj.apiKey as string) ?? '',
            baseUrl: (obj.baseUrl as string) ?? 'https://api.deepseek.com',
            model: ((obj.model as string) === 'deepseek-v4-flash' ? 'deepseek-v4-flash' : 'deepseek-v4-pro') as 'deepseek-v4-pro' | 'deepseek-v4-flash',
            thinkingEnabled: (obj.thinkingEnabled as boolean) ?? true,
            reasoningEffort: ((obj.reasoningEffort as string) === 'max' ? 'max' : 'high') as 'high' | 'max',
            toolsEnabled: (obj.toolsEnabled as boolean) ?? true
          };
        }
      }
    } catch (e) {
      console.error('[Prefs] Error loading settings', JSON.stringify(e));
    }
    return defaultSettings;
  }

  static saveSettings(context: common.Context, settings: AppSettings): void {
    try {
      const prefs = PreferencesManager.getPrefs(context);
      prefs.putSync(PreferencesManager.KEY_SETTINGS, JSON.stringify(settings));
      prefs.flushSync();
    } catch (e) {
      console.error('[Prefs] Error saving settings', JSON.stringify(e));
    }
  }

  static getSessions(context: common.Context): ChatSession[] {
    const prefs = PreferencesManager.getPrefs(context);
    try {
      const jsonStr = prefs.getSync(PreferencesManager.KEY_SESSIONS, '') as string;
      if (jsonStr) {
        const sessions = JSON.parse(jsonStr) as ChatSession[];
        if (Array.isArray(sessions)) {
          return sessions;
        }
      }
    } catch (e) {
      console.error('[Prefs] Error loading sessions', JSON.stringify(e));
    }
    return [];
  }

  static saveSessions(context: common.Context, sessions: ChatSession[]): void {
    try {
      const prefs = PreferencesManager.getPrefs(context);
      prefs.putSync(PreferencesManager.KEY_SESSIONS, JSON.stringify(sessions));
      prefs.flushSync();
    } catch (e) {
      console.error('[Prefs] Error saving sessions', JSON.stringify(e));
    }
  }
}
