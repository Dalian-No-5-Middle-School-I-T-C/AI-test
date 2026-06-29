import { http } from '@kit.NetworkKit'

export class DsHttp {
  static async postStream(
    url: string,
    apiKey: string,
    bodyStr: string,
    onDelta: (content: string, reasoning: string) => void,
  ): Promise<void> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + apiKey,
    }

    let response: any = null
    try {
      const req = http.createHttp()
      const resp = await req.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: bodyStr,
        connectTimeout: 60000,
        readTimeout: 120000,
        usingCache: false,
      })
      response = resp
    } catch (err) {
      return
    }

    if (!response || !response.result) {
      return
    }

    const buf: ArrayBuffer = response.result as ArrayBuffer
    const decoder: TextDecoder = new TextDecoder('utf-8')
    const text: string = decoder.decode(buf)

    const lines: string[] = text.split('\n')
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim()
      if (line.startsWith('data: ')) {
        const data: string = line.substring(6)
        if (data === '[DONE]') continue
        try {
          const parsed: any = JSON.parse(data)
          const arr: any[] = parsed['choices']
          if (arr && arr.length > 0) {
            const delta: any = arr[0]['delta']
            if (delta) {
              const content: string = delta['content']
              const reasoning: string = delta['reasoning_content']
              if (content.length > 0) {
                onDelta(content, '')
              }
              if (reasoning.length > 0) {
                onDelta('', reasoning)
              }
            }
          }
        } catch (err) {}
      }
    }
  }
}
