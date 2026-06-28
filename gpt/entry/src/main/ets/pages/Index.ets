import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppSettings, ChatMessage, Conversation, executeTool, ModelId, ReasoningEffort, ToolCall } from '../model/ChatModels';
import { ChatStorage } from '../service/ChatStorage';
import { DeepSeekService } from '../service/DeepSeekService';

@Entry
@Component
struct Index {
  @State messages: ChatMessage[] = [];
  @State history: Conversation[] = [];
  @State inputText: string = '';
  @State apiKey: string = '';
  @State model: ModelId = 'deepseek-v4-pro';
  @State thinkingEnabled: boolean = true;
  @State reasoningEffort: ReasoningEffort = 'high';
  @State showSettings: boolean = false;
  @State showHistory: boolean = false;
  @State thinkingExpanded: boolean = true;
  @State streaming: boolean = false;
  @State streamingReasoning: string = '';
  @State streamingContent: string = '';
  @State toolStatus: string = '';
  @State currentTitle: string = '新对话';
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private client: DeepSeekService = new DeepSeekService();
  private conversationId: string = Date.now().toString();

  aboutToAppear(): void { this.loadData(); }

  private async loadData(): Promise<void> {
    try {
      const settings: AppSettings = await ChatStorage.loadSettings(this.context);
      this.apiKey = settings.apiKey;
      this.model = settings.model;
      this.thinkingEnabled = settings.thinkingEnabled;
      this.reasoningEffort = settings.reasoningEffort;
      this.history = await ChatStorage.loadConversations(this.context);
      if (this.history.length > 0) this.openConversation(this.history[0]);
    } catch (_) {}
  }

  private settings(): AppSettings {
    return { apiKey: this.apiKey.trim(), model: this.model, thinkingEnabled: this.thinkingEnabled, reasoningEffort: this.reasoningEffort };
  }

  private async saveSettings(): Promise<void> {
    try {
      await ChatStorage.saveSettings(this.context, this.settings());
      this.showSettings = false;
      promptAction.showToast({ message: '设置已保存' });
    } catch (_) { promptAction.showToast({ message: '设置保存失败' }); }
  }

  private title(): string {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].role === 'user') {
        const text: string = this.messages[i].content;
        return text.length > 18 ? text.substring(0, 18) + '…' : text;
      }
    }
    return '新对话';
  }

  private async saveConversation(): Promise<void> {
    if (this.messages.length === 0) return;
    this.currentTitle = this.title();
    const current: Conversation = { id: this.conversationId, title: this.currentTitle, updatedAt: Date.now(), messages: this.messages };
    const result: Conversation[] = [current];
    for (let i = 0; i < this.history.length; i++) if (this.history[i].id !== current.id) result.push(this.history[i]);
    this.history = result;
    try { await ChatStorage.saveConversations(this.context, result); } catch (_) {}
  }

  private newConversation(): void {
    if (this.streaming) return;
    this.saveConversation();
    this.messages = [];
    this.conversationId = Date.now().toString();
    this.currentTitle = '新对话';
    this.inputText = '';
    this.showHistory = false;
  }

  private openConversation(item: Conversation): void {
    if (this.streaming) return;
    this.conversationId = item.id;
    this.currentTitle = item.title;
    this.messages = item.messages;
    this.showHistory = false;
  }

  private async send(): Promise<void> {
    const content: string = this.inputText.trim();
    if (content.length === 0 || this.streaming) return;
    if (this.apiKey.trim().length === 0) {
      this.showSettings = true;
      promptAction.showToast({ message: '请先填写 DeepSeek API Key' });
      return;
    }
    this.messages = this.messages.concat([{ role: 'user', content: content, createdAt: Date.now() }]);
    this.inputText = '';
    this.streaming = true;
    this.streamingReasoning = '';
    this.streamingContent = '';
    this.toolStatus = '';
    this.thinkingExpanded = true;
    await this.runRound();
  }

  private async runRound(): Promise<void> {
    await this.client.stream(this.settings(), this.messages, {
      onReasoning: (text: string): void => { this.streamingReasoning += text; },
      onContent: (text: string): void => { this.streamingContent += text; },
      onTool: (name: string): void => { this.toolStatus = name === 'get_current_system_time' ? '正在获取手机系统时间' : '正在调用工具'; },
      onDone: async (calls: ToolCall[]): Promise<void> => {
        const valid: ToolCall[] = calls.filter((call: ToolCall) => call.function.name.length > 0);
        this.messages = this.messages.concat([{
          role: 'assistant', content: this.streamingContent, reasoning: this.streamingReasoning, toolCalls: valid, createdAt: Date.now()
        }]);
        this.streamingReasoning = '';
        this.streamingContent = '';
        if (valid.length > 0) {
          const result: ChatMessage[] = [];
          for (let i = 0; i < valid.length; i++) {
            result.push({ role: 'tool', content: executeTool(valid[i].function.name), toolCallId: valid[i].id, name: valid[i].function.name, createdAt: Date.now() });
          }
          this.messages = this.messages.concat(result);
          this.toolStatus = '已获取当前手机系统时间';
          await this.runRound();
          return;
        }
        this.toolStatus = '';
        this.streaming = false;
        await this.saveConversation();
      },
      onError: (message: string): void => {
        this.streaming = false;
        this.streamingReasoning = '';
        this.streamingContent = '';
        this.toolStatus = '';
        promptAction.showToast({ message: message.length > 50 ? '请求失败，请检查网络或 API Key' : message });
      }
    });
  }

  private stop(): void {
    this.client.stop();
    if (this.streamingContent.length > 0 || this.streamingReasoning.length > 0) {
      this.messages = this.messages.concat([{ role: 'assistant', content: this.streamingContent, reasoning: this.streamingReasoning, createdAt: Date.now() }]);
      this.saveConversation();
    }
    this.streaming = false;
    this.streamingContent = '';
    this.streamingReasoning = '';
    this.toolStatus = '';
  }

  @Builder Header() {
    Row() {
      Column() {
        Text('DeepChat').fontSize(21).fontWeight(FontWeight.Bold).fontColor('#151521')
        Text(this.currentTitle).fontSize(12).fontColor('#858594').margin({ top: 2 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button('＋').width(38).height(38).fontSize(22).fontColor('#6253DF').backgroundColor('#F3F1FF').borderRadius(19).margin({ right: 8 }).onClick(() => this.newConversation())
      Button('对话').height(38).fontSize(13).fontColor('#3D3859').backgroundColor('#F5F5F8').borderRadius(19).margin({ right: 8 }).onClick(() => this.showHistory = true)
      Button('设置').height(38).fontSize(13).fontColor('#3D3859').backgroundColor('#F5F5F8').borderRadius(19).onClick(() => this.showSettings = true)
    }.width('100%').padding({ left: 20, right: 20, top: 14, bottom: 12 }).backgroundColor(Color.White)
  }

  @Builder UserMessage(message: ChatMessage) {
    Row() {
      Blank()
      Text(message.content).fontSize(16).fontColor('#28223D').lineHeight(23).backgroundColor('#EEEAFE').borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 5 }).padding({ left: 14, right: 14, top: 10, bottom: 10 }).constraintSize({ maxWidth: '78%' })
    }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 8 })
  }

  @Builder ReasoningBlock(reasoning: string, live: boolean) {
    if (this.thinkingEnabled && reasoning.length > 0) {
      Column() {
        Row() {
          Text(live ? '● 正在思考' : '● 思考过程').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#6B57E8')
          Blank()
          Text(this.thinkingExpanded ? '收起' : '展开').fontSize(12).fontColor('#776DB4').onClick(() => this.thinkingExpanded = !this.thinkingExpanded)
        }.width('100%')
        if (this.thinkingExpanded) Text(reasoning).fontSize(13).fontColor('#665F78').lineHeight(20).margin({ top: 8 })
      }.width('100%').backgroundColor('#F8F7FE').borderRadius(12).padding(12).margin({ bottom: 9 })
    }
  }

  @Builder ToolLine(name: string) {
    Row() {
      Text('✓').fontSize(14).fontColor('#20A875').margin({ right: 7 })
      Text(name === 'get_current_system_time' ? '已获取当前手机系统时间' : '已完成工具调用').fontSize(12).fontColor('#397565')
    }.padding({ left: 10, right: 10, top: 7, bottom: 7 }).backgroundColor('#F0FAF6').borderRadius(8).margin({ bottom: 8 })
  }

  @Builder AssistantMessage(message: ChatMessage) {
    Column() {
      Row() { Text('DeepChat').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#5F51D5'); Text('  AI 助手').fontSize(12).fontColor('#A09DAA') }.width('100%').margin({ bottom: 8 })
      this.ReasoningBlock(message.reasoning === undefined ? '' : message.reasoning, false)
      if (message.toolCalls !== undefined) ForEach(message.toolCalls, (call: ToolCall) => { this.ToolLine(call.function.name) }, (call: ToolCall, index: number) => call.id + index.toString())
      if (message.content.length > 0) Text(message.content).fontSize(16).fontColor('#252331').lineHeight(25).padding({ left: 14, right: 14, top: 11, bottom: 11 }).backgroundColor(Color.White).borderRadius({ topLeft: 5, topRight: 18, bottomLeft: 18, bottomRight: 18 }).border({ width: 1, color: '#EEEAF7' }).width('100%')
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 36, top: 9, bottom: 9 })
  }

  @Builder LiveMessage() {
    Column() {
      Row() { Text('DeepChat').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#5F51D5'); Text('  正在生成').fontSize(12).fontColor('#A09DAA') }.width('100%').margin({ bottom: 8 })
      this.ReasoningBlock(this.streamingReasoning, true)
      if (this.toolStatus.length > 0) Text('◌ ' + this.toolStatus).fontSize(12).fontColor('#397565').backgroundColor('#F0FAF6').borderRadius(8).padding({ left: 10, right: 10, top: 7, bottom: 7 }).margin({ bottom: 8 })
      if (this.streamingContent.length > 0) Text(this.streamingContent).fontSize(16).fontColor('#252331').lineHeight(25).padding({ left: 14, right: 14, top: 11, bottom: 11 }).backgroundColor(Color.White).borderRadius(16).border({ width: 1, color: '#EEEAF7' }).width('100%')
      else Text('正在连接 DeepSeek…').fontSize(14).fontColor('#7B7689').backgroundColor(Color.White).borderRadius(16).padding({ left: 14, right: 14, top: 10, bottom: 10 })
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 36, top: 9, bottom: 9 })
  }

  @Builder Suggestion(text: string) {
    Button(text).fontSize(13).fontColor('#4C4670').backgroundColor('#F7F6FC').borderRadius(12).height(54).layoutWeight(1).margin({ left: 4, right: 4, top: 4, bottom: 4 }).onClick(() => this.inputText = text)
  }

  @Builder EmptyState() {
    Column() {
      Text('你好，我是 DeepChat').fontSize(27).fontWeight(FontWeight.Bold).fontColor('#211E32')
      Text('由 DeepSeek 驱动的 AI 助手').fontSize(15).fontColor('#8A8599').margin({ top: 9, bottom: 28 })
      Row() { this.Suggestion('解释一个复杂概念'); this.Suggestion('帮我写一段文案') }.width('100%')
      Row() { this.Suggestion('规划周末安排'); this.Suggestion('现在几点了？') }.width('100%')
    }.width('100%').padding({ left: 20, right: 20, top: 90 })
  }

  @Builder Composer() {
    Row() {
      TextInput({ text: this.inputText, placeholder: '问点什么…' }).layoutWeight(1).height(48).fontSize(16).fontColor('#282437').placeholderColor('#AAA6B5').backgroundColor('#F7F6FA').borderRadius(24).padding({ left: 16, right: 14 }).onChange((value: string) => this.inputText = value).onSubmit(() => this.send())
      if (this.streaming) Button('停止').height(48).fontSize(14).fontColor(Color.White).backgroundColor('#E26161').borderRadius(24).margin({ left: 9 }).onClick(() => this.stop())
      else Button('发送').height(48).fontSize(14).fontColor(Color.White).backgroundColor(this.inputText.trim().length > 0 ? '#6253DF' : '#C8C4D3').borderRadius(24).margin({ left: 9 }).enabled(this.inputText.trim().length > 0).onClick(() => this.send())
    }.width('100%').padding({ left: 20, right: 20, top: 10, bottom: 18 }).backgroundColor(Color.White)
  }

  @Builder Choice(text: string, selected: boolean, action: () => void) {
    Button(text).height(42).layoutWeight(1).fontSize(14).fontColor(selected ? '#5B4BD3' : '#6E697C').backgroundColor(selected ? '#EEEAFE' : '#F7F6FA').border({ width: selected ? 1 : 0, color: '#B8AFFD' }).borderRadius(10).margin({ right: 6 }).onClick(action)
  }

  @Builder SettingsSheet() {
    if (this.showSettings) {
      Column() {
        Row() { Text('设置').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#211E32'); Blank(); Button('关闭').fontSize(13).fontColor('#6253DF').backgroundColor(Color.Transparent).onClick(() => this.showSettings = false) }.width('100%')
        Text('DeepSeek API Key').fontSize(13).fontColor('#5E596C').margin({ top: 24, bottom: 8 })
        TextInput({ text: this.apiKey, placeholder: 'sk-…' }).type(InputType.Password).width('100%').height(48).backgroundColor('#F7F6FA').borderRadius(10).padding({ left: 12, right: 12 }).onChange((value: string) => this.apiKey = value)
        Text('模型').fontSize(13).fontColor('#5E596C').margin({ top: 19, bottom: 8 })
        Row() { this.Choice('V4 Flash', this.model === 'deepseek-v4-flash', () => this.model = 'deepseek-v4-flash'); this.Choice('V4 Pro', this.model === 'deepseek-v4-pro', () => this.model = 'deepseek-v4-pro') }.width('100%')
        Row() { Text('开启思考').fontSize(16).fontColor('#282437').layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.thinkingEnabled }).selectedColor('#6253DF').onChange((value: boolean) => this.thinkingEnabled = value) }.width('100%').margin({ top: 22, bottom: 10 })
        if (this.thinkingEnabled) {
          Text('思考深度').fontSize(13).fontColor('#5E596C').margin({ bottom: 8 })
          Row() { this.Choice('高', this.reasoningEffort === 'high', () => this.reasoningEffort = 'high'); this.Choice('最大', this.reasoningEffort === 'max', () => this.reasoningEffort = 'max') }.width('100%')
        }
        Button('保存设置').width('100%').height(50).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White).backgroundColor('#6253DF').borderRadius(12).margin({ top: 26 }).onClick(() => this.saveSettings())
      }.width('100%').padding({ left: 22, right: 22, top: 22, bottom: 30 }).backgroundColor(Color.White).borderRadius({ topLeft: 22, topRight: 22 }).position({ x: 0, y: '30%' }).zIndex(10)
    }
  }

  @Builder HistorySheet() {
    if (this.showHistory) {
      Column() {
        Row() { Text('历史对话').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#211E32'); Blank(); Button('新建').fontSize(14).fontColor('#6253DF').backgroundColor(Color.Transparent).onClick(() => this.newConversation()); Button('关闭').fontSize(13).fontColor('#6253DF').backgroundColor(Color.Transparent).onClick(() => this.showHistory = false) }.width('100%')
        if (this.history.length === 0) Text('还没有已保存的对话').fontSize(14).fontColor('#898493').margin({ top: 28 })
        else List() {
          ForEach(this.history, (item: Conversation) => {
            ListItem() {
              Column() { Text(item.title).fontSize(16).fontColor('#2B2738').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }); Text(new Date(item.updatedAt).toLocaleString()).fontSize(11).fontColor('#9994A2').margin({ top: 4 }) }
                .alignItems(HorizontalAlign.Start).width('100%').padding({ top: 14, bottom: 14 }).border({ width: { bottom: 1 }, color: '#F0EEF5' }).onClick(() => this.openConversation(item))
            }
          }, (item: Conversation) => item.id)
        }.width('100%').layoutWeight(1).margin({ top: 12 })
      }.width('100%').height('72%').padding({ left: 22, right: 22, top: 22, bottom: 20 }).backgroundColor(Color.White).borderRadius({ topLeft: 22, topRight: 22 }).position({ x: 0, y: '28%' }).zIndex(10)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.Header()
        if (this.messages.length === 0) { this.EmptyState(); Blank() }
        else List() {
          ForEach(this.messages, (message: ChatMessage) => {
            ListItem() { if (message.role === 'user') this.UserMessage(message); else if (message.role === 'assistant') this.AssistantMessage(message) }
          }, (message: ChatMessage, index: number) => message.createdAt.toString() + index.toString())
          if (this.streaming) ListItem() { this.LiveMessage() }
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
        this.Composer()
      }.width('100%').height('100%').backgroundColor('#FCFBFE')
      if (this.showSettings || this.showHistory) Column().width('100%').height('100%').backgroundColor('#55000000').zIndex(8).onClick(() => { this.showSettings = false; this.showHistory = false })
      this.HistorySheet()
      this.SettingsSheet()
    }.width('100%').height('100%')
  }
}
