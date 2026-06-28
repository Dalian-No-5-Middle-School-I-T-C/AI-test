import { router } from '@kit.ArkUI';
import { ChatMessage, Conversation, ToolCallInfo } from '../models/ChatModels';
import { StorageService } from '../services/StorageService';
import { DeepSeekService, StreamCallbacks } from '../services/DeepSeekService';
import { ToolService } from '../services/ToolService';
import { MessageBubble } from '../components/MessageBubble';
import { ChatInput } from '../components/ChatInput';

@Entry
@Component
struct ChatPage {
  @State messages: ChatMessage[] = [];
  @State isStreaming: boolean = false;
  @State streamingReasoning: string = '';
  @State streamingContent: string = '';
  @State streamingToolCalls: ToolCallInfo[] = [];
  @State conversationId: string = '';
  @State conversationTitle: string = '新对话';
  @State errorMessage: string = '';
  private createdAt: number = Date.now();
  private scroller: Scroller = new Scroller();
  private deepseek: DeepSeekService = new DeepSeekService();
  private toolCallDepth: number = 0;
  private static readonly MAX_TOOL_DEPTH: number = 5;

  aboutToAppear(): void {
    let params = router.getParams() as Record<string, Object>;
    if (params) {
      let convId = params['conversationId'] as string;
      if (convId && convId.length > 0) {
        this.conversationId = convId;
        this.loadConversation(convId);
      } else {
        this.conversationId = StorageService.generateId();
        this.createdAt = Date.now();
      }
    } else {
      this.conversationId = StorageService.generateId();
      this.createdAt = Date.now();
    }
  }

  loadConversation(convId: string): void {
    let conv = StorageService.loadConversation(convId);
    if (conv) {
      this.messages = conv.messages;
      this.conversationTitle = conv.title;
      this.createdAt = conv.createdAt;
    }
  }

  saveConversation(): void {
    let conv: Conversation = {
      id: this.conversationId,
      title: this.conversationTitle,
      messages: this.messages,
      model: StorageService.getModel(),
      createdAt: this.createdAt,
      updatedAt: Date.now()
    };
    StorageService.saveConversation(conv);
  }

  build() {
    Column() {
      Row() {
        Button() {
          Text('←')
            .fontSize(20)
            .fontColor('#333333')
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.saveConversation();
          router.back();
        })

        Text(this.conversationTitle)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button() {
          Text('...')
            .fontSize(20)
            .fontColor('#333333')
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showClearDialog();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .backgroundColor('#FFFFFF')

      Divider().strokeWidth(1).color('#EEEEEE')

      if (this.errorMessage.length > 0) {
        Row() {
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor('#FF3B30')
            .layoutWeight(1)
          Button('✕')
            .fontSize(14)
            .width(28)
            .height(28)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.errorMessage = '';
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor('#FFF0F0')
      }

      List({ scroller: this.scroller }) {
        ForEach(this.messages, (msg: ChatMessage) => {
          ListItem() {
            MessageBubble({
              role: msg.role,
              content: msg.content,
              reasoningContent: msg.reasoningContent,
              toolCalls: this.formatToolCallsDisplay(msg),
              timestamp: msg.timestamp
            })
          }
          .width('100%')
        }, (msg: ChatMessage) => msg.id)

        if (this.isStreaming) {
          ListItem() {
            Column() {
              if (this.streamingReasoning.length > 0) {
                Column() {
                  Text('思考中...')
                    .fontSize(12)
                    .fontColor('#888888')
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  Scroll() {
                    Text(this.streamingReasoning)
                      .fontSize(13)
                      .fontColor('#666666')
                      .padding({ left: 8, right: 8, bottom: 8 })
                  }
                  .height(120)
                  .width('100%')
                  .scrollable(ScrollDirection.Vertical)
                }
                .width('90%')
                .backgroundColor('#F5F5FA')
                .borderRadius(8)
                .margin({ bottom: 4 })
              }

              if (this.streamingContent.length > 0) {
                Text(this.streamingContent)
                  .fontSize(15)
                  .fontColor('#333333')
                  .padding(10)
                  .borderRadius(12)
                  .backgroundColor('#F0F0F0')
                  .constraintSize({ maxWidth: '80%' })
              }

              if (this.streamingContent.length === 0 && this.streamingReasoning.length === 0) {
                Row() {
                  LoadingProgress()
                    .width(20)
                    .height(20)
                    .color('#4A90D9')
                  Text('正在响应...')
                    .fontSize(13)
                    .fontColor('#999999')
                    .margin({ left: 8 })
                }
                .padding(10)
              }

              ForEach(this.streamingToolCalls, (tc: ToolCallInfo) => {
                Text(`🔧 ${tc.functionName}: ${tc.result ? tc.result : '执行中...'}`)
                  .fontSize(12)
                  .fontColor('#666666')
                  .padding(6)
                  .backgroundColor('#FFF3E0')
                  .borderRadius(6)
                  .margin({ top: 4 })
                  .width('90%')
              }, (tc: ToolCallInfo) => tc.id)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          }
          .width('100%')
        }
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0 })

      Divider().strokeWidth(1).color('#EEEEEE')

      ChatInput({
        placeholder: this.isStreaming ? '等待回复中...' : '输入消息...',
        inputEnabled: !this.isStreaming,
        onSend: (text: string) => {
          this.sendMessage(text);
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
  }

  private sendMessage(userText: string): void {
    let apiKey = StorageService.getApiKey();
    if (apiKey.length === 0) {
      this.errorMessage = '请先在设置中填写 API Key';
      return;
    }

    let userMsg: ChatMessage = {
      id: StorageService.generateId(),
      role: 'user',
      content: userText,
      reasoningContent: '',
      toolCalls: [],
      toolCallId: '',
      timestamp: Date.now()
    };
    this.messages = [...this.messages, userMsg];

    if (this.conversationTitle === '新对话') {
      this.conversationTitle = userText.length > 20 ? userText.substring(0, 20) + '...' : userText;
    }

    this.isStreaming = true;
    this.streamingReasoning = '';
    this.streamingContent = '';
    this.streamingToolCalls = [];
    this.errorMessage = '';

    this.scrollToBottom();
    this.saveConversation();

    this.runChatLoop(apiKey);
  }

  private runChatLoop(apiKey: string): void {
    this.toolCallDepth = 0;
    this.runChatLoopInternal(apiKey);
  }

  private async runChatLoopInternal(apiKey: string): Promise<void> {
    let model = StorageService.getModel();
    let thinkingEnabled = StorageService.getThinkingEnabled();
    let reasoningEffort = StorageService.getReasoningEffort();

    let callbacks: StreamCallbacks = {
      onReasoning: (text: string) => {
        this.streamingReasoning += text;
        this.scrollToBottom();
      },
      onContent: (text: string) => {
        this.streamingContent += text;
        this.scrollToBottom();
      },
      onToolCall: (tc: ToolCallInfo) => {
      },
      onToolResult: (tc: ToolCallInfo) => {
        let idx = this.streamingToolCalls.findIndex((t: ToolCallInfo) => t.id === tc.id);
        if (idx >= 0) {
          this.streamingToolCalls[idx] = tc;
        } else {
          this.streamingToolCalls = [...this.streamingToolCalls, tc];
        }
      },
      onComplete: (content: string, reasoning: string, toolCalls: ToolCallInfo[]) => {
        this.onStreamComplete(apiKey, content, reasoning, toolCalls);
      },
      onError: (error: string) => {
        this.isStreaming = false;
        this.errorMessage = error;
        this.saveConversation();
      }
    };

    this.deepseek.streamChat(apiKey, model, thinkingEnabled, reasoningEffort, this.messages, callbacks);
  }

  private onStreamComplete(apiKey: string, content: string, reasoning: string,
    toolCalls: ToolCallInfo[]): void {
    let executedTools: ToolCallInfo[] = [];
    if (toolCalls.length > 0) {
      for (let i = 0; i < toolCalls.length; i++) {
        let tc = toolCalls[i];
        let result = ToolService.executeTool(tc.functionName, tc.functionArgs);
        tc.result = result;
        executedTools.push(tc);
      }

      let assistantMsg: ChatMessage = {
        id: StorageService.generateId(),
        role: 'assistant',
        content: this.streamingContent,
        reasoningContent: this.streamingReasoning,
        toolCalls: executedTools,
        toolCallId: '',
        timestamp: Date.now()
      };
      this.messages = [...this.messages, assistantMsg];

      for (let i = 0; i < executedTools.length; i++) {
        let toolMsg: ChatMessage = {
          id: StorageService.generateId(),
          role: 'tool',
          content: executedTools[i].result,
          reasoningContent: '',
          toolCalls: [],
          toolCallId: executedTools[i].id,
          timestamp: Date.now()
        };
        this.messages = [...this.messages, toolMsg];
      }

      this.streamingContent = '';
      this.streamingReasoning = '';
      this.streamingToolCalls = [];
      this.saveConversation();
      this.scrollToBottom();

      this.toolCallDepth++;
      if (this.toolCallDepth >= ChatPage.MAX_TOOL_DEPTH) {
        this.isStreaming = false;
        this.errorMessage = '工具调用次数已达上限';
        this.saveConversation();
        return;
      }

      this.runChatLoopInternal(apiKey);
      return;
    }

    let assistantMsg: ChatMessage = {
      id: StorageService.generateId(),
      role: 'assistant',
      content: this.streamingContent,
      reasoningContent: this.streamingReasoning,
      toolCalls: [],
      toolCallId: '',
      timestamp: Date.now()
    };
    this.messages = [...this.messages, assistantMsg];

    this.isStreaming = false;
    this.streamingContent = '';
    this.streamingReasoning = '';
    this.streamingToolCalls = [];
    this.saveConversation();
    this.scrollToBottom();
  }

  private scrollToBottom(): void {
    this.scroller.scrollEdge(Edge.Bottom);
  }

  private formatToolCallsDisplay(msg: ChatMessage): string {
    if (!msg.toolCalls || msg.toolCalls.length === 0) {
      return '';
    }
    let parts: string[] = [];
    for (let i = 0; i < msg.toolCalls.length; i++) {
      let tc = msg.toolCalls[i];
      parts.push(`${tc.functionName}: ${tc.result}`);
    }
    return parts.join('\n');
  }

  private showClearDialog(): void {
    AlertDialog.show({
      title: '清空对话',
      message: '确定要清空当前对话吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: '#FF3B30',
        action: () => {
          this.messages = [];
          this.conversationTitle = '新对话';
          this.createdAt = Date.now();
          this.saveConversation();
        }
      }
    });
  }
}
