// StorageService.ets - 本地存储服务（ArkTS 严格模式最终版）
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { AppSettings, Conversation } from '../model/ChatModels';

type Context = common.Context;

const SETTINGS_KEY: string = 'app_settings';
const CONVERSATIONS_KEY: string = 'conversations';
const PREF_NAME: string = 'dschat_pref';

let _prefContext: Context | undefined = undefined;

/**
 * 初始化存储上下文
 * 在 UI 页面的 aboutToAppear 中调用一次：
 *   initStorageContext(getContext(this) as Context)
 */
export function initStorageContext(ctx: Context): void {
  _prefContext = ctx;
}

function getPrefContext(): Context {
  if (!_prefContext) {
    throw new Error('StorageService 未初始化，请先调用 initStorageContext(getContext(this))');
  }
  return _prefContext;
}

async function getPreferences(): Promise<preferences.Preferences> {
  const ctx: Context = getPrefContext();
  return preferences.getPreferences(ctx, PREF_NAME);
}

/**
 * 保存设置
 */
export async function saveSettings(settings: AppSettings): Promise<void> {
  const pref: preferences.Preferences = await getPreferences();
  await pref.put(SETTINGS_KEY, JSON.stringify(settings));
  await pref.flush();
}

/**
 * 读取设置
 */
export async function loadSettings(): Promise<AppSettings | null> {
  const pref: preferences.Preferences = await getPreferences();
  const val: preferences.ValueType = await pref.get(SETTINGS_KEY, '');
  if (!val) return null;
  try {
    const str: string = typeof val === 'string' ? val : String(val);
    return JSON.parse(str) as AppSettings;
  } catch {
    return null;
  }
}

/**
 * 获取默认设置
 */
export function getDefaultSettings(): AppSettings {
  return {
    apiKey: '',
    model: 'deepseek-v4-pro',
    thinkingEnabled: true,
    reasoningEffort: 'high',
  };
}

/**
 * 保存所有会话
 */
export async function saveConversations(conversations: Conversation[]): Promise<void> {
  const pref: preferences.Preferences = await getPreferences();
  await pref.put(CONVERSATIONS_KEY, JSON.stringify(conversations));
  await pref.flush();
}

/**
 * 读取所有会话
 */
export async function loadConversations(): Promise<Conversation[]> {
  const pref: preferences.Preferences = await getPreferences();
  const val: preferences.ValueType = await pref.get(CONVERSATIONS_KEY, '[]');
  if (!val) return [];
  try {
    const str: string = typeof val === 'string' ? val : String(val);
    return JSON.parse(str) as Conversation[];
  } catch {
    return [];
  }
}

/**
 * 删除指定会话
 */
export async function deleteConversation(conversationId: string): Promise<void> {
  const conversations: Conversation[] = await loadConversations();
  const filtered: Conversation[] = conversations.filter(
    (c: Conversation): boolean => c.id !== conversationId
  );
  await saveConversations(filtered);
}

/**
 * 生成唯一 ID
 */
export function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
}
