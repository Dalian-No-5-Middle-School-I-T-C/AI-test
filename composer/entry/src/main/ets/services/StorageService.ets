import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { ChatMessage, Conversation, ConversationSummary } from '../models/ChatModels';

const PREF_NAME = 'composer_chat_prefs';
const CONV_DIR = 'conversations';
const CONV_LIST_FILE = 'conv_list.json';

export class StorageService {
  private static context: Context;

  static init(context: Context): void {
    StorageService.context = context;
    StorageService.ensureConvDir();
  }

  private static ensureConvDir(): void {
    let dirPath = StorageService.context.filesDir + '/' + CONV_DIR;
    try {
      if (!fileIo.accessSync(dirPath)) {
        fileIo.mkdirSync(dirPath, true);
      }
    } catch (e) {
      // ignore
    }
  }

  private static getPrefs(): preferences.Preferences {
    return preferences.getPreferencesSync(StorageService.context, { name: PREF_NAME });
  }

  private static writeTextFile(filePath: string, text: string): void {
    try {
      let file = fileIo.openSync(filePath, 0o1101);
      fileIo.writeSync(file.fd, text);
      fileIo.closeSync(file.fd);
    } catch (e) {
      // ignore
    }
  }

  private static readTextFile(filePath: string): string {
    try {
      if (!fileIo.accessSync(filePath)) {
        return '';
      }
      return fileIo.readTextSync(filePath);
    } catch (e) {
      return '';
    }
  }

  static getApiKey(): string {
    let pref = StorageService.getPrefs();
    return pref.getSync('api_key', '') as string;
  }

  static setApiKey(key: string): void {
    let pref = StorageService.getPrefs();
    pref.putSync('api_key', key);
    pref.flushSync();
  }

  static getModel(): string {
    let pref = StorageService.getPrefs();
    return pref.getSync('model', 'deepseek-v4-pro') as string;
  }

  static setModel(model: string): void {
    let pref = StorageService.getPrefs();
    pref.putSync('model', model);
    pref.flushSync();
  }

  static getThinkingEnabled(): boolean {
    let pref = StorageService.getPrefs();
    return pref.getSync('thinking_enabled', true) as boolean;
  }

  static setThinkingEnabled(enabled: boolean): void {
    let pref = StorageService.getPrefs();
    pref.putSync('thinking_enabled', enabled);
    pref.flushSync();
  }

  static getReasoningEffort(): string {
    let pref = StorageService.getPrefs();
    return pref.getSync('reasoning_effort', 'high') as string;
  }

  static setReasoningEffort(effort: string): void {
    let pref = StorageService.getPrefs();
    pref.putSync('reasoning_effort', effort);
    pref.flushSync();
  }

  static loadConversationList(): ConversationSummary[] {
    let filePath = StorageService.context.filesDir + '/' + CONV_LIST_FILE;
    let content = StorageService.readTextFile(filePath);
    if (content.length === 0) {
      return [];
    }
    try {
      return JSON.parse(content) as ConversationSummary[];
    } catch (e) {
      return [];
    }
  }

  private static saveConversationList(list: ConversationSummary[]): void {
    let filePath = StorageService.context.filesDir + '/' + CONV_LIST_FILE;
    StorageService.writeTextFile(filePath, JSON.stringify(list));
  }

  static loadConversation(convId: string): Conversation | null {
    let filePath = StorageService.context.filesDir + '/' + CONV_DIR + '/' + convId + '.json';
    let content = StorageService.readTextFile(filePath);
    if (content.length === 0) {
      return null;
    }
    try {
      return JSON.parse(content) as Conversation;
    } catch (e) {
      return null;
    }
  }

  static saveConversation(conv: Conversation): void {
    let filePath = StorageService.context.filesDir + '/' + CONV_DIR + '/' + conv.id + '.json';
    StorageService.writeTextFile(filePath, JSON.stringify(conv));

    let list = StorageService.loadConversationList();
    let idx = list.findIndex((s: ConversationSummary) => s.id === conv.id);
    let lastMsg = '';
    if (conv.messages.length > 0) {
      let last = conv.messages[conv.messages.length - 1];
      lastMsg = last.content.length > 50 ? last.content.substring(0, 50) + '...' : last.content;
    }
    let summary: ConversationSummary = {
      id: conv.id,
      title: conv.title,
      lastMessage: lastMsg,
      createdAt: conv.createdAt,
      updatedAt: conv.updatedAt,
      model: conv.model
    };
    if (idx >= 0) {
      list[idx] = summary;
    } else {
      let newList: ConversationSummary[] = [summary];
      for (let i = 0; i < list.length; i++) {
        newList.push(list[i]);
      }
      list = newList;
    }
    StorageService.saveConversationList(list);
  }

  static deleteConversation(convId: string): void {
    let filePath = StorageService.context.filesDir + '/' + CONV_DIR + '/' + convId + '.json';
    try {
      if (fileIo.accessSync(filePath)) {
        fileIo.unlinkSync(filePath);
      }
    } catch (e) {
      // ignore
    }
    let list = StorageService.loadConversationList();
    let filtered: ConversationSummary[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].id !== convId) {
        filtered.push(list[i]);
      }
    }
    StorageService.saveConversationList(filtered);
  }

  static generateId(): string {
    return Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
  }
}
