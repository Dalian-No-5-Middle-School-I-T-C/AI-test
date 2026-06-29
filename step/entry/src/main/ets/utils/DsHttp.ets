import { http } from '@kit.NetworkKit'

export class DsHttp {
  static async postStream(
    url: string,
    apiKey: string,
    body: Record<string, any>,
    onDelta: (content: string, reasoning: string) => void,
  ): Promise<number> {
    const headers = {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + apiKey,
    }
    const bodyStr = JSON.stringify(body)

    let response: http.HttpResponse | null = null
    let tid: number = -1
    try {
      const req = http.createHttp()
      response = await req.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: bodyStr,
        connectTimeout: 60000,
        readTimeout: 120000,
        usingHttpCache: false,
      })
    } catch (err) {
      return -1
    }

    if (!response || !response.result) {
      if (response) response.destroy()
      return -2
    }

    let buf = ''
    const useIterable = typeof (response.result as any)[Symbol.asyncIterator] === 'function'

    if (useIterable) {
      const dec = new TextDecoder('utf-8')
      const reader = response.result as AsyncIterable<ArrayBuffer>
      for await (const chunk of reader) {
        buf += dec.decode(chunk)
        let idx: number
        while ((idx = buf.indexOf('\n')) >= 0) {
          const line = buf.slice(0, idx).trim()
          buf = buf.slice(idx + 1)
          if (line.startsWith('data: ')) {
            const data = line.slice(6)
            if (data === '[DONE]') continue
            try {
              const parsed = JSON.parse(data)
              const delta = parsed.choices?.[0]?.delta
              if (delta) {
                onDelta(delta.content || '', delta.reasoning_content || '')
              }
            } catch (_) { }
          }
        }
      }
    } else {
      const dec = new TextDecoder('utf-8')
      buf = dec.decode(response.result as ArrayBuffer)
    }

    response.destroy()
    return 200
  }

  static async postJson(
    url: string,
    apiKey: string,
    body: Record<string, any>,
  ): Promise<{ code: number; data: any }> {
    const headers = {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + apiKey,
    }
    const bodyStr = JSON.stringify(body)

    let response: http.HttpResponse | null = null
    try {
      const req = http.createHttp()
      response = await req.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: bodyStr,
        connectTimeout: 60000,
        readTimeout: 120000,
        usingHttpCache: false,
      })
    } catch (err) {
      return { code: -1, data: String(err) }
    }

    if (!response || !response.result) {
      if (response) response.destroy()
      return { code: -2, data: 'No response' }
    }

    let buf = ''
    const useIterable = typeof (response.result as any)[Symbol.asyncIterator] === 'function'

    if (useIterable) {
      const dec = new TextDecoder('utf-8')
      const reader = response.result as AsyncIterable<ArrayBuffer>
      for await (const chunk of reader) {
        buf += dec.decode(chunk)
      }
    } else {
      buf = new TextDecoder('utf-8').decode(response.result as ArrayBuffer)
    }

    response.destroy()

    try {
      return { code: 200, data: JSON.parse(buf) }
    } catch (e) {
      return { code: -3, data: buf }
    }
  }
}
