import { PreferenceUtil } from './PreferenceUtil'

const PREF_API_KEY = 'deepseek_api_key'
const PREF_MODEL = 'deepseek_model'
const PREF_THINK = 'deepseek_think'
const PREF_MAP = 'deepseek_map'
const PREF_MSG_PREFIX = 'conv_msg_'

export class ConvItem {
  id: string
  title: string

  constructor(id: string, title: string) {
    this.id = id
    this.title = title
  }
}

export class MsgItem {
  id: string
  role: string
  content: string
  reasoning: string
  timestamp: number

  constructor(id: string, role: string, content: string, reasoning: string, timestamp: number) {
    this.id = id
    this.role = role
    this.content = content
    this.reasoning = reasoning
    this.timestamp = timestamp
  }
}

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

  static saveConvMap(items: ConvItem[]): void {
    const arr: object[] = []
    for (let i = 0; i < items.length; i++) {
      arr.push(items[i])
    }
    const str = JSON.stringify(arr)
    PreferenceUtil.setString(PREF_MAP, str)
  }

  static getConvMap(): ConvItem[] {
    const raw = PreferenceUtil.getString(PREF_MAP, '')
    if (raw === '') {
      return []
    }
    try {
      const parsed = JSON.parse(raw)
      const out: ConvItem[] = []
      for (let i = 0; i < parsed.length; i++) {
        const it = parsed[i]
        out.push(new ConvItem(it['id'], it['title']))
      }
      return out
    } catch (err) {
      return []
    }
  }

  static saveMessages(id: string, arr: MsgItem[]): void {
    const str = JSON.stringify(arr)
    PreferenceUtil.setString(PREF_MSG_PREFIX + id, str)
  }

  static getMessages(id: string): MsgItem[] {
    const raw = PreferenceUtil.getString(PREF_MSG_PREFIX + id, '[]')
    try {
      const parsed = JSON.parse(raw)
      const out: MsgItem[] = []
      for (let i = 0; i < parsed.length; i++) {
        const it = parsed[i]
        out.push(new MsgItem(it['id'], it['role'], it['content'], it['reasoning'], it['timestamp']))
      }
      return out
    } catch (err) {
      return []
    }
  }
}
