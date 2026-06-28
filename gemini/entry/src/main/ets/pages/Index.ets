import { common } from '@kit.AbilityKit';
import { AppSettings, ChatMessage, ChatSession } from '../models/ChatModels';
import { PreferencesManager } from '../utils/PreferencesManager';
import { DeepSeekClient } from '../utils/DeepSeekClient';
import { SettingsDialog } from '../components/SettingsDialog';

@Entry
@Component
struct Index {
  // Application settings and state
  @State settings: AppSettings = {
    apiKey: '',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-v4-pro',
    thinkingEnabled: true,
    reasoningEffort: 'high',
    toolsEnabled: true
  };

  // Sessions and UI active states
  @State sessions: ChatSession[] = [];
  @State currentSessionId: string = '';
  @State isShowSideBar: boolean = true;
  @State inputText: string = '';
  @State isGenerating: boolean = false;
  
  // Streaming state holders
  @State streamingReasoning: string = '';
  @State streamingContent: string = '';
  
  // Collapsible accordion mapping (session message ID -> collapsed state)
  @State collapsedThinking: Record<string, boolean> = {};

  // Controllers
  private scroller: Scroller = new Scroller();
  private settingsDialogController: CustomDialogController | null = null;
  private context: common.Context = getContext(this) as common.Context;

  aboutToAppear(): void {
    // Load Settings
    this.settings = PreferencesManager.getSettings(this.context);
    
    // Load Sessions
    this.sessions = PreferencesManager.getSessions(this.context);
    if (this.sessions.length > 0) {
      this.currentSessionId = this.sessions[0].id;
    } else {
      this.createNewSession();
    }

    // Initialize custom dialog controller
    this.settingsDialogController = new CustomDialogController({
      builder: SettingsDialog({
        settings: this.settings,
        onSave: (newSettings: AppSettings) => {
          this.settings = newSettings;
          PreferencesManager.saveSettings(this.context, newSettings);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
  }

  aboutToDisappear(): void {
    this.settingsDialogController = null;
  }

  // Get active session index
  private getActiveSessionIndex(): number {
    return this.sessions.findIndex(s => s.id === this.currentSessionId);
  }

  // Helper to get active session
  private getActiveSession(): ChatSession | null {
    const idx = this.getActiveSessionIndex();
    if (idx !== -1) {
      return this.sessions[idx];
    }
    return null;
  }

  // Helper to get active session messages
  private getActiveMessages(): ChatMessage[] {
    const session = this.getActiveSession();
    return session ? session.messages : [];
  }

  // Create new session
  private createNewSession(): void {
    const newSession: ChatSession = {
      id: `session_${Date.now()}`,
      title: `New Chat ${this.sessions.length + 1}`,
      messages: [],
      timestamp: Date.now()
    };
    this.sessions.unshift(newSession);
    this.currentSessionId = newSession.id;
    this.saveSessionsState();
  }

  // Delete session
  private deleteSession(sessionId: string): void {
    this.sessions = this.sessions.filter(s => s.id !== sessionId);
    if (this.sessions.length === 0) {
      this.createNewSession();
    } else if (this.currentSessionId === sessionId) {
      this.currentSessionId = this.sessions[0].id;
    }
    this.saveSessionsState();
  }

  // Save session state to persistent store
  private saveSessionsState(): void {
    PreferencesManager.saveSessions(this.context, this.sessions);
  }

  // Send message implementation
  private async sendMessage(): Promise<void> {
    if (this.isGenerating || !this.inputText.trim()) {
      return;
    }

    const textToSend = this.inputText;
    this.inputText = '';
    this.isGenerating = true;
    this.streamingReasoning = '';
    this.streamingContent = '';

    const userMessage: ChatMessage = {
      id: `msg_${Date.now()}`,
      role: 'user',
      content: textToSend,
      timestamp: Date.now()
    };

    const sessionIdx = this.getActiveSessionIndex();
    if (sessionIdx === -1) {
      this.isGenerating = false;
      return;
    }

    // Append user message
    this.sessions[sessionIdx].messages.push(userMessage);
    
    // Automatically update session title on first message
    if (this.sessions[sessionIdx].messages.filter(m => m.role === 'user').length === 1) {
      const shortTitle = textToSend.length > 15 ? `${textToSend.substring(0, 15)}...` : textToSend;
      this.sessions[sessionIdx].title = shortTitle;
    }
    
    this.saveSessionsState();
    this.scrollToBottom();

    // Trigger DeepSeek send
    const client = new DeepSeekClient(this.settings);
    
    // Strip tool content and reasoning_content correctly for subsequent standard calls
    // except when sending back tool responses which requires assistant's reasoning_content.
    // Our sendChatStream handles mapping logic internally.
    try {
      await client.sendChatStream(
        this.sessions[sessionIdx].messages,
        {
          onReasoningDelta: (delta: string) => {
            this.streamingReasoning += delta;
            this.scrollToBottom();
          },
          onContentDelta: (delta: string) => {
            this.streamingContent += delta;
            this.scrollToBottom();
          },
          onComplete: (fullMessage: ChatMessage) => {
            this.sessions[sessionIdx].messages.push(fullMessage);
            this.streamingReasoning = '';
            this.streamingContent = '';
            this.isGenerating = false;
            this.saveSessionsState();
            this.scrollToBottom();
          },
          onError: (errorMsg: string) => {
            const systemErrorMessage: ChatMessage = {
              id: `msg_err_${Date.now()}`,
              role: 'system',
              content: `Error: ${errorMsg}`,
              timestamp: Date.now()
            };
            this.sessions[sessionIdx].messages.push(systemErrorMessage);
            this.streamingReasoning = '';
            this.streamingContent = '';
            this.isGenerating = false;
            this.saveSessionsState();
            this.scrollToBottom();
          }
        }
      );
    } catch (e) {
      console.error('[Index] Send chat stream exception:', JSON.stringify(e));
      this.isGenerating = false;
    }
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  build() {
    Column() {
      // Top Navigation Bar
      Row() {
        Row({ space: 10 }) {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Image($r('app.media.startIcon'))
              .width(24)
              .height(24)
              .fillColor(Color.White)
          }
          .width(36)
          .height(36)
          .borderRadius(8)
          .backgroundColor('#007DFF')
          .onClick(() => {
            this.isShowSideBar = !this.isShowSideBar;
          })

          Text('DeepSeek AI Chat')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
        }

        Row({ space: 10 }) {
          // Model Badge
          Text(this.settings.model)
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor('#007DFF')
            .backgroundColor('#E1F0FF')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(12)

          // Settings Button
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Image($r('app.media.startIcon'))
              .width(20)
              .height(20)
              .fillColor('#333333')
          }
          .width(36)
          .height(36)
          .borderRadius(8)
          .backgroundColor('#F0F0F0')
          .onClick(() => {
            this.settingsDialogController?.open();
          })
        }
      }
      .width('100%')
      .height(56)
      .backgroundColor(Color.White)
      .padding({ left: 16, right: 16 })
      .justifyContent(FlexAlign.SpaceBetween)
      .border({ width: { bottom: 1 }, color: '#EAEAEA' })

      // Main Sidebar + Content
      SideBarContainer(SideBarContainerType.Embed) {
        
        // --- SIDEBAR: Chat History List ---
        Column() {
          Row() {
            Text('Conversations')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
            
            Button('+ New', { type: ButtonType.Capsule })
              .fontSize(12)
              .height(28)
              .backgroundColor('#007DFF')
              .fontColor(Color.White)
              .onClick(() => {
                this.createNewSession();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 16, bottom: 12 })
          .justifyContent(FlexAlign.SpaceBetween)

          List({ space: 6 }) {
            ForEach(this.sessions, (session: ChatSession) => {
              ListItem() {
                Row() {
                  Text(session.title)
                    .fontSize(14)
                    .fontColor(this.currentSessionId === session.id ? '#007DFF' : '#555555')
                    .fontWeight(this.currentSessionId === session.id ? FontWeight.Medium : FontWeight.Normal)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  
                  // Delete conversation icon/button
                  Button({ type: ButtonType.Normal }) {
                    Image($r('app.media.startIcon'))
                      .width(16)
                      .height(16)
                      .fillColor('#FF3B30')
                  }
                  .width(28)
                  .height(28)
                  .borderRadius(6)
                  .backgroundColor('transparent')
                  .onClick((e: ClickEvent) => {
                    this.deleteSession(session.id);
                  })
                }
                .width('100%')
                .height(48)
                .padding({ left: 12, right: 8 })
                .borderRadius(8)
                .backgroundColor(this.currentSessionId === session.id ? '#E6F2FF' : 'transparent')
                .onClick(() => {
                  this.currentSessionId = session.id;
                  this.streamingReasoning = '';
                  this.streamingContent = '';
                  this.scrollToBottom();
                })
              }
            }, (session: ChatSession) => session.id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 8, right: 8 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F7F7F7')
        .border({ width: { right: 1 }, color: '#EAEAEA' })

        // --- MAIN CONTENT: Chat Room ---
        Column() {
          // Message History Scroll List
          List({ scroller: this.scroller }) {
            ForEach(this.getActiveMessages(), (msg: ChatMessage) => {
              ListItem() {
                this.MessageBubble(msg)
              }
            }, (msg: ChatMessage) => msg.id)

            // Streaming assistant bubble placeholder
            if (this.isGenerating && (this.streamingReasoning || this.streamingContent)) {
              ListItem() {
                this.StreamingBubble()
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .edgeEffect(EdgeEffect.Spring)
          .padding({ left: 12, right: 12, top: 12, bottom: 12 })

          // Bottom Input Controls
          Column() {
            // Quick Status Info Line
            Row() {
              Text(
                `Model: ${this.settings.model} | Thinking: ${this.settings.thinkingEnabled ? `ON (${this.settings.reasoningEffort})` : 'OFF'}`
              )
                .fontSize(11)
                .fontColor('#999999')
              
              if (this.isGenerating) {
                Text('DeepSeek is typing...')
                  .fontSize(11)
                  .fontColor('#007DFF')
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 6 })
            .justifyContent(FlexAlign.SpaceBetween)

            // Input Bar
            Row({ space: 10 }) {
              TextInput({ text: this.inputText, placeholder: 'Ask DeepSeek anything...' })
                .layoutWeight(1)
                .height(40)
                .backgroundColor('#F2F2F2')
                .borderRadius(20)
                .onChange((val: string) => {
                  this.inputText = val;
                })
                .onSubmit(() => {
                  this.sendMessage();
                })

              Button({ type: ButtonType.Normal }) {
                Image($r('app.media.startIcon'))
                  .width(20)
                  .height(20)
                  .fillColor(Color.White)
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor(this.inputText.trim() ? '#007DFF' : '#B0D4FF')
              .enabled(!this.isGenerating)
              .onClick(() => {
                this.sendMessage();
              })
            }
            .width('100%')
            .padding({ left: 12, right: 12, bottom: 12 })
          }
          .width('100%')
          .backgroundColor(Color.White)
          .border({ width: { top: 1 }, color: '#EAEAEA' })
          .padding({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F9F9F9')

      }
      .showSideBar($$this.isShowSideBar)
      .sideBarPosition(SideBarPosition.Start)
      .sideBarWidth(260)
      .minSideBarWidth(200)
      .maxSideBarWidth(320)
      .autoHide(true)
      .showControlButton(false) // Hide default control button since we made a custom modern one in titlebar
      .divider({
        strokeWidth: '1vp',
        color: '#EAEAEA',
        startMargin: '0vp',
        endMargin: '0vp'
      })
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  // Builder for completed messages
  @Builder
  MessageBubble(msg: ChatMessage) {
    Row() {
      if (msg.role === 'user') {
        // User Alignment: Right
        Row() {
          Column() {
            Row() {
              Text(msg.content)
                .fontSize(15)
                .fontColor(Color.White)
                .lineHeight(20)
            }
            .padding(12)
            .borderRadius(16)
            .backgroundColor('#007DFF')
            .constraintSize({ maxWidth: '75%' })
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ bottom: 12 })

      } else if (msg.role === 'assistant') {
        // Assistant Alignment: Left
        Row() {
          Column({ space: 6 }) {
            // Thinking accordion if reasoning exists
            if (msg.reasoning_content) {
              this.ThinkingAccordion(msg.id, msg.reasoning_content)
            }

            // Normal Content Bubble
            if (msg.content) {
              Row() {
                Text(msg.content)
                  .fontSize(15)
                  .fontColor('#1A1A1A')
                  .lineHeight(22)
              }
              .padding(12)
              .borderRadius(16)
              .backgroundColor(Color.White)
              .border({ width: 1, color: '#E8E8E8' })
              .constraintSize({ maxWidth: '80%' })
            }
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .margin({ bottom: 12 })

      } else if (msg.role === 'tool') {
        // Tool Execution Results Log: Centered grey pill
        Row() {
          Text(`⚙️ [Tool Output: get_current_time] => ${msg.content}`)
            .fontSize(11)
            .fontColor('#666666')
            .backgroundColor('#EFEFEF')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(8)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 12 })

      } else if (msg.role === 'system') {
        // Error or System Messages: Red/Grey warning logs
        Row() {
          Text(msg.content)
            .fontSize(12)
            .fontColor(msg.content.startsWith('Error') ? '#FF3B30' : '#8E8E93')
            .backgroundColor(msg.content.startsWith('Error') ? '#FFEBEA' : '#F2F2F7')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(8)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 12 })
      }
    }
  }

  // Builder for stream update message placeholder
  @Builder
  StreamingBubble() {
    Row() {
      Column({ space: 6 }) {
        // Active Thinking Box
        if (this.streamingReasoning) {
          this.ThinkingAccordion('streaming_reasoning', this.streamingReasoning)
        }

        // Active Content Box
        if (this.streamingContent) {
          Row() {
            Text(this.streamingContent)
              .fontSize(15)
              .fontColor('#1A1A1A')
              .lineHeight(22)
          }
          .padding(12)
          .borderRadius(16)
          .backgroundColor(Color.White)
          .border({ width: 1, color: '#E8E8E8' })
          .constraintSize({ maxWidth: '80%' })
        }
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .margin({ bottom: 12 })
  }

  // Collapsible accordion for Chain of Thought reasoning block
  @Builder
  ThinkingAccordion(id: string, text: string) {
    Column() {
      Row() {
        Row({ space: 6 }) {
          Image($r('app.media.startIcon'))
            .width(14)
            .height(14)
            .fillColor('#666666')
          Text(this.isGenerating && id === 'streaming_reasoning' ? 'Thinking process...' : 'Thought process')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#666666')
        }

        Text(this.isCollapsed(id) ? 'Expand' : 'Collapse')
          .fontSize(11)
          .fontColor('#007DFF')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .backgroundColor('#F5F5F5')
      .borderRadius(6)
      .onClick(() => {
        this.toggleCollapsed(id);
      })

      if (!this.isCollapsed(id)) {
        Column() {
          Text(text)
            .fontSize(13)
            .fontColor('#666666')
            .lineHeight(18)
            .width('100%')
        }
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .backgroundColor('#FDFDFD')
        .border({ width: { left: 3 }, color: '#D0D0D0' })
        .margin({ top: 4 })
      }
    }
    .width('80%')
    .borderRadius(8)
    .border({ width: 1, color: '#E0E0E0' })
    .backgroundColor('#F5F5F5')
  }

  // Helper to check collapsed status
  private isCollapsed(id: string): boolean {
    const val = this.collapsedThinking[id];
    if (val === undefined || val === null) {
      // Default: streaming thinking is expanded, finished thoughts are collapsed
      return id !== 'streaming_reasoning';
    }
    return val as boolean;
  }

  // Toggle collapsed status
  private toggleCollapsed(id: string): void {
    const currentStatus = this.isCollapsed(id);
    const updated: Record<string, boolean> = {};
    const keys = Object.keys(this.collapsedThinking);
    for (let i = 0; i < keys.length; i++) {
       const key = keys[i];
       updated[key] = this.collapsedThinking[key];
    }
    updated[id] = !currentStatus;
    this.collapsedThinking = updated;
  }
}
