// DeepSeek AI 聊天 - 主页面
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import {
  ChatMessage,
  AppSettings,
  DEFAULT_SETTINGS,
  Conversation,
  ModelId,
  ReasoningEffort,
  toSerializable,
  fromSerializable,
  SerializableMessage,
  ToolCall
} from '../models/ChatModels';
import { Storage } from '../storage/Storage';
import { ChatController, ChatControllerCallbacks } from '../service/ChatController';

@Entry
@Component
struct Index {
  // 消息列表（当前会话）
  @State messages: ChatMessage[] = [];
  // 输入框文本
  @State inputText: string = '';
  // 应用设置
  @State settings: AppSettings = {
    apiKey: DEFAULT_SETTINGS.apiKey,
    model: DEFAULT_SETTINGS.model,
    thinkingEnabled: DEFAULT_SETTINGS.thinkingEnabled,
    reasoningEffort: DEFAULT_SETTINGS.reasoningEffort
  };
  // 是否正在生成
  @State generating: boolean = false;
  // 设置面板可见
  @State showSettings: boolean = false;
  // 历史抽屉可见
  @State showHistory: boolean = false;
  // 全部会话历史
  @State conversations: Conversation[] = [];
  // 当前会话 id（空表示新会话）
  @State currentConversationId: string = '';

  private controller: ChatController = new ChatController();
  private scroller: Scroller = new Scroller();
  private initialized: boolean = false;

  async aboutToAppear(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await Storage.init(context);
    this.settings = await Storage.loadSettings();
    this.conversations = await Storage.loadConversations();
    this.initialized = true;
  }

  // 滚动到底部
  private scrollToBottom(): void {
    this.scroller.scrollEdge(Edge.Bottom);
  }

  // 持久化当前会话
  private async persistCurrentConversation(): Promise<void> {
    if (this.messages.length === 0) {
      return;
    }
    const serializable: SerializableMessage[] = this.messages.map((m) => toSerializable(m));
    const now: number = Date.now();

    if (this.currentConversationId.length === 0) {
      // 新建会话
      const id: string = `conv_${now}_${Math.floor(Math.random() * 100000)}`;
      const title: string = this.makeTitle();
      const conv: Conversation = {
        id: id,
        title: title,
        createdAt: now,
        updatedAt: now,
        messages: serializable
      };
      this.currentConversationId = id;
      this.conversations = [conv, ...this.conversations];
    } else {
      // 更新已有会话
      const updated: Conversation[] = this.conversations.map((c) => {
        if (c.id === this.currentConversationId) {
          const nc: Conversation = {
            id: c.id,
            title: c.title,
            createdAt: c.createdAt,
            updatedAt: now,
            messages: serializable
          };
          return nc;
        }
        return c;
      });
      this.conversations = updated;
    }
    await Storage.saveConversations(this.conversations);
  }

  // 用首条用户消息生成标题
  private makeTitle(): string {
    for (const m of this.messages) {
      if (m.role === 'user' && m.content.length > 0) {
        const t: string = m.content.trim();
        return t.length > 20 ? `${t.substring(0, 20)}...` : t;
      }
    }
    return '新对话';
  }

  // 发送消息
  private async onSend(): Promise<void> {
    const text: string = this.inputText.trim();
    if (text.length === 0) {
      return;
    }
    if (this.generating) {
      return;
    }
    if (this.settings.apiKey.length === 0) {
      promptAction.showToast({ message: '请先在设置中填写 API Key', duration: 2500 });
      this.showSettings = true;
      return;
    }

    // 加入用户消息与助手占位消息（流式），一次性换新引用触发 ForEach 渲染
    const userMsg = new ChatMessage('user', text);
    const assistantMsg = new ChatMessage('assistant', '');
    assistantMsg.streaming = true;
    this.messages.push(userMsg);
    this.messages.push(assistantMsg);
    this.messages = this.messages.slice();
    this.inputText = '';
    this.generating = true;
    this.scrollToBottom();

    const cb: ChatControllerCallbacks = {
      // UI 始终是消息数组的唯一所有者；控制器通过此回调实时读取最新数组
      getHistory: () => this.messages,
      // 追加新消息：先 push 再换新引用触发 ForEach 重建。
      // 因为 getHistory 总是返回 this.messages（即换后的新数组），不会再分裂。
      appendMessage: (msg: ChatMessage) => {
        this.messages.push(msg);
        this.messages = this.messages.slice();
        this.scrollToBottom();
      },
      onUpdate: () => {
        // 流式增量靠 @ObjectLink 精确刷新单条消息，这里只需滚动到底部
        this.scrollToBottom();
      },
      onComplete: () => {
        this.generating = false;
        this.persistCurrentConversation();
      },
      onError: (message: string) => {
        this.generating = false;
        promptAction.showToast({ message: message, duration: 3000 });
        this.persistCurrentConversation();
      }
    };

    this.controller.startRound(assistantMsg, this.settings, cb);
  }

  // 停止生成
  private onStop(): void {
    this.controller.stop();
    this.generating = false;
    // 标记最后一条流式消息结束
    for (let i = this.messages.length - 1; i >= 0; i--) {
      if (this.messages[i].streaming) {
        this.messages[i].streaming = false;
        break;
      }
    }
    this.messages = this.messages.slice();
    this.persistCurrentConversation();
  }

  // 新建会话
  private onNewChat(): void {
    if (this.generating) {
      this.controller.stop();
      this.generating = false;
    }
    this.messages = [];
    this.currentConversationId = '';
    this.showHistory = false;
  }

  // 加载某个历史会话
  private onLoadConversation(conv: Conversation): void {
    if (this.generating) {
      this.controller.stop();
      this.generating = false;
    }
    this.messages = conv.messages.map((s) => fromSerializable(s));
    this.currentConversationId = conv.id;
    this.showHistory = false;
    this.scrollToBottom();
  }

  // 删除某个历史会话
  private async onDeleteConversation(id: string): Promise<void> {
    this.conversations = this.conversations.filter((c) => c.id !== id);
    await Storage.saveConversations(this.conversations);
    if (this.currentConversationId === id) {
      this.messages = [];
      this.currentConversationId = '';
    }
  }

  // 保存设置
  private async onSaveSettings(): Promise<void> {
    await Storage.saveSettings(this.settings);
    this.showSettings = false;
    promptAction.showToast({ message: '设置已保存', duration: 1500 });
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        this.TopBar()
        this.MessageList()
        this.InputBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F2F3F5')

      // 设置面板
      if (this.showSettings) {
        this.SettingsPanel()
      }

      // 历史抽屉
      if (this.showHistory) {
        this.HistoryDrawer()
      }
    }
    .width('100%')
    .height('100%')
  }

  // ---- 顶部栏 ----
  @Builder
  TopBar() {
    Row() {
      Button() {
        Text('☰').fontSize(20).fontColor('#333333')
      }
      .backgroundColor(Color.Transparent)
      .width(40)
      .height(40)
      .onClick(() => {
        this.showHistory = true;
      })

      Column() {
        Text('DeepSeek 助手')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
        Text(this.modelLabel())
          .fontSize(11)
          .fontColor('#888888')
      }
      .alignItems(HorizontalAlign.Center)
      .layoutWeight(1)

      Button() {
        Text('＋').fontSize(22).fontColor('#333333')
      }
      .backgroundColor(Color.Transparent)
      .width(40)
      .height(40)
      .onClick(() => {
        this.onNewChat();
      })

      Button() {
        Text('⚙').fontSize(20).fontColor('#333333')
      }
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
    .backgroundColor('#FFFFFF')
    .alignItems(VerticalAlign.Center)
    .shadow({ radius: 4, color: '#11000000', offsetY: 1 })
  }

  private modelLabel(): string {
    const name: string = this.settings.model === 'deepseek-v4-pro' ? 'V4 Pro' : 'V4 Flash';
    if (this.settings.thinkingEnabled) {
      return `${name} · 思考(${this.settings.reasoningEffort})`;
    }
    return `${name} · 不思考`;
  }

  // ---- 消息列表 ----
  @Builder
  MessageList() {
    Scroll(this.scroller) {
      Column({ space: 12 }) {
        if (this.messages.length === 0) {
          this.EmptyState()
        }
        ForEach(this.messages, (msg: ChatMessage) => {
          MessageItemView({ message: msg, onToggleReasoning: () => {
            this.messages = this.messages.slice();
          } })
        }, (msg: ChatMessage) => msg.id)
        // 底部留白
        Blank().height(8)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .constraintSize({ minHeight: '100%' })
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  EmptyState() {
    Column({ space: 12 }) {
      Text('🤖')
        .fontSize(56)
      Text('开始和 DeepSeek 对话吧')
        .fontSize(16)
        .fontColor('#666666')
      Text('支持思考模式、多轮对话、工具调用')
        .fontSize(13)
        .fontColor('#999999')
    }
    .width('100%')
    .padding({ top: 120 })
    .alignItems(HorizontalAlign.Center)
  }

  // ---- 输入栏 ----
  @Builder
  InputBar() {
    Column() {
      Row({ space: 8 }) {
        TextInput({ text: this.inputText, placeholder: '输入消息…' })
          .layoutWeight(1)
          .fontSize(15)
          .backgroundColor('#F2F3F5')
          .borderRadius(20)
          .padding({ left: 16, right: 16 })
          .height(44)
          .enabled(!this.generating)
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit(() => {
            this.onSend();
          })

        if (this.generating) {
          Button() {
            Text('停止').fontSize(14).fontColor('#FFFFFF')
          }
          .width(60)
          .height(44)
          .backgroundColor('#D03050')
          .borderRadius(22)
          .onClick(() => {
            this.onStop();
          })
        } else {
          Button() {
            Text('发送').fontSize(14).fontColor('#FFFFFF')
          }
          .width(60)
          .height(44)
          .backgroundColor(this.inputText.trim().length > 0 ? '#3B7BF6' : '#A9C4FB')
          .borderRadius(22)
          .enabled(this.inputText.trim().length > 0)
          .onClick(() => {
            this.onSend();
          })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .shadow({ radius: 4, color: '#11000000', offsetY: -1 })
  }

  // ---- 设置面板 ----
  @Builder
  SettingsPanel() {
    Column() {
      // 遮罩
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showSettings = false;
        })

      // 面板主体
      Column({ space: 16 }) {
        Row() {
          Text('设置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          Text('✕')
            .fontSize(18)
            .fontColor('#999999')
            .onClick(() => {
              this.showSettings = false;
            })
        }
        .width('100%')

        // API Key
        Column({ space: 6 }) {
          Text('API Key')
            .fontSize(14)
            .fontColor('#333333')
            .width('100%')
            .textAlign(TextAlign.Start)
          TextInput({ text: this.settings.apiKey, placeholder: 'sk-...' })
            .type(InputType.Password)
            .fontSize(14)
            .backgroundColor('#F2F3F5')
            .borderRadius(8)
            .height(44)
            .width('100%')
            .onChange((value: string) => {
              this.settings.apiKey = value;
            })
        }
        .width('100%')

        // 模型选择
        Column({ space: 6 }) {
          Text('模型')
            .fontSize(14)
            .fontColor('#333333')
            .width('100%')
            .textAlign(TextAlign.Start)
          Row({ space: 10 }) {
            this.ModelOption('deepseek-v4-flash', 'V4 Flash')
            this.ModelOption('deepseek-v4-pro', 'V4 Pro')
          }
          .width('100%')
        }
        .width('100%')

        // 思考开关
        Row() {
          Column() {
            Text('开启思考')
              .fontSize(14)
              .fontColor('#333333')
              .width('100%')
              .textAlign(TextAlign.Start)
            Text('关闭后模型直接回答，不展示思考过程')
              .fontSize(11)
              .fontColor('#999999')
              .width('100%')
              .textAlign(TextAlign.Start)
          }
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.settings.thinkingEnabled })
            .selectedColor('#3B7BF6')
            .onChange((isOn: boolean) => {
              this.settings.thinkingEnabled = isOn;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // 思考深度（仅在开启思考时显示）
        if (this.settings.thinkingEnabled) {
          Column({ space: 6 }) {
            Text('思考深度')
              .fontSize(14)
              .fontColor('#333333')
              .width('100%')
              .textAlign(TextAlign.Start)
            Row({ space: 10 }) {
              this.EffortOption('high', 'High（标准）')
              this.EffortOption('max', 'Max（深度）')
            }
            .width('100%')
          }
          .width('100%')
        }

        // 保存按钮
        Button('保存设置')
          .width('100%')
          .height(46)
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor('#3B7BF6')
          .borderRadius(10)
          .margin({ top: 4 })
          .onClick(() => {
            this.onSaveSettings();
          })
      }
      .width('100%')
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ModelOption(model: string, label: string) {
    Text(label)
      .fontSize(14)
      .fontColor(this.settings.model === model ? '#FFFFFF' : '#333333')
      .backgroundColor(this.settings.model === model ? '#3B7BF6' : '#F2F3F5')
      .borderRadius(8)
      .padding({ top: 10, bottom: 10 })
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .onClick(() => {
        this.settings.model = model as ModelId;
      })
  }

  @Builder
  EffortOption(effort: string, label: string) {
    Text(label)
      .fontSize(14)
      .fontColor(this.settings.reasoningEffort === effort ? '#FFFFFF' : '#333333')
      .backgroundColor(this.settings.reasoningEffort === effort ? '#3B7BF6' : '#F2F3F5')
      .borderRadius(8)
      .padding({ top: 10, bottom: 10 })
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .onClick(() => {
        this.settings.reasoningEffort = effort as ReasoningEffort;
      })
  }

  // ---- 历史抽屉 ----
  @Builder
  HistoryDrawer() {
    Row() {
      // 抽屉主体
      Column() {
        Row() {
          Text('历史对话')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          Text('✕')
            .fontSize(18)
            .fontColor('#999999')
            .onClick(() => {
              this.showHistory = false;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        Button('＋ 新建对话')
          .width('90%')
          .height(42)
          .fontSize(15)
          .fontColor('#3B7BF6')
          .backgroundColor('#EAF1FE')
          .borderRadius(10)
          .margin({ bottom: 12 })
          .onClick(() => {
            this.onNewChat();
          })

        if (this.conversations.length === 0) {
          Column() {
            Text('暂无历史对话')
              .fontSize(14)
              .fontColor('#999999')
          }
          .width('100%')
          .padding({ top: 60 })
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.conversations, (conv: Conversation) => {
              ListItem() {
                this.HistoryItem(conv)
              }
            }, (conv: Conversation) => conv.id)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 12, right: 12 })
          .scrollBar(BarState.Off)
        }
      }
      .width('80%')
      .height('100%')
      .backgroundColor('#FFFFFF')

      // 遮罩
      Column()
        .layoutWeight(1)
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showHistory = false;
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  HistoryItem(conv: Conversation) {
    Row() {
      Column({ space: 4 }) {
        Text(conv.title)
          .fontSize(15)
          .fontColor(conv.id === this.currentConversationId ? '#3B7BF6' : '#1A1A1A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)
        Text(this.formatTime(conv.updatedAt))
          .fontSize(11)
          .fontColor('#999999')
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)

      Text('🗑')
        .fontSize(16)
        .padding(6)
        .onClick(() => {
          this.onDeleteConversation(conv.id);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(conv.id === this.currentConversationId ? '#EAF1FE' : '#F7F8FA')
    .borderRadius(10)
    .onClick(() => {
      this.onLoadConversation(conv);
    })
  }

  private formatTime(ts: number): string {
    const d = new Date(ts);
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
}

// 单条消息视图：通过 @ObjectLink 订阅 @Observed 的 ChatMessage，
// 使流式增量更新（content / reasoning）能精确触发本组件重绘
@Component
struct MessageItemView {
  @ObjectLink message: ChatMessage;
  // 切换思考展开后通知父组件（用于必要的列表刷新）
  onToggleReasoning: () => void = () => {};

  build() {
    if (this.message.role === 'user') {
      // 用户消息：右对齐
      Row() {
        Blank().layoutWeight(1)
        Text(this.message.content)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor('#3B7BF6')
          .borderRadius(12)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .constraintSize({ maxWidth: '78%' })
          .textAlign(TextAlign.Start)
      }
      .width('100%')
    } else if (this.message.role === 'tool') {
      // 工具调用结果：居中小卡片
      Row() {
        Text(`🔧 ${this.message.toolLabel}`)
          .fontSize(12)
          .fontColor('#7A6000')
          .backgroundColor('#FFF6D6')
          .borderRadius(8)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .constraintSize({ maxWidth: '90%' })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      // 助手消息：左对齐
      Column({ space: 6 }) {
        // 思考区
        if (this.message.reasoning.length > 0) {
          this.ReasoningBlock()
        }
        // 工具调用提示（assistant 发起调用时）
        if (this.message.toolCalls.length > 0) {
          this.ToolCallHint()
        }
        // 正文
        if (this.message.content.length > 0 || (this.message.streaming && this.message.reasoning.length === 0)) {
          Text(this.message.content.length > 0 ? this.message.content : '思考中…')
            .fontSize(15)
            .fontColor(this.message.isError ? '#D03050' : '#1A1A1A')
            .backgroundColor(this.message.isError ? '#FDE7EC' : '#FFFFFF')
            .borderRadius(12)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .constraintSize({ maxWidth: '85%' })
            .textAlign(TextAlign.Start)
        }
        // 流式进度提示
        if (this.message.streaming && this.message.content.length > 0) {
          Row() {
            LoadingProgress().width(16).height(16).color('#3B7BF6')
            Text('生成中').fontSize(11).fontColor('#999999').margin({ left: 4 })
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  // 思考折叠块
  @Builder
  ReasoningBlock() {
    Column() {
      Row() {
        Text('💭 思考过程')
          .fontSize(12)
          .fontColor('#666666')
          .layoutWeight(1)
        Text(this.message.reasoningExpanded ? '收起 ▲' : '展开 ▼')
          .fontSize(12)
          .fontColor('#3B7BF6')
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .onClick(() => {
        this.message.reasoningExpanded = !this.message.reasoningExpanded;
        this.onToggleReasoning();
      })

      if (this.message.reasoningExpanded) {
        Text(this.message.reasoning)
          .fontSize(13)
          .fontColor('#777777')
          .padding({ left: 10, right: 10, top: 0, bottom: 8 })
          .width('100%')
          .textAlign(TextAlign.Start)
      }
    }
    .backgroundColor('#F0F1F3')
    .borderRadius(10)
    .border({ width: 1, color: '#E2E4E8' })
    .constraintSize({ maxWidth: '85%' })
  }

  @Builder
  ToolCallHint() {
    Column() {
      ForEach(this.message.toolCalls, (tc: ToolCall) => {
        Text(`🔧 调用工具: ${tc.function.name}`)
          .fontSize(12)
          .fontColor('#7A6000')
      }, (tc: ToolCall, idx: number) => `${this.message.id}_tc_${idx}`)
    }
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#FFF6D6')
    .borderRadius(8)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .constraintSize({ maxWidth: '85%' })
  }
}
