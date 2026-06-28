import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';
import dataPreferences from '@ohos.data.preferences';
import { deepSeekService, ChatMessage, DeepSeekConfig, StreamCallback } from '../services/DeepSeekService';

interface HistoryItem {
  id: number;
  messages: ChatMessage[];
  model: string;
  thinkingEnabled: boolean;
  thinkingEffort: string;
  timestamp: number;
}

@Entry
@Component
struct ChatPage {
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State isLoading: boolean = false;
  @State showSettings: boolean = false;
  @State showHistory: boolean = false;
  @State apiKey: string = '';
  @State model: 'deepseek-v4-flash' | 'deepseek-v4-pro' = 'deepseek-v4-pro';
  @State thinkingEnabled: boolean = true;
  @State thinkingEffort: 'high' | 'max' = 'high';
  @State thinkingContent: string = '';
  @State currentResponse: string = '';
  @State history: HistoryItem[] = [];
  @State thinkingBuffer: string = '';
  @State errorMsg: string = '';

  private prefs: dataPreferences.Preferences | null = null;
  private streamCancelled: boolean = false;

  aboutToAppear() {
    this.loadSettings();
    this.loadHistory();
  }

  aboutToDisappear() {
    this.saveHistory();
    deepSeekService.destroy();
  }

  loadSettings() {
    let context = getContext(this) as Context;
    dataPreferences.getPreferences(context, 'ds_chat_settings').then((prefs: dataPreferences.Preferences) => {
      this.prefs = prefs;
      prefs.get('api_key', '').then((raw: dataPreferences.ValueType) => {
        if (typeof raw === 'string') {
          this.apiKey = raw;
        }
      });
      prefs.get('model', 'deepseek-v4-pro').then((raw: dataPreferences.ValueType) => {
        if (typeof raw === 'string') {
          this.model = (raw === 'deepseek-v4-flash') ? 'deepseek-v4-flash' : 'deepseek-v4-pro';
        }
      });
      prefs.get('thinking_enabled', true).then((raw: dataPreferences.ValueType) => {
        if (typeof raw === 'boolean') {
          this.thinkingEnabled = raw;
        }
      });
      prefs.get('thinking_effort', 'high').then((raw: dataPreferences.ValueType) => {
        if (typeof raw === 'string') {
          this.thinkingEffort = (raw === 'max') ? 'max' : 'high';
        }
      });
    });
  }

  saveSettings() {
    if (this.prefs) {
      this.prefs.put('api_key', this.apiKey);
      this.prefs.put('model', this.model);
      this.prefs.put('thinking_enabled', this.thinkingEnabled);
      this.prefs.put('thinking_effort', this.thinkingEffort);
      this.prefs.flush();
    }
  }

  loadHistory() {
    let context = getContext(this) as Context;
    dataPreferences.getPreferences(context, 'ds_chat_history').then((prefs: dataPreferences.Preferences) => {
      prefs.get('history', '[]').then((raw: dataPreferences.ValueType) => {
        if (typeof raw === 'string') {
          try {
            this.history = JSON.parse(raw) as HistoryItem[];
          } catch {
            this.history = [];
          }
        } else {
          this.history = [];
        }
      });
    });
  }

  saveHistory() {
    if (this.prefs) {
      this.prefs.put('history', JSON.stringify(this.history));
      this.prefs.flush();
    }
  }

  addToHistory() {
    if (this.messages.length < 2) return;
    const item: HistoryItem = {
      id: Date.now(),
      messages: JSON.parse(JSON.stringify(this.messages)),
      model: this.model,
      thinkingEnabled: this.thinkingEnabled,
      thinkingEffort: this.thinkingEffort,
      timestamp: Date.now()
    };
    this.history.unshift(item);
    if (this.history.length > 50) {
      this.history = this.history.slice(0, 50);
    }
    this.saveHistory();
  }

  clearHistory() {
    this.history = [];
    this.saveHistory();
  }

  loadFromHistory(item: HistoryItem) {
    this.messages = JSON.parse(JSON.stringify(item.messages));
    if (this.prefs) {
      this.prefs.get('api_key', '').then((raw: dataPreferences.ValueType) => {
        if (typeof raw === 'string') {
          this.apiKey = raw;
        }
      });
    }
    this.model = item.model as 'deepseek-v4-flash' | 'deepseek-v4-pro';
    this.thinkingEnabled = item.thinkingEnabled;
    this.thinkingEffort = item.thinkingEffort as 'high' | 'max';
    this.showHistory = false;
  }

  async sendMessage() {
    if (!this.inputText.trim()) return;
    if (!this.apiKey) {
      promptAction.showToast({ message: 'Please set API Key first' });
      return;
    }

    const userMsg: ChatMessage = { role: 'user', content: this.inputText.trim() };
    this.messages = [...this.messages, userMsg];
    this.inputText = '';
    this.isLoading = true;
    this.errorMsg = '';
    this.currentResponse = '';
    this.thinkingContent = '';
    this.thinkingBuffer = '';
    this.streamCancelled = false;

    const config: DeepSeekConfig = {
      apiKey: this.apiKey,
      model: this.model,
      thinkingEnabled: this.thinkingEnabled,
      reasoningEffort: this.thinkingEffort
    };

    const callback: StreamCallback = {
      onToken: (token: string) => {
        if (!this.streamCancelled) {
          this.currentResponse += token;
        }
      },
      onThinking: (thinking: string) => {
        if (!this.streamCancelled) {
          this.thinkingBuffer += thinking;
          if (this.thinkingBuffer.length > 10) {
            this.thinkingContent = this.thinkingBuffer;
          }
        }
      },
      onDone: () => {
        if (!this.streamCancelled) {
          this.isLoading = false;
          if (this.currentResponse) {
            const assistantMsg: ChatMessage = { role: 'assistant', content: this.currentResponse };
            this.messages = [...this.messages, assistantMsg];
            this.addToHistory();
          }
          this.thinkingContent = this.thinkingBuffer;
        }
      },
      onError: (error: string) => {
        this.isLoading = false;
        this.errorMsg = error;
      }
    };

    await deepSeekService.chatStream(this.messages, config, callback);
  }

  cancelStream() {
    this.streamCancelled = true;
    this.isLoading = false;
    deepSeekService.destroy();
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.chat_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Button($r('app.string.history_title'))
          .fontSize(14)
          .fontColor($r('app.color.primary_blue'))
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.showHistory = true; this.loadHistory(); })
        Button($r('app.string.settings_title'))
          .fontSize(14)
          .fontColor($r('app.color.primary_blue'))
          .backgroundColor(Color.Transparent)
          .margin({ left: 8 })
          .onClick(() => { this.showSettings = true; })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .backgroundColor($r('app.color.chat_bg'))

      if (this.messages.length === 0) {
        Column() {
          Text('🤖').fontSize(48)
          Text($r('app.string.empty_history'))
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 16 })
          Text('Set your API key and start chatting')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.messages, (msg: ChatMessage, index: number) => {
            ListItem() {
              Column() {
                if (msg.role === 'user') {
                  Row() {
                    Text(msg.content)
                      .fontSize(15)
                      .fontColor(Color.White)
                      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                  }
                  .width('70%')
                  .alignSelf(ItemAlign.End)
                  .borderRadius(18)
                  .backgroundColor($r('app.color.user_bubble'))
                  .margin({ left: 'auto' })
                } else {
                  Column() {
                    if (this.thinkingContent && this.thinkingEnabled) {
                      Row() {
                        Text('🧠').fontSize(14)
                        Text($r('app.string.thinking_content'))
                          .fontSize(12)
                          .fontColor('#F57F17')
                          .margin({ left: 4 })
                        Blank()
                        Text('...')
                          .fontSize(12)
                          .fontColor('#F57F17')
                      }
                      .width('100%')
                      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                      .backgroundColor($r('app.color.thinking_bg'))
                      .borderRadius(12)
                      .margin({ bottom: 6 })
                    }
                    Text(msg.content)
                      .fontSize(15)
                      .fontColor($r('app.color.text_primary'))
                      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                      .lineHeight(22)
                  }
                  .width('80%')
                  .alignSelf(ItemAlign.Start)
                  .borderRadius(18)
                  .backgroundColor($r('app.color.ai_bubble'))
                }
              }
              .width('100%')
            }
          }, (msg: ChatMessage, index: number) => index.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .scrollBar(BarState.Off)
      }

      Row() {
        if (this.isLoading) {
          Button('Cancel')
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.primary_blue'))
            .borderRadius(16)
            .height(40)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.cancelStream())
          Blank()
        }
        TextInput({ text: this.inputText, placeholder: $r('app.string.api_key_placeholder') })
          .height(40)
          .fontSize(15)
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius(20)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => { this.inputText = value; })
          .layoutWeight(1)
          .margin({ left: this.isLoading ? 8 : 0, right: this.isLoading ? 8 : 8 })
        if (!this.isLoading) {
          Button($r('app.string.send_btn'))
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor(this.inputText.trim() ? $r('app.color.primary_blue') : '#CCCCCC')
            .borderRadius(20)
            .height(40)
            .width(70)
            .onClick(() => this.sendMessage())
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 12 })
      .backgroundColor($r('app.color.chat_bg'))

      if (this.showSettings) {
        Column() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#33000000')
            .onClick(() => { this.showSettings = false; this.saveSettings(); })
          Column() {
            Row() {
              Text($r('app.string.settings_title'))
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text('✕')
                .fontSize(20)
                .fontColor($r('app.color.text_secondary'))
                .onClick(() => { this.showSettings = false; this.saveSettings(); })
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 20, bottom: 16 })
            Text($r('app.string.api_key_label'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({ left: 20 })
            TextInput({ text: this.apiKey, placeholder: $r('app.string.api_key_placeholder') })
              .height(44)
              .fontSize(14)
              .backgroundColor($r('app.color.input_bg'))
              .borderRadius(12)
              .padding({ left: 16, right: 16 })
              .width('90%')
              .margin({ top: 8 })
              .type(InputType.Normal)
              .onChange((value: string) => { this.apiKey = value; })
            Text($r('app.string.model_label'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({ left: 20, top: 20 })
            Row() {
              Button($r('app.string.model_flash'))
                .fontSize(13)
                .fontColor(this.model === 'deepseek-v4-flash' ? Color.White : $r('app.color.text_primary'))
                .backgroundColor(this.model === 'deepseek-v4-flash' ? $r('app.color.primary_blue') : '#E8E8E8')
                .borderRadius(20)
                .height(36)
                .layoutWeight(1)
                .margin({ right: 8 })
                .onClick(() => { this.model = 'deepseek-v4-flash'; })
              Button($r('app.string.model_pro'))
                .fontSize(13)
                .fontColor(this.model === 'deepseek-v4-pro' ? Color.White : $r('app.color.text_primary'))
                .backgroundColor(this.model === 'deepseek-v4-pro' ? $r('app.color.primary_blue') : '#E8E8E8')
                .borderRadius(20)
                .height(36)
                .layoutWeight(1)
                .onClick(() => { this.model = 'deepseek-v4-pro'; })
            }
            .width('90%')
            .margin({ top: 8 })
            Text($r('app.string.thinking_label'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({ left: 20, top: 20 })
            Row() {
              Button($r('app.string.thinking_off'))
                .fontSize(13)
                .fontColor(!this.thinkingEnabled ? Color.White : $r('app.color.text_primary'))
                .backgroundColor(!this.thinkingEnabled ? $r('app.color.primary_blue') : '#E8E8E8')
                .borderRadius(20)
                .height(36)
                .layoutWeight(1)
                .margin({ right: 4 })
                .onClick(() => { this.thinkingEnabled = false; })
              Button($r('app.string.thinking_high'))
                .fontSize(13)
                .fontColor(this.thinkingEnabled && this.thinkingEffort === 'high' ? Color.White : $r('app.color.text_primary'))
                .backgroundColor(this.thinkingEnabled && this.thinkingEffort === 'high' ? $r('app.color.primary_blue') : '#E8E8E8')
                .borderRadius(20)
                .height(36)
                .layoutWeight(1)
                .margin({ right: 4 })
                .onClick(() => { this.thinkingEnabled = true; this.thinkingEffort = 'high'; })
              Button($r('app.string.thinking_max'))
                .fontSize(13)
                .fontColor(this.thinkingEnabled && this.thinkingEffort === 'max' ? Color.White : $r('app.color.text_primary'))
                .backgroundColor(this.thinkingEnabled && this.thinkingEffort === 'max' ? $r('app.color.primary_blue') : '#E8E8E8')
                .borderRadius(20)
                .height(36)
                .layoutWeight(1)
                .onClick(() => { this.thinkingEnabled = true; this.thinkingEffort = 'max'; })
            }
            .width('90%')
            .margin({ top: 8 })
            Blank()
          }
          .width('90%')
          .backgroundColor(Color.White)
          .borderRadius(20)
          .padding({ bottom: 24 })
          .alignSelf(ItemAlign.Center)
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 60 })
      }

      if (this.showHistory) {
        Column() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#33000000')
            .onClick(() => { this.showHistory = false; })
          Column() {
            Row() {
              Text($r('app.string.history_title'))
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text('✕')
                .fontSize(20)
                .fontColor($r('app.color.text_secondary'))
                .onClick(() => { this.showHistory = false; })
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 20, bottom: 16 })
            if (this.history.length === 0) {
              Text($r('app.string.empty_history'))
                .fontSize(16)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 40 })
            } else {
              List({ space: 8 }) {
                ForEach(this.history, (item: HistoryItem) => {
                  ListItem() {
                    Row() {
                      Column() {
                        Text(`${item.model} ${item.thinkingEnabled ? '🧠' : ''}`)
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                        Text(new Date(item.timestamp).toLocaleString())
                          .fontSize(11)
                          .fontColor($r('app.color.text_secondary'))
                      }
                      .alignItems(HorizontalAlign.Start)
                      Blank()
                      Text('Load →')
                        .fontSize(13)
                        .fontColor($r('app.color.primary_blue'))
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                    .backgroundColor('#F9F9F9')
                    .borderRadius(12)
                    .onClick(() => this.loadFromHistory(item))
                  }
                }, (item: HistoryItem) => item.id.toString())
              }
              .width('100%')
              .layoutWeight(1)
              .scrollBar(BarState.Off)
              .padding({ left: 20, right: 20 })
            }
            Button($r('app.string.clear_history_btn'))
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor('#FF4444')
              .borderRadius(12)
              .height(44)
              .width('90%')
              .margin({ top: 16 })
              .onClick(() => { this.clearHistory(); })
            Blank()
          }
          .width('90%')
          .backgroundColor(Color.White)
          .borderRadius(20)
          .padding({ bottom: 24 })
          .alignSelf(ItemAlign.Center)
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 60 })
      }
    }
  }
}

export default ChatPage;
