import { Column, Row, Text, TextInput, Button, List, Blank, Divider, ScrollController, TextArea, Select, FlexAlign, Alignment, FontWeight, BarState, TextController } from '@kit.ArkUI'
import { DeepSeekApi } from '../service/DeepSeekApi'
import { StorageUtil, ConvItem, MsgItem } from '../utils/StorageUtil'
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

class ChatConf {
  model: string
  thinkDepth: ThinkDepth
  apiKey: string

  constructor(model: string = 'deepseek-v4-flash', thinkDepth: ThinkDepth = ThinkDepth.OFF, apiKey: string = '') {
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
  @State streaming: boolean = false
  @State conf: ChatConf = new ChatConf()
  @State title: string = ''
  @State convId: string = ''
  @State settingsOpen: boolean = false

  scroller: ScrollController = new ScrollController()
  rowScroll: ScrollController = new ScrollController()
  ctrl: TextController = new TextController()
  timer: number = 0

  aboutToAppear(): void {
    this.conf = new ChatConf()
    this.conf.model = StorageUtil.getModel()
    const think = StorageUtil.getThink()
    this.conf.thinkDepth = think === 'high' ? ThinkDepth.HIGH : think === 'max' ? ThinkDepth.MAX : ThinkDepth.OFF
    this.conf.apiKey = StorageUtil.getApiKey()
    const convs = StorageUtil.getConvMap()
    if (convs.length === 0) {
      this.newConversation()
    } else {
      this.convId = convs[0].id
      this.title = convs[0].title
      this.loadMessages(this.convId)
    }
  }

  newConversation(): void {
    const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 7)
    this.convId = id
    this.title = 'New Chat'
    this.messages = []
    const c0 = new ConvItem(id, this.title)
    const arr: ConvItem[] = []
    arr.push(c0)
    StorageUtil.saveConvMap(arr)
    StorageUtil.saveMessages(id, [])
  }

  loadMessages(id: string): void {
    const list = StorageUtil.getMessages(id)
    const out: ChatMsg[] = []
    let i = 0
    while (i < list.length) {
      const it = list[i]
      out.push(new ChatMsg(it.id, it.role, it.content, it.reasoning, false, it.timestamp))
      i = i + 1
    }
    this.messages = out
  }

  persist(): void {
    const arr: MsgItem[] = []
    let i = 0
    while (i < this.messages.length) {
      const m = this.messages[i]
      arr.push(new MsgItem(m.id, m.role, m.content, m.reasoningContent, m.timestamp))
      i = i + 1
    }
    StorageUtil.saveMessages(this.convId, arr)
    const convs: ConvItem[] = []
    convs.push(new ConvItem(this.convId, this.title))
    StorageUtil.saveConvMap(convs)
  }

  switchConv(id: string): void {
    if (this.streaming) { return }
    this.persist()
    this.convId = id
    const convs = StorageUtil.getConvMap()
    let i = 0
    while (i < convs.length) {
      if (convs[i].id === id) { this.title = convs[i].title; break }
      i = i + 1
    }
    this.loadMessages(id)
    this.settingsOpen = false
  }

  sendMessage(): void {
    const text = this.inputText.trim()
    if (text.length === 0 || this.streaming) { return }
    this.inputText = ''
    if (this.conf.apiKey.length === 0) { return }
    const uid = Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
    const userMsg = new ChatMsg(uid, UserRole.USER, text, '', false, Date.now())
    this.messages = this.appendMsg(userMsg)
    if (this.countUser() === 1) { this.title = text.slice(0, 20) }
    this.persist()
    const aid = Date.now().toString(36)
    const bot = new ChatMsg(aid, UserRole.ASSISTANT, '', '', false, Date.now())
    const idx = this.messages.length
    this.messages = this.appendMsg(bot)
    this.streaming = true
    const apiMsgs = this.buildApiMsgs()
    DeepSeekApi.chatStream(this.conf.model, apiMsgs, this.conf.thinkDepth, (content: string, reasoning: string) => {
      if (reasoning.length > 0) {
        const cur = this.getMessage(idx)
        const upd = new ChatMsg(cur.id, cur.role, cur.content, cur.reasoningContent + reasoning, cur.reasoningVisible, cur.timestamp)
        this.setMessage(idx, upd)
      }
      if (content.length > 0) {
        const cur = this.getMessage(idx)
        const upd = new ChatMsg(cur.id, cur.role, cur.content + content, cur.reasoningContent, cur.reasoningVisible, cur.timestamp)
        this.setMessage(idx, upd)
        this.scroll()
      }
    })
    this.streaming = false
    this.persist()
  }

  buildApiMsgs(): string[] {
    const out: string[] = []
    let i = 0
    while (i < this.messages.length) {
      const m = this.messages[i]
      const role = m.role
      const content = m.content
      if (role.length > 0 && content.length > 0) { out.push(role + '|' + content) }
      i = i + 1
    }
    return out
  }

  getMessage(i: number): ChatMsg { return this.messages[i] }

  setMessage(i: number, m: ChatMsg): void {
    const arr = this.messages.slice(0)
    arr[i] = m
    this.messages = arr
  }

  appendMsg(m: ChatMsg): ChatMsg[] {
    const arr = this.messages.slice(0)
    arr.push(m)
    return arr
  }

  countUser(): number {
    let n = 0
    let i = 0
    while (i < this.messages.length) {
      if (this.messages[i].role === UserRole.USER) { n = n + 1 }
      i = i + 1
    }
    return n
  }
  scroll(): void {
    setTimeout(() => {
      this.scroller.scrollToIndex(this.messages.length - 1)
    }, 30)
  }
  save(): void {
    StorageUtil.saveApiKey(this.conf.apiKey)
    StorageUtil.saveModel(this.conf.model)
    const d = this.conf.thinkDepth
    StorageUtil.saveThink(d === ThinkDepth.HIGH ? 'high' : d === ThinkDepth.MAX ? 'max' : 'off');
    this.settingsOpen = false;
  }

  newChat(): void { if (this.streaming) { return } this.persist(); this.newConversation() }

  clearChat(): void { if (this.streaming) { return } this.messages = []; this.persist() }

  toggleReasoning(id: string): void {
    const arr = this.messages.slice(0)
    let i = 0
    while (i < arr.length) {
      if (arr[i].id === id) {
        const m = arr[i]
        const upd = new ChatMsg(m.id, m.role, m.content, m.reasoningContent, !m.reasoningVisible, m.timestamp)
        arr[i] = upd
        break
      }
      i = i + 1
    }
    this.messages = arr
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Text(this.title).fontSize(17).fontWeight(FontWeight.Bold).layoutWeight(1)
          Button('New').fontSize(13).onClick(() => this.newChat())
          Button('Clear').fontSize(13).onClick(() => this.clearChat())
          Button(this.settingsOpen ? 'Close' : 'Settings').fontSize(13).onClick(() => { this.settingsOpen = !this.settingsOpen })
        }
        .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 6 }).backgroundColor('#f5f5f5')

        if (this.settingsOpen) {
          Divider()
          Column() {
            Text('History').fontSize(15).fontWeight(FontWeight.Bold).width('100%').margin({ bottom: 6 })
            Scroll(this.rowScroll) {
              Row() {
                ForEach(StorageUtil.getConvMap(), (c: ConvItem) => {
                  Row() {
                    Text(c.title).fontSize(13).maxLines(1).padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  }
                  .backgroundColor(c.id === this.convId ? '#bbdefb' : '#eeeeee')
                  .borderRadius(16).margin({ left: 4, right: 4 })
                  .onClick(() => { if (c.id !== this.convId) { this.switchConv(c.id) } })
                })
              }
              .width('100%').space(6)
            }
            .width('100%').height(52)

            Text('API Key').margin({ top: 10, bottom: 4 }).fontSize(14)
            TextInput({ placeholder: 'sk-...', text: this.conf.apiKey })
              .height(40).width('100%').backgroundColor('#f5f5f5').margin({ bottom: 8 })
              .onChange((v: string) => {
                const c = this.conf
                this.conf = new ChatConf()
                this.conf.model = c.model
                this.conf.thinkDepth = c.thinkDepth
                this.conf.apiKey = v
              })

            Text('Model').margin({ bottom: 4 }).fontSize(14)
            Select([
              { value: 'deepseek-v4-flash', label: 'deepseek-v4-flash' },
              { value: 'deepseek-v4-pro', label: 'deepseek-v4-pro' },
            ])
              .value(this.conf.model).width('100%').margin({ bottom: 10 })
              .onSelect((idx: number) => {
                this.conf = new ChatConf(idx === 0 ? 'deepseek-v4-flash' : 'deepseek-v4-pro', this.conf.thinkDepth, this.conf.apiKey)
              })

            Text('Think Mode').margin({ bottom: 4 }).fontSize(14)
            Select([
              { value: ThinkDepth.OFF, label: 'Off' },
              { value: ThinkDepth.HIGH, label: 'High' },
              { value: ThinkDepth.MAX, label: 'Max' },
            ])
              .value(this.conf.thinkDepth).width('100%').margin({ bottom: 10 })
              .onSelect((idx: number) => {
                const depths: ThinkDepth[] = [ThinkDepth.OFF, ThinkDepth.HIGH, ThinkDepth.MAX]
                this.conf = new ChatConf(this.conf.model, depths[idx], this.conf.apiKey)
              })

            Button('Save').fontSize(14).onClick(() => this.save())
          }
          .width('100%').padding(16).backgroundColor('#fafafa')
        }

        Divider()

        List({ scroller: this.scroller }) {
          ForEach(this.messages, (msg: ChatMsg, index: number) => {
            ListItem() {
              if (msg.role === UserRole.USER) {
                Row() { Text(msg.content).fontSize(15).maxLines(500).width('100%') }
                .width('78%').backgroundColor('#95ec69').borderRadius(16).padding({ left: 12, right: 12, top: 8, bottom: 8 })
              } else if (msg.role === UserRole.SYSTEM) {
                Row() { Text(msg.content).fontSize(12).fontColor('#888').maxLines(200).width('94%') }
                .width('94%')
              } else {
                Column() {
                  if (msg.reasoningContent.length > 0) {
                    Text(msg.reasoningVisible ? 'Collapse' : 'Expand').fontSize(12).fontColor('#1565c0').onClick(() => this.toggleReasoning(msg.id))
                    if (msg.reasoningVisible) {
                      Text(msg.reasoningContent).fontSize(13).fontColor('#555').maxLines(500).padding(6).backgroundColor('#f9f9f9').borderRadius(6).width('100%')
                    }
                  }
                  if (msg.content.length > 0) { Text(msg.content).fontSize(15).maxLines(1000).width('100%') }
                }
                .width('78%').borderRadius(16).padding({ left: 12, right: 12, top: 8, bottom: 8 })
              }
            }
          })
        }
        .scrollBar(BarState.Auto).layoutWeight(1).width('100%')

        Row() {
          TextArea({ placeholder: 'Type message...', controller: this.ctrl })
            .placeholderColor('#aaaaaa').height(56).layoutWeight(1).maxLines(5).autoKeyboard(true).margin({ right: 8 })
            .onChange((v: string) => { this.inputText = v })
          Button(this.streaming ? 'Stop' : 'Send').width(80).height(44).fontSize(14)
            .onClick(() => { if (this.streaming) { this.streaming = false } else { this.sendMessage() } })
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 10 }).backgroundColor('#fafafa')
        .border({ width: { top: 0.5 } })
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }
}
