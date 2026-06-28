import { preferences } from '@kit.ArkData';
import {
  AppSettings,
  ChatSession,
  ChatMessage,
  ToolCall,
  Role,
  DEFAULT_SETTINGS
} from '../model/ChatModels';
import { Context } from '@kit.AbilityKit';

interface SettingsJson {
  apiKey?: string;
  baseUrl?: string;
  model?: string;
  thinkingEnabled?: boolean;
  reasoningEffort?: string;
}

interface ToolCallJson {
  id?: string;
  type?: string;
  functionName?: string;
  functionArgs?: string;
}

interface MessageJson {
  id?: string;
  role?: string;
  content?: string;
  thinking?: string;
  timestamp?: number;
  toolCallId?: string;
  toolCalls?: ToolCallJson[];
}

interface SessionJson {
  id?: string;
  title?: string;
  createdAt?: number;
  updatedAt?: number;
  messages?: MessageJson[];
}

const PREFERENCES_NAME = 'deepseek_chat_prefs';
const KEY_SETTINGS = 'app_settings';
const KEY_SESSIONS = 'chat_sessions';
const KEY_CURRENT_SESSION_ID = 'current_session_id';

let dataPreferences: preferences.Preferences | null = null;

export async function initPreferences(context: Context): Promise<void> {
  try {
    dataPreferences = await preferences.getPreferences(context, PREFERENCES_NAME);
  } catch (e) {
    console.error('Failed to init preferences');
  }
}

function getPrefs(): preferences.Preferences {
  if (!dataPreferences) {
    throw new Error('Preferences not initialized');
  }
  return dataPreferences;
}

function str(v: string | undefined, def: string): string {
  return v ? v : def;
}

export async function loadSettings(): Promise<AppSettings> {
  try {
    const prefs = getPrefs();
    const json = await prefs.get(KEY_SETTINGS, '') as string;
    if (json && json.length > 0) {
      const saved = JSON.parse(json) as SettingsJson;
      const result: AppSettings = {
        apiKey: str(saved.apiKey, DEFAULT_SETTINGS.apiKey),
        baseUrl: str(saved.baseUrl, DEFAULT_SETTINGS.baseUrl),
        model: str(saved.model, DEFAULT_SETTINGS.model),
        thinkingEnabled: saved.thinkingEnabled !== undefined ? saved.thinkingEnabled : DEFAULT_SETTINGS.thinkingEnabled,
        reasoningEffort: str(saved.reasoningEffort, DEFAULT_SETTINGS.reasoningEffort)
      };
      return result;
    }
  } catch (e) {
    console.error('Failed to load settings');
  }
  const result: AppSettings = {
    apiKey: DEFAULT_SETTINGS.apiKey,
    baseUrl: DEFAULT_SETTINGS.baseUrl,
    model: DEFAULT_SETTINGS.model,
    thinkingEnabled: DEFAULT_SETTINGS.thinkingEnabled,
    reasoningEffort: DEFAULT_SETTINGS.reasoningEffort
  };
  return result;
}

export async function saveSettings(settings: AppSettings): Promise<void> {
  try {
    const prefs = getPrefs();
    await prefs.put(KEY_SETTINGS, JSON.stringify(settings));
    await prefs.flush();
  } catch (e) {
    console.error('Failed to save settings');
  }
}

function reconstructToolCall(raw: ToolCallJson): ToolCall {
  const call = new ToolCall(
    str(raw.id, ''),
    str(raw.functionName, ''),
    str(raw.functionArgs, '')
  );
  call.type = str(raw.type, 'function');
  return call;
}

function reconstructMessage(raw: MessageJson): ChatMessage {
  const roleStr = str(raw.role, 'user');
  let role: Role = Role.USER;
  if (roleStr === 'assistant') {
    role = Role.ASSISTANT;
  } else if (roleStr === 'system') {
    role = Role.SYSTEM;
  } else if (roleStr === 'tool') {
    role = Role.TOOL;
  }

  const msg = new ChatMessage(role, str(raw.content, ''), str(raw.toolCallId, ''));
  msg.id = str(raw.id, msg.id);
  msg.thinking = str(raw.thinking, '');
  msg.thinkingExpanded = false;
  msg.isStreaming = false;
  msg.timestamp = raw.timestamp ? raw.timestamp : Date.now();

  if (raw.toolCalls) {
    const list: ToolCall[] = [];
    for (let i = 0; i < raw.toolCalls.length; i++) {
      list.push(reconstructToolCall(raw.toolCalls[i]));
    }
    msg.toolCalls = list;
  }
  return msg;
}

function reconstructSession(raw: SessionJson): ChatSession {
  const s = new ChatSession(str(raw.title, '新对话'));
  s.id = str(raw.id, s.id);
  s.createdAt = raw.createdAt ? raw.createdAt : s.createdAt;
  s.updatedAt = raw.updatedAt ? raw.updatedAt : s.updatedAt;
  if (raw.messages) {
    const list: ChatMessage[] = [];
    for (let i = 0; i < raw.messages.length; i++) {
      list.push(reconstructMessage(raw.messages[i]));
    }
    s.messages = list;
  }
  return s;
}

export async function loadSessions(): Promise<ChatSession[]> {
  try {
    const prefs = getPrefs();
    const json = await prefs.get(KEY_SESSIONS, '') as string;
    if (json && json.length > 0) {
      const arr = JSON.parse(json) as SessionJson[];
      const result: ChatSession[] = [];
      for (let i = 0; i < arr.length; i++) {
        result.push(reconstructSession(arr[i]));
      }
      return result;
    }
  } catch (e) {
    console.error('Failed to load sessions');
  }
  return [];
}

export async function saveSessions(sessions: ChatSession[]): Promise<void> {
  try {
    const prefs = getPrefs();
    await prefs.put(KEY_SESSIONS, JSON.stringify(sessions));
    await prefs.flush();
  } catch (e) {
    console.error('Failed to save sessions');
  }
}

export async function loadCurrentSessionId(): Promise<string> {
  try {
    const prefs = getPrefs();
    return await prefs.get(KEY_CURRENT_SESSION_ID, '') as string;
  } catch (e) {
    console.error('Failed to load current session id');
  }
  return '';
}

export async function saveCurrentSessionId(id: string): Promise<void> {
  try {
    const prefs = getPrefs();
    await prefs.put(KEY_CURRENT_SESSION_ID, id);
    await prefs.flush();
  } catch (e) {
    console.error('Failed to save current session id');
  }
}
