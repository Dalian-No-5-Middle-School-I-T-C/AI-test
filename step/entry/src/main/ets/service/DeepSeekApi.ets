import { DsHttp } from '../utils/DsHttp'
import { ThinkDepth } from '../model/ChatModel'

const BASE_URL = 'https://api.deepseek.com'
const CHAT_URL = BASE_URL + '/chat/completions'
const MODELS_URL = BASE_URL + '/models'

export class DeepSeekApi {
  static async getModels(apiKey: string): Promise<string[]> {
    const { data } = await DsHttp.postJson(MODELS_URL, apiKey, {})
    if (data?.data?.id && Array.isArray(data.data.id)) {
      return data.data.id
    }
    if (data?.id && Array.isArray(data.id)) {
      return data.id
    }
    if (Array.isArray(data)) {
      return data as string[]
    }
    return ['deepseek-v4-flash', 'deepseek-v4-pro']
  }

  static async chatStream(
    apiKey: string,
    model: string,
    messages: Array<{ role: string; content: string; reasoning_content?: string }>,
    thinkDepth: ThinkDepth,
    onToken: (content: string, reasoning: string) => void,
  ): Promise<void> {
    const enableThinking = thinkDepth !== ThinkDepth.OFF
    const body: Record<string, any> = {
      model,
      messages,
      stream: true,
    }
    if (enableThinking) {
      body.thinking = { type: 'enabled' }
      body.reasoning_effort = thinkDepth
    }

    const toolDefs = [
      {
        type: 'function',
        function: {
          name: 'get_current_system_time',
          description: '获取当前手机系统时间',
          parameters: {
            type: 'object',
            properties: {},
            required: [],
          },
        },
      },
    ]
    body.tools = toolDefs

    await DsHttp.postStream(CHAT_URL, apiKey, body, (content, reasoning) => {
      if (reasoning) {
        onToken('', reasoning)
      }
      if (content) {
        onToken(content, '')
      }
    })
  }

  static buildMessages(
    msgs: Array<{ role: string; content: string; reasoning?: string }>,
  ): Array<{ role: string; content: string; reasoning_content?: string }> {
    return msgs.map((m) => {
      const item: any = { role: m.role, content: m.content }
      if (m.reasoning) {
        item.reasoning_content = m.reasoning
      }
      return item
    })
  }
}
