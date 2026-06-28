import { ChatMessage, ChatSession, Role, AppSettings, ToolCall } from '../model/ChatModels';
import { DeepSeekAPI } from '../api/DeepSeekAPI';
import { executeToolCall } from '../util/ToolHandler';
import {
  initPreferences,
  loadSettings,
  loadSessions,
  saveSessions,
  saveCurrentSessionId,
  loadCurrentSessionId
} from '../util/PreferencesUtil';
import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

interface HistoryNavParams {
  sessions: ChatSession[];
  onSelect: (s: ChatSession) => void;
  onDelete: (id: string) => void;
  onNewChat: () => void;
}

interface SettingsNavParams {
  settings: AppSettings;
  onSaved: (s: AppSettings) => void;
}

@Entry
@Component
struct Index {
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State isSending: boolean = false;
  @State settings: AppSettings = {
    apiKey: '',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-v4-flash',
    thinkingEnabled: true,
    reasoningEffort: 'high'
  };
  @State sessions: ChatSession[] = [];
  @State currentSession: ChatSession | null = null;
  @State api: DeepSeekAPI | null = null;
  @State showApiKeyHint: boolean = false;
  private scroller: Scroller = new Scroller();
  private isInitialized: boolean = false;

  async aboutToAppear(): Promise<void> {
    if (this.isInitialized) return;
    this.isInitialized = true;

    try {
      const context = getContext(this) as common.UIAbilityContext;
      await initPreferences(context);
    } catch (e) {
      console.error('initPreferences failed');
    }

    this.settings = await loadSettings();
    this.sessions = await loadSessions();
    this.api = new DeepSeekAPI(this.settings);
    this.showApiKeyHint = this.settings.apiKey.length === 0;

    const currentId = await loadCurrentSessionId();
    if (currentId.length > 0) {
      let found: ChatSession | null = null;
      for (let i = 0; i < this.sessions.length; i++) {
        if (this.sessions[i].id === currentId) {
          found = this.sessions[i];
          break;
        }
      }
      if (found) {
        this.currentSession = found;
        this.messages = found.messages.slice();
        return;
      }
    }
    this.createNewSession(false);
  }

  private createNewSession(persist: boolean): void {
    const session = new ChatSession();
    this.currentSession = session;
    this.messages = [];
    if (persist) {
      const newList: ChatSession[] = [session];
      for (let i = 0; i < this.sessions.length; i++) {
        newList.push(this.sessions[i]);
      }
      this.sessions = newList;
      this.persist();
    }
  }

  private persist(): void {
    if (this.currentSession) {
      this.currentSession.messages = this.messages.slice();
      this.currentSession.updatedAt = Date.now();
      let foundIdx = -1;
      for (let i = 0; i < this.sessions.length; i++) {
        if (this.sessions[i].id === this.currentSession.id) {
          foundIdx = i;
          break;
        }
      }
      if (foundIdx >= 0) {
        this.sessions[foundIdx] = this.currentSession;
      } else {
        const newList: ChatSession[] = [this.currentSession];
        for (let i = 0; i < this.sessions.length; i++) {
          newList.push(this.sessions[i]);
        }
        this.sessions = newList;
      }
    }
    saveSessions(this.sessions.slice());
    if (this.currentSession) {
      saveCurrentSessionId(this.currentSession.id);
    }
  }

  private refresh(): void {
    this.messages = this.messages.slice();
  }

  private scrollBottom(): void {
    setTimeout(() => {
      try { this.scroller.scrollEdge(Edge.Bottom); } catch (_) {}
    }, 30);
  }

  private setTitle(userMsg: ChatMessage): void {
    if (this.currentSession && this.currentSession.title === '新对话' && userMsg.content.length > 0) {
      this.currentSession.title = userMsg.content.length > 20
        ? userMsg.content.substring(0, 20) + '...'
        : userMsg.content;
    }
  }

  private async sendMessage(): Promise<void> {
    const text = this.inputText.trim();
    if (text.length === 0 || this.isSending) return;

    const apiKey = this.settings.apiKey.trim();
    if (apiKey.length === 0) {
      promptAction.showToast({ message: '请先在设置中填写 API Key', duration: 2000 });
      this.openSettings();
      return;
    }
    if (apiKey !== this.settings.apiKey) {
      this.settings.apiKey = apiKey;
    }

    this.showApiKeyHint = false;
    const userMsg = new ChatMessage(Role.USER, text);
    const newMsgs = this.messages.slice();
    newMsgs.push(userMsg);
    this.messages = newMsgs;
    this.setTitle(userMsg);
    this.inputText = '';
    this.isSending = true;
    this.scrollBottom();

    await this.runCompletion();
  }

  private async runCompletion(): Promise<void> {
    if (!this.api) return;

    const assistantMsg = new ChatMessage(Role.ASSISTANT, '');
    assistantMsg.isStreaming = true;
    const newMsgs = this.messages.slice();
    newMsgs.push(assistantMsg);
    this.messages = newMsgs;
    this.scrollBottom();

    this.api.updateSettings(this.settings);
    const historyMsgs = this.messages.slice(0, -1);

    await this.api.chatStream(historyMsgs, {
      onContent: (delta: string) => {
        assistantMsg.content = assistantMsg.content + delta;
        this.refresh();
        this.scrollBottom();
      },
      onThinking: (delta: string) => {
        assistantMsg.thinking = assistantMsg.thinking + delta;
        assistantMsg.thinkingExpanded = true;
        this.refresh();
        this.scrollBottom();
      },
      onToolCall: (_index: number, toolCall: ToolCall) => {
        assistantMsg.toolCalls.push(toolCall);
        this.refresh();
      },
      onDone: () => {
        assistantMsg.isStreaming = false;
        this.isSending = false;
        this.refresh();
        this.persist();
        if (assistantMsg.toolCalls.length > 0) {
          this.runToolResults(assistantMsg);
        }
      },
      onError: (error: string) => {
        assistantMsg.isStreaming = false;
        if (assistantMsg.content.length === 0) {
          assistantMsg.content = '错误: ' + error;
        }
        this.isSending = false;
        this.refresh();
        this.persist();
        promptAction.showToast({ message: error, duration: 3000 });
      }
    });
  }

  private async runToolResults(assistantMsg: ChatMessage): Promise<void> {
    const newMsgs = this.messages.slice();
    for (let i = 0; i < assistantMsg.toolCalls.length; i++) {
      const tc = assistantMsg.toolCalls[i];
      const result = executeToolCall(tc);
      const toolMsg = new ChatMessage(Role.TOOL, result, tc.id);
      newMsgs.push(toolMsg);
    }
    this.messages = newMsgs;
    this.persist();
    this.isSending = true;
    await this.runCompletion();
  }

  private openSettings(): void {
    const params: SettingsNavParams = {
      settings: this.settings,
      onSaved: (newSettings: AppSettings) => {
        this.settings = newSettings;
        this.showApiKeyHint = newSettings.apiKey.length === 0;
        if (this.api) this.api.updateSettings(newSettings);
      }
    };
    AppStorage.setOrCreate<SettingsNavParams>('settingsParams', params);
    router.pushUrl({ url: 'pages/SettingsPage' });
  }

  private openHistory(): void {
    if (this.currentSession) {
      this.currentSession.messages = this.messages.slice();
      this.currentSession.updatedAt = Date.now();
      let foundIdx = -1;
      for (let i = 0; i < this.sessions.length; i++) {
        if (this.sessions[i].id === this.currentSession.id) {
          foundIdx = i;
          break;
        }
      }
      if (foundIdx >= 0) {
        this.sessions[foundIdx] = this.currentSession;
      }
    }
    const params: HistoryNavParams = {
      sessions: this.sessions.slice(),
      onSelect: (session: ChatSession) => {
        this.persist();
        this.currentSession = session;
        this.messages = session.messages.slice();
      },
      onDelete: (sessionId: string) => {
        const filtered: ChatSession[] = [];
        for (let i = 0; i < this.sessions.length; i++) {
          if (this.sessions[i].id !== sessionId) {
            filtered.push(this.sessions[i]);
          }
        }
        this.sessions = filtered;
        saveSessions(this.sessions.slice());
        if (this.currentSession && this.currentSession.id === sessionId) {
          this.createNewSession(false);
        }
      },
      onNewChat: () => {
        this.persist();
        this.createNewSession(true);
      }
    };
    AppStorage.setOrCreate<HistoryNavParams>('historyParams', params);
    router.pushUrl({ url: 'pages/HistoryPage' });
  }

  private stopGenerate(): void {
    this.isSending = false;
    if (this.api) {
      this.api.destroy();
      this.api = new DeepSeekAPI(this.settings);
    }
    if (this.messages.length > 0) {
      const last = this.messages[this.messages.length - 1];
      if (last && last.role === Role.ASSISTANT) {
        last.isStreaming = false;
      }
    }
    this.refresh();
    this.persist();
  }

  private toggleThinking(msg: ChatMessage): void {
    msg.thinkingExpanded = !msg.thinkingExpanded;
    this.refresh();
  }

  private isUserMsg(msg: ChatMessage): boolean {
    return msg.role === Role.USER;
  }

  @Builder
  thinkingView(msg: ChatMessage) {
    if (msg.thinking.length > 0) {
      Column() {
        Row() {
          Text(msg.isStreaming ? '思考中...' : '已深度思考')
            .fontSize(12)
            .fontColor('#888888')
            .layoutWeight(1)
          Text(msg.thinkingExpanded ? '收起' : '展开')
            .fontSize(12)
            .fontColor('#4A90D9')
            .onClick(() => this.toggleThinking(msg))
        }
        .width('100%')

        if (msg.thinkingExpanded) {
          Text(msg.thinking)
            .fontSize(13)
            .fontColor('#999999')
            .width('100%')
            .padding({ top: 8 })
            .fontStyle(FontStyle.Italic)
        }
      }
      .width('100%')
      .padding(10)
      .margin({ bottom: 8 })
      .backgroundColor('#F5F5F5')
      .borderRadius(8)
    }
  }

  @Builder
  toolCallsView(msg: ChatMessage) {
    if (msg.toolCalls.length > 0) {
      Column() {
        ForEach(msg.toolCalls, (tc: ToolCall) => {
          Row() {
            Text('工具')
              .fontSize(10)
              .fontColor('#FFFFFF')
              .backgroundColor('#F5A623')
              .borderRadius(4)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .margin({ right: 6 })
            Text(tc.functionName)
              .fontSize(12)
              .fontColor('#666666')
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        })
      }
      .width('100%')
      .padding(8)
      .margin({ bottom: 8 })
      .backgroundColor('#FFF8E1')
      .borderRadius(8)
    }
  }

  @Builder
  messageBubble(msg: ChatMessage) {
    Row() {
      if (this.isUserMsg(msg)) {
        Blank()
      }

      Column() {
        if (!this.isUserMsg(msg)) {
          this.thinkingView(msg)
          this.toolCallsView(msg)
        }

        if (msg.content.length > 0 || msg.isStreaming) {
          Text(msg.content)
            .fontSize(15)
            .fontColor(this.isUserMsg(msg) ? '#FFFFFF' : '#333333')
            .lineHeight(22)
            .width('100%')
        }

        if (msg.isStreaming) {
          Text('▋')
            .fontSize(15)
            .fontColor(this.isUserMsg(msg) ? '#FFFFFF' : '#333333')
            .opacity(0.5)
        }
      }
      .padding(12)
      .backgroundColor(this.isUserMsg(msg) ? '#4A90D9' : '#F7F7F8')
      .borderRadius({
        topLeft: this.isUserMsg(msg) ? 16 : 4,
        topRight: this.isUserMsg(msg) ? 4 : 16,
        bottomLeft: 16,
        bottomRight: 16
      })
      .constraintSize({ maxWidth: '78%' })

      if (!this.isUserMsg(msg)) {
        Blank()
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

  @Builder
  emptyView() {
    Column() {
      Text('DeepSeek Chat')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
      Text('有什么可以帮你的？')
        .fontSize(15)
        .fontColor('#999999')
        .margin({ top: 8 })

      if (this.showApiKeyHint) {
        Button('设置 API Key')
          .fontSize(14)
          .margin({ top: 24 })
          .backgroundColor('#4A90D9')
          .fontColor(Color.White)
          .borderRadius(20)
          .onClick(() => this.openSettings())
      }
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle }) {
          Text('≡')
            .fontSize(22)
            .fontColor('#333333')
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.openHistory())

        Column() {
          Text((this.currentSession ? this.currentSession.title : 'DeepSeek Chat') || 'DeepSeek Chat')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.settings.model)
            .fontSize(11)
            .fontColor('#999999')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Button({ type: ButtonType.Circle }) {
          Text('+')
            .fontSize(22)
            .fontColor('#333333')
            .fontWeight(FontWeight.Bold)
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.persist();
          this.createNewSession(true);
        })

        Button({ type: ButtonType.Circle }) {
          Text('⚙')
            .fontSize(20)
            .fontColor('#333333')
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.openSettings())
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .backgroundColor('#FFFFFF')

      if (this.messages.length === 0) {
        this.emptyView()
      } else {
        List({ scroller: this.scroller }) {
          ForEach(this.messages, (msg: ChatMessage) => {
            if (msg.role === Role.TOOL) {
              ListItem() {
                Row() {
                  Text('工具返回结果')
                    .fontSize(11)
                    .fontColor('#888888')
                    .fontStyle(FontStyle.Italic)
                }
                .width('100%')
                .padding({ left: 16, top: 4, bottom: 4 })
              }
            } else {
              ListItem() {
                this.messageBubble(msg)
              }
            }
          }, (msg: ChatMessage, index: number) => msg.id + '_' + msg.content.length.toString() + '_' + msg.thinking.length.toString() + '_' + index.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }

      Column() {
        Row({ space: 8 }) {
          Text(this.settings.thinkingEnabled ? '思考: ' + this.settings.reasoningEffort : '思考: 关闭')
            .fontSize(11)
            .fontColor('#888888')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor('#F0F0F0')
            .borderRadius(10)
            .onClick(() => this.openSettings())
        }
        .width('100%')
        .padding({ left: 12, bottom: 4 })

        Row() {
          TextInput({
            text: this.inputText,
            placeholder: '输入消息...'
          })
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .backgroundColor('#F5F5F5')
            .borderRadius(20)
            .padding({ left: 16, right: 16 })
            .onChange((v: string) => {
              this.inputText = v;
            })
            .onSubmit(() => {
              if (!this.isSending) this.sendMessage();
            })

          if (this.isSending) {
            Button({ type: ButtonType.Circle }) {
              Text('■')
                .fontSize(12)
                .fontColor(Color.White)
            }
            .width(40)
            .height(40)
            .backgroundColor('#FF6B6B')
            .margin({ left: 8 })
            .onClick(() => this.stopGenerate())
          } else {
            Button({ type: ButtonType.Circle }) {
              Text('↑')
                .fontSize(18)
                .fontColor(Color.White)
                .fontWeight(FontWeight.Bold)
            }
            .width(40)
            .height(40)
            .backgroundColor(this.inputText.trim().length > 0 ? '#4A90D9' : '#CCCCCC')
            .margin({ left: 8 })
            .enabled(this.inputText.trim().length > 0)
            .onClick(() => this.sendMessage())
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 10 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
