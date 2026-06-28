import { ChatController } from '../common/ChatController';
import { ChatMessage, Conversation, ToolCall } from '../common/Storage';
import { sendChatStream, SendOptions } from '../common/DeepSeekService';
import { router } from '@kit.ArkUI';

type UiRole = 'user' | 'assistant' | 'system' | 'tool';

class ToolCallDisplay {
  id: string = '';
  name: string = '';
  args: string = '';
  result: string = '';
}

class UiMessage {
  key: string = '';
  role: UiRole = 'assistant';
  content: string = '';
  reasoning: string = '';
  streaming: boolean = false;
  toolCalls: ToolCallDisplay[] = [];
  showReasoning: boolean = false;
}

@Entry
@Component
struct Index {
  controller: ChatController = ChatController.get();

  @State uiMessages: UiMessage[] = [];
  @State inputText: string = '';
  @State sending: boolean = false;
  @State thinkingVisible: boolean = true;
  @State statusText: string = '';
  @State currentConv: Conversation | null = null;
  @State apiKeyWarning: boolean = false;

  private scroller: Scroller = new Scroller();
  private tokenCounter: number = 0;
  private cancelRequested: boolean = false;

  aboutToAppear(): void {
    this.controller.load();
    if (!this.controller.getCurrentConversation()) {
      this.controller.startNewConversation();
    }
    this.refreshFromStorage();
    this.apiKeyWarning = this.controller.settings.apiKey.length === 0;
  }

  onPageShow(): void {
    this.refreshFromStorage();
    this.apiKeyWarning = this.controller.settings.apiKey.length === 0;
  }

  private refreshFromStorage(): void {
    const conv = this.controller.ensureCurrent();
    this.currentConv = conv;
    this.thinkingVisible = conv.thinkingEnabled;
    this.uiMessages = this.convertMessages(conv.messages);
  }

  private convertMessages(list: ChatMessage[]): UiMessage[] {
    const out: UiMessage[] = [];
    for (let i = 0; i < list.length; i++) {
      const m = list[i];
      const ui = new UiMessage();
      ui.key = `m_${i}_${this.tokenCounter++}`;
      if (m.role === 'system') {
        ui.role = 'system';
      } else if (m.role === 'tool') {
        ui.role = 'tool';
      } else if (m.role === 'user') {
        ui.role = 'user';
      } else {
        ui.role = 'assistant';
      }
      ui.content = m.content;
      ui.reasoning = m.reasoning;
      out.push(ui);
    }
    return out;
  }

  build() {
    Column() {
      this.headerBar()

      if (this.apiKeyWarning) {
        this.apiKeyBanner()
      }

      Scroll(this.scroller) {
        Column() {
          if (this.uiMessages.length === 0) {
            this.emptyState()
          } else {
            ForEach(this.uiMessages, (item: UiMessage) => {
              this.messageBubble(item)
            }, (item: UiMessage) => item.key)
          }
          if (this.statusText.length > 0) {
            Text(this.statusText)
              .fontSize(12)
              .fontColor('#999999')
              .margin({ top: 8, bottom: 8 })
          }
        }
        .padding(12)
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#F7F8FA')
      .onAppear(() => {
        this.scrollToBottom();
      })

      this.inputBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8FA')
  }

  @Builder
  headerBar() {
    Row() {
      Column() {
        Text(this.currentConv?.title ?? 'DeepSeek Chat')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.subtitleText())
          .fontSize(11)
          .fontColor('#666666')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('🕒')
        .fontSize(18)
        .padding(6)
        .onClick(() => {
          router.pushUrl({ url: 'pages/History' });
        })
      Text('⚙')
        .fontSize(18)
        .padding(6)
        .onClick(() => {
          router.pushUrl({ url: 'pages/Settings' });
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 12 })
    .backgroundColor(Color.White)
  }

  private subtitleText(): string {
    const s = this.controller.settings;
    const think = s.thinkingEnabled ? `思考 ${s.reasoningEffort}` : '思考关';
    const tools = s.toolsEnabled ? '· 工具开' : '· 工具关';
    return `${s.model} · ${think} ${tools}`;
  }

  @Builder
  apiKeyBanner() {
    Row() {
      Text('⚠ 未配置 API Key,请先到设置填写')
        .fontSize(13)
        .fontColor('#A14D00')
        .layoutWeight(1)
      Text('去设置')
        .fontSize(13)
        .fontColor('#0A59F7')
        .onClick(() => {
          router.pushUrl({ url: 'pages/Settings' });
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFF7E6')
  }

  @Builder
  emptyState() {
    Column() {
      Text('DeepSeek Chat')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 60 })
      Text('支持思考模式、流式输出、工具调用、多轮对话')
        .fontSize(14)
        .fontColor('#888888')
        .margin({ top: 12 })
      Text('点击右上角 ⚙ 配置 API Key 后开始对话')
        .fontSize(13)
        .fontColor('#AAAAAA')
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  messageBubble(m: UiMessage) {
    if (m.role === 'user') {
      Row() {
        Text(m.content)
          .fontSize(15)
          .fontColor(Color.White)
          .padding(12)
          .backgroundColor('#0A59F7')
          .borderRadius(12)
          .constraintSize({ maxWidth: '80%' })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 8 })
    } else if (m.role === 'assistant') {
      Column() {
        if (m.reasoning.length > 0) {
          Row() {
            Text('💭 思考过程')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)
            Text(m.showReasoning ? '收起' : '展开')
              .fontSize(12)
              .fontColor('#0A59F7')
              .onClick(() => {
                this.toggleReasoning(m);
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 4 })

          if (m.showReasoning) {
            Text(m.reasoning + (m.streaming ? ' ▍' : ''))
              .fontSize(13)
              .fontColor('#555555')
              .padding(12)
              .backgroundColor('#EEF2FF')
              .borderRadius(8)
              .width('100%')
          }
        }

        Text(this.assistantBodyText(m))
          .fontSize(15)
          .fontColor('#222222')
          .padding(12)
          .backgroundColor(Color.White)
          .borderRadius(8)
          .width('100%')
          .margin({ top: m.reasoning.length > 0 ? 6 : 0 })

        if (m.toolCalls.length > 0) {
          ForEach(m.toolCalls, (tc: ToolCallDisplay) => {
            this.toolCallCard(tc)
          }, (tc: ToolCallDisplay) => tc.id)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .margin({ top: 8 })
    } else if (m.role === 'tool') {
      Text('(工具结果) ' + m.content)
        .fontSize(12)
        .fontColor('#2A7A2A')
        .padding(8)
        .backgroundColor('#F0F8F0')
        .borderRadius(8)
        .margin({ top: 4 })
        .width('100%')
    }
  }

  @Builder
  toolCallCard(tc: ToolCallDisplay) {
    Column() {
      Row() {
        Text('🔧 工具调用')
          .fontSize(12)
          .fontColor('#666')
          .layoutWeight(1)
        Text(tc.name)
          .fontSize(12)
          .fontColor('#0A59F7')
      }
      .width('100%')
      Text(tc.args)
        .fontSize(12)
        .fontColor('#444')
        .margin({ top: 4 })
      if (tc.result.length > 0) {
        Text('↳ 结果: ' + tc.result)
          .fontSize(12)
          .fontColor('#2A7A2A')
          .margin({ top: 4 })
      }
    }
    .padding(10)
    .backgroundColor('#FAFAFA')
    .borderRadius(8)
    .margin({ top: 6 })
    .width('100%')
  }

  private assistantBodyText(m: UiMessage): string {
    const base = m.content.length > 0 ? m.content : (m.streaming ? '' : '(空响应)');
    return base + (m.streaming ? ' ▍' : '');
  }

  private toggleReasoning(m: UiMessage): void {
    const idx = this.findIndex(m);
    if (idx < 0) {
      return;
    }
    const arr = this.uiMessages.slice();
    const cur = arr[idx];
    const updated = new UiMessage();
    updated.key = cur.key;
    updated.role = cur.role;
    updated.content = cur.content;
    updated.reasoning = cur.reasoning;
    updated.streaming = cur.streaming;
    updated.toolCalls = cur.toolCalls;
    updated.showReasoning = !cur.showReasoning;
    arr[idx] = updated;
    this.uiMessages = arr;
  }

  private findIndex(m: UiMessage): number {
    for (let i = 0; i < this.uiMessages.length; i++) {
      if (this.uiMessages[i].key === m.key) {
        return i;
      }
    }
    return -1;
  }

  @Builder
  inputBar() {
    Column() {
      Divider().color('#EAEAEA')

      Row() {
        Button(this.sending ? '停止' : '发送')
          .height(40)
          .width(72)
          .fontSize(14)
          .backgroundColor(this.sending ? '#FF4D4F' : '#0A59F7')
          .onClick(() => {
            if (this.sending) {
              this.cancelRequested = true;
              this.statusText = '已请求取消,等待当前响应结束…';
            } else {
              this.send();
            }
          })

        TextInput({ text: this.inputText, placeholder: '输入消息,Enter 发送' })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#F2F3F5')
          .borderRadius(20)
          .padding({ left: 12, right: 12 })
          .margin({ left: 8 })
          .onChange((v) => {
            this.inputText = v;
          })
          .onSubmit(() => {
            if (!this.sending) {
              this.send();
            }
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(Color.White)
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 30);
  }

  private pushUiMessage(m: UiMessage): void {
    const arr = this.uiMessages.slice();
    arr.push(m);
    this.uiMessages = arr;
    this.scrollToBottom();
  }

  private cloneUi(m: UiMessage): UiMessage {
    const tcs: ToolCallDisplay[] = [];
    for (let i = 0; i < m.toolCalls.length; i++) {
      const tc = m.toolCalls[i];
      const c = new ToolCallDisplay();
      c.id = tc.id;
      c.name = tc.name;
      c.args = tc.args;
      c.result = tc.result;
      tcs.push(c);
    }
    const r = new UiMessage();
    r.key = m.key;
    r.role = m.role;
    r.content = m.content;
    r.reasoning = m.reasoning;
    r.streaming = m.streaming;
    r.toolCalls = tcs;
    r.showReasoning = m.showReasoning;
    return r;
  }

  private updateLastUi(updater: (m: UiMessage) => void): void {
    if (this.uiMessages.length === 0) {
      return;
    }
    const idx = this.uiMessages.length - 1;
    const cloned = this.cloneUi(this.uiMessages[idx]);
    updater(cloned);
    const arr = this.uiMessages.slice();
    arr[idx] = cloned;
    this.uiMessages = arr;
  }

  private send(): void {
    const text = this.inputText.trim();
    if (text.length === 0) {
      return;
    }
    if (this.controller.settings.apiKey.length === 0) {
      this.apiKeyWarning = true;
      this.statusText = '请先在设置中填写 API Key';
      return;
    }
    const userMsg = new ChatMessage();
    userMsg.role = 'user';
    userMsg.content = text;
    this.controller.appendMessage(userMsg);
    const userUi = new UiMessage();
    userUi.key = `u_${this.tokenCounter++}`;
    userUi.role = 'user';
    userUi.content = text;
    this.pushUiMessage(userUi);
    this.inputText = '';

    const conv = this.controller.getCurrentConversation();
    if (conv && conv.messages.length > 0 && conv.messages[0].role !== 'system'
        && this.controller.settings.systemPrompt.length > 0) {
      const sys = new ChatMessage();
      sys.role = 'system';
      sys.content = this.controller.settings.systemPrompt;
      conv.messages.unshift(sys);
      this.controller.saveConversations();
    }

    this.startAssistantStream();
  }

  private startAssistantStream(): void {
    this.sending = true;
    this.cancelRequested = false;
    this.statusText = '正在连接…';

    const assistantKey = `a_${this.tokenCounter++}`;
    const uiPlaceholder = new UiMessage();
    uiPlaceholder.key = assistantKey;
    uiPlaceholder.role = 'assistant';
    uiPlaceholder.streaming = true;
    uiPlaceholder.showReasoning = this.thinkingVisible;
    this.pushUiMessage(uiPlaceholder);

    const conv = this.controller.getCurrentConversation();
    const settings = this.controller.settings;
    let messagesForApi: ChatMessage[] = conv ? conv.messages.slice() : [];

    let accContent = '';
    let accReasoning = '';

    const sendOpts = new SendOptions();
    sendOpts.apiKey = settings.apiKey;
    sendOpts.baseUrl = settings.baseUrl;
    sendOpts.model = settings.model;
    sendOpts.messages = messagesForApi;
    sendOpts.thinkingEnabled = settings.thinkingEnabled;
    sendOpts.reasoningEffort = settings.reasoningEffort;
    sendOpts.toolsEnabled = settings.toolsEnabled;
    const onContentDelta = (c: string): void => {
      accContent += c;
      this.updateLastUi((m: UiMessage): void => {
        m.content = accContent;
        m.streaming = true;
      });
      this.scrollToBottom();
    };
    const onReasoningDelta = (c: string): void => {
      accReasoning += c;
      this.updateLastUi((m: UiMessage): void => {
        m.reasoning = accReasoning;
        m.streaming = true;
        m.showReasoning = true;
      });
      this.scrollToBottom();
    };
    const onToolCallsProduced = (calls: ToolCall[], toolMessages: ChatMessage[]): void => {
      const newDisplays: ToolCallDisplay[] = [];
      for (let i = 0; i < calls.length; i++) {
        const tc = calls[i];
        const tm = i < toolMessages.length ? toolMessages[i] : null;
        const d = new ToolCallDisplay();
        d.id = tc.id;
        d.name = tc.function.name;
        d.args = tc.function.arguments;
        d.result = tm ? tm.content : '';
        newDisplays.push(d);
      }
      for (let i = 0; i < toolMessages.length; i++) {
        this.controller.appendMessage(toolMessages[i]);
        const toolUi = new UiMessage();
        toolUi.key = `t_${this.tokenCounter++}`;
        toolUi.role = 'tool';
        toolUi.content = toolMessages[i].content;
        this.pushUiMessage(toolUi);
      }
      this.updateLastUi((m: UiMessage): void => {
        for (let i = 0; i < newDisplays.length; i++) {
          m.toolCalls.push(newDisplays[i]);
        }
      });
      this.statusText = `工具调用 ${calls.length} 个,继续生成…`;
      this.scrollToBottom();
    };
    const onError = (msg: string): void => {
      this.statusText = `错误: ${msg}`;
    };

    sendChatStream(sendOpts, onContentDelta, onReasoningDelta, onToolCallsProduced, onError).then((res): void => {
      accContent = res.finalContent;
      this.updateLastUi((m: UiMessage): void => {
        m.content = accContent;
        m.streaming = false;
        if (accReasoning.length > 0) {
          m.reasoning = accReasoning;
        }
      });
      const finalAssistant = new ChatMessage();
      finalAssistant.role = 'assistant';
      finalAssistant.content = accContent;
      finalAssistant.reasoning = accReasoning;
      this.controller.appendMessage(finalAssistant);
      this.statusText = res.finishReason === 'error'
        ? `出错了(${accContent.substring(0, 80)})`
        : `完成 (${res.finishReason}, ${res.toolCallRounds} 轮, ${accContent.length}字)`;
      this.sending = false;
      this.scrollToBottom();
    });
  }
}