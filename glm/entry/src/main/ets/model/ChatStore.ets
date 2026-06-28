import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSettings, ChatMessage, HistoryItem, ThinkingType, ReasoningEffort, ModelId } from './Types';

const PREF_NAME: string = 'dschat_prefs';
const KEY_API_KEY: string = 'api_key';
const KEY_MODEL: string = 'model';
const KEY_THINKING: string = 'thinking_type';
const KEY_EFFORT: string = 'reasoning_effort';
const KEY_SYSTEM: string = 'system_prompt';
const KEY_HISTORY: string = 'history';

const DEFAULT_SYSTEM: string = 'You are a helpful assistant.';

export async function loadSettings(ctx: common.Context): Promise<AppSettings> {
  const pref: preferences.Preferences = await preferences.getPreferences(ctx, PREF_NAME);
  const apiKey: string = (await pref.get(KEY_API_KEY, '')).toString();
  const modelStr: string = (await pref.get(KEY_MODEL, 'deepseek-v4-pro')).toString();
  const thinkingStr: string = (await pref.get(KEY_THINKING, 'enabled')).toString();
  const effortStr: string = (await pref.get(KEY_EFFORT, 'high')).toString();
  const system: string = (await pref.get(KEY_SYSTEM, DEFAULT_SYSTEM)).toString();

  const model: ModelId = modelStr === 'deepseek-v4-flash' ? 'deepseek-v4-flash' : 'deepseek-v4-pro';
  const thinkingType: ThinkingType = thinkingStr === 'disabled' ? 'disabled' : 'enabled';
  const reasoningEffort: ReasoningEffort = effortStr === 'max' ? 'max' : 'high';

  return {
    apiKey: apiKey,
    model: model,
    thinkingType: thinkingType,
    reasoningEffort: reasoningEffort,
    systemPrompt: system
  };
}

export async function saveSettings(ctx: common.Context, s: AppSettings): Promise<void> {
  const pref: preferences.Preferences = await preferences.getPreferences(ctx, PREF_NAME);
  await pref.put(KEY_API_KEY, s.apiKey);
  await pref.put(KEY_MODEL, s.model);
  await pref.put(KEY_THINKING, s.thinkingType);
  await pref.put(KEY_EFFORT, s.reasoningEffort);
  await pref.put(KEY_SYSTEM, s.systemPrompt);
  await pref.flush();
}

export async function saveHistory(ctx: common.Context, messages: ChatMessage[]): Promise<void> {
  const pref: preferences.Preferences = await preferences.getPreferences(ctx, PREF_NAME);
  const items: HistoryItem[] = [];
  for (let i = 0; i < messages.length; i++) {
    const m: ChatMessage = messages[i];
    items.push({
      id: m.id,
      role: m.role,
      content: m.content,
      reasoningContent: m.reasoningContent,
      isToolCall: m.isToolCall,
      toolCalls: m.toolCalls,
      toolCallId: m.toolCallId,
      isError: m.isError,
      timestamp: m.timestamp
    });
  }
  await pref.put(KEY_HISTORY, JSON.stringify(items));
  await pref.flush();
}

export async function loadHistory(ctx: common.Context): Promise<ChatMessage[]> {
  const pref: preferences.Preferences = await preferences.getPreferences(ctx, PREF_NAME);
  const raw: string = (await pref.get(KEY_HISTORY, '[]')).toString();
  if (raw.length === 0) {
    return [];
  }
  const parsed: HistoryItem[] = JSON.parse(raw) as HistoryItem[];
  const result: ChatMessage[] = [];
  for (let i = 0; i < parsed.length; i++) {
    const item: HistoryItem = parsed[i];
    const m: ChatMessage = new ChatMessage(item.id, item.role, item.content);
    m.reasoningContent = item.reasoningContent;
    m.isToolCall = item.isToolCall;
    m.toolCalls = item.toolCalls;
    m.toolCallId = item.toolCallId;
    m.isError = item.isError;
    m.timestamp = item.timestamp;
    result.push(m);
  }
  return result;
}
