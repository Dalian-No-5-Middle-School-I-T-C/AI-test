import { ChatController } from '../common/ChatController';

@Entry
@Component
struct Settings {
  controller: ChatController = ChatController.get();

  @State apiKeyInput: string = '';
  @State baseUrlInput: string = '';
  @State modelIndex: number = 0;
  @State thinkingEnabled: boolean = true;
  @State effortIndex: number = 0;
  @State systemPrompt: string = '';
  @State toolsEnabled: boolean = true;
  @State savedTip: string = '';

  private models: string[] = ['deepseek-v4-flash', 'deepseek-v4-pro'];

  aboutToAppear(): void {
    this.apiKeyInput = this.controller.settings.apiKey;
    this.baseUrlInput = this.controller.settings.baseUrl;
    this.modelIndex = this.models.indexOf(this.controller.settings.model);
    if (this.modelIndex < 0) {
      this.modelIndex = 1;
    }
    this.thinkingEnabled = this.controller.settings.thinkingEnabled;
    this.effortIndex = this.controller.settings.reasoningEffort === 'max' ? 1 : 0;
    this.systemPrompt = this.controller.settings.systemPrompt;
  }

  build() {
    Column() {
      Row() {
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text('保存')
          .fontColor('#0A59F7')
          .fontSize(16)
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column() {
          this.sectionTitle('API Key')
          TextInput({ text: this.apiKeyInput, placeholder: '请输入 DeepSeek API Key' })
            .type(InputType.Password)
            .width('100%')
            .height(44)
            .backgroundColor('#F2F3F5')
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((v) => {
              this.apiKeyInput = v;
            })

          this.sectionTitle('Base URL')
          TextInput({ text: this.baseUrlInput, placeholder: 'https://api.deepseek.com' })
            .width('100%')
            .height(44)
            .backgroundColor('#F2F3F5')
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((v) => {
              this.baseUrlInput = v;
            })

          this.sectionTitle('模型')
          Row() {
            ForEach(this.models, (item: string, idx: number) => {
              Text(item)
                .layoutWeight(1)
                .height(40)
                .textAlign(TextAlign.Center)
                .borderRadius(8)
                .backgroundColor(this.modelIndex === idx ? '#0A59F7' : '#F2F3F5')
                .fontColor(this.modelIndex === idx ? Color.White : Color.Black)
                .margin({ right: idx === this.models.length - 1 ? 0 : 8 })
                .onClick(() => {
                  this.modelIndex = idx;
                })
            }, (item: string, idx: number) => `${idx}_${item}`)
          }
          .width('100%')

          this.sectionTitle('思考模式')
          Row() {
            Text(this.thinkingEnabled ? '已启用' : '已关闭')
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.thinkingEnabled })
              .onChange((v) => {
                this.thinkingEnabled = v;
              })
          }
          .width('100%')
          .height(44)
          .alignItems(VerticalAlign.Center)

          if (this.thinkingEnabled) {
            this.sectionTitle('思考深度')
            Row() {
              ForEach(['high', 'max'], (item: string, idx: number) => {
                Text(item)
                  .layoutWeight(1)
                  .height(40)
                  .textAlign(TextAlign.Center)
                  .borderRadius(8)
                  .backgroundColor(this.effortIndex === idx ? '#0A59F7' : '#F2F3F5')
                  .fontColor(this.effortIndex === idx ? Color.White : Color.Black)
                  .margin({ right: idx === 1 ? 0 : 8 })
                  .onClick(() => {
                    this.effortIndex = idx;
                  })
              }, (item: string, idx: number) => `${idx}_${item}`)
            }
            .width('100%')
          }

          this.sectionTitle('工具调用')
          Row() {
            Text(this.toolsEnabled ? '已启用 (get_current_time)' : '已关闭')
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.toolsEnabled })
              .onChange((v) => {
                this.toolsEnabled = v;
              })
          }
          .width('100%')
          .height(44)
          .alignItems(VerticalAlign.Center)

          this.sectionTitle('系统提示词')
          TextArea({ text: this.systemPrompt, placeholder: 'You are a helpful assistant.' })
            .width('100%')
            .height(100)
            .backgroundColor('#F2F3F5')
            .borderRadius(8)
            .padding(12)
            .onChange((v) => {
              this.systemPrompt = v;
            })

          if (this.savedTip.length > 0) {
            Text(this.savedTip)
              .fontSize(14)
              .fontColor('#0A59F7')
              .margin({ top: 12 })
          }
        }
        .padding(16)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontColor('#666666')
      .margin({ top: 16, bottom: 8 })
      .width('100%')
  }

  private save(): void {
    const c = this.controller;
    c.settings.apiKey = this.apiKeyInput.trim();
    c.settings.baseUrl = (this.baseUrlInput.trim().length === 0
      ? 'https://api.deepseek.com'
      : this.baseUrlInput.trim());
    c.settings.model = this.models[this.modelIndex];
    c.settings.thinkingEnabled = this.thinkingEnabled;
    c.settings.reasoningEffort = this.effortIndex === 1 ? 'max' : 'high';
    c.settings.systemPrompt = this.systemPrompt;
    c.settings.toolsEnabled = this.toolsEnabled;
    c.saveSettings();
    this.savedTip = '已保存 ✓';
    setTimeout(() => {
      this.savedTip = '';
    }, 1500);
  }
}