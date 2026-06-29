// ChatPage.ets - 主聊天页面（ArkTS 严格模式最终版）
import { MessageRole, Conversation, ChatMessage, AppSettings, ToolCallItem, ToolDefinition, ToolCallResult } from '../model/ChatModels';
import { DeepSeekService, ToolExecutor, StreamCallbacks } from '../service/DeepSeekService';
import {
  initStorageContext, saveConversations, loadConversations, saveSettings, loadSettings,
  getDefaultSettings, generateId
} from '../service/StorageService';
import { MessageBubble } from '../components/MessageBubble';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct ChatPage {
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State isLoading: boolean = false;
  @State showThinking: boolean = true;
  @State thinkingEnabled: boolean = true;
  @State reasoningEffort: string = 'high';
  @State selectedModel: string = 'deepseek-v4-pro';
  @State apiKey: string = '';
  @State showSettings: boolean = false;
  @State showHistory: boolean = false;
  @State conversationTitle: string = '新对话';
  @State currentConvId: string = '';
  @State statusText: string = '';

  private dsService: DeepSeekService = new DeepSeekService();
  private conversations: Conversation[] = [];
  private scroller: Scroller = new Scroller();
  private pendingToolCalls: ToolCallItem[] = [];

  aboutToAppear(): void {
    initStorageContext(getContext(this));
    this.loadLocalData();
  }

  async loadLocalData(): Promise<void> {
    const settings: AppSettings | null = await loadSettings();
    if (settings) {
      this.apiKey = settings.apiKey;
      this.selectedModel = settings.model;
      this.thinkingEnabled = settings.thinkingEnabled;
      this.reasoningEffort = settings.reasoningEffort;
    } else {
      const def: AppSettings = getDefaultSettings();
      this.apiKey = def.apiKey;
      this.selectedModel = def.model;
      this.thinkingEnabled = def.thinkingEnabled;
      this.reasoningEffort = def.reasoningEffort;
    }
    this.dsService.setApiKey(this.apiKey);
    this.conversations = await loadConversations();
    this.startNewConversation();
  }

  startNewConversation(): void {
    this.currentConvId = generateId();
    this.conversationTitle = '新对话';
    const sysMsg: ChatMessage = {
      id: generateId(),
      role: MessageRole.System,
      content: '你好！我是 DeepSeek AI 助手，有什么可以帮您的吗？',
      timestamp: Date.now(),
    };
    this.messages = [sysMsg];
    this.statusText = '';
  }

  async sendMessage(): Promise<void> {
    const text: string = this.inputText.trim();
    if (!text || this.isLoading) return;
    if (!this.apiKey) {
      this.statusText = '请先在设置中填写 API Key';
      return;
    }

    const userMsg: ChatMessage = {
      id: generateId(),
      role: MessageRole.User,
      content: text,
      timestamp: Date.now(),
    };
    this.messages.push(userMsg);
    this.inputText = '';
    this.isLoading = true;
    this.statusText = this.thinkingEnabled ? '思考中...' : '回复中...';
    this.scrollToBottom();

    const assistantMsg: ChatMessage = {
      id: generateId(),
      role: MessageRole.Assistant,
      content: '',
      reasoning_content: '',
      timestamp: Date.now(),
    };
    this.messages.push(assistantMsg);
    const assistantIndex: number = this.messages.length - 1;
    const apiMessages: ChatMessage[] = this.messages.filter((m: ChatMessage): boolean => m.role !== MessageRole.System);
    const tools: ToolDefinition[] = ToolExecutor.getToolDefinitions();

    const callbacks: StreamCallbacks = {
      onReasoning: (text: string): void => {
        this.statusText = '思考中...';
        const msg: ChatMessage = this.messages[assistantIndex];
        if (msg) msg.reasoning_content = (msg.reasoning_content || '') + text;
      },
      onContent: (text: string): void => {
        this.statusText = '';
        const msg: ChatMessage = this.messages[assistantIndex];
        if (msg) msg.content = (msg.content || '') + text;
      },
      onToolCall: (toolCalls: ToolCallItem[]): void => {
        this.pendingToolCalls = toolCalls;
      },
      onDone: (): void => {
        this.isLoading = false;
        this.statusText = '';
        if (this.pendingToolCalls.length > 0) {
          this.handleToolCalls(this.pendingToolCalls, assistantIndex);
          this.pendingToolCalls = [];
        } else {
          this.saveCurrentConversation();
        }
      },
      onError: (err: string): void => {
        this.isLoading = false;
        this.statusText = `错误: ${err}`;
        const last: ChatMessage = this.messages[this.messages.length - 1];
        if (last && last.content === '' && !last.reasoning_content) {
          this.messages.pop();
        }
      },
    };

    try {
      await this.dsService.chatStream(
        apiMessages, this.selectedModel,
        this.thinkingEnabled, this.reasoningEffort,
        callbacks, tools
      );
    } catch (e) {
      this.isLoading = false;
      this.statusText = `发送失败: ${(e as Error).message}`;
    }
  }

  async handleToolCalls(toolCalls: ToolCallItem[], assistantIndex: number): Promise<void> {
    // 将 tool_calls 附加到助手消息
    const assistantMsg: ChatMessage = this.messages[assistantIndex];
    if (assistantMsg) {
      assistantMsg.tool_calls = toolCalls;
    }
    const results: ToolCallResult[] = ToolExecutor.executeToolCalls(toolCalls);
    for (const res of results) {
      const toolMsg: ChatMessage = {
        id: generateId(),
        role: MessageRole.Tool,
        content: res.content,
        timestamp: Date.now(),
      };
      this.messages.push(toolMsg);
    }

    this.statusText = '处理工具结果...';
    const apiMessages: ChatMessage[] = this.messages.filter((m: ChatMessage): boolean => m.role !== MessageRole.System);

    const callbacks: StreamCallbacks = {
      onContent: (text: string): void => {
        this.statusText = '';
        let lastMsg: ChatMessage = this.messages[this.messages.length - 1];
        if (!lastMsg || lastMsg.role !== MessageRole.Assistant) {
          const newMsg: ChatMessage = {
            id: generateId(),
            role: MessageRole.Assistant,
            content: '',
            reasoning_content: '',
            timestamp: Date.now(),
          };
          this.messages.push(newMsg);
          lastMsg = newMsg;
        }
        lastMsg.content = (lastMsg.content || '') + text;
      },
      onDone: (): void => {
        this.isLoading = false;
        this.statusText = '';
        this.saveCurrentConversation();
      },
      onError: (err: string): void => {
        this.isLoading = false;
        this.statusText = `工具处理错误: ${err}`;
      },
    };

    try {
      await this.dsService.chatStream(
        apiMessages, this.selectedModel,
        this.thinkingEnabled, this.reasoningEffort,
        callbacks, ToolExecutor.getToolDefinitions()
      );
    } catch (e) {
      this.isLoading = false;
      this.statusText = `工具调用失败: ${(e as Error).message}`;
    }
  }

  async saveCurrentConversation(): Promise<void> {
    const firstUser: ChatMessage | undefined = this.messages.find((m: ChatMessage): boolean => m.role === MessageRole.User);
    if (firstUser && this.conversationTitle === '新对话') {
      this.conversationTitle = (firstUser.content as string).substring(0, 30) || '新对话';
    }
    const conv: Conversation = {
      id: this.currentConvId,
      title: this.conversationTitle,
      messages: [...this.messages] as ChatMessage[],
      model: this.selectedModel,
      thinkingEnabled: this.thinkingEnabled,
      reasoningEffort: this.reasoningEffort,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    const idx: number = this.conversations.findIndex((c: Conversation): boolean => c.id === this.currentConvId);
    if (idx >= 0) {
      this.conversations[idx] = conv;
    } else {
      this.conversations.unshift(conv);
    }
    if (this.conversations.length > 50) {
      this.conversations = this.conversations.slice(0, 50);
    }
    await saveConversations(this.conversations);
  }

  loadConversation(conv: Conversation): void {
    this.currentConvId = conv.id;
    this.conversationTitle = conv.title;
    this.selectedModel = conv.model;
    this.thinkingEnabled = conv.thinkingEnabled;
    this.reasoningEffort = conv.reasoningEffort;
    this.messages = [...conv.messages] as ChatMessage[];
    this.showHistory = false;
    this.scrollToBottom();
  }

  async saveSettings(): Promise<void> {
    const settings: AppSettings = {
      apiKey: this.apiKey,
      model: this.selectedModel,
      thinkingEnabled: this.thinkingEnabled,
      reasoningEffort: this.reasoningEffort,
    };
    await saveSettings(settings);
    this.dsService.setApiKey(this.apiKey);
    this.showSettings = false;
  }

  scrollToBottom(): void {
    setTimeout((): void => { this.scroller.scrollEdge(Edge.Bottom); }, 100);
  }

  async deleteConversation(id: string): Promise<void> {
    await import('../service/StorageService').then((mod: Object): void => {
      // 动态导入以避免循环依赖
    });
    // 直接在此处从 conversations 中移除
    this.conversations = this.conversations.filter((c: Conversation): boolean => c.id !== id);
    await saveConversations(this.conversations);
    if (id === this.currentConvId) {
      this.startNewConversation();
    }
  }

  // ==================== UI ====================

  build() {
    Stack() {
      Column() {
        this.buildTopBar()
        this.buildMessageList()
        if (this.statusText) {
          Text(this.statusText)
            .fontSize(12).fontColor('#999').padding(8)
        }
        this.buildInputBar()
      }
      .width('100%').height('100%').backgroundColor('#F6F6F6')

      if (this.showSettings) { this.settingsPanel() }
      if (this.showHistory) { this.historyPanel() }
    }
    .width('100%').height('100%')
  }

  @Builder
  buildTopBar() {
    Row({ space: 12 }) {
      Text('📋').fontSize(22).padding(8)
        .onClick((): void => { this.showHistory = true; })

      Column() {
        Text(this.conversationTitle)
          .fontSize(16).fontWeight(FontWeight.Medium).maxLines(1)
        Row({ space: 4 }) {
          Text(this.selectedModel).fontSize(11).fontColor('#999')
          if (this.thinkingEnabled) {
            Text(`· ${this.reasoningEffort}`).fontSize(11).fontColor('#007DFF')
          }
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Center)

      Text('✏️').fontSize(22).padding(8)
        .onClick((): void => { this.startNewConversation(); })
      Text('⚙️').fontSize(22).padding(8)
        .onClick((): void => { this.showSettings = true; })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
    .border({ width: { bottom: 1 }, color: '#EEEEEE' })
  }

  @Builder
  buildMessageList() {
    List({ scroller: this.scroller }) {
      ForEach(this.messages, (msg: ChatMessage): void => {
        ListItem() {
          MessageBubble({ message: msg, showThinking: this.showThinking })
        }
        .padding({ top: 4, bottom: 4 })
      }, (msg: ChatMessage): string => msg.id)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  buildInputBar() {
    Row({ space: 8 }) {
      TextInput({ placeholder: '输入消息...', text: this.inputText })
        .layoutWeight(1)
        .backgroundColor('#FFFFFF')
        .borderRadius(20)
        .padding({ left: 16, right: 16 })
        .onChange((val: string): void => { this.inputText = val; })
        .onSubmit((): void => { this.sendMessage(); })

      Text(this.isLoading ? '⏳' : '➤')
        .fontSize(22)
        .padding(10)
        .borderRadius(20)
        .backgroundColor(this.isLoading ? '#CCCCCC' : '#007DFF')
        .fontColor('#FFFFFF')
        .onClick((): void => { this.sendMessage(); })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .border({ width: { top: 1 }, color: '#EEEEEE' })
  }

  @Builder
  settingsPanel() {
    Column() {
      Row() {
        Text('设置').fontSize(18).fontWeight(FontWeight.Bold)
        Blank()
        Text('✕').fontSize(22).padding(8).onClick((): void => { this.showSettings = false; })
      }
      .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 12 })
      Divider()
      this.settingsForm()
      Button('保存设置')
        .width('90%').margin(16)
        .onClick((): void => { this.saveSettings(); })
    }
    .backgroundColor('#FFFFFF').borderRadius({ topLeft: 20, topRight: 20 })
    .width('100%').height('80%')
    .position({ x: 0, y: '20%' })
    .zIndex(100)
  }

  @Builder
  settingsForm() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Text('API Key').fontSize(14).fontColor('#666').alignSelf(ItemAlign.Start)
        TextInput({ placeholder: '请输入 DeepSeek API Key', text: this.apiKey })
          .width('100%').type(InputType.Password)
          .onChange((val: string): void => { this.apiKey = val; })
      }.padding(16)

      Divider()

      Column({ space: 8 }) {
        Text('模型').fontSize(14).fontColor('#666').alignSelf(ItemAlign.Start)
        Row({ space: 12 }) {
          this.buildChip(this.selectedModel === 'deepseek-v4-pro', 'V4 Pro',
            (): void => { this.selectedModel = 'deepseek-v4-pro'; })
          this.buildChip(this.selectedModel === 'deepseek-v4-flash', 'V4 Flash',
            (): void => { this.selectedModel = 'deepseek-v4-flash'; })
        }
      }.padding(16)

      Divider()

      Column({ space: 8 }) {
        Row() {
          Text('思考模式').fontSize(14).fontColor('#666')
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.thinkingEnabled })
            .onChange((val: boolean): void => { this.thinkingEnabled = val; })
        }
        if (this.thinkingEnabled) {
          Row({ space: 12 }) {
            this.buildChip(this.reasoningEffort === 'high', 'High',
              (): void => { this.reasoningEffort = 'high'; })
            this.buildChip(this.reasoningEffort === 'max', 'Max',
              (): void => { this.reasoningEffort = 'max'; })
          }
        }
      }.padding(16)

      Divider()

      Row() {
        Text('显示思考过程').fontSize(14).fontColor('#666')
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.showThinking })
          .onChange((val: boolean): void => { this.showThinking = val; })
      }.padding(16)
    }
    .width('100%').layoutWeight(1).alignSelf(ItemAlign.Start)
  }

  @Builder
  buildChip(selected: boolean, label: string, onClick: () => void) {
    Button(label)
      .backgroundColor(selected ? '#007DFF' : '#F0F0F0')
      .fontColor(selected ? '#FFFFFF' : '#333333')
      .onClick(onClick)
  }

  @Builder
  historyPanel() {
    Column() {
      Row() {
        Text('历史会话').fontSize(18).fontWeight(FontWeight.Bold)
        Blank()
        Text('✕').fontSize(22).padding(8).onClick((): void => { this.showHistory = false; })
      }
      .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 12 })
      Divider()

      if (this.conversations.length === 0) {
        Text('暂无历史会话').fontSize(14).fontColor('#999').padding(40)
      } else {
        List() {
          ForEach(this.conversations, (conv: Conversation): void => {
            ListItem() {
              Row() {
                Column({ space: 4 }) {
                  Text(conv.title).fontSize(15).fontColor('#1A1A1A').maxLines(1)
                  Text(`${new Date(conv.updatedAt).toLocaleString()} · ${conv.model}`)
                    .fontSize(12).fontColor('#999')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .onClick((): void => { this.loadConversation(conv); })

                Text('🗑️')
                  .fontSize(18).padding(8)
                  .onClick((): void => { this.deleteConversation(conv.id); })
              }
              .width('100%').padding(16)
            }
          }, (conv: Conversation): string => conv.id)
        }
        .width('100%').layoutWeight(1)
      }
    }
    .backgroundColor('#FFFFFF').borderRadius({ topLeft: 20, topRight: 20 })
    .width('100%').height('80%')
    .position({ x: 0, y: '20%' })
    .zIndex(100)
  }
}
