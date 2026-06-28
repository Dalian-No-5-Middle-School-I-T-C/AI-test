import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import {
  ChatMessage, Conversation, ToolCall,
  createUserMessage, createAssistantMessage, createToolMessage,
  ToolDefinitionSchema, ToolFunctionSchema
} from '../model/ChatModel';
import { DeepSeekService, StreamCallbacks } from '../service/DeepSeekService';
import { StorageService, AppSettings } from '../service/StorageService';

function buildTools(): Array<ToolDefinitionSchema> {
  let func = new ToolFunctionSchema();
  func.name = 'get_current_time';
  func.description = 'Get the current system date and time of the device';
  func.parameters = '{"type":"object","properties":{},"required":[]}';

  let tool = new ToolDefinitionSchema();
  tool.type = 'function';
  tool.function = func;

  let tools: Array<ToolDefinitionSchema> = [];
  tools.push(tool);
  return tools;
}

const TOOLS: Array<ToolDefinitionSchema> = buildTools();

@Entry
@Component
struct Index {
  @State messages: Array<ChatMessage> = [];
  @State inputText: string = '';
  @State isLoading: boolean = false;
  @State streamingThinking: string = '';
  @State streamingContent: string = '';
  @State streamingToolNames: Array<string> = [];
  @State conversationTitle: string = 'New Chat';
  @State thinkingExpanded: boolean = true;
  @StorageLink('apiKey') apiKey: string = '';
  @StorageLink('model') model: string = 'deepseek-v4-pro';
  @StorageLink('thinkingEnabled') thinkingEnabled: boolean = true;
  @StorageLink('reasoningEffort') reasoningEffort: string = 'high';

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private deepSeekService: DeepSeekService = new DeepSeekService();
  private currentConversationId: string = Date.now().toString();
  private scroller: Scroller = new Scroller();
  private pendingToolCalls: Array<ToolCall> = [];

  aboutToAppear(): void {
    this.loadSettings();
    this.loadLastConversation();
  }

  onPageShow(): void {
    let selectedId = AppStorage.get<string>('selectedConversationId');
    if (selectedId && selectedId.length > 0) {
      this.loadConversationById(selectedId);
      AppStorage.set<string>('selectedConversationId', '');
    }
    this.loadSettings();
  }

  async loadSettings(): Promise<void> {
    try {
      let settings: AppSettings = await StorageService.loadSettings(this.context);
      if (settings.apiKey.length > 0) {
        this.apiKey = settings.apiKey;
      }
      if (settings.model.length > 0) {
        this.model = settings.model;
      }
      this.thinkingEnabled = settings.thinkingEnabled;
      if (settings.reasoningEffort.length > 0) {
        this.reasoningEffort = settings.reasoningEffort;
      }
    } catch (e) {
      // use defaults
    }
  }

  async loadLastConversation(): Promise<void> {
    try {
      let conversations = await StorageService.loadConversations(this.context);
      if (conversations.length > 0) {
        let last = conversations[conversations.length - 1];
        this.messages = last.messages;
        this.currentConversationId = last.id;
        this.conversationTitle = last.title;
      }
    } catch (e) {
      // start fresh
    }
  }

  async loadConversationById(id: string): Promise<void> {
    try {
      let conversations = await StorageService.loadConversations(this.context);
      for (let i = 0; i < conversations.length; i++) {
        if (conversations[i].id === id) {
          this.messages = conversations[i].messages;
          this.currentConversationId = conversations[i].id;
          this.conversationTitle = conversations[i].title;
          break;
        }
      }
    } catch (e) {
      // ignore
    }
  }

  async saveCurrentConversation(): Promise<void> {
    if (this.messages.length === 0) {
      return;
    }
    try {
      let conversations = await StorageService.loadConversations(this.context);
      let existingIndex: number = -1;
      for (let i = 0; i < conversations.length; i++) {
        if (conversations[i].id === this.currentConversationId) {
          existingIndex = i;
          break;
        }
      }

      let title = this.conversationTitle;
      if (title === 'New Chat') {
        for (let i = 0; i < this.messages.length; i++) {
          if (this.messages[i].role === 'user') {
            let content = this.messages[i].content;
            title = content.length > 30 ? content.substring(0, 30) + '...' : content;
            this.conversationTitle = title;
            break;
          }
        }
      }

      let conv = new Conversation();
      conv.id = this.currentConversationId;
      conv.title = title;
      conv.messages = this.messages;
      conv.timestamp = Date.now();

      if (existingIndex >= 0) {
        conversations[existingIndex] = conv;
      } else {
        conversations.push(conv);
      }

      await StorageService.saveConversations(this.context, conversations);
    } catch (e) {
      // ignore
    }
  }

  async sendMessage(): Promise<void> {
    let text = this.inputText.trim();
    if (text.length === 0 || this.isLoading) {
      return;
    }

    if (!this.apiKey) {
      promptAction.showToast({ message: 'Please set API Key in Settings' });
      return;
    }

    let userMsg = createUserMessage(text);
    this.messages.push(userMsg);
    this.inputText = '';
    this.isLoading = true;
    this.streamingThinking = '';
    this.streamingContent = '';
    this.streamingToolNames = [];
    this.pendingToolCalls = [];
    this.thinkingExpanded = true;

    this.scrollToBottom();
    await this.doChat();
  }

  async doChat(): Promise<void> {
    let self = this;

    let callbacks: StreamCallbacks = {
      onThinking: (text: string) => {
        self.streamingThinking += text;
      },
      onContent: (text: string) => {
        self.streamingContent += text;
        self.scrollToBottom();
      },
      onToolCall: (toolCalls: Array<ToolCall>) => {
        for (let i = 0; i < toolCalls.length; i++) {
          let tc = toolCalls[i];
          if (tc.id) {
            self.pendingToolCalls.push(tc);
            self.streamingToolNames.push(tc.name);
          } else if (self.pendingToolCalls.length > 0) {
            let last = self.pendingToolCalls[self.pendingToolCalls.length - 1];
            last.arguments += tc.arguments;
          }
        }
      },
      onDone: async (finishReason: string) => {
        if (finishReason === 'tool_calls' && self.pendingToolCalls.length > 0) {
          let assistantMsg = createAssistantMessage(
            self.streamingContent, self.streamingThinking, self.pendingToolCalls
          );
          self.messages.push(assistantMsg);

          for (let i = 0; i < self.pendingToolCalls.length; i++) {
            let tc = self.pendingToolCalls[i];
            let result = self.executeTool(tc.name, tc.arguments);
            let toolMsg = createToolMessage(tc.id, result);
            self.messages.push(toolMsg);
          }

          self.streamingThinking = '';
          self.streamingContent = '';
          self.streamingToolNames = [];
          self.pendingToolCalls = [];

          self.scrollToBottom();
          await self.doChat();
        } else {
          let assistantMsg = createAssistantMessage(
            self.streamingContent, self.streamingThinking, []
          );
          self.messages.push(assistantMsg);
          self.isLoading = false;
          self.streamingThinking = '';
          self.streamingContent = '';
          self.streamingToolNames = [];
          self.pendingToolCalls = [];
          self.scrollToBottom();
          await self.saveCurrentConversation();
        }
      },
      onError: (error: string) => {
        self.isLoading = false;
        let errorMsg = createAssistantMessage('Error: ' + error, '', []);
        self.messages.push(errorMsg);
        self.streamingThinking = '';
        self.streamingContent = '';
        self.streamingToolNames = [];
        self.pendingToolCalls = [];
      }
    };

    await this.deepSeekService.streamChat(
      this.apiKey,
      this.model,
      this.messages,
      this.thinkingEnabled,
      this.reasoningEffort,
      TOOLS,
      callbacks
    );
  }

  executeTool(name: string, args: string): string {
    if (name === 'get_current_time') {
      let now = new Date();
      let year = now.getFullYear().toString();
      let month = (now.getMonth() + 1).toString().padStart(2, '0');
      let day = now.getDate().toString().padStart(2, '0');
      let hours = now.getHours().toString().padStart(2, '0');
      let minutes = now.getMinutes().toString().padStart(2, '0');
      let seconds = now.getSeconds().toString().padStart(2, '0');
      return year + '-' + month + '-' + day + ' ' + hours + ':' + minutes + ':' + seconds;
    }
    return 'Unknown tool: ' + name;
  }

  startNewChat(): void {
    if (this.isLoading) {
      return;
    }
    this.saveCurrentConversation();
    this.messages = [];
    this.currentConversationId = Date.now().toString();
    this.conversationTitle = 'New Chat';
    this.inputText = '';
  }

  stopGeneration(): void {
    this.deepSeekService.cancel();
    this.isLoading = false;
    if (this.streamingContent.length > 0 || this.streamingThinking.length > 0) {
      let msg = createAssistantMessage(this.streamingContent, this.streamingThinking, []);
      this.messages.push(msg);
    }
    this.streamingThinking = '';
    this.streamingContent = '';
    this.streamingToolNames = [];
    this.pendingToolCalls = [];
    this.saveCurrentConversation();
  }

  scrollToBottom(): void {
    setTimeout(() => {
      let total = this.messages.length;
      if (this.isLoading) {
        total += 1;
      }
      if (total > 0) {
        this.scroller.scrollToIndex(total - 1);
      }
    }, 50);
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text(this.conversationTitle)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a1a1a')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.model + (this.thinkingEnabled ? (' | Thinking: ' + this.reasoningEffort) : ''))
            .fontSize(11)
            .fontColor('#999999')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button() {
          Text('+')
            .fontSize(22)
            .fontColor('#4A90D9')
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor('#F0F0F0')
        .onClick(() => {
          this.startNewChat();
        })

        Button() {
          Text('H')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#4A90D9')
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor('#F0F0F0')
        .margin({ left: 8 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/HistoryPage' });
        })

        Button() {
          Text('S')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#4A90D9')
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor('#F0F0F0')
        .margin({ left: 8 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/SettingsPage' });
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 2, color: '#1A000000', offsetY: 1 })

      List({ scroller: this.scroller }) {
        ForEach(this.messages, (msg: ChatMessage, index: number) => {
          ListItem() {
            if (msg.role === 'user') {
              this.UserBubble(msg)
            } else if (msg.role === 'assistant') {
              this.AssistantBubble(msg)
            } else if (msg.role === 'tool') {
              this.ToolResultBubble(msg)
            }
          }
        }, (msg: ChatMessage, index: number) => index.toString() + '_' + msg.role)

        if (this.isLoading) {
          ListItem() {
            this.StreamingBubble()
          }
        }
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor('#FAFAFA')
      .divider({ strokeWidth: 0 })

      Row() {
        TextInput({ text: this.inputText, placeholder: 'Message DeepSeek...' })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#F0F0F0')
          .borderRadius(20)
          .padding({ left: 16, right: 16 })
          .fontSize(15)
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit(() => {
            this.sendMessage();
          })

        if (this.isLoading) {
          Button() {
            Text('Stop')
              .fontSize(13)
              .fontColor('#FFFFFF')
          }
          .height(40)
          .width(64)
          .margin({ left: 8 })
          .backgroundColor('#E53935')
          .borderRadius(20)
          .onClick(() => {
            this.stopGeneration();
          })
        } else {
          Button() {
            Text('Send')
              .fontSize(13)
              .fontColor('#FFFFFF')
          }
          .height(40)
          .width(64)
          .margin({ left: 8 })
          .backgroundColor(this.inputText.trim().length > 0 ? '#4A90D9' : '#CCCCCC')
          .borderRadius(20)
          .enabled(this.inputText.trim().length > 0)
          .onClick(() => {
            this.sendMessage();
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 12 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 2, color: '#1A000000', offsetY: -1 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
  }

  @Builder
  UserBubble(msg: ChatMessage) {
    Row() {
      Blank()
      Text(msg.content)
        .fontSize(15)
        .fontColor('#FFFFFF')
        .backgroundColor('#4A90D9')
        .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 4 })
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .constraintSize({ maxWidth: '78%' })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
  }

  @Builder
  AssistantBubble(msg: ChatMessage) {
    Column() {
      if (msg.reasoningContent && msg.reasoningContent.length > 0) {
        Column() {
          Row() {
            Text('Thinking Process')
              .fontSize(12)
              .fontColor('#8D6E00')
              .fontWeight(FontWeight.Medium)
            Blank()
            Text(this.thinkingExpanded ? 'Collapse' : 'Expand')
              .fontSize(11)
              .fontColor('#4A90D9')
              .onClick(() => {
                this.thinkingExpanded = !this.thinkingExpanded;
              })
          }
          .width('100%')

          if (this.thinkingExpanded) {
            Text(msg.reasoningContent)
              .fontSize(13)
              .fontColor('#666666')
              .margin({ top: 6 })
              .lineHeight(20)
          }
        }
        .width('100%')
        .backgroundColor('#FFF8E1')
        .borderRadius(10)
        .padding(12)
        .margin({ bottom: 8 })
      }

      if (msg.toolCalls && msg.toolCalls.length > 0) {
        Column() {
          ForEach(msg.toolCalls, (tc: ToolCall) => {
            Row() {
              Text('Tool: ' + tc.name)
                .fontSize(12)
                .fontColor('#1565C0')
            }
            .backgroundColor('#E3F2FD')
            .borderRadius(6)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .margin({ bottom: 4 })
          }, (tc: ToolCall, index: number) => tc.id + '_' + index.toString())
        }
        .margin({ bottom: 8 })
      }

      if (msg.content && msg.content.length > 0) {
        Text(msg.content)
          .fontSize(15)
          .fontColor('#333333')
          .backgroundColor('#FFFFFF')
          .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 4, bottomRight: 16 })
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .constraintSize({ maxWidth: '85%' })
          .lineHeight(22)
          .shadow({ radius: 1, color: '#0D000000', offsetY: 1 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
  }

  @Builder
  ToolResultBubble(msg: ChatMessage) {
    Row() {
      Row() {
        Text('Tool Result')
          .fontSize(10)
          .fontColor('#2E7D32')
          .fontWeight(FontWeight.Medium)
      }
      .backgroundColor('#E8F5E9')
      .borderRadius(4)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .margin({ right: 6 })

      Text(msg.content)
        .fontSize(13)
        .fontColor('#555555')
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 2, bottom: 2 })
  }

  @Builder
  StreamingBubble() {
    Column() {
      if (this.streamingThinking && this.streamingThinking.length > 0) {
        Column() {
          Row() {
            Text('Thinking...')
              .fontSize(12)
              .fontColor('#8D6E00')
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')

          Text(this.streamingThinking)
            .fontSize(13)
            .fontColor('#666666')
            .margin({ top: 6 })
            .lineHeight(20)
            .maxLines(8)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .backgroundColor('#FFF8E1')
        .borderRadius(10)
        .padding(12)
        .margin({ bottom: 8 })
      }

      if (this.streamingToolNames.length > 0) {
        Column() {
          ForEach(this.streamingToolNames, (name: string, index: number) => {
            Text('Calling: ' + name + '...')
              .fontSize(12)
              .fontColor('#1565C0')
              .backgroundColor('#E3F2FD')
              .borderRadius(6)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .margin({ bottom: 4 })
          }, (name: string, index: number) => name + '_' + index.toString())
        }
        .margin({ bottom: 8 })
      }

      if (this.streamingContent && this.streamingContent.length > 0) {
        Text(this.streamingContent)
          .fontSize(15)
          .fontColor('#333333')
          .backgroundColor('#FFFFFF')
          .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 4, bottomRight: 16 })
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .constraintSize({ maxWidth: '85%' })
          .lineHeight(22)
          .shadow({ radius: 1, color: '#0D000000', offsetY: 1 })
      } else if (!this.streamingThinking && this.streamingToolNames.length === 0) {
        Row() {
          Text('...')
            .fontSize(15)
            .fontColor('#999999')
        }
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .shadow({ radius: 1, color: '#0D000000', offsetY: 1 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
  }
}
