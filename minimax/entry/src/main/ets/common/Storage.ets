import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export class ToolCallFunction {
  name: string = '';
  arguments: string = '';
}

export class ToolCall {
  id: string = '';
  type: 'function' = 'function';
  function: ToolCallFunction = new ToolCallFunction();
}

export class ChatMessage {
  role: 'system' | 'user' | 'assistant' | 'tool' = 'user';
  content: string = '';
  reasoning: string = '';
  toolCallId: string = '';
  toolCalls: ToolCall[] = [];
  name: string = '';
}

export class Conversation {
  id: string = '';
  title: string = '新对话';
  model: string = '';
  thinkingEnabled: boolean = true;
  reasoningEffort: 'high' | 'max' | '' = 'high';
  systemPrompt: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;
  messages: ChatMessage[] = [];
}

export class AppSettings {
  apiKey: string = '';
  model: string = 'deepseek-v4-pro';
  thinkingEnabled: boolean = true;
  reasoningEffort: 'high' | 'max' = 'high';
  systemPrompt: string = 'You are a helpful assistant.';
  baseUrl: string = 'https://api.deepseek.com';
  toolsEnabled: boolean = true;
}

const STORE_NAME = 'deepseek_chat_store';

let store: preferences.Preferences | null = null;

export function initStorage(ctx: common.UIAbilityContext): void {
  if (store) {
    return;
  }
  const options: preferences.Options = { name: STORE_NAME };
  store = preferences.getPreferencesSync(ctx, options);
}

function getStore(): preferences.Preferences {
  if (store) {
    return store;
  }
  const ctx = getContext() as common.UIAbilityContext;
  const options: preferences.Options = { name: STORE_NAME };
  store = preferences.getPreferencesSync(ctx, options);
  return store;
}

export function readString(key: string, defVal: string): string {
  try {
    const s = getStore();
    const v = s.getSync(key, defVal) as string;
    return v;
  } catch (e) {
    return defVal;
  }
}

export function writeString(key: string, value: string): void {
  try {
    const s = getStore();
    s.putSync(key, value);
    s.flushSync();
  } catch (e) {
  }
}

export function readObject<T>(key: string, defVal: T): T {
  try {
    const raw = readString(key, '');
    if (raw.length === 0) {
      return defVal;
    }
    return JSON.parse(raw) as T;
  } catch (e) {
    return defVal;
  }
}

export function writeObject<T>(key: string, value: T): void {
  try {
    const raw = JSON.stringify(value);
    writeString(key, raw);
  } catch (e) {
  }
}

export function newId(): string {
  const t = Date.now().toString(36);
  const r = Math.floor(Math.random() * 1_000_000).toString(36);
  return `${t}_${r}`;
}

export function nowMillis(): number {
  return Date.now();
}