import { router } from '@kit.ArkUI'
import { DeepSeekService } from '../services/DeepSeekService'
import { storageService } from '../services/StorageService'
import { Message, Conversation, AppSettings, DEFAULT_SETTINGS, ToolCall } from '../models/Message'
import { getAvailableTools, executeTool } from '../services/ToolService'
import { ChatMessageComponent } from '../components/ChatMessageComponent'
import { Context } from '@kit.AbilityKit'

@Entry
@Component
struct ChatPage {
  @State messages: Message[] = []
  @State inputText: string = ''
  @State isLoading: boolean = false
  @State settings: AppSettings = DEFAULT_SETTINGS
  @State currentConversation: Conversation | null = null
  private listController: ListScroller = new ListScroller()
  private conversationId: string = ''

  async aboutToAppear() {
    const params = router.getParams() as Record<string, string>
    if (params && params['conversationId']) {
      this.conversationId = params['conversationId']
    }

    const context = getContext(this) as Context
    await storageService.init(context)
    this.settings = await storageService.getSettings()

    if (!this.settings.apiKey) {
      router.pushUrl({ url: 'pages/SettingsPage' })
      return
    }

    if (this.conversationId) {
      const conversations = await storageService.getConversations()
      const conversation = conversations.find(c => c.id === this.conversationId)
      if (conversation) {
        this.currentConversation = conversation
        this.messages = conversation.messages
      }
    } else {
      const conversations = await storageService.getConversations()
      if (conversations.length > 0) {
        this.currentConversation = conversations[0]
        this.messages = this.currentConversation.messages
      }
    }
  }

  replaceLastMessage(msg: Message) {
    const newArr: Message[] = []
    for (let i = 0; i < this.messages.length - 1; i++) {
      newArr.push(this.messages[i])
    }
    newArr.push(msg)
    this.messages = newArr
  }

  async sendMessage() {
    if (!this.inputText.trim() || this.isLoading) return

    const userMessage: Message = {
      id: Date.now().toString(),
      role: 'user',
      content: this.inputText.trim(),
      timestamp: Date.now()
    }

    const newMessages: Message[] = []
    for (let i = 0; i < this.messages.length; i++) {
      newMessages.push(this.messages[i])
    }
    newMessages.push(userMessage)

    const assistantMessage: Message = {
      id: (Date.now() + 1).toString(),
      role: 'assistant',
      content: '',
      thinking: '',
      timestamp: Date.now()
    }
    newMessages.push(assistantMessage)

    this.messages = newMessages
    this.inputText = ''
    this.isLoading = true

    this.scrollToBottom()

    await this.callDeepSeek()
  }

  buildMessagesForApi(): Message[] {
    const result: Message[] = []
    for (let i = 0; i < this.messages.length; i++) {
      const m = this.messages[i]
      if (m.role === 'user' || m.role === 'system' || m.role === 'tool') {
        result.push(m)
      } else if (m.role === 'assistant') {
        if (m.content || m.thinking || (m.toolCalls && m.toolCalls.length > 0)) {
          result.push(m)
        }
      }
    }
    return result
  }

  async callDeepSeek() {
    const service = new DeepSeekService(
      this.settings.apiKey,
      this.settings.model,
      this.settings.thinkingEnabled,
      this.settings.reasoningEffort
    )

    const messagesForApi = this.buildMessagesForApi()

    await service.sendMessage(
      messagesForApi,
      {
        onThinking: (text: string) => {
          const lastIdx = this.messages.length - 1
          const old = this.messages[lastIdx]
          if (old.role === 'assistant') {
            const updated: Message = {
              id: old.id,
              role: old.role,
              content: old.content,
              thinking: (old.thinking || '') + text,
              timestamp: old.timestamp,
              toolCalls: old.toolCalls,
              toolCallId: old.toolCallId
            }
            this.replaceLastMessage(updated)
          }
        },
        onContent: (text: string) => {
          const lastIdx = this.messages.length - 1
          const old = this.messages[lastIdx]
          if (old.role === 'assistant') {
            const updated: Message = {
              id: old.id,
              role: old.role,
              content: old.content + text,
              thinking: old.thinking,
              timestamp: old.timestamp,
              toolCalls: old.toolCalls,
              toolCallId: old.toolCallId
            }
            this.replaceLastMessage(updated)
            this.scrollToBottom()
          }
        },
        onToolCall: async (toolCall: ToolCall) => {
          const lastIdx = this.messages.length - 1
          const old = this.messages[lastIdx]
          if (old.role === 'assistant') {
            const toolCalls: ToolCall[] = []
            if (old.toolCalls) {
              for (let i = 0; i < old.toolCalls.length; i++) {
                toolCalls.push(old.toolCalls[i])
              }
            }
            toolCalls.push(toolCall)

            const updated: Message = {
              id: old.id,
              role: old.role,
              content: old.content,
              thinking: old.thinking,
              timestamp: old.timestamp,
              toolCalls: toolCalls,
              toolCallId: old.toolCallId
            }
            this.replaceLastMessage(updated)

            const result = executeTool(toolCall.function.name, toolCall.id)

            const toolMessage: Message = {
              id: Date.now().toString(),
              role: 'tool',
              content: result.result,
              toolCallId: result.toolCallId,
              timestamp: Date.now()
            }

            const newAssistant: Message = {
              id: (Date.now() + 1).toString(),
              role: 'assistant',
              content: '',
              thinking: '',
              timestamp: Date.now()
            }

            const arr: Message[] = []
            for (let i = 0; i < this.messages.length; i++) {
              arr.push(this.messages[i])
            }
            arr.push(toolMessage)
            arr.push(newAssistant)
            this.messages = arr
            this.scrollToBottom()

            await this.callDeepSeek()
          }
        },
        onComplete: () => {
          this.isLoading = false
          this.saveConversation()
        },
        onError: (error: string) => {
          this.isLoading = false
          const lastIdx = this.messages.length - 1
          const old = this.messages[lastIdx]
          if (old.role === 'assistant') {
            const updated: Message = {
              id: old.id,
              role: old.role,
              content: '错误: ' + error,
              thinking: old.thinking,
              timestamp: old.timestamp,
              toolCalls: old.toolCalls,
              toolCallId: old.toolCallId
            }
            this.replaceLastMessage(updated)
          }
        }
      },
      getAvailableTools()
    )
  }

  async saveConversation() {
    if (!this.currentConversation) {
      this.currentConversation = {
        id: Date.now().toString(),
        title: this.messages[0]?.content.substring(0, 50) || '新对话',
        messages: this.messages,
        createdAt: Date.now(),
        updatedAt: Date.now()
      }
      await storageService.addConversation(this.currentConversation)
    } else {
      this.currentConversation.messages = this.messages
      this.currentConversation.updatedAt = Date.now()
      await storageService.updateConversation(this.currentConversation)
    }
  }

  scrollToBottom() {
    if (this.messages.length > 0) {
      this.listController.scrollToIndex(this.messages.length - 1)
    }
  }

  build() {
    Column() {
      this.Header()
      this.MessageList()
      this.InputArea()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  Header() {
    Row() {
      Text('←')
        .fontSize(24)
        .onClick(() => {
          router.back()
        })

      Text(this.settings.model)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ left: 12 })

      Blank()

      Text('⚙️')
        .fontSize(24)
        .onClick(() => {
          router.pushUrl({ url: 'pages/SettingsPage' })
        })

      Text('🕒')
        .fontSize(24)
        .margin({ left: 16 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/ConversationListPage' })
        })

      Text('➕')
        .fontSize(24)
        .margin({ left: 16 })
        .onClick(() => {
          this.messages = []
          this.currentConversation = null
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  MessageList() {
    List({ scroller: this.listController }) {
      ForEach(this.messages, (message: Message) => {
        ListItem() {
          ChatMessageComponent({ message: message })
        }
      })
    }
    .layoutWeight(1)
    .width('100%')
    .divider({ strokeWidth: 0 })
  }

  @Builder
  InputArea() {
    Column() {
      if (this.isLoading) {
        Row() {
          LoadingProgress()
            .width(20)
            .height(20)
            .color('#007DFF')
          Text('AI正在思考...')
            .fontSize(14)
            .fontColor('#666666')
            .margin({ left: 8 })
        }
        .width('100%')
        .padding(8)
      }

      Row() {
        TextInput({ text: this.inputText, placeholder: '输入消息...' })
          .layoutWeight(1)
          .height(40)
          .onChange((value: string) => {
            this.inputText = value
          })
          .onSubmit(() => {
            this.sendMessage()
          })

        Button('发送')
          .height(40)
          .margin({ left: 8 })
          .onClick(() => {
            this.sendMessage()
          })
          .enabled(!this.isLoading && this.inputText.trim().length > 0)
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
  }
}