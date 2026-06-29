import { Column, Row, Text, TextInput, Button, List, Blank, Divider, ScrollController, TextArea, Select, FlexAlign, Alignment, FontWeight } from '@kit.ArkUI'
import { AbilityKit } from '@kit.AbilityKit'
import { DeepSeekApi } from '../service/DeepSeekApi'
import { StorageUtil } from '../utils/StorageUtil'
import { UserRole, ThinkDepth } from '../model/ChatModel'

class ChatMsg {
  id: string
  role: string
  content: string
  reasoningContent: string
  reasoningVisible: boolean
  timestamp: number

  constructor(id: string, role: string, content: string, rc: string, rv: boolean, ts: number) {
    this.id = id
    this.role = role
    this.content = content
    this.reasoningContent = rc
    this.reasoningVisible = rv
    this.timestamp = ts
  }
}

class ChatConfig {
  model: string
  thinkDepth: ThinkDepth
  apiKey: string

  constructor(model: string, thinkDepth: ThinkDepth, apiKey: string) {
    this.model = model
    this.thinkDepth = thinkDepth
    this.apiKey = apiKey
  }
}

@Entry
@Component
struct ChatPage {
  @State messages: ChatMsg[] = []
  @State inputText: string = ''
  @State isStreaming: boolean = false
  @State showSettings: boolean = false
  @State config: ChatConfig = new ChatConfig('deepseek-v4-flash', ThinkDepth.OFF, '')
  @State convTitle: string = ''
  @State convId: string = ''

  listScroller: ScrollController = new ScrollController()
  rowScroller: ScrollController = new ScrollController()
  textCtrl: TextController = new TextController()
  scrollTimer: number = 0

  aboutToAppear(): void {
    this.loadConfig()
    this.loadConversationMap()
  }

  loadConfig(): void {
    this.config = new ChatConfig(
      StorageUtil.getModel(),
      StorageUtil.getThink() === 'high' ? ThinkDepth.HIGH : StorageUtil.getThink() === 'max' ? ThinkDepth.MAX : ThinkDepth.OFF,
      StorageUtil.getApiKey(),
    )
  }

  loadConversationMap(): void {
    const rawMap = StorageUtil.getConvMap()
    const keys: string[] = Object.keys(rawMap)
    if (keys.length === 0) {
      this.createNewConversation()
      return
    }
    this.convId = keys[0]
    this.convTitle = rawMap[this.convId]
    this.loadMessages(this.convId)
  }

  createNewConversation(): void {
    const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 7)
    this.convId = id
    this.convTitle = '新对话'
    this.messages = []
    const map: Record<string, string> = StorageUtil.getConvMap()
    map[id] = this.convTitle
    StorageUtil.saveConvMap(map)
    StorageUtil.saveMessages(id, [])
  }

  loadMessages(id: string): void {
    const arr = StorageUtil.getMessages(id)
    const out: ChatMsg[] = []
    for (let i = 0; i < arr.length; i++) {
      const m = arr[i]
      const msg = new ChatMsg(
        m['id'] || (Date.now().toString(36) + Math.random().toString(36).slice(2, 6)),
        m['role'] || UserRole.USER,
        m['content'] || '',
        m['reasoning'] || '',
        false,
        m['timestamp'] || 0,
      )
      out.push(msg)
    }
    this.messages = out
  }

  persistMessages(): void {
    const msgArr: Object[] = []
    for (let i = 0; i < this.messages.length; i++) {
      const m = this.messages[i]
      msgArr.push({
        id: m.id,
        role: m.role,
        content: m.content,
        reasoning: m.reasoningContent,
        timestamp: m.timestamp,
      })
    }
    StorageUtil.saveMessages(this.convId, msgArr)
    const map: Record<string, string> = StorageUtil.getConvMap()
    map[this.convId] = this.convTitle
    StorageUtil.saveConvMap(map)
  }

  switchConversation(id: string): void {
    if (this.isStreaming) {
      return
    }
    this.persistMessages()
    this.convId = id
    const map: Record<string, string> = StorageUtil.getConvMap()
    this.convTitle = map[id]
    this.loadMessages(id)
    this.showSettings = false
  }

  async sendMessage(): Promise<void> {
    const text = this.inputText.trim()
    if (!text || this.isStreaming) {
      return
    }
    this.inputText = ''
    this.textCtrl.deselectText()

    if (this.config.apiKey.length === 0) {
      return
    }

    const uid = Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
    const userMsg = new ChatMsg(uid, UserRole.USER, text, '', false, Date.now())
    this.messages = this.messages.concat([userMsg])

    if (this.messages.filter(m => m.role === UserRole.USER).length === 1) {
      this.convTitle = text.slice(0, 20)
    }
    this.persistMessages()

    const aid = Date.now().toString(36)
    const assistantMsg = new ChatMsg(aid, UserRole.ASSISTANT, '', '', false, Date.now())
    this.messages = this.messages.concat([assistantMsg])
    this.isStreaming = true

    const apiMessages = this.buildApiMessages()
    const lastIdx = this.messages.length - 1
    let assistantBuffer = ''

    await DeepSeekApi.chatStream(
      this.config.model,
      apiMessages,
      this.config.thinkDepth,
      (content: string, reasoning: string) => {
        if (reasoning && reasoning.length > 0) {
          const cur = this.messages[lastIdx]
          const updated = new ChatMsg(cur.id, cur.role, cur.content, cur.reasoningContent + reasoning, cur.reasoningVisible, cur.timestamp)
          this.messages = this.messages.slice(0, lastIdx).concat([updated])
        }
        if (content && content.length > 0) {
          assistantBuffer += content
          const cur = this.messages[lastIdx]
          const updated = new ChatMsg(cur.id, cur.role, cur.content + content, cur.reasoningContent, cur.reasoningVisible, cur.timestamp)
          this.messages = this.messages.slice(0, lastIdx).concat([updated])
          this.scheduleScroll()
        }
      },
    )

    this.isStreaming = false
    this.persistMessages()
  }

  buildApiMessages(): Object[] {
    const result: Object[] = []
    for (let i = 0; i < this.messages.length; i++) {
      const m = this.messages[i]
      const item: Record<string, Object> = { role: m.role, content: m.content }
      if (m.reasoningContent && m.reasoningContent.length > 0) {
        item['reasoning_content'] = m.reasoningContent
      }
      result.push(item)
    }
    const sys: Record<string, Object> = { role: 'system', content: 'You are a helpful assistant. 需要当前时间时调用 get_current_system_time。' }
    result.unshift(sys)
    return result
  }

  scheduleScroll(): void {
    this.scrollTimer = setTimeout(() => {
      if (this.messages.length > 0) {
        this.listScroller.scrollToIndex(this.messages.length - 1)
      }
    }, 30)
  }

  saveSettings(): void {
    StorageUtil.saveApiKey(this.config.apiKey)
    StorageUtil.saveModel(this.config.model)
    const thinkStr = this.config.thinkDepth === ThinkDepth.HIGH ? 'high' : this.config.thinkDepth === ThinkDepth.MAX ? 'max' : 'off'
    StorageUtil.saveThink(thinkStr)
    this.showSettings = false
  }

  newChat(): void {
    if (this.isStreaming) {
      return
    }
    this.persistMessages()
    this.createNewConversation()
  }

  clearChat(): void {
    if (this.isStreaming) {
      return
    }
    this.messages = []
    this.persistMessages()
  }

  toggleSettings(): void {
    this.showSettings = !this.showSettings
  }

  toggleReasoning(id: string): void {
    const out: ChatMsg[] = []
    for (let i = 0; i < this.messages.length; i++) {
      const m = this.messages[i]
      if (m.id === id) {
        out.push(new ChatMsg(m.id, m.role, m.content, m.reasoningContent, !m.reasoningVisible, m.timestamp))
      } else {
        out.push(m)
      }
    }
    this.messages = out
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Text(this.convTitle)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .maxLines(1)
            .onClick(() => {})
          Blank()
          Button('新建')
            .fontSize(13)
            .onClick(() => this.newChat())
          Button('清除')
            .fontSize(13)
            .onClick(() => this.clearChat())
          Button(this.showSettings ? '关闭' : '设置')
            .fontSize(13)
            .onClick(() => this.toggleSettings())
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 6 })
        .backgroundColor('#f5f5f5')

        if (this.showSettings) {
          Divider()
          this.buildSettings()
        }

        Divider()

        List({ scroller: this.listScroller }) {
          ForEach(this.messages, (msg: ChatMsg, index: number) => {
            ListItem() {
              Row() {
                if (msg.role === UserRole.USER) {
                  this.buildUserBubble(msg)
                } else {
                  if (msg.role === UserRole.SYSTEM) {
                    this.buildSystemBubble(msg)
                  } else {
                    this.buildAssistantBubble(msg, index)
                  }
                }
              }
              .width('100%')
            }
          })
        }
        .scrollBar(BarState.Auto)
        .edgeEffect(ScrollEdgeEffect.None)
        .layoutWeight(1)
        .width('100%')

        Row() {
          TextArea({
            placeholder: '输入消息...',
            controller: this.textCtrl,
          })
            .placeholderColor('#aaaaaa')
            .height(56)
            .layoutWeight(1)
            .maxLines(5)
            .autoKeyboard(true)
            .margin({ right: 8 })
            .onChange((val: string) => {
              this.inputText = val
            })

          Button(this.isStreaming ? '停止' : '发送')
            .width(80)
            .height(44)
            .fontSize(14)
            .onClick(() => {
              if (this.isStreaming) {
                this.isStreaming = false
              } else {
                this.sendMessage()
              }
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 10 })
        .backgroundColor('#fafafa')
        .border({ width: { top: 0.5 } })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
  }

  @Builder buildUserBubble(msg: ChatMsg) {
    Row() {
      Text(msg.content)
        .fontSize(15)
        .maxLines(500)
        .width('100%')
    }
    .backgroundColor('#95ec69')
    .borderRadius(16)
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  @Builder buildSystemBubble(msg: ChatMsg) {
    Row() {
      Text(msg.content)
        .fontSize(12)
        .fontColor('#888')
        .maxLines(200)
    }
    .backgroundColor('#f0f0f0')
    .borderRadius(8)
    .padding(8)
    .width('94%')
  }

  @Builder buildAssistantBubble(msg: ChatMsg, index: number) {
    Column() {
      if (msg.reasoningContent && msg.reasoningContent.length > 0) {
        Row() {
          Text(msg.reasoningVisible ? '收起思维' : '展开思维')
            .fontSize(12)
            .fontColor('#1565c0')
            .onClick(() => {
              this.toggleReasoning(msg.id)
            })
        }
        .padding({ bottom: 4 })
        if (msg.reasoningVisible) {
          Text(msg.reasoningContent)
            .fontSize(13)
            .fontColor('#555')
            .maxLines(500)
            .padding({ left: 6, right: 6, top: 4, bottom: 4 })
            .backgroundColor('#f9f9f9')
            .borderRadius(6)
            .width('100%')
        }
      }
      if (msg.content && msg.content.length > 0) {
        Text(msg.content)
          .fontSize(15)
          .maxLines(1000)
          .width('100%')
      }
    }
    .width('78%')
    .borderRadius(16)
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  @Builder buildSettings() {
    Column() {
      Text('设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .margin({ bottom: 12 })

      Text('API Key (必填)')
        .fontSize(14)
        .margin({ top: 10, bottom: 4 })
      TextInput({ placeholder: 'sk-xxxxxxxxxxxxxxxx', text: this.config.apiKey })
        .height(40)
        .width('100%')
        .backgroundColor('#f5f5f5')
        .margin({ bottom: 8 })
        .onChange((val: string) => {
          const newCfg = new ChatConfig(this.config.model, this.config.thinkDepth, val)
          this.config = newCfg
        })

      Text('模型')
        .fontSize(14)
        .margin({ bottom: 4 })
      Select([
        { value: 'deepseek-v4-flash', label: 'deepseek-v4-flash (推荐)' },
        { value: 'deepseek-v4-pro', label: 'deepseek-v4-pro' },
      ])
        .value(this.config.model)
        .width('100%')
        .margin({ bottom: 10 })
        .onSelect((index: number) => {
          const newCfg = new ChatConfig(index === 0 ? 'deepseek-v4-flash' : 'deepseek-v4-pro', this.config.thinkDepth, this.config.apiKey)
          this.config = newCfg
        })

      Text('思考模式')
        .fontSize(14)
        .margin({ bottom: 4 })
      Select([
        { value: 'off', label: '关闭' },
        { value: 'high', label: 'high' },
        { value: 'max', label: 'max (最深)' },
      ])
        .value(this.config.thinkDepth)
        .width('100%')
        .margin({ bottom: 10 })
        .onSelect((index: number) => {
          const depths: ThinkDepth[] = [ThinkDepth.OFF, ThinkDepth.HIGH, ThinkDepth.MAX]
          const newCfg = new ChatConfig(this.config.model, depths[index], this.config.apiKey)
          this.config = newCfg
        })

      Text('历史会话')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .margin({ bottom: 6 })

      this.buildConvHistory()

      Row() {
        Blank()
        Button('保存')
          .fontSize(14)
          .onClick(() => this.saveSettings())
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .border({ width: { top: 0.5 } })
    .backgroundColor('#fafafa')
  }

  buildConvHistory() {
    const map: Record<string, string> = StorageUtil.getConvMap()
    const keys: string[] = Object.keys(map)
    if (keys.length === 0) {
      Text('暂无历史会话')
        .fontSize(13)
        .fontColor('#888')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 10 })
    } else {
      Scroll({ scroller: this.rowScroller }) {
        Row() {
          ForEach(keys, (key: string) => {
            Row() {
              Text(map[key])
                .fontSize(13)
                .maxLines(1)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            }
            .backgroundColor(key === this.convId ? '#bbdefb' : '#eeeeee')
            .borderRadius(16)
            .margin({ left: 4, right: 4 })
            .onClick(() => {
              if (key !== this.convId) {
                this.switchConversation(key)
              }
            })
          })
        }
        .alignItems(Alignment.Center)
        .width('100%')
        .space(6)
      }
      .width('100%')
      .height(52)
      .scrollBar(BarState.Auto)
    }
  }
}
