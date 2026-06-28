import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import {
  AppSettings,
  ApiMessage,
  ChatMessage,
  ToolCall,
  genId
} from '../model/Types';
import { DeepSeekClient } from '../model/DeepSeekClient';
import { getToolDefs, executeTool } from '../model/Tools';
import { loadSettings, loadHistory, saveHistory } from '../model/ChatStore';
import { ChatBubble } from '../components/ChatBubble';

@Entry
@Component
struct Index {
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State isStreaming: boolean = false;
  @State settings: AppSettings = {
    apiKey: '',
    model: 'deepseek-v4-pro',
    thinkingType: 'enabled',
    reasoningEffort: 'high',
    systemPrompt: 'You are a helpful assistant.'
  };

  private scroller: ListScroller = new ListScroller();
  private currentClient: DeepSeekClient | null = null;

  aboutToAppear() {
    this.init();
  }

  onPageShow() {
    const ctx: common.Context = getContext(this) as common.Context;
    loadSettings(ctx).then((s: AppSettings) => {
      this.settings = s;
    });
  }

  async init() {
    const ctx: common.Context = getContext(this) as common.Context;
    this.settings = await loadSettings(ctx);
    this.messages = await loadHistory(ctx);
    this.scrollToBottom();
  }

  build() {
    Column() {
      this.Header()

      if (this.messages.length === 0) {
        Column() {
          Text('DeepSeek')
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor('#3366FF')
          Text('开始一段新的对话')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.scroller }) {
          ForEach(this.messages, (m: ChatMessage) => {
            ListItem() {
              ChatBubble({ msg: m })
            }
          }, (m: ChatMessage) => m.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ top: 4, bottom: 4 })
      }

      this.InputBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  Header() {
    Row() {
      Text('DeepSeek 聊天')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#222222')
      Blank()
      Button('新对话')
        .fontSize(14)
        .height(32)
        .enabled(!this.isStreaming)
        .onClick(() => this.newChat())
      Button('设置')
        .fontSize(14)
        .height(32)
        .margin({ left: 8 })
        .enabled(!this.isStreaming)
        .onClick(() => {
          router.pushUrl({ url: 'pages/Settings' });
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  InputBar() {
    Row() {
      TextArea({ text: this.inputText, placeholder: '输入消息...' })
        .fontSize(16)
        .constraintSize({ maxHeight: 120, minHeight: 40 })
        .layoutWeight(1)
        .enabled(!this.isStreaming)
        .onChange((v: string) => {
          this.inputText = v;
        })

      if (this.isStreaming) {
        Button('停止')
          .fontSize(14)
          .height(40)
          .margin({ left: 8 })
          .backgroundColor('#CC3333')
          .onClick(() => this.onStop())
      } else {
        Button('发送')
          .fontSize(14)
          .height(40)
          .margin({ left: 8 })
          .onClick(() => this.onSend())
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#FFFFFF')
  }

  onSend() {
    const text: string = this.inputText.trim();
    if (text.length === 0 || this.isStreaming) {
      return;
    }
    if (this.settings.apiKey.length === 0) {
      promptAction.showToast({ message: '请先在设置中填写 API Key' });
      return;
    }
    const userMsg: ChatMessage = new ChatMessage(genId(), 'user', text);
    this.messages.push(userMsg);
    this.inputText = '';
    this.scrollToBottom();
    this.sendAndStream();
  }

  onStop() {
    if (this.currentClient) {
      this.currentClient.cancel();
    }
  }

  newChat() {
    if (this.isStreaming) {
      return;
    }
    this.messages = [];
    this.saveHistory();
  }

  async sendAndStream() {
    const assistantMsg: ChatMessage = new ChatMessage(genId(), 'assistant', '');
    assistantMsg.isThinking = this.settings.thinkingType === 'enabled';
    this.messages.push(assistantMsg);
    this.scrollToBottom();
    this.isStreaming = true;
    try {
      await this.runTurn(assistantMsg);
    } finally {
      this.isStreaming = false;
      assistantMsg.isThinking = false;
      this.saveHistory();
    }
  }

  async runTurn(targetMsg: ChatMessage): Promise<void> {
    const apiMessages: ApiMessage[] = this.buildApiMessages(targetMsg.id);
    const client: DeepSeekClient = new DeepSeekClient();
    this.currentClient = client;
    let pendingToolCalls: ToolCall[] = [];

    await client.streamChat(apiMessages, this.settings, getToolDefs(), {
      onReasoning: (chunk: string) => {
        targetMsg.reasoningContent += chunk;
        targetMsg.isThinking = true;
        this.scrollToBottom();
      },
      onContent: (chunk: string) => {
        targetMsg.content += chunk;
        targetMsg.isThinking = false;
        this.scrollToBottom();
      },
      onToolCalls: (toolCalls: ToolCall[]) => {
        pendingToolCalls = toolCalls;
      },
      onDone: () => {
        targetMsg.isThinking = false;
      },
      onError: (message: string) => {
        targetMsg.isError = true;
        targetMsg.content = (targetMsg.content.length > 0 ? targetMsg.content + '\n' : '') + '⚠️ ' + message;
      }
    });

    this.currentClient = null;

    if (pendingToolCalls.length > 0 && !targetMsg.isError) {
      targetMsg.toolCalls = pendingToolCalls;
      targetMsg.isToolCall = true;

      for (let i = 0; i < pendingToolCalls.length; i++) {
        const tc: ToolCall = pendingToolCalls[i];
        const result: string = executeTool(tc.function.name, tc.function.arguments);
        const toolMsg: ChatMessage = new ChatMessage(genId(), 'tool', result);
        toolMsg.toolCallId = tc.id;
        this.messages.push(toolMsg);
      }
      this.scrollToBottom();

      const nextMsg: ChatMessage = new ChatMessage(genId(), 'assistant', '');
      nextMsg.isThinking = this.settings.thinkingType === 'enabled';
      this.messages.push(nextMsg);
      this.scrollToBottom();
      await this.runTurn(nextMsg);
    }
  }

  buildApiMessages(excludeId: string): ApiMessage[] {
    const result: ApiMessage[] = [];
    if (this.settings.systemPrompt.length > 0) {
      result.push({ role: 'system', content: this.settings.systemPrompt });
    }
    for (let i = 0; i < this.messages.length; i++) {
      const m: ChatMessage = this.messages[i];
      if (m.id === excludeId) {
        continue;
      }
      const apiMsg: ApiMessage = { role: m.role };
      if (m.content.length > 0) {
        apiMsg.content = m.content;
      }
      if (m.role === 'tool') {
        apiMsg.tool_call_id = m.toolCallId;
      }
      if (m.role === 'assistant' && m.isToolCall) {
        apiMsg.tool_calls = m.toolCalls;
      }
      result.push(apiMsg);
    }
    return result;
  }

  scrollToBottom() {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  async saveHistory() {
    const ctx: common.Context = getContext(this) as common.Context;
    await saveHistory(ctx, this.messages);
  }
}
