import { PreferenceUtil } from './PreferenceUtil'

const PREF_API_KEY = 'deepseek_api_key'
const PREF_MODEL = 'deepseek_model'
const PREF_THINK = 'deepseek_think'
const PREF_MAP = 'deepseek_map'
const PREF_MSG_PREFIX = 'conv_msg_'
const SEP = '|'
const REC = '\n'

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
    let i = 0
    const parts: string[] = []
    while (i < items.length) {
      const it = items[i]
      parts.push(it.id + SEP + it.title)
      i = i + 1
    }
    PreferenceUtil.setString(PREF_MAP, parts.join(REC))
  }

  static getConvMap(): ConvItem[] {
    const raw = PreferenceUtil.getString(PREF_MAP, '')
    if (raw === '') {
      return []
    }
    const out: ConvItem[] = []
    const records = raw.split(REC)
    let i = 0
    while (i < records.length) {
      const rec = records[i]
      if (rec.length === 0) {
        i = i + 1
        continue
      }
      const idx = rec.indexOf(SEP)
      if (idx < 0) {
        i = i + 1
        continue
      }
      const id = rec.substring(0, idx)
      const title = rec.substring(idx + 1)
      out.push(new ConvItem(id, title))
      i = i + 1
    }
    return out
  }

  static saveMessages(id: string, arr: MsgItem[]): void {
    let i = 0
    const parts: string[] = []
    while (i < arr.length) {
      const m = arr[i]
      parts.push(m.id + SEP + m.role + SEP + m.content + SEP + m.reasoning + SEP + String(m.timestamp))
      i = i + 1
    }
    PreferenceUtil.setString(PREF_MSG_PREFIX + id, parts.join(REC))
  }

  static getMessages(id: string): MsgItem[] {
    const raw = PreferenceUtil.getString(PREF_MSG_PREFIX + id, '')
    if (raw === '') {
      return []
    }
    const out: MsgItem[] = []
    const records = raw.split(REC)
    let i = 0
    while (i < records.length) {
      const rec = records[i]
      if (rec.length === 0) {
        i = i + 1
        continue
      }
      const parts: string[] = rec.split(SEP)
      if (parts.length < 5) {
        i = i + 1
        continue
      }
      const itemId = parts[0]
      const role = parts[1]
      const content = parts[2]
      const reasoning = parts[3]
      const ts = Number(parts[4])
      out.push(new MsgItem(itemId, role, content, reasoning, ts))
      i = i + 1
    }
    return out
  }
}
