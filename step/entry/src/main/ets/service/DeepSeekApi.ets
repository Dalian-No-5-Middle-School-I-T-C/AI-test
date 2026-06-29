import { http, HttpResponse } from '@kit.NetworkKit'
import { StorageUtil } from '../utils/StorageUtil'

const BASE_URL = 'https://api.deepseek.com'
const CHAT_URL = BASE_URL + '/chat/completions'

interface ReqOptions {
  method: string
  header: Record<string, string>
  extraData: string
  connectTimeout: number
  readTimeout: number
  usingCache: boolean
}

export class DeepSeekApi {
  static async getModels(): Promise<string[]> {
    return ['deepseek-v4-flash', 'deepseek-v4-pro']
  }

  static async chatStream(
    model: string,
    messages: Object[],
    thinkDepth: string,
    onToken: (content: string, reasoning: string) => void,
  ): Promise<void> {
    const apiKey = StorageUtil.getApiKey()
    const enableThinking = thinkDepth !== 'off'
    const bodyObj: Record<string, Object> = {
      model: model,
      messages: messages,
      stream: true,
    }
    if (enableThinking) {
      bodyObj['thinking'] = { type: 'enabled' }
      bodyObj['reasoning_effort'] = thinkDepth
    }
    bodyObj['tools'] = [
      {
        type: 'function',
        function: {
          name: 'get_current_system_time',
          description: '获取当前手机系统时间',
          parameters: { type: 'object', properties: {}, required: [] },
        },
      },
    ]

    const bodyStr = JSON.stringify(bodyObj)
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + apiKey,
    }

    let response: HttpResponse | null = null
    try {
      const req = http.createHttp()
      const resp = await req.request(CHAT_URL, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: bodyStr,
        connectTimeout: 60000,
        readTimeout: 120000,
        usingCache: false,
      } as any)
      response = resp
    } catch (e) {
      return
    }

    if (!response || !response.result) {
      return
    }

    let buf = ''
    const reader = response.result as any
    while (true) {
      const chunkObj = await reader.read(4096)
      if (!chunkObj) break
      const val = chunkObj.value
      const finished = chunkObj.finished
      if (typeof val === 'string') {
        buf += val
      }
      if (finished === true) break
    }

    try {
      reader.release()
    } catch (e) {}

    let start = 0
    const bufStr = buf as string
    while (true) {
      const idx = bufStr.indexOf('\n', start)
      if (idx < 0) break
      const line = bufStr.substring(start, idx).trim()
      start = idx + 1
      if (line.startsWith('data: ')) {
        const data = line.substring(6)
        if (data === '[DONE]') continue
        try {
          const parsed = JSON.parse(data)
          const arr = parsed['choices']
          if (arr && arr.length > 0) {
            const delta = arr[0]['delta']
            if (delta) {
              const content = delta['content']
              const reasoning = delta['reasoning_content']
              if (typeof content === 'string' && content.length > 0) {
                onToken(content, '')
              }
              if (typeof reasoning === 'string' && reasoning.length > 0) {
                onToken('', reasoning)
              }
            }
          }
        } catch (e) {}
      }
    }
  }
}
