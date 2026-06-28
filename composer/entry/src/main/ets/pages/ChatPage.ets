import { AppSettings, DisplayMessage, MODEL_OPTIONS, REASONING_EFFORT_OPTIONS } from '../model/ChatModels';
import { MessageBubble } from '../components/MessageBubble';
import { chatManager, ChatStreamUpdate } from '../service/ChatManager';
import { storageService } from '../service/StorageService';

@Component
export struct ChatPage {
  @Link settings: AppSettings;
  @Prop @Watch('onRefreshKeyChange') refreshKey: number = 0;
  @State messages: DisplayMessage[] = [];
  @State inputText: string = '';
  @State isLoading: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadCurrentConversation();
  }

  onRefreshKeyChange(): void {
    this.loadCurrentConversation();
  }

  async loadCurrentConversation(): Promise<void> {
    const conv = await chatManager.ensureConversation();
    this.messages = [...conv.messages];
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  async sendMessage(): Promise<void> {
    const text = this.inputText.trim();
    if (!text || this.isLoading) {
      return;
    }

    if (!this.settings.apiKey || this.settings.apiKey.trim().length === 0) {
      AlertDialog.show({
        title: '缺少 API Key',
        message: '请先在「设置」页面填写 DeepSeek API Key',
        confirm: { value: '知道了', action: () => {} },
      });
      return;
    }

    this.inputText = '';

    await chatManager.sendMessage(text, this.settings, {
      onStreamUpdate: (_update: ChatStreamUpdate) => {
        this.messages = [...(chatManager.getConversation()?.messages ?? [])];
        this.scrollToBottom();
      },
      onMessageAdded: (_message: DisplayMessage) => {
        this.messages = [...(chatManager.getConversation()?.messages ?? [])];
        this.scrollToBottom();
      },
      onConversationUpdated: async (_conv) => {
        this.messages = [...(chatManager.getConversation()?.messages ?? [])];
      },
      onError: (message: string) => {
        AlertDialog.show({
          title: '请求失败',
          message: message,
          confirm: { value: '确定', action: () => {} },
        });
      },
      onLoadingChange: (loading: boolean) => {
        this.isLoading = loading;
      },
    });
  }

  async startNewChat(): Promise<void> {
    if (this.isLoading) {
      chatManager.cancelRequest();
    }
    await chatManager.createNewConversation();
    this.messages = [];
  }

  getDisplayMessages(): DisplayMessage[] {
    return this.messages.filter((m) => m.role !== 'tool');
  }

  build() {
    Column() {
      Row() {
        Text('DeepSeek 对话')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')

        Blank()

        Button('新对话')
          .fontSize(13)
          .height(32)
          .backgroundColor('#F0F0F0')
          .fontColor('#007AFF')
          .onClick(() => {
            this.startNewChat();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Row() {
        Text(`${this.settings.model}`)
          .fontSize(11)
          .fontColor('#888888')
        Text(' · ')
          .fontSize(11)
          .fontColor('#CCCCCC')
        Text(this.settings.thinkingEnabled ?
          `思考: ${this.settings.reasoningEffort}` : '思考: 关闭')
          .fontSize(11)
          .fontColor('#888888')
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      if (this.messages.length === 0) {
        Column() {
          Text('👋')
            .fontSize(48)
            .margin({ bottom: 16 })
          Text('开始与 DeepSeek 对话')
            .fontSize(18)
            .fontColor('#333333')
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 8 })
          Text('支持思考模式、流式输出、工具调用')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ bottom: 4 })
          Text('试试问：「现在几点了？」')
            .fontSize(13)
            .fontColor('#007AFF')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        Scroll(this.scroller) {
          Column() {
            ForEach(this.getDisplayMessages(), (msg: DisplayMessage) => {
              MessageBubble({ message: msg })
            }, (msg: DisplayMessage) => msg.id)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }

      Row() {
        TextInput({ placeholder: '输入消息...', text: this.inputText })
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .backgroundColor('#F5F5F5')
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit(() => {
            this.sendMessage();
          })

        Button() {
          if (this.isLoading) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color('#FFFFFF')
          } else {
            Text('发送')
              .fontSize(14)
              .fontColor('#FFFFFF')
          }
        }
        .width(64)
        .height(44)
        .margin({ left: 8 })
        .borderRadius(22)
        .backgroundColor(this.inputText.trim().length > 0 ? '#007AFF' : '#CCCCCC')
        .enabled(this.inputText.trim().length > 0 || this.isLoading)
        .onClick(() => {
          if (this.isLoading) {
            chatManager.cancelRequest();
            this.isLoading = false;
          } else {
            this.sendMessage();
          }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
  }
}
