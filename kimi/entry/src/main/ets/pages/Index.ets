import { ChatMessage, Conversation, ToolCall, AVAILABLE_MODELS } from '../models/ChatModels';
import { StorageService } from '../services/StorageService';
import { DeepSeekService } from '../services/DeepSeekService';

@Entry
@Component
struct Index {
  @State conversations: Conversation[] = [];
  @State currentConversationId: string = '';
  @State currentConversation: Conversation | null = null;
  @State inputText: string = '';
  @State isStreaming: boolean = false;
  @State showSettings: boolean = false;
  @State showHistory: boolean = false;
  @State errorMessage: string = '';
  @State messageRefreshToken: number = 0;

  @State apiKey: string = '';
  @State selectedModel: string = 'deepseek-v4-pro';
  @State thinkingEnabled: boolean = true;
  @State reasoningEffort: 'high' | 'max' = 'high';

  private storage: StorageService | null = null;
  private deepSeekService: DeepSeekService = new DeepSeekService();
  private listScroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    this.initialize();
  }

  private async initialize(): Promise<void> {
    try {
      this.storage = new StorageService(getContext(this).getApplicationContext());
      await this.loadSettings();
      await this.loadConversations();
    } catch (e) {
      this.errorMessage = e instanceof Error ? e.message : '初始化失败';
      await this.createNewConversation();
    }
  }

  aboutToDisappear(): void {
    this.deepSeekService.cancel();
  }

  private async loadSettings(): Promise<void> {
    if (!this.storage) {
      return;
    }
    try {
      this.apiKey = await this.storage.getApiKey();
      this.selectedModel = await this.storage.getDefaultModel();
      this.thinkingEnabled = await this.storage.getThinkingEnabled();
      this.reasoningEffort = await this.storage.getReasoningEffort();
    } catch (e) {
      // Use defaults if settings cannot be loaded
    }
  }

  private async saveSettings(): Promise<void> {
    if (!this.storage) {
      return;
    }
    try {
      await this.storage.setApiKey(this.apiKey);
      await this.storage.setDefaultModel(this.selectedModel);
      await this.storage.setThinkingEnabled(this.thinkingEnabled);
      await this.storage.setReasoningEffort(this.reasoningEffort);
      if (this.currentConversation) {
        this.currentConversation.model = this.selectedModel;
        this.currentConversation.thinkingEnabled = this.thinkingEnabled;
        this.currentConversation.reasoningEffort = this.reasoningEffort;
        await this.saveConversations();
      }
    } catch (e) {
      this.errorMessage = e instanceof Error ? e.message : '保存设置失败';
    }
  }

  private async loadConversations(): Promise<void> {
    if (!this.storage) {
      await this.createNewConversation();
      return;
    }
    try {
      this.conversations = await this.storage.getConversations();
      const savedId = await this.storage.getCurrentConversationId();
      if (savedId && this.conversations.some(c => c.id === savedId)) {
        this.currentConversationId = savedId;
      } else if (this.conversations.length > 0) {
        this.currentConversationId = this.conversations[0].id;
      } else {
        await this.createNewConversation();
      }
      this.updateCurrentConversation();
    } catch (e) {
      this.conversations = [];
      await this.createNewConversation();
    }
  }

  private async saveConversations(): Promise<void> {
    if (!this.storage) {
      return;
    }
    await this.storage.saveConversations(this.conversations);
    await this.storage.setCurrentConversationId(this.currentConversationId);
  }

  private updateCurrentConversation(): void {
    this.currentConversation = this.conversations.find(c => c.id === this.currentConversationId) ?? null;
  }

  private async createNewConversation(): Promise<void> {
    const newConversation: Conversation = {
      id: `${Date.now()}_${Math.random().toString(36).slice(2, 9)}`,
      title: '新对话',
      messages: [],
      createTime: Date.now(),
      updateTime: Date.now(),
      model: this.selectedModel,
      thinkingEnabled: this.thinkingEnabled,
      reasoningEffort: this.reasoningEffort
    };
    this.conversations = [newConversation, ...this.conversations];
    this.currentConversationId = newConversation.id;
    this.updateCurrentConversation();
    try {
      await this.saveConversations();
    } catch (e) {
      // Keep the conversation in memory even if save fails
    }
  }

  private async switchConversation(id: string): Promise<void> {
    this.currentConversationId = id;
    this.updateCurrentConversation();
    this.showHistory = false;
    try {
      await this.saveConversations();
    } catch (e) {
      // Ignore save errors
    }
  }

  private async deleteConversation(id: string): Promise<void> {
    const index = this.conversations.findIndex(c => c.id === id);
    if (index < 0) {
      return;
    }
    this.conversations = this.conversations.filter(c => c.id !== id);
    if (this.currentConversationId === id) {
      if (this.conversations.length > 0) {
        this.currentConversationId = this.conversations[0].id;
      } else {
        await this.createNewConversation();
      }
    }
    this.updateCurrentConversation();
    try {
      await this.saveConversations();
    } catch (e) {
      // Ignore save errors
    }
  }

  private async sendMessage(): Promise<void> {
    const text = this.inputText.trim();
    if (!text) {
      return;
    }
    if (!this.apiKey) {
      this.errorMessage = '请先填写 API Key';
      return;
    }

    let conversation = this.currentConversation;
    if (!conversation) {
      await this.createNewConversation();
      conversation = this.currentConversation;
    }
    if (!conversation) {
      this.errorMessage = '创建会话失败';
      return;
    }
    const activeConversation = conversation;

    this.errorMessage = '';
    this.inputText = '';

    const userMessage: ChatMessage = {
      id: `${Date.now()}_${Math.random().toString(36).slice(2, 9)}`,
      role: 'user',
      content: text
    };
    activeConversation.messages.push(userMessage);
    activeConversation.updateTime = Date.now();
    if (activeConversation.title === '新对话') {
      activeConversation.title = text.slice(0, 20);
    }
    this.forceUpdateMessages();
    try {
      await this.saveConversations();
    } catch (e) {
      // Continue even if save fails
    }
    this.scrollToBottom();

    this.isStreaming = true;
    let assistantMessage: ChatMessage | null = null;

    try {
      await this.deepSeekService.sendMessageStream(
        this.apiKey,
        activeConversation.model,
        activeConversation.thinkingEnabled,
        activeConversation.reasoningEffort,
        activeConversation.messages,
        {
          onStart: () => {
            assistantMessage = {
              id: `${Date.now()}_${Math.random().toString(36).slice(2, 9)}`,
              role: 'assistant',
              content: '',
              isStreaming: true,
              model: activeConversation.model
            };
            activeConversation.messages.push(assistantMessage!);
            this.forceUpdateMessages();
            this.scrollToBottom();
          },
          onContentDelta: (delta: string) => {
            if (assistantMessage) {
              assistantMessage.content += delta;
              this.forceUpdateMessages();
            }
          },
          onReasoningDelta: (delta: string) => {
            if (assistantMessage) {
              assistantMessage.reasoningContent = (assistantMessage.reasoningContent || '') + delta;
              this.forceUpdateMessages();
            }
          },
          onToolCall: (toolCall: ToolCall) => {
            if (assistantMessage) {
              if (!assistantMessage.toolCalls) {
                assistantMessage.toolCalls = [];
              }
              const existing = assistantMessage.toolCalls.find(tc => tc.id === toolCall.id);
              if (!existing) {
                assistantMessage.toolCalls.push(toolCall);
              }
              this.forceUpdateMessages();
            }
          },
          onToolResult: (toolResult: ChatMessage) => {
            activeConversation.messages.push(toolResult);
            this.forceUpdateMessages();
            this.scrollToBottom();
          },
          onComplete: async (finalMessage: ChatMessage) => {
            if (assistantMessage) {
              assistantMessage.content = finalMessage.content;
              assistantMessage.reasoningContent = finalMessage.reasoningContent;
              assistantMessage.toolCalls = finalMessage.toolCalls;
              assistantMessage.isStreaming = false;
              assistantMessage.model = finalMessage.model;
            }
            this.isStreaming = false;
            activeConversation.updateTime = Date.now();
            try {
              await this.saveConversations();
            } catch (e) {
              // Ignore save errors
            }
            this.forceUpdateMessages();
            this.scrollToBottom();
          },
          onError: async (message: string) => {
            this.isStreaming = false;
            this.errorMessage = message;
            if (assistantMessage) {
              assistantMessage.isStreaming = false;
              if (!assistantMessage.content) {
                assistantMessage.content = `出错了：${message}`;
              }
            }
            try {
              await this.saveConversations();
            } catch (e) {
              // Ignore save errors
            }
            this.forceUpdateMessages();
          }
        }
      );
    } catch (e) {
      this.isStreaming = false;
      this.errorMessage = e instanceof Error ? e.message : 'Unknown error';
    }
  }

  private forceUpdateMessages(): void {
    const conversation = this.currentConversation;
    if (conversation) {
      // Reassign to trigger state change
      conversation.messages = [...conversation.messages];
      this.currentConversation = conversation;
    }
    this.messageRefreshToken++;
  }

  private scrollToBottom(): void {
    const conversation = this.currentConversation;
    if (!conversation) {
      return;
    }
    setTimeout(() => {
      const index = conversation.messages.length - 1;
      if (index >= 0) {
        this.listScroller.scrollToIndex(index, true);
      }
    }, 100);
  }

  private async stopStreaming(): Promise<void> {
    this.deepSeekService.cancel();
    this.isStreaming = false;
    const conversation = this.currentConversation;
    if (conversation) {
      const lastMessage = conversation.messages[conversation.messages.length - 1];
      if (lastMessage && lastMessage.role === 'assistant') {
        lastMessage.isStreaming = false;
      }
    }
    try {
      await this.saveConversations();
    } catch (e) {
      // Ignore save errors
    }
    this.forceUpdateMessages();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.HeaderBuilder()
        this.ChatListBuilder()
        this.InputAreaBuilder()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#f5f5f5')

      if (this.showHistory) {
        this.HistoryPanelBuilder()
      }

      if (this.showSettings) {
        this.SettingsPanelBuilder()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  HeaderBuilder() {
    Row() {
      Button('三')
        .fontSize(20)
        .fontColor('#333333')
        .type(ButtonType.Circle)
        .backgroundColor(Color.Transparent)
        .width(40)
        .height(40)
        .onClick(() => {
          this.showHistory = true;
        })

      Text(this.currentConversation?.title ?? 'DeepSeek Chat')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Button('设')
        .fontSize(20)
        .fontColor('#333333')
        .type(ButtonType.Circle)
        .backgroundColor(Color.Transparent)
        .width(40)
        .height(40)
        .onClick(() => {
          this.showSettings = true;
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .backgroundColor('#ffffff')
  }

  @Builder
  ChatListBuilder() {
    List({ scroller: this.listScroller }) {
      ForEach(this.currentConversation?.messages ?? [], (msg: ChatMessage, index: number) => {
        ListItem() {
          this.MessageItemBuilder(msg)
        }
        .width('100%')
        .key(`${msg.id}_${this.messageRefreshToken}`)
      }, (msg: ChatMessage) => msg.id)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8 })
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Auto)
  }

  @Builder
  MessageItemBuilder(msg: ChatMessage) {
    Column() {
      if (msg.role === 'user') {
        Row() {
          Text(msg.content)
            .fontSize(15)
            .fontColor('#ffffff')
            .maxLines(1000)
            .lineHeight(22)
        }
        .width('auto')
        .constraintSize({ maxWidth: '80%' })
        .padding(12)
        .backgroundColor('#4f7cff')
        .borderRadius({ topLeft: 16, topRight: 4, bottomLeft: 16, bottomRight: 16 })
      } else if (msg.role === 'assistant') {
        Column() {
          if (msg.reasoningContent) {
            Column() {
              Text('思考过程')
                .fontSize(12)
                .fontColor('#888888')
                .margin({ bottom: 4 })
              Text(msg.reasoningContent)
                .fontSize(14)
                .fontColor('#666666')
                .maxLines(1000)
                .lineHeight(20)
            }
            .width('100%')
            .padding(10)
            .backgroundColor('#f0f0f0')
            .borderRadius(8)
            .margin({ bottom: 8 })
          }

          Text(msg.content + (msg.isStreaming ? '▌' : ''))
            .fontSize(15)
            .fontColor('#222222')
            .maxLines(1000)
            .lineHeight(22)
            .width('100%')

          if (msg.toolCalls && msg.toolCalls.length > 0) {
            Column() {
              Text('工具调用')
                .fontSize(12)
                .fontColor('#888888')
                .margin({ bottom: 4 })
              ForEach(msg.toolCalls, (tc: ToolCall) => {
                Text(`${tc.function.name}(${tc.function.arguments})`)
                  .fontSize(12)
                  .fontColor('#4f7cff')
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2, bottom: 2 })
              }, (tc: ToolCall) => tc.id)
            }
            .width('100%')
            .padding(10)
            .backgroundColor('#eef2ff')
            .borderRadius(8)
            .margin({ top: 8 })
          }
        }
        .width('auto')
        .constraintSize({ maxWidth: '85%' })
        .alignSelf(ItemAlign.Start)
        .padding(12)
        .backgroundColor('#ffffff')
        .borderRadius({ topLeft: 4, topRight: 16, bottomLeft: 16, bottomRight: 16 })
      } else if (msg.role === 'tool') {
        Row() {
          Text(`工具结果: ${msg.content}`)
            .fontSize(13)
            .fontColor('#555555')
            .maxLines(1000)
            .lineHeight(20)
        }
        .width('auto')
        .constraintSize({ maxWidth: '85%' })
        .alignSelf(ItemAlign.Start)
        .padding(10)
        .backgroundColor('#e8e8e8')
        .borderRadius(8)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .alignItems(msg.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  @Builder
  InputAreaBuilder() {
    Column() {
      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(13)
          .fontColor('#ff4d4f')
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 6 })
      }

      Row() {
        TextInput({ placeholder: '输入消息...', text: this.inputText })
          .placeholderColor('#999999')
          .fontSize(15)
          .height(48)
          .backgroundColor('#ffffff')
          .borderRadius(24)
          .padding({ left: 16, right: 16 })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit(() => {
            if (!this.isStreaming) {
              this.sendMessage();
            }
          })

        if (this.isStreaming) {
          Button('停止')
            .fontSize(14)
            .fontColor('#ff4d4f')
            .backgroundColor('#ffffff')
            .border({ width: 1, color: '#ff4d4f' })
            .borderRadius(24)
            .height(44)
            .margin({ left: 8 })
            .onClick(() => {
              this.stopStreaming();
            })
        } else {
          Button('发送')
            .fontSize(14)
            .fontColor('#ffffff')
            .backgroundColor('#4f7cff')
            .borderRadius(24)
            .height(44)
            .margin({ left: 8 })
            .enabled(this.inputText.trim().length > 0)
            .onClick(() => {
              this.sendMessage();
            })
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#f5f5f5')
    }
  }

  @Builder
  HistoryPanelBuilder() {
    Column() {
      Row() {
        Text('历史记录')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)

        Button('新建')
          .fontSize(14)
          .fontColor('#4f7cff')
          .backgroundColor(Color.Transparent)
          .onClick(async () => {
            await this.createNewConversation();
            this.showHistory = false;
          })

        Button('×')
          .fontSize(18)
          .fontColor('#666666')
          .type(ButtonType.Circle)
          .backgroundColor(Color.Transparent)
          .width(36)
          .height(36)
          .onClick(() => {
            this.showHistory = false;
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 8 })
      .backgroundColor('#ffffff')

      List() {
        ForEach(this.conversations, (conv: Conversation) => {
          ListItem() {
            Row() {
              Column() {
                Text(conv.title || '新对话')
                  .fontSize(15)
                  .fontColor('#222222')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(new Date(conv.updateTime).toLocaleString())
                  .fontSize(12)
                  .fontColor('#999999')
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .onClick(() => {
                this.switchConversation(conv.id);
              })

              Button('删')
                .fontSize(14)
                .fontColor('#999999')
                .type(ButtonType.Circle)
                .backgroundColor(Color.Transparent)
                .width(32)
                .height(32)
                .onClick(() => {
                  this.deleteConversation(conv.id);
                })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.currentConversationId === conv.id ? '#eef2ff' : '#ffffff')
          }
        }, (conv: Conversation) => conv.id)
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: '#eeeeee' })
    }
    .width('75%')
    .height('100%')
    .backgroundColor('#ffffff')
    .align(Alignment.Start)
  }

  @Builder
  SettingsPanelBuilder() {
    Column() {
      Row() {
        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)

        Button('×')
          .fontSize(18)
          .fontColor('#666666')
          .type(ButtonType.Circle)
          .backgroundColor(Color.Transparent)
          .width(36)
          .height(36)
          .onClick(() => {
            this.showSettings = false;
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 8 })
      .backgroundColor('#ffffff')

      Scroll() {
        Column() {
          Text('API Key')
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')
            .margin({ top: 16, bottom: 8 })

          TextInput({ placeholder: '请输入 DeepSeek API Key', text: this.apiKey })
            .type(InputType.Password)
            .fontSize(15)
            .height(48)
            .backgroundColor('#f5f5f5')
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .width('100%')
            .onChange((value: string) => {
              this.apiKey = value;
            })

          Text('模型')
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')
            .margin({ top: 16, bottom: 8 })

          Column() {
            ForEach(AVAILABLE_MODELS, (model: string) => {
              Row() {
                Text(model)
                  .fontSize(15)
                  .fontColor('#222222')
                  .layoutWeight(1)
                Radio({ value: model, group: 'model_group' })
                  .checked(this.selectedModel === model)
                  .onChange((isChecked: boolean) => {
                    if (isChecked) {
                      this.selectedModel = model;
                    }
                  })
              }
              .width('100%')
              .height(48)
              .padding({ left: 12, right: 12 })
              .backgroundColor('#f5f5f5')
              .borderRadius(8)
              .margin({ bottom: 8 })
            }, (model: string) => model)
          }
          .width('100%')

          Row() {
            Text('开启思考')
              .fontSize(15)
              .fontColor('#222222')
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.thinkingEnabled })
              .onChange((isOn: boolean) => {
                this.thinkingEnabled = isOn;
              })
          }
          .width('100%')
          .height(56)
          .padding({ left: 12, right: 12 })
          .backgroundColor('#f5f5f5')
          .borderRadius(8)
          .margin({ top: 8 })

          Text('思考深度')
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')
            .margin({ top: 16, bottom: 8 })

          Row() {
            Button('high')
              .fontSize(14)
              .fontColor(this.reasoningEffort === 'high' ? '#ffffff' : '#222222')
              .backgroundColor(this.reasoningEffort === 'high' ? '#4f7cff' : '#f5f5f5')
              .layoutWeight(1)
              .margin({ right: 8 })
              .onClick(() => {
                this.reasoningEffort = 'high';
              })

            Button('max')
              .fontSize(14)
              .fontColor(this.reasoningEffort === 'max' ? '#ffffff' : '#222222')
              .backgroundColor(this.reasoningEffort === 'max' ? '#4f7cff' : '#f5f5f5')
              .layoutWeight(1)
              .onClick(() => {
                this.reasoningEffort = 'max';
              })
          }
          .width('100%')
          .height(48)

          Button('保存设置')
            .fontSize(16)
            .fontColor('#ffffff')
            .backgroundColor('#4f7cff')
            .borderRadius(24)
            .height(48)
            .width('100%')
            .margin({ top: 32 })
            .onClick(() => {
              this.saveSettings();
              this.showSettings = false;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 32 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('75%')
    .height('100%')
    .backgroundColor('#ffffff')
    .align(Alignment.End)
  }
}
