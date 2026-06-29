import { PreferenceUtil } from './PreferenceUtil'

const PREF_API_KEY = 'deepseek_api_key'
const PREF_MODEL = 'deepseek_model'
const PREF_THINK = 'deepseek_think'
const PREF_MAP = 'deepseek_map'

export class StorageUtil {
  static saveApiKey(key: string): void {
    PreferenceUtil.setString(PREF_API_KEY, key)
  }

  static getApiKey(): string {
    return PreferenceUtil.getString(PREF_API_KEY, '')
  }

  static saveModel(model: string): void {
    PreferenceUtil.setString(PREF_MODEL, model)
  }

  static getModel(): string {
    return PreferenceUtil.getString(PREF_MODEL, 'deepseek-v4-flash')
  }

  static saveThink(depth: string): void {
    PreferenceUtil.setString(PREF_THINK, depth)
  }

  static getThink(): string {
    return PreferenceUtil.getString(PREF_THINK, 'off')
  }

  static saveConvMap(mapData: Record<string, string>): void {
    PreferenceUtil.setString(PREF_MAP, JSON.stringify(mapData))
  }

  static getConvMap(): Record<string, string> {
    const raw = PreferenceUtil.getString(PREF_MAP, '')
    if (!raw) return {}
    try {
      return JSON.parse(raw) as Record<string, string>
    } catch (e) {
      return {}
    }
  }

  static saveMessages(id: string, arr: Object[]): void {
    PreferenceUtil.setString('conv_' + id, JSON.stringify(arr))
  }

  static getMessages(id: string): Object[] {
    const raw = PreferenceUtil.getString('conv_' + id, '[]')
    try {
      return JSON.parse(raw) as Object[]
    } catch (e) {
      return []
    }
  }
}
