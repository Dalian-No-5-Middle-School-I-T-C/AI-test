// ChatPage.ets - 主聊天页面（ArkTS 严格模式最终版）
import router from '@ohos.router';
import { generateId, initStorageContext } from '../service/StorageService';
import { MessageRole, Conversation, ChatMessage, AppSettings, ToolCallItem, ToolDefinition, ToolCallResult } from '../model/ChatModels';
import { DeepSeekService, StreamCallbacks, ToolExecutor } from '../service/DeepSeekService';
import { MessageBubble } from '../components/MessageBubble';

@Entry
@Component
export struct ChatPage {
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State isLoading: boolean = false;
  @State statusText: string = '';
  @State selectedModel: string = 'deepseek-v4-pro';
  @State showThinking: boolean = true;
  @State thinkingEnabled: boolean = true;
  @State reasoningEffort: string = 'high';
  @State showSettings: boolean = false;
  @State showHistory: boolean = false;
  @State apiKey: string = '';
  @State conversations: Conversation[] = [];
  @State conversationTitle: string = '新对话';
  @State pendingToolCalls: ToolCallItem[] = [];

  private dsService: DeepSeekService = new DeepSeekService();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    initStorageContext(getContext(this));
    this.loadSettingsAndData();
  }

  async loadSettingsAndData(): Promise<void> {
    const settings: AppSettings | null = await loadSettings();
    if (settings) {
      this.apiKey = settings.apiKey;
      this.selectedModel = settings.model;
      this.thinkingEnabled = settings.thinkingEnabled;
      this.reasoningEffort = settings.reasoningEffort;
      this.dsService.setApiKey(settings.apiKey);
    }
    const convs: Conversation[] = await loadConversations();
    this.conversations = convs;
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

  async newConversation(): Promise<void> {
    this.messages = [];
    this.conversationTitle = '新对话';
    this.statusText = '';
    this.inputText = '';
  }

  async saveCurrentConversation(): Promise<void> {
    if (this.messages.length <= 1) return;
    const titleMsg: ChatMessage | undefined = this.messages.find(
      (m: ChatMessage): boolean => m.role === MessageRole.User
    );
    const title: string = titleMsg
      ? (titleMsg.content as string).substring(0, 30)
      : '新对话';
    const conv: Conversation = {
      id: generateId(),
      title: title,
      messages: this.messages,
      model: this.selectedModel,
      thinkingEnabled: this.thinkingEnabled,
      reasoningEffort: this.reasoningEffort,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    const idx: number = this.conversations.findIndex(
      (c: Conversation): boolean => c.title === this.conversationTitle && c.model === this.selectedModel
    );
    if (idx >= 0) {
      this.conversations[idx] = conv;
    } else {
      this.conversations.push(conv);
    }
    await saveConversations(this.conversations);
  }

  async loadConversation(conv: Conversation): Promise<void> {
    this.messages = conv.messages;
    this.selectedModel = conv.model;
    this.thinkingEnabled = conv.thinkingEnabled;
    this.reasoningEffort = conv.reasoningEffort;
    this.conversationTitle = conv.title;
    this.showHistory = false;
  }

  async deleteConversation(id: string): Promise<void> {
    this.conversations = this.conversations.filter(
      (c: Conversation): boolean => c.id !== id
    );
    await saveConversations(this.conversations);
  }

  scrollToBottom(): void {
    setTimeout((): void => {
      this.scroller.scrollToIndex(this.messages.length - 1);
    }, 100);
  }

  /**
   * 发送消息（修复：预先添加 assistant 占位消息，onContent 直接更新它）
   */
  async sendMessage(): Promise<void> {
    if (!this.inputText.trim() || this.isLoading) return;
    if (!this.apiKey.trim()) {
      this.statusText = '请先在设置中填写 API Key';
      return;
    }

    const userContent: string = this.inputText.trim();

    const userMsg: ChatMessage = {
      id: generateId(),
      role: MessageRole.User,
      content: userContent,
      timestamp: Date.now(),
    };
    this.messages.push(userMsg);
    this.inputText = '';
    this.isLoading = true;
    this.statusText = this.thinkingEnabled ? '思考中...' : '回复中...';
    this.scrollToBottom();

    // 预先添加 assistant 占位消息
    const assistantMsg: ChatMessage = {
      id: generateId(),
      role: MessageRole.Assistant,
      content: '',
      reasoning_content: '',
      timestamp: Date.now(),
    };
    this.messages.push(assistantMsg);
    const assistantIdx: number = this.messages.length - 1;

    const apiMessages: ChatMessage[] = this.messages.filter(
      (m: ChatMessage): boolean => m.role !== MessageRole.System
    );
    const tools: ToolDefinition[] = ToolExecutor.getToolDefinitions();

    const callbacks: StreamCallbacks = {
      onReasoning: (text: string): void => {
        this.statusText = '思考中...';
        if (assistantIdx >= 0 && assistantIdx < this.messages.length) {
          const old: ChatMessage = this.messages[assistantIdx];
          this.messages[assistantIdx] = {
            id: old.id,
            role: old.role,
            content: old.content,
            reasoning_content: text,
            tool_calls: old.tool_calls,
            timestamp: old.timestamp,
          };
        }
      },
      onContent: (text: string): void => {
        this.statusText = '';
        if (assistantIdx >= 0 && assistantIdx < this.messages.length) {
          const old: ChatMessage = this.messages[assistantIdx];
          this.messages[assistantIdx] = {
            id: old.id,
            role: old.role,
            content: text,
            reasoning_content: old.reasoning_content,
            tool_calls: old.tool_calls,
            timestamp: old.timestamp,
          };
        }
        this.scrollToBottom();
      },
      onToolCall: (toolCalls: ToolCallItem[]): void => {
        this.pendingToolCalls = toolCalls;
      },
      onDone: (): void => {
        // 先不把 isLoading 设为 false，让 handleToolCalls 继续控制
        this.statusText = '';
        if (this.pendingToolCalls.length > 0) {
          this.handleToolCalls(this.pendingToolCalls, assistantIdx);
          this.pendingToolCalls = [];
        } else {
          this.isLoading = false;
          this.saveCurrentConversation();
        }
      },
      onError: (err: string): void => {
        this.isLoading = false;
        this.statusText = `错误: ${err}`;
        // 移除空的 assistant 占位消息
        if (assistantIdx >= 0 && assistantIdx < this.messages.length) {
          const last: ChatMessage = this.messages[assistantIdx];
          if (last && last.content === '' && !last.reasoning_content) {
            this.messages.splice(assistantIdx, 1);
          }
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
      if (assistantIdx >= 0 && assistantIdx < this.messages.length) {
        const last: ChatMessage = this.messages[assistantIdx];
        if (last && last.content === '' && !last.reasoning_content) {
          this.messages.splice(assistantIdx, 1);
        }
      }
    }
  }

  /**
   * 处理工具调用，并把结果发回模型
   */
  async handleToolCalls(toolCalls: ToolCallItem[], assistantIdx: number): Promise<void> {
    // 把 tool_calls 附到占位消息上
    if (assistantIdx >= 0 && assistantIdx < this.messages.length) {
      const old: ChatMessage = this.messages[assistantIdx];
      this.messages[assistantIdx] = {
        id: old.id,
        role: old.role,
        content: old.content,
        reasoning_content: old.reasoning_content,
        tool_calls: toolCalls,
        timestamp: old.timestamp,
      };
    }

    const results: ToolCallResult[] = ToolExecutor.executeToolCalls(toolCalls);

    // 把工具结果作为 Tool 消息加入
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

    // 重新构建 apiMessages（不含 System）
    const apiMessages: ChatMessage[] = this.messages.filter(
      (m: ChatMessage): boolean => m.role !== MessageRole.System
    );

    // 创建一个新的 assistant 占位（接收工具调用后的最终回复）
    const finalAssistantMsg: ChatMessage = {
      id: generateId(),
      role: MessageRole.Assistant,
      content: '',
      reasoning_content: '',
      timestamp: Date.now(),
    };
    this.messages.push(finalAssistantMsg);
    const finalIdx: number = this.messages.length - 1;

    const callbacks: StreamCallbacks = {
      onReasoning: (text: string): void => {
        this.statusText = '思考中...';
        if (finalIdx >= 0 && finalIdx < this.messages.length) {
          const old: ChatMessage = this.messages[finalIdx];
          this.messages[finalIdx] = {
            id: old.id,
            role: old.role,
            content: old.content,
            reasoning_content: text,
            tool_calls: old.tool_calls,
            timestamp: old.timestamp,
          };
        }
      },
      onContent: (text: string): void => {
        this.statusText = '';
        if (finalIdx >= 0 && finalIdx < this.messages.length) {
          const old: ChatMessage = this.messages[finalIdx];
          this.messages[finalIdx] = {
            id: old.id,
            role: old.role,
            content: text,
            reasoning_content: old.reasoning_content,
            tool_calls: old.tool_calls,
            timestamp: old.timestamp,
          };
        }
        this.scrollToBottom();
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

  build() {
    Stack() {
      // 主聊天界面
      Column() {
        // 顶部栏
        this.buildTopBar()
        Divider().color('#EEEEEE').height(1)

        // 消息列表
        List({ scroller: this.scroller }) {
          ForEach(this.messages, (msg: ChatMessage) => {
            ListItem() {
              MessageBubble({ message: msg, showThinking: this.showThinking })
            }
            .padding({ top: 6, bottom: 6 })
          }, (msg: ChatMessage) => msg.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 8, right: 8 })

        // 状态栏
        if (this.statusText) {
          Text(this.statusText)
            .fontSize(13)
            .fontColor('#007DFF')
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 4, bottom: 4 })
            .backgroundColor('#F0F8FF')
        }

        // 输入栏
        this.buildInputBar()
      }
      .width('100%')
      .height('100%')

      // 设置面板（侧滑）
      if (this.showSettings) {
        this.buildSettingsPanel()
      }

      // 历史面板（侧滑）
      if (this.showHistory) {
        this.buildHistoryPanel()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildTopBar() {
    Row() {
      Text('💬 DeepSeek 聊天')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
      Blank()
      Row({ space: 12 }) {
        Text('📋')
          .fontSize(20)
          .padding(8)
          .onClick((): void => { this.newConversation(); })
        Text('⚙️')
          .fontSize(20)
          .padding(8)
          .onClick((): void => { this.showSettings = !this.showSettings; })
        Text('📑')
          .fontSize(20)
          .padding(8)
          .onClick((): void => { this.showHistory = !this.showHistory; })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  buildInputBar() {
    Row({ space: 8 }) {
      TextInput({ placeholder: '输入消息...', text: this.inputText })
        .width('100%')
        .layoutWeight(1)
        .height(40)
        .backgroundColor('#F5F5F5')
        .borderRadius(20)
        .padding({ left: 16, right: 16 })
        .onChange((val: string): void => {
          this.inputText = val;
        })
        .onSubmit((): void => {
          this.sendMessage();
        })

      Text('➤')
        .fontSize(22)
        .fontColor(this.isLoading ? '#CCCCCC' : '#007DFF')
        .padding(8)
        .onClick((): void => {
          this.sendMessage();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .border({ width: { top: 1 }, color: '#EEEEEE' })
  }

  @Builder
  buildSettingsPanel() {
    Column() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick((): void => { this.showSettings = false; })

      // 设置内容
      Column({ space: 16 }) {
        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ bottom: 8 })

        // API Key
        Column({ space: 6 }) {
          Text('API Key').fontSize(14).fontColor('#666').width('100%')
          TextInput({ placeholder: '请输入 DeepSeek API Key', text: this.apiKey })
            .width('100%')
            .type(InputType.Password)
            .onChange((val: string): void => { this.apiKey = val; })
        }

        // 模型选择
        Column({ space: 6 }) {
          Text('模型').fontSize(14).fontColor('#666').width('100%')
          Row({ space: 12 }) {
            Text('Flash')
              .fontSize(14)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor(this.selectedModel === 'deepseek-v4-flash' ? '#007DFF' : '#F0F0F0')
              .fontColor(this.selectedModel === 'deepseek-v4-flash' ? '#FFFFFF' : '#333333')
              .borderRadius(16)
              .onClick((): void => { this.selectedModel = 'deepseek-v4-flash'; })
            Text('Pro')
              .fontSize(14)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor(this.selectedModel === 'deepseek-v4-pro' ? '#007DFF' : '#F0F0F0')
              .fontColor(this.selectedModel === 'deepseek-v4-pro' ? '#FFFFFF' : '#333333')
              .borderRadius(16)
              .onClick((): void => { this.selectedModel = 'deepseek-v4-pro'; })
          }
        }

        // 思考模式
        Row() {
          Text('思考模式').fontSize(14).fontColor('#666')
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.thinkingEnabled })
            .onChange((val: boolean): void => { this.thinkingEnabled = val; })
        }
        .width('100%')

        // 思考深度
        if (this.thinkingEnabled) {
          Column({ space: 6 }) {
            Text('思考深度').fontSize(14).fontColor('#666').width('100%')
            Row({ space: 12 }) {
              Text('high')
                .fontSize(14)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .backgroundColor(this.reasoningEffort === 'high' ? '#007DFF' : '#F0F0F0')
                .fontColor(this.reasoningEffort === 'high' ? '#FFFFFF' : '#333333')
                .borderRadius(16)
                .onClick((): void => { this.reasoningEffort = 'high'; })
              Text('max')
                .fontSize(14)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .backgroundColor(this.reasoningEffort === 'max' ? '#007DFF' : '#F0F0F0')
                .fontColor(this.reasoningEffort === 'max' ? '#FFFFFF' : '#333333')
                .borderRadius(16)
                .onClick((): void => { this.reasoningEffort = 'max'; })
            }
          }
        }

        // 显示思考内容
        Row() {
          Text('显示思考内容').fontSize(14).fontColor('#666')
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.showThinking })
            .onChange((val: boolean): void => { this.showThinking = val; })
        }
        .width('100%')

        // 保存按钮
        Text('保存设置')
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor('#007DFF')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .borderRadius(8)
          .margin({ top: 16 })
          .onClick((): void => { this.saveSettings(); })
      }
      .width('85%')
      .height('100%')
      .backgroundColor('#FFFFFF')
      .padding(20)
      .alignSelf(ItemAlign.End)
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(100)
  }

  @Builder
  buildHistoryPanel() {
    Column() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick((): void => { this.showHistory = false; })

      // 历史内容
      Column({ space: 12 }) {
        Text('历史对话')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ bottom: 8 })

        List() {
          ForEach(this.conversations, (conv: Conversation) => {
            ListItem() {
              Row() {
                Column({ space: 4 }) {
                  Text(conv.title).fontSize(15).fontColor('#1A1A1A').maxLines(1)
                  Text(`${new Date(conv.updatedAt).toLocaleString()} · ${conv.model}`)
                    .fontSize(12).fontColor('#999')
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)

                Text('🗑️')
                  .fontSize(18).padding(8)
                  .onClick((): void => {
                    this.deleteConversation(conv.id);
                  })
              }
              .width('100%').padding(16)
              .backgroundColor('#F9F9F9')
              .borderRadius(8)
              .onClick((): void => {
                this.loadConversation(conv);
              })
            }
            .padding({ bottom: 8 })
          }, (conv: Conversation) => conv.id)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('85%')
      .height('100%')
      .backgroundColor('#FFFFFF')
      .padding(20)
      .alignSelf(ItemAlign.Start)
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(100)
  }
}
