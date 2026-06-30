import { http } from '@kit.NetworkKit'
import { StorageUtil } from '../utils/StorageUtil'

const CHAT_URL = 'https://api.deepseek.com/chat/completions'

function buildMsgArr(messages: string[]): Object[] {
  const out: Object[] = []
  let i = 0
  while (i < messages.length) {
    const item: Record<string, string> = {}
    const parts: string[] = messages[i].split('|')
    item['role'] = parts[0]
    item['content'] = parts[1]
    out.push(item)
    i = i + 1
  }
  return out
}

function buildToolObj(): Object {
  const fn: Record<string, Object> = {}
  fn['name'] = 'get_current_system_time'
  fn['description'] = 'get current device time'
  const params: Record<string, Object> = {}
  params['type'] = 'object'
  params['properties'] = new Object()
  params['required'] = []
  fn['parameters'] = params
  const tool: Record<string, Object> = {}
  tool['type'] = 'function'
  tool['function'] = fn
  return tool
}

function buildRequestBody(model: string, messages: string[], thinkDepth: string, apiKey: string): Record<string, Object> {
  const body: Record<string, Object> = {}
  body['model'] = model
  body['messages'] = buildMsgArr(messages)
  body['stream'] = true
  body['tools'] = [buildToolObj()]
  if (thinkDepth !== 'off') {
    const think: Record<string, string> = {}
    think['type'] = 'enabled'
    body['thinking'] = think
    body['reasoning_effort'] = thinkDepth
  }
  return body
}

function extractTokens(payload: string, onToken: (content: string, reasoning: string) => void): void {
  const key1 = '"content":"'
  const idx1 = payload.indexOf(key1)
  if (idx1 >= 0) {
    const s = idx1 + key1.length
    const e = payload.indexOf('"', s)
    if (e >= 0) {
      onToken(payload.substring(s, e), '')
    }
  }
  const key2 = '"reasoning_content":"'
  const idx2 = payload.indexOf(key2)
  if (idx2 >= 0) {
    const s = idx2 + key2.length
    const e = payload.indexOf('"', s)
    if (e >= 0) {
      onToken('', payload.substring(s, e))
    }
  }
}

export class DeepSeekApi {
  static getModels(): string[] {
    return ['deepseek-v4-flash', 'deepseek-v4-pro']
  }

  static chatStream(model: string, messages: string[], thinkDepth: string, onToken: (content: string, reasoning: string) => void): void {
    const apiKey = StorageUtil.getApiKey()
    const body = buildRequestBody(model, messages, thinkDepth, apiKey)
    const bodyStr = JSON.stringify(body)
    const headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    headers['Authorization'] = 'Bearer ' + apiKey

    http.createHttp().request(CHAT_URL, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: bodyStr,
      connectTimeout: 60000,
      readTimeout: 120000,
      usingCache: false,
    }, (error: object, data: object) => {
      if (error !== undefined && error !== null) {
        return
      }
      const dataObj = data as Record<string, Object>
      const raw = dataObj['result']
      if (!raw) {
        return
      }
      const buf: ArrayBuffer = raw as ArrayBuffer
      const uint8 = new Uint8Array(buf)
      let textContent = ''
      let i = 0
      while (i < uint8.length) {
        textContent = textContent + String.fromCharCode(uint8[i])
        i = i + 1
      }
      const lines: string[] = textContent.split('\n')
      let j = 0
      while (j < lines.length) {
        const line: string = lines[j].trim()
        if (line.startsWith('data: ')) {
          const payload: string = line.substring(6)
          if (payload.length > 0 && payload !== '[DONE]') {
            extractTokens(payload, onToken)
          }
        }
        j = j + 1
      }
    })
  }
}
