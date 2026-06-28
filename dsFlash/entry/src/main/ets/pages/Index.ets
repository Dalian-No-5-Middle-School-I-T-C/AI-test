import router from '@ohos.router';
import {
  MODEL_FLASH,
  MODEL_PRO,
  STORAGE_KEY_API,
  STORAGE_KEY_SESSIONS,
  DEEPSEEK_SYSTEM_PROMPT
} from '../common/constants';
import { generateId, formatTime, formatDate } from '../common/utils';
import {
  ChatMessage,
  MessageRole,
  ChatSession,
  ToolCallInfo,
  ToolCall,
  ApiMessage
} from '../models/ChatModels';
import { DeepSeekService } from '../services/DeepSeekService';
import { ToolService } from '../services/ToolService';

PersistentStorage.persistProp(STORAGE_KEY_API, '');
PersistentStorage.persistProp(STORAGE_KEY_SESSIONS, '[]');

@Entry
@Component
struct Index {
  @StorageLink(STORAGE_KEY_API) apiKey: string = '';
  @StorageLink(STORAGE_KEY_SESSIONS) sessionsJson: string = '';

  @State messages: ChatMessage[] = [];
  @State currentModel: string = MODEL_FLASH;
  @State thinkingEnabled: boolean = true;
  @State reasoningEffort: string = 'high';
  @State inputText: string = '';
  @State isStreaming: boolean = false;
  @State currentThinking: string = '';
  @State currentContent: string = '';
  @State sessions: ChatSession[] = [];
  @State currentSessionId: string = '';
  @State showHistory: boolean = false;
  @State thinkingExpanded: boolean = false;

  private listScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadSessions();
    this.startNewSession();
  }

  loadSessions(): void {
    try {
      const parsed: object = JSON.parse(this.sessionsJson);
      if (Array.isArray(parsed)) {
        this.sessions = parsed as ChatSession[];
      }
    } catch (e) {
      this.sessions = [];
    }
  }

  saveSessions(): void {
    this.sessionsJson = JSON.stringify(this.sessions);
  }

  startNewSession(): void {
    this.currentSessionId = generateId();
    this.messages = [];
    this.currentThinking = '';
    this.currentContent = '';
    this.thinkingExpanded = false;
    this.isStreaming = false;

    const sysMsg: ChatMessage = {
      id: generateId(),
      role: MessageRole.SYSTEM,
      content: DEEPSEEK_SYSTEM_PROMPT,
      timestamp: Date.now()
    };
    this.messages.push(sysMsg);
  }

  switchSession(sessionId: string): void {
    const session: ChatSession | undefined = this.findSession(sessionId);
    if (session) {
      this.currentSessionId = session.id;
      this.messages = session.messages.slice();
      this.currentModel = session.model;
      this.thinkingEnabled = session.thinkingEnabled;
      this.reasoningEffort = session.reasoningEffort;
      this.showHistory = false;
    }
  }

  findSession(sessionId: string): ChatSession | undefined {
    for (const s of this.sessions) {
      if (s.id === sessionId) {
        return s;
      }
    }
    return undefined;
  }

  deleteSession(sessionId: string): void {
    const newSessions: ChatSession[] = [];
    for (const s of this.sessions) {
      if (s.id !== sessionId) {
        newSessions.push(s);
      }
    }
    this.sessions = newSessions;
    this.saveSessions();
    if (this.currentSessionId === sessionId) {
      this.startNewSession();
    }
  }

  getSessionTitle(messages: ChatMessage[]): string {
    for (const msg of messages) {
      if (msg.role === MessageRole.USER && msg.content.length > 0) {
        if (msg.content.length > 40) {
          return msg.content.slice(0, 40) + '...';
        }
        return msg.content;
      }
    }
    return 'New Chat';
  }

  saveCurrentSession(): void {
    if (this.messages.length <= 1) {
      return;
    }
    const title: string = this.getSessionTitle(this.messages);
    const now: number = Date.now();
    const existing: number = this.findSessionIndex(this.currentSessionId);
    const session: ChatSession = {
      id: this.currentSessionId,
      title: title,
      messages: this.messages.slice(),
      model: this.currentModel,
      reasoningEffort: this.reasoningEffort,
      thinkingEnabled: this.thinkingEnabled,
      createdAt: existing >= 0 ? this.sessions[existing].createdAt : now,
      updatedAt: now
    };
    if (existing >= 0) {
      this.sessions[existing] = session;
    } else {
      this.sessions.unshift(session);
    }
    if (this.sessions.length > 50) {
      this.sessions = this.sessions.slice(0, 50);
    }
    this.saveSessions();
  }

  findSessionIndex(sessionId: string): number {
    for (let i: number = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === sessionId) {
        return i;
      }
    }
    return -1;
  }

  buildApiMessages(): ApiMessage[] {
    const result: ApiMessage[] = [];
    for (const msg of this.messages) {
      if (msg.role === MessageRole.SYSTEM) {
        const apiMsg: ApiMessage = { role: 'system', content: msg.content };
        result.push(apiMsg);
      } else if (msg.role === MessageRole.USER) {
        const apiMsg: ApiMessage = { role: 'user', content: msg.content };
        result.push(apiMsg);
      } else if (msg.role === MessageRole.ASSISTANT) {
        if (msg.toolCalls && msg.toolCalls.length > 0) {
          const apiMsg: ApiMessage = {
            role: 'assistant',
            content: msg.content || '',
            tool_calls: msg.toolCalls
          };
          result.push(apiMsg);
        } else {
          const apiMsg: ApiMessage = { role: 'assistant', content: msg.content };
          result.push(apiMsg);
        }
      } else if (msg.role === MessageRole.TOOL) {
        const apiMsg: ApiMessage = {
          role: 'tool',
          content: msg.content,
          tool_call_id: msg.toolCallId || ''
        };
        result.push(apiMsg);
      }
    }
    return result;
  }

  sendMessage(): void {
    const text: string = this.inputText.trim();
    if (!text || this.isStreaming) {
      return;
    }
    if (!this.apiKey) {
      const errMsg: ChatMessage = {
        id: generateId(),
        role: MessageRole.ASSISTANT,
        content: 'Please set your DeepSeek API Key first. Go to Settings to configure it.',
        timestamp: Date.now()
      };
      this.messages.push(errMsg);
      return;
    }

    this.inputText = '';
    const userMsg: ChatMessage = {
      id: generateId(),
      role: MessageRole.USER,
      content: text,
      timestamp: Date.now()
    };
    this.messages.push(userMsg);
    this.scrollToBottom();

    this.streamWithToolLoop();
  }

  async streamWithToolLoop(): Promise<void> {
    let keepLooping: boolean = true;

    while (keepLooping) {
      keepLooping = false;

      const assistantId: string = generateId();
      const assistantMsg: ChatMessage = {
        id: assistantId,
        role: MessageRole.ASSISTANT,
        content: '',
        thinkingContent: '',
        timestamp: Date.now()
      };
      this.messages.push(assistantMsg);

      const currentApiMessages: ApiMessage[] = this.buildApiMessages();
      this.isStreaming = true;
      this.currentThinking = '';
      this.currentContent = '';
      this.thinkingExpanded = true;

      let toolCallResults: ToolCallInfo[] = [];
      let streamError: string = '';

      const service: DeepSeekService = new DeepSeekService(this.apiKey);

      await new Promise<void>((resolve: () => void) => {
        service.streamChat(
          this.currentModel,
          currentApiMessages,
          this.thinkingEnabled,
          this.reasoningEffort,
          (thinking: string) => {
            assistantMsg.thinkingContent = (assistantMsg.thinkingContent || '') + thinking;
            this.currentThinking = assistantMsg.thinkingContent || '';
            this.messages = [...this.messages];
            this.scrollToBottom();
          },
          (content: string) => {
            assistantMsg.content += content;
            this.currentContent = assistantMsg.content;
            this.messages = [...this.messages];
            this.scrollToBottom();
          },
          (toolCalls: ToolCallInfo[]) => {
            toolCallResults = toolCallResults.concat(toolCalls);
          },
          (finishReason: string) => {
            // finish reason received, stream will end soon
          },
          (error: string) => {
            streamError = error;
            assistantMsg.content = 'Error: ' + error;
            this.messages = [...this.messages];
          },
          () => {
            // onComplete - stream fully ended
            resolve();
          }
        );
      });

      this.isStreaming = false;

      if (streamError) {
        this.saveCurrentSession();
        return;
      }

      // Handle tool calls
      if (toolCallResults.length > 0) {
        const toolCallsForMsg: ToolCall[] = [];
        for (const tc of toolCallResults) {
          const t: ToolCall = {
            id: tc.id,
            type: tc.type,
            function: {
              name: tc.functionName,
              arguments: tc.functionArguments
            }
          };
          toolCallsForMsg.push(t);
        }
        assistantMsg.toolCalls = toolCallsForMsg;

        for (const tc of toolCallResults) {
          const result: string = ToolService.executeTool(tc.functionName, tc.functionArguments);

          const toolCallEntry: ChatMessage = {
            id: generateId(),
            role: MessageRole.ASSISTANT,
            content: '',
            timestamp: Date.now(),
            toolCalls: [{
              id: tc.id,
              type: tc.type,
              function: {
                name: tc.functionName,
                arguments: tc.functionArguments
              }
            }]
          };
          this.messages.push(toolCallEntry);

          const toolResultEntry: ChatMessage = {
            id: generateId(),
            role: MessageRole.TOOL,
            content: result,
            timestamp: Date.now(),
            toolCallId: tc.id,
            toolName: tc.functionName
          };
          this.messages.push(toolResultEntry);
        }

        keepLooping = true;
      } else {
        this.saveCurrentSession();
      }
    }
  }

  scrollToBottom(): void {
    setTimeout(() => {
      this.listScroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  clearChat(): void {
    this.saveCurrentSession();
    this.startNewSession();
    this.showHistory = false;
  }

  build() {
    Column() {
      // Header
      Row() {
        Text('DeepSeek Chat')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)

        Blank()

        Button() {
          Text('New')
            .fontSize(14)
        }
        .onClick(() => {
          this.clearChat();
        })
        .backgroundColor('#007aff')
        .fontColor(Color.White)
        .borderRadius(16)
        .height(32)
        .padding({ left: 12, right: 12 })

        Button() {
          Text('History')
            .fontSize(14)
        }
        .onClick(() => {
          this.loadSessions();
          this.showHistory = !this.showHistory;
        })
        .backgroundColor(this.showHistory ? '#e0e0e0' : '#f0f0f0')
        .fontColor('#333333')
        .borderRadius(16)
        .height(32)
        .padding({ left: 12, right: 12 })
        .margin({ left: 6 })

        Button() {
          Text('⚙')
            .fontSize(18)
        }
        .onClick(() => {
          this.saveCurrentSession();
          router.pushUrl({ url: 'pages/Settings' });
        })
        .backgroundColor(Color.Transparent)
        .fontColor('#333333')
        .margin({ left: 4 })
      }
      .width('100%')
      .padding({ left: 12, right: 8, top: 10, bottom: 10 })
      .backgroundColor('#f8f8f8')

      // Control bar
      Row() {
        Text('Model:')
          .fontSize(13)
          .fontColor('#666666')

        Select([{ value: MODEL_FLASH, icon: '' }, { value: MODEL_PRO, icon: '' }])
          .selected(this.currentModel === MODEL_PRO ? 1 : 0)
          .value(this.currentModel === MODEL_PRO ? 'Pro' : 'Flash')
          .onSelect((index: number, value: string) => {
            this.currentModel = value;
          })
          .margin({ left: 4 })
          .height(32)

        Text('Think:')
          .fontSize(13)
          .fontColor('#666666')
          .margin({ left: 12 })

        Toggle({ type: ToggleType.Switch, isOn: this.thinkingEnabled })
          .onChange((isOn: boolean) => {
            this.thinkingEnabled = isOn;
          })
          .height(24)

        if (this.thinkingEnabled) {
          Text('Effort:')
            .fontSize(13)
            .fontColor('#666666')
            .margin({ left: 8 })

          Select([{ value: 'high', icon: '' }, { value: 'max', icon: '' }])
            .selected(this.reasoningEffort === 'max' ? 1 : 0)
            .value(this.reasoningEffort === 'max' ? 'Max' : 'High')
            .onSelect((index: number, value: string) => {
              this.reasoningEffort = value;
            })
            .height(32)
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor('#fefefe')
      .border({ width: { bottom: 1 }, color: '#e8e8e8' })

      // Main content area
      Row() {
        // History sidebar
        if (this.showHistory) {
          Column() {
            Text('Chat History')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .padding(12)

            List() {
              ForEach(this.sessions, (session: ChatSession) => {
                ListItem() {
                  Row() {
                    Column() {
                      Text(session.title)
                        .fontSize(14)
                        .lineHeight(20)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })

                      Text(formatDate(session.updatedAt) + ' ' + formatTime(session.updatedAt))
                        .fontSize(11)
                        .fontColor('#999999')
                        .margin({ top: 2 })
                    }
                    .layoutWeight(1)
                    .onClick(() => {
                      this.switchSession(session.id);
                    })

                    Button() {
                      Text('✕')
                        .fontSize(12)
                    }
                    .onClick(() => {
                      this.deleteSession(session.id);
                    })
                    .backgroundColor(Color.Transparent)
                    .fontColor('#ff3b30')
                    .width(28)
                    .height(28)
                  }
                  .padding({ top: 8, bottom: 8, left: 12, right: 4 })
                }
                .backgroundColor(session.id === this.currentSessionId ? '#e8f0fe' : Color.White)
              })
            }
            .layoutWeight(1)
          }
          .width('40%')
          .backgroundColor('#fafafa')
          .border({ width: { right: 1 }, color: '#e0e0e0' })
        }

        // Chat area
        Column() {
          if (this.messages.length <= 1 && !this.isStreaming) {
            Column() {
              Text('DeepSeek Chat')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')

              Text('Powered by DeepSeek AI models')
                .fontSize(14)
                .fontColor('#999999')
                .margin({ top: 8 })

              Text('Ask anything, get intelligent answers with optional thinking mode.')
                .fontSize(14)
                .fontColor('#999999')
                .margin({ top: 4 })

              if (!this.apiKey) {
                Text('⚠ Please set your API Key in Settings to start chatting.')
                  .fontSize(14)
                  .fontColor('#ff9500')
                  .margin({ top: 24 })
                  .onClick(() => {
                    router.pushUrl({ url: 'pages/Settings' });
                  })
              }
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .padding(24)
          } else {
            List({ scroller: this.listScroller }) {
              ForEach(this.messages, (msg: ChatMessage) => {
                ListItem() {
                  if (msg.role === MessageRole.SYSTEM) {
                    Column() {
                    }
                  } else if (msg.role === MessageRole.USER) {
                    this.UserMessageItem(msg)
                  } else if (msg.role === MessageRole.TOOL) {
                    this.ToolResultItem(msg)
                  } else {
                    this.AssistantMessageItem(msg)
                  }
                }
              })
            }
            .layoutWeight(1)
            .width('100%')
          }

          // Input area
          Row() {
            TextArea({ placeholder: 'Type a message...', text: this.inputText })
              .onChange((value: string) => {
                this.inputText = value;
              })
              .layoutWeight(1)
              .constraintSize({ minHeight: 40 })
              .maxHeight(120)
              .backgroundColor('#f5f5f5')
              .borderRadius(20)
              .padding({ left: 16, right: 16 })
              .margin({ right: 8 })

            Button() {
              Text('Send')
                .fontSize(14)
                .fontColor(Color.White)
            }
            .onClick(() => {
              this.sendMessage();
            })
            .enabled(!this.isStreaming && this.inputText.trim().length > 0)
            .backgroundColor('#007aff')
            .borderRadius(20)
            .height(40)
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 12 })
          .backgroundColor('#ffffff')
          .border({ width: { top: 1 }, color: '#e8e8e8' })
        }
        .layoutWeight(1)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
  }

  @Builder
  UserMessageItem(msg: ChatMessage) {
    Column() {
      Row() {
        Text('You')
          .fontSize(12)
          .fontColor('#007aff')
          .fontWeight(FontWeight.Medium)

        Blank()

        Text(formatTime(msg.timestamp))
          .fontSize(11)
          .fontColor('#999999')
      }
      .width('100%')
      .padding({ bottom: 4 })

      Text(msg.content)
        .fontSize(15)
        .lineHeight(22)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#f0f7ff')
    .borderRadius(12)
    .margin({ left: 12, right: 12, top: 4, bottom: 4 })
  }

  @Builder
  AssistantMessageItem(msg: ChatMessage) {
    Column() {
      Row() {
        Text('AI')
          .fontSize(12)
          .fontColor('#34c759')
          .fontWeight(FontWeight.Medium)

        Blank()

        if (msg.thinkingContent && msg.thinkingContent.length > 0) {
          Text('Thinking')
            .fontSize(11)
            .fontColor('#ff9500')
            .margin({ right: 8 })
        }

        Text(formatTime(msg.timestamp))
          .fontSize(11)
          .fontColor('#999999')
      }
      .width('100%')
      .padding({ bottom: 4 })

      // Thinking content (collapsible)
      if (msg.thinkingContent && msg.thinkingContent.length > 0) {
        Column() {
          Row() {
            Text('🧠 Thinking')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#666666')

            Blank()

            Button() {
              Text(this.thinkingExpanded ? '▲' : '▼')
                .fontSize(12)
            }
            .onClick(() => {
              this.thinkingExpanded = !this.thinkingExpanded;
            })
            .backgroundColor(Color.Transparent)
            .fontColor('#999999')
            .width(24)
            .height(24)
          }

          if (this.thinkingExpanded) {
            Text(msg.thinkingContent)
              .fontSize(13)
              .fontColor('#666666')
              .lineHeight(20)
              .width('100%')
              .padding({ top: 8, bottom: 4 })
              .border({ width: { top: 1 }, color: '#e8e8e8' })
          }
        }
        .width('100%')
        .padding(8)
        .backgroundColor('#fff8e1')
        .borderRadius(8)
        .margin({ bottom: 8 })
      }

      // Tool calls display
      if (msg.toolCalls && msg.toolCalls.length > 0) {
        ForEach(msg.toolCalls, (tc: ToolCall) => {
          Row() {
            Text('🔧 ')
              .fontSize(12)
            Text('Calling tool: ' + tc.function.name + '...')
              .fontSize(13)
              .fontColor('#8e8e93')
              .fontStyle(FontStyle.Italic)
          }
          .padding({ top: 2, bottom: 2 })
        })
      }

      // Content text
      Text(msg.content)
        .fontSize(15)
        .lineHeight(22)
        .width('100%')

      // Streaming cursor
      if (this.isStreaming && this.messages.length > 0 && msg.id === this.messages[this.messages.length - 1].id) {
        Text('▊')
          .fontSize(15)
          .fontColor('#34c759')
          .margin({ left: 2 })
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .margin({ left: 12, right: 12, top: 4, bottom: 4 })
  }

  @Builder
  ToolResultItem(msg: ChatMessage) {
    Column() {
      Row() {
        Text('🔧 ')
          .fontSize(12)
        Text('Tool result (' + (msg.toolName || 'tool') + '):')
          .fontSize(12)
          .fontColor('#8e8e93')

        Blank()

        Text(formatTime(msg.timestamp))
          .fontSize(11)
          .fontColor('#999999')
      }
      .width('100%')
      .padding({ bottom: 4 })

      Text(msg.content)
        .fontSize(13)
        .fontColor('#555555')
        .lineHeight(20)
        .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#f5f5f5')
    .borderRadius(8)
    .margin({ left: 12, right: 12, top: 2, bottom: 2 })
  }
}
