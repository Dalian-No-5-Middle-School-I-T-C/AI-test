import {
  Column, Row, Text, TextInput, Button, List, Blank, Divider,
  ScrollController, TextArea, TextController, Select, FlexAlign,
  Alignment, FontWeight, BarState, ScrollEdgeEffect, Scroller,
  VerticalAlignment, EllipsisMode, ScrollState, KeyEvent,
} from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { initAppContext } from '../utils/PreferenceUtil'
import { DeepSeekApi } from '../service/DeepSeekApi'
import { StorageUtil } from '../utils/StorageUtil'
import { UserRole, ThinkDepth } from '../model/ChatModel'
import { promptAction } from '@kit.ArkUI'

const DOMAIN = 0x0000
const TAG = 'ChatPage'

type Msg = {
  id: string
  role: string
  content: string
  reasoningContent: string
  reasoningVisible: boolean
  timestamp: number
}

@Entry
@Component
struct ChatPage {
  @State messages: Msg[] = []
  @State inputText: string = ''
  @State isStreaming: boolean = false
  @State showSettings: boolean = false
  @State config: {
    model: string
    thinkDepth: ThinkDepth
    apiKey: string
  } = {
    model: 'deepseek-v4-flash',
    thinkDepth: ThinkDepth.OFF,
    apiKey: '',
  }
  @State convTitle: string = ''
  @State convId: string = ''

  scrollTimer: number = 0
  listScroller: ScrollController = new ScrollController()
  rowScroller: Scroller = new Scroller()
  textCtrl: TextController = new TextController()

  aboutToAppear(): void {
    initAppContext(this)
    this.loadConfig()
    this.loadConversationMap()
  }

  loadConfig(): void {
    this.config = {
      model: StorageUtil.getDefaultModel(),
      thinkDepth: StorageUtil.getDefaultThink() === 'high'
        ? ThinkDepth.HIGH
        : StorageUtil.getDefaultThink() === 'max'
          ? ThinkDepth.MAX
          : ThinkDepth.OFF,
      apiKey: StorageUtil.getApiKey(),
    }
  }

  loadConversationMap(): void {
    const map = StorageUtil.loadConversationMap()
    if (map.size === 0) {
      this.createNewConversation()
      return
    }
    const keys = Array.from(map.keys())
    this.convId = keys[0]
    this.convTitle = map.get(this.convId) ?? ''
    this.loadMessages(this.convId)
  }

  createNewConversation(): void {
    const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 7)
    this.convId = id
    this.convTitle = '新对话'
    this.messages = []
    const map = StorageUtil.loadConversationMap()
    map.set(id, this.convTitle)
    StorageUtil.saveConversationMap(map)
    StorageUtil.setStringSync('conv_' + id, JSON.stringify([]))
  }

  loadMessages(id: string): void {
    const raw = StorageUtil.getStringSync('conv_' + id, '[]')
    try {
      const list = JSON.parse(raw)
      if (!Array.isArray(list)) {
        this.messages = []
        return
      }
      this.messages = list.map((m: any) => ({
        id: m.id ?? (Date.now().toString(36) + Math.random().toString(36).slice(2, 6)),
        role: m.role ?? UserRole.USER,
        content: m.content ?? '',
        reasoningContent: m.reasoning ?? '',
        reasoningVisible: false,
        timestamp: m.timestamp ?? 0,
      }))
    } catch (e) {
      this.messages = []
    }
  }

  persistMessages(): void {
    const arr = this.messages.map(m => ({
      id: m.id,
      role: m.role,
      content: m.content,
      reasoning: m.reasoningContent,
      timestamp: m.timestamp,
    }))
    try {
      StorageUtil.setStringSync('conv_' + this.convId, JSON.stringify(arr))
      const map = StorageUtil.loadConversationMap()
      map.set(this.convId, this.convTitle)
      StorageUtil.saveConversationMap(map)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'persistMessages failed: %s', JSON.stringify(e))
    }
  }

  switchConversation(id: string): void {
    if (this.isStreaming) {
      promptAction.showToast({ message: '请等待当前回复完成' })
      return
    }
    this.persistMessages()
    this.convId = id
    const map = StorageUtil.loadConversationMap()
    this.convTitle = map.get(id) ?? '未命名对话'
    this.loadMessages(id)
    this.showSettings = false
  }

  async sendMessage(): Promise<void> {
    const text = this.inputText.trim()
    if (!text || this.isStreaming) return
    this.inputText = ''
    this.textCtrl.deselectText()

    if (!this.config.apiKey) {
      promptAction.showToast({ message: '请先在设置中填写 API Key' })
      return
    }

    const uid: string = Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
    const userMsg: Msg = {
      id: uid,
      role: UserRole.USER,
      content: text,
      reasoningContent: '',
      reasoningVisible: false,
      timestamp: Date.now(),
    }
    this.messages = [...this.messages, userMsg]
    if (this.messages.filter(m => m.role === UserRole.USER).length === 1) {
      this.convTitle = text.slice(0, 20) || '新对话'
    }
    this.persistMessages()

    const aid: string = (Date.now() + 1).toString(36) + Math.random().toString(36).slice(2, 6)
    const assistantMsg: Msg = {
      id: aid,
      role: UserRole.ASSISTANT,
      content: '',
      reasoningContent: '',
      reasoningVisible: false,
      timestamp: Date.now(),
    }
    this.messages = [...this.messages, assistantMsg]
    this.isStreaming = true

    const apiMessages = this.buildApiMessages()
    const lastIdx = this.messages.length - 1
    let toolCallDetected = false
    let assistantBuffer = ''

    await DeepSeekApi.chatStream(
      this.config.apiKey,
      this.config.model,
      apiMessages,
      this.config.thinkDepth,
      (content: string, reasoning: string) => {
        if (reasoning) {
          const cur = this.messages[lastIdx]
          this.messages = this.messages.slice(0, lastIdx).concat([{
            ...cur,
            reasoningContent: cur.reasoningContent + reasoning,
          }])
        }
        if (content) {
          assistantBuffer += content
          const cur = this.messages[lastIdx]
          this.messages = this.messages.slice(0, lastIdx).concat([{
            ...cur,
            content: cur.content + content,
          }])
          this.scheduleScroll()
        }
      },
    )

    if (
      assistantBuffer.includes('get_current_system_time') ||
      assistantBuffer.includes('function_call')
    ) {
      toolCallDetected = true
    }

    if (toolCallDetected) {
      const toolResult = new Date().toLocaleString('zh-CN', {
        hour12: false,
      })
      const toolMsg: Msg = {
        id: (Date.now() + 2).toString(36),
        role: UserRole.SYSTEM,
        content: '[工具结果] get_current_system_time 返回: ' + toolResult,
        reasoningContent: '',
        reasoningVisible: false,
        timestamp: Date.now(),
      }
      this.messages = [...this.messages, toolMsg]

      const cur = this.messages[lastIdx]
      const cleanedLast = {
        ...cur,
        content: '',
        reasoningContent: '',
      }
      this.messages = this.messages.slice(0, lastIdx).concat([cleanedLast])

      await DeepSeekApi.chatStream(
        this.config.apiKey,
        this.config.model,
        this.buildApiMessages(),
        this.config.thinkDepth,
        (content: string, reasoning: string) => {
          const idx = this.messages.length - 1
          if (reasoning) {
            const c = this.messages[idx]
            this.messages = this.messages.slice(0, idx).concat([{
              ...c,
              reasoningContent: c.reasoningContent + reasoning,
            }])
          }
          if (content) {
            const c = this.messages[idx]
            this.messages = this.messages.slice(0, idx).concat([{
              ...c,
              content: c.content + content,
            }])
            this.scheduleScroll()
          }
        },
      )
    }

    this.isStreaming = false
    this.persistMessages()
  }

  buildApiMessages(): Array<{
    role: string
    content: string
    reasoning_content?: string
  }> {
    const result: Array<{
      role: string
      content: string
      reasoning_content?: string
    }> = []
    for (const m of this.messages) {
      const item: any = { role: m.role, content: m.content }
      if (m.reasoningContent) {
        item.reasoning_content = m.reasoningContent
      }
      result.push(item)
    }
    const sys: any = {
      role: 'system',
      content: 'You are a helpful assistant. 需要当前时间时调用 get_current_system_time。',
    }
    result.unshift(sys)
    return result
  }

  scheduleScroll(): void {
    clearTimeout(this.scrollTimer)
    this.scrollTimer = setTimeout(() => {
      if (this.messages.length > 0) {
        this.listScroller.scrollToIndex(this.messages.length - 1)
      }
    }, 30) as unknown as number
  }

  saveSettings(): void {
    StorageUtil.saveApiKey(this.config.apiKey)
    StorageUtil.saveDefaultModel(this.config.model)
    const thinkStr =
      this.config.thinkDepth === ThinkDepth.HIGH
        ? 'high'
        : this.config.thinkDepth === ThinkDepth.MAX
          ? 'max'
          : 'off'
    StorageUtil.saveDefaultThink(thinkStr)
    this.showSettings = false
    promptAction.showToast({ message: '设置已保存' })
  }

  newChat(): void {
    if (this.isStreaming) return
    this.persistMessages()
    this.createNewConversation()
  }

  clearChat(): void {
    if (this.isStreaming) return
    this.messages = []
    this.persistMessages()
  }

  toggleSettings(): void {
    this.showSettings = !this.showSettings
  }

  @Builder
  buildUserBubble(msg: Msg) {
    Row() {
      Column() {
        Text(msg.content)
          .fontSize(15)
          .textAlign(TextAlign.Start)
          .maxLines(500)
          .width('100%')
      }
      .backgroundColor('#95ec69')
      .borderRadius(16)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .width('78%')
  }

  @Builder
  buildSystemBubble(msg: Msg) {
    Row() {
      Column() {
        Text(msg.content)
          .fontSize(12)
          .fontColor('#888')
          .maxLines(200)
      }
      .backgroundColor('#f0f0f0')
      .borderRadius(8)
      .padding(8)
    }
    .width('94%')
  }

  @Builder
  buildAssistantBubble(msg: Msg, index: number) {
    Column() {
      if (msg.reasoningContent) {
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
      if (msg.content) {
        Text(msg.content)
          .fontSize(15)
          .textAlign(TextAlign.Start)
          .maxLines(1000)
          .width('100%')
      }
    }
    .width('78%')
    .borderRadius(16)
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  toggleReasoning(id: string): void {
    this.messages = this.messages.map(m =>
      m.id === id ? { ...m, reasoningVisible: !m.reasoningVisible } : m,
    )
  }

  @Builder
  buildSettingsPanel() {
    const convMap = StorageUtil.loadConversationMap()
    const convArr: Array<[string, string]> = Array.from(convMap.entries())

    Column() {
      Text('会话历史').fontSize(15).fontWeight(FontWeight.Bold).width('100%').margin({ bottom: 6 })
      if (convArr.length === 0) {
        Text('暂无历史会话')
          .fontSize(13)
          .fontColor('#888')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 10 })
      } else {
        Scroll({ scroller: this.rowScroller, state: ScrollState.Forward }) {
          Row() {
            ForEach(convArr, item => {
              Row() {
                Text(item[1])
                  .fontSize(13)
                  .maxLines(1)
                  .ellipsisMode(EllipsisMode.END)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              }
              .backgroundColor(item[0] === this.convId ? '#bbdefb' : '#eeeeee')
              .borderRadius(16)
              .margin({ left: 4, right: 4 })
              .onClick(() => {
                if (item[0] === this.convId) return
                this.switchConversation(item[0])
              })
            })
          }
          .alignItems(VerticalAlignment.Center)
          .width('100%')
          .space(6)
        }
        .width('100%')
        .height(52)
        .scrollBar(BarState.Auto)
      }

      Text('API Key (必填)').margin({ top: 10, bottom: 4 }).fontSize(14)
      TextInput({
        placeholder: 'sk-xxxxxxxxxxxxxxxx',
        text: this.config.apiKey,
      })
        .height(40)
        .width('100%')
        .backgroundColor('#f5f5f5')
        .margin({ bottom: 8 })
        .onChange(val => {
          this.config = { ...this.config, apiKey: val }
        })

      Text('模型').fontSize(14).margin({ bottom: 4 })
      Select([
        { value: 'deepseek-v4-flash', label: 'deepseek-v4-flash (推荐)' },
        { value: 'deepseek-v4-pro', label: 'deepseek-v4-pro' },
      ])
        .value(this.config.model)
        .width('100%')
        .margin({ bottom: 10 })
        .onSelect(idx => {
          this.config = {
            ...this.config,
            model: idx === 0 ? 'deepseek-v4-flash' : 'deepseek-v4-pro',
          }
        })

      Text('思考模式').fontSize(14).margin({ bottom: 4 })
      Select([
        { value: 'off', label: '关闭' },
        { value: 'high', label: 'high' },
        { value: 'max', label: 'max (最深)' },
      ])
        .value(this.config.thinkDepth)
        .width('100%')
        .margin({ bottom: 10 })
        .onSelect(idx => {
          const depths: ThinkDepth[] = [ThinkDepth.OFF, ThinkDepth.HIGH, ThinkDepth.MAX]
          this.config = { ...this.config, thinkDepth: depths[idx] }
        })

      Row() {
        Blank()
        Button('保存').fontSize(14).onClick(() => {
          this.saveSettings()
        })
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

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Text(this.convTitle)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .maxLines(1)
            .ellipsisMode(EllipsisMode.END)
          Blank()
          Button('新建').fontSize(13).onClick(() => this.newChat())
          Button('清除').fontSize(13).onClick(() => this.clearChat())
          Button(this.showSettings ? '关闭' : '设置').fontSize(13).onClick(() => {
            this.toggleSettings()
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 6 })
        .backgroundColor('#f5f5f5')

        if (this.showSettings) {
          Divider()
          this.buildSettingsPanel()
        }

        Divider()

        List({ scroller: this.listScroller }) {
          ForEach(this.messages, (msg: Msg, index: number) => {
            ListItem() {
              Column() {
                if (msg.role === UserRole.USER) {
                  this.buildUserBubble(msg)
                } else if (msg.role === UserRole.SYSTEM) {
                  this.buildSystemBubble(msg)
                } else {
                  this.buildAssistantBubble(msg, index)
                }
              }
              .width('100%')
              .alignItems(
                msg.role === UserRole.USER ? Alignment.End : Alignment.Start,
              )
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
            .textAlign(TextAlign.Start)
            .height(56)
            .layoutWeight(1)
            .maxLines(5)
            .autoKeyboard(true)
            .margin({ right: 8 })
            .onChange(val => {
              this.inputText = val
            })

          Button(this.isStreaming ? '停止' : '发送')
            .width(80)
            .height(44)
            .fontSize(14)
            .enabled(!this.isStreaming ? this.inputText.trim().length > 0 : true)
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
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
    .onKeyEvent((event: KeyEvent) => {
      if (event.keyCode === 13 && event.action === KeyEvent.ACTION_UP) {
        if (!this.isStreaming) {
          this.sendMessage()
        }
        return true
      }
      return false
    })
  }
}
