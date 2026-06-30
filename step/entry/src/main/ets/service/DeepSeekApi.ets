import { http } from '@kit.NetworkKit'
import { StorageUtil } from '../utils/StorageUtil'

const CHAT_URL = 'https://api.deepseek.com/chat/completions'

class DeepSeekApi {
  static getModels(): string[] {
    return ['deepseek-v4-flash', 'deepseek-v4-pro']
  }

  static chatStream(model: string, messages: string[], thinkDepth: string, onToken: (content: string, reasoning: string) => void): void {
    const body = this.buildBody(model, messages, thinkDepth)
    const bodyStr = JSON.stringify(body)
    const apiKey = StorageUtil.getApiKey()
    const headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    headers['Authorization'] = 'Bearer ' + apiKey

    http.createHttp().request(CHAT_URL, {
      method: 'POST',
      header: headers,
      extraData: bodyStr,
      connectTimeout: 60000,
      readTimeout: 120000,
      usingCache: false,
    }, (error: object, data: object) => {
      if (error !== undefined && error !== null) {
        return
      }
      if (!data) {
        return
      }
      const raw = (data as any)['result']
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
            this.extractTokens(payload, onToken)
          }
        }
        j = j + 1
      }
    })
  }

  private static buildBody(model: string, messages: string[], thinkDepth: string): object {
    const msgsArr: Object[] = []
    let i = 0
    while (i < messages.length) {
      const segs: string[] = messages[i].split('|')
      const entry: Record<string, string> = {}
      entry['role'] = segs[0]
      entry['content'] = segs[1]
      msgsArr.push(entry)
      i = i + 1
    }
    const thinkingOn = thinkDepth !== 'off'
    if (thinkingOn) {
      const fullBody: Record<string, Object> = {}
      fullBody['model'] = model
      fullBody['messages'] = msgsArr
      fullBody['stream'] = true
      fullBody['thinking'] = '{"type":"enabled"}'
      fullBody['reasoning_effort'] = thinkDepth
      fullBody['tools'] = [this.makeTool()]
      return fullBody
    } else {
      const fullBody: Record<string, Object> = {}
      fullBody['model'] = model
      fullBody['messages'] = msgsArr
      fullBody['stream'] = true
      fullBody['tools'] = [this.makeTool()]
      return fullBody
    }
  }

  private static makeTool(): object {
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

  private static extractTokens(payload: string, onToken: (content: string, reasoning: string) => void): void {
    const contentIdx = payload.indexOf('"content":"')
    if (contentIdx >= 0) {
      const start = contentIdx + 11
      const end = payload.indexOf('"', start)
      if (end >= 0) {
        onToken(payload.substring(start, end), '')
      }
    }
    const reasonIdx = payload.indexOf('"reasoning_content":"')
    if (reasonIdx >= 0) {
      const start = reasonIdx + 22
      const end = payload.indexOf('"', start)
      if (end >= 0) {
        onToken('', payload.substring(start, end))
      }
    }
  }
}

export { DeepSeekApi }
