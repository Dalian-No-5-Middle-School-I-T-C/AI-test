import { PreferenceUtil } from './PreferenceUtil'

const PREF_API_KEY = 'deepseek_api_key'
const PREF_DEFAULT_MODEL = 'deepseek_default_model'
const PREF_DEFAULT_THINK = 'deepseek_default_think'
const PREF_HISTORY_KEY = 'deepseek_chat_history_key'

export class StorageUtil {
  static async saveApiKey(key: string): Promise<void> {
    PreferenceUtil.setStringSync(PREF_API_KEY, key)
  }

  static getApiKey(): string {
    return PreferenceUtil.getStringSync(PREF_API_KEY, '')
  }

  static async saveDefaultModel(model: string): Promise<void> {
    PreferenceUtil.setStringSync(PREF_DEFAULT_MODEL, model)
  }

  static getDefaultModel(): string {
    return PreferenceUtil.getStringSync(PREF_DEFAULT_MODEL, 'deepseek-v4-flash')
  }

  static async saveDefaultThink(depth: string): Promise<void> {
    PreferenceUtil.setStringSync(PREF_DEFAULT_THINK, depth)
  }

  static getDefaultThink(): string {
    return PreferenceUtil.getStringSync(PREF_DEFAULT_THINK, 'off')
  }

  static async saveConversationMap(convMap: Map<string, string>): Promise<void> {
    const obj: Record<string, string> = {}
    convMap.forEach((v, k) => { obj[k] = v })
    PreferenceUtil.setStringSync(PREF_HISTORY_KEY, JSON.stringify(obj))
  }

  static loadConversationMap(): Map<string, string> {
    const raw = PreferenceUtil.getStringSync(PREF_HISTORY_KEY, '')
    if (!raw) return new Map()
    try {
      const obj = JSON.parse(raw)
      const m = new Map<string, string>()
      for (const k of Object.keys(obj)) {
        m.set(k, obj[k])
      }
      return m
    } catch (e) {
      return new Map()
    }
  }
}
