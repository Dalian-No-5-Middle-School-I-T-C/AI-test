import { http } from '@kit.NetworkKit'
import { StorageUtil } from '../utils/StorageUtil'

const CHAT_URL = 'https://api.deepseek.com/chat/completions'

class DeepSeekApi {
  static getModels(): string[] {
    return ['deepseek-v4-flash', 'deepseek-v4-pro']
  }

  static chatStream(model: string, messages: string[], thinkDepth: string, onToken: (content: string, reasoning: string) => void): void {
    const body = new Object()
    body['model'] = model
    body['stream'] = true
    body['reasoning_effort'] = thinkDepth

    const msgsArr: Object[] = []
    let i: number = 0
    while (i < messages.length) {
      const item: Record<string, string> = {}
      const parts: string[] = messages[i].split('|')
      item['role'] = parts[0]
      item['content'] = parts[1]
      msgsArr.push(item)
      i = i + 1
    }
    body['messages'] = msgsArr

    const thinkingObj: Record<string, string> = {}
    thinkingObj['type'] = 'enabled'
    body['thinking'] = thinkingObj

    const funcObj: Record<string, Object> = {}
    funcObj['name'] = 'get_current_system_time'
    funcObj['description'] = 'get current system time'
    const paramsObj: Record<string, Object> = {}
    paramsObj['type'] = 'object'
    paramsObj['properties'] = new Object()
    paramsObj['required'] = []
    funcObj['parameters'] = paramsObj
    const toolObj: Record<string, Object> = {}
    toolObj['type'] = 'function'
    toolObj['function'] = funcObj
    const toolsArr: Object[] = []
    toolsArr.push(toolObj)
    body['tools'] = toolsArr

    const bodyStr: string = JSON.stringify(body)
    const headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    headers['Authorization'] = 'Bearer ' + StorageUtil.getApiKey()

    const options: Object = new Object()
    options['url'] = CHAT_URL
    options['method'] = http.RequestMethod.POST as Object
    options['header'] = headers
    options['extraData'] = bodyStr
    options['connectTimeout'] = 60000
    options['readTimeout'] = 120000
    options['usingCache'] = false

    http.createHttp().request(CHAT_URL, options, (error: BusinessError, data: any) => {
      if (error !== undefined && error !== null) {
        return
      }
      if (!data || !data.result) {
        return
      }
      const buf: ArrayBuffer = data.result as ArrayBuffer
      const uint8: Uint8Array = new Uint8Array(buf)
      const textContent: string = String.fromCharCode(...uint8)
      const lines: string[] = textContent.split('\n')
      let j: number = 0
      while (j < lines.length) {
        const line: string = lines[j]
        if (line.startsWith('data: ')) {
          const jsonStr: string = line.substring(6)
          if (jsonStr.trim() !== '' && jsonStr !== '[DONE]') {
            try {
              const parsed: any = JSON.parse(jsonStr)
              const choices: any[] = parsed['choices']
              if (choices !== undefined && choices !== null && choices.length > 0) {
                const delta: any = choices[0]['delta']
                if (delta !== undefined && delta !== null) {
                  const content: string = delta['content']
                  const reasoning: string = delta['reasoning_content']
                  if (content !== undefined && content !== null && content !== '') {
                    onToken(content, '')
                  }
                  if (reasoning !== undefined && reasoning !== null && reasoning !== '') {
                    onToken('', reasoning)
                  }
                }
              }
            } catch (e) {
            }
          }
        }
        j = j + 1
      }
    })
  }
}

export { DeepSeekApi }
