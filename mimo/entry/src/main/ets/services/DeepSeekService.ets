import { http } from '@kit.NetworkKit'
import { Message, ToolCall, FunctionCall } from '../models/Message'

const BASE_URL = 'https://api.deepseek.com'

export interface StreamCallbacks {
  onThinking: (text: string) => void
  onContent: (text: string) => void
  onToolCall: (toolCall: ToolCall) => Promise<void>
  onComplete: () => void
  onError: (error: string) => void
}

interface ThinkingConfig {
  type: string
}

interface RequestBody {
  model: string
  messages: MessageForApi[]
  stream: boolean
  thinking?: ThinkingConfig
  reasoning_effort?: string
  tools?: object[]
}

interface ApiToolCall {
  id: string
  type: string
  function: ApiFunctionCall
}

interface ApiFunctionCall {
  name: string
  arguments: string
}

interface MessageForApi {
  role: string
  content: string
  tool_call_id?: string
  tool_calls?: ApiToolCall[]
}

interface StreamChunk {
  choices: ChunkChoice[]
}

interface ChunkChoice {
  delta: ChunkDelta
  finish_reason: string | null
}

interface ChunkDelta {
  reasoning_content?: string
  content?: string
  tool_calls?: ChunkToolCall[]
}

interface ChunkFunction {
  name?: string
  arguments?: string
}

interface ChunkToolCall {
  index: number
  id?: string
  function?: ChunkFunction
}

export class DeepSeekService {
  private apiKey: string
  private model: string
  private thinkingEnabled: boolean
  private reasoningEffort: string

  constructor(apiKey: string, model: string, thinkingEnabled: boolean, reasoningEffort: string) {
    this.apiKey = apiKey
    this.model = model
    this.thinkingEnabled = thinkingEnabled
    this.reasoningEffort = reasoningEffort
  }

  async sendMessage(
    messages: Message[],
    callbacks: StreamCallbacks,
    tools?: object[]
  ): Promise<void> {
    if (!this.apiKey || this.apiKey.trim().length === 0) {
      callbacks.onError('请先在设置中填写API Key')
      return
    }

    const httpRequest = http.createHttp()

    const messagesForApi: MessageForApi[] = []
    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i]
      const msgObj: MessageForApi = {
        role: msg.role,
        content: msg.content
      }
      if (msg.toolCallId) {
        msgObj.tool_call_id = msg.toolCallId
      }
      if (msg.toolCalls && msg.toolCalls.length > 0) {
        const apiToolCalls: ApiToolCall[] = []
        for (let j = 0; j < msg.toolCalls.length; j++) {
          const tc = msg.toolCalls[j]
          const apiFunc: ApiFunctionCall = {
            name: tc.function.name,
            arguments: tc.function.arguments
          }
          const apiTc: ApiToolCall = {
            id: tc.id,
            type: tc.type,
            function: apiFunc
          }
          apiToolCalls.push(apiTc)
        }
        msgObj.tool_calls = apiToolCalls
        if (!msgObj.content) {
          msgObj.content = ''
        }
      }
      messagesForApi.push(msgObj)
    }

    const requestBody: RequestBody = {
      model: this.model,
      messages: messagesForApi,
      stream: true
    }

    if (this.thinkingEnabled) {
      requestBody.thinking = { type: 'enabled' }
      requestBody.reasoning_effort = this.reasoningEffort
    } else {
      requestBody.thinking = { type: 'disabled' }
    }

    if (tools && tools.length > 0) {
      requestBody.tools = tools
    }

    try {
      const response = await httpRequest.request(
        `${BASE_URL}/chat/completions`,
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${this.apiKey}`
          },
          extraData: JSON.stringify(requestBody),
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 30000,
          readTimeout: 120000
        }
      )

      if (response.responseCode !== 200) {
        const errorBody = response.result as string
        callbacks.onError(`HTTP ${response.responseCode}: ${errorBody}`)
        return
      }

      const responseText = response.result as string
      await this.parseSSE(responseText, callbacks)
    } catch (error) {
      let errorMsg = '未知错误'
      if (error != null) {
        try {
          const err = error as Error
          if (err.message) {
            errorMsg = err.message
          }
        } catch (e) {
          errorMsg = String(error)
        }
      }
      callbacks.onError(`请求失败: ${errorMsg}`)
    } finally {
      httpRequest.destroy()
    }
  }

  private async parseSSE(responseText: string, callbacks: StreamCallbacks): Promise<void> {
    const lines = responseText.split('\n')
    const toolCallsMap: Map<number, ToolCall> = new Map()

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (!line) continue
      if (!line.startsWith('data:')) continue

      const jsonStr = line.substring(5).trim()
      if (jsonStr === '[DONE]') {
        callbacks.onComplete()
        return
      }

      let chunk: StreamChunk
      try {
        chunk = JSON.parse(jsonStr) as StreamChunk
      } catch (e) {
        continue
      }

      if (!chunk.choices || chunk.choices.length === 0) continue

      const choice = chunk.choices[0]
      const delta = choice.delta
      const finishReason = choice.finish_reason

      if (delta) {
        if (delta.reasoning_content) {
          callbacks.onThinking(delta.reasoning_content)
        }
        if (delta.content) {
          callbacks.onContent(delta.content)
        }
        if (delta.tool_calls) {
          for (let j = 0; j < delta.tool_calls.length; j++) {
            const tc = delta.tool_calls[j]
            const idx = tc.index
            if (!toolCallsMap.has(idx)) {
              toolCallsMap.set(idx, {
                id: tc.id || '',
                type: 'function',
                function: {
                  name: tc.function?.name || '',
                  arguments: tc.function?.arguments || ''
                }
              })
            } else {
              const existing = toolCallsMap.get(idx)
              if (existing) {
                if (tc.id) existing.id = tc.id
                if (tc.function?.name) existing.function.name = tc.function.name
                if (tc.function?.arguments) existing.function.arguments += tc.function.arguments
              }
            }
          }
        }
      }

      if (finishReason === 'tool_calls') {
        const firstToolCall = toolCallsMap.get(0)
        if (firstToolCall) {
          await callbacks.onToolCall(firstToolCall)
        }
        return
      }

      if (finishReason === 'stop') {
        callbacks.onComplete()
        return
      }
    }

    callbacks.onComplete()
  }
}