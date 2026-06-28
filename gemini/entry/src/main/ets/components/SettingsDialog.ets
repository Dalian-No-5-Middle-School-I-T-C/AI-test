import { AppSettings } from '../models/ChatModels';

@CustomDialog
export struct SettingsDialog {
  controller?: CustomDialogController;
  @State settings: AppSettings = {
    apiKey: '',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-v4-pro',
    thinkingEnabled: true,
    reasoningEffort: 'high',
    toolsEnabled: true
  };
  onSave?: (settings: AppSettings) => void;

  build() {
    Column({ space: 15 }) {
      Text('DeepSeek Settings')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .margin({ bottom: 5 })

      // API Key
      Column({ space: 5 }) {
        Text('API Key')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#666666')
          .width('100%')
        TextInput({ text: this.settings.apiKey, placeholder: 'Enter DeepSeek API Key' })
          .type(InputType.Password)
          .width('100%')
          .onChange((val: string) => {
            this.settings.apiKey = val;
          })
      }

      // Base URL
      Column({ space: 5 }) {
        Text('Base URL')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#666666')
          .width('100%')
        TextInput({ text: this.settings.baseUrl, placeholder: 'https://api.deepseek.com' })
          .width('100%')
          .onChange((val: string) => {
            this.settings.baseUrl = val;
          })
      }

      // Model Type
      Column({ space: 5 }) {
        Text('Model')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#666666')
          .width('100%')
        Row({ space: 10 }) {
          Button('deepseek-v4-pro', { type: ButtonType.Normal, stateEffect: true })
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .borderRadius(8)
            .backgroundColor(this.settings.model === 'deepseek-v4-pro' ? '#007DFF' : '#EAEAEA')
            .fontColor(this.settings.model === 'deepseek-v4-pro' ? Color.White : '#333333')
            .onClick(() => {
              this.settings.model = 'deepseek-v4-pro';
            })
          
          Button('deepseek-v4-flash', { type: ButtonType.Normal, stateEffect: true })
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .borderRadius(8)
            .backgroundColor(this.settings.model === 'deepseek-v4-flash' ? '#007DFF' : '#EAEAEA')
            .fontColor(this.settings.model === 'deepseek-v4-flash' ? Color.White : '#333333')
            .onClick(() => {
              this.settings.model = 'deepseek-v4-flash';
            })
        }
      }

      // Thinking toggles
      Row() {
        Text('Enable Thinking')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
        Toggle({ type: ToggleType.Switch, isOn: this.settings.thinkingEnabled })
          .onChange((isOn: boolean) => {
            this.settings.thinkingEnabled = isOn;
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // Reasoning Effort (Visible if Thinking is enabled)
      if (this.settings.thinkingEnabled) {
        Column({ space: 5 }) {
          Text('Reasoning Effort')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#666666')
            .width('100%')
          Row({ space: 10 }) {
            Button('high', { type: ButtonType.Normal, stateEffect: true })
              .layoutWeight(1)
              .height(36)
              .fontSize(12)
              .borderRadius(8)
              .backgroundColor(this.settings.reasoningEffort === 'high' ? '#007DFF' : '#EAEAEA')
              .fontColor(this.settings.reasoningEffort === 'high' ? Color.White : '#333333')
              .onClick(() => {
                this.settings.reasoningEffort = 'high';
              })
            
            Button('max', { type: ButtonType.Normal, stateEffect: true })
              .layoutWeight(1)
              .height(36)
              .fontSize(12)
              .borderRadius(8)
              .backgroundColor(this.settings.reasoningEffort === 'max' ? '#007DFF' : '#EAEAEA')
              .fontColor(this.settings.reasoningEffort === 'max' ? Color.White : '#333333')
              .onClick(() => {
                this.settings.reasoningEffort = 'max';
              })
          }
        }
      }

      // Tools Switch
      Row() {
        Text('Enable Custom Tools')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
        Toggle({ type: ToggleType.Switch, isOn: this.settings.toolsEnabled })
          .onChange((isOn: boolean) => {
            this.settings.toolsEnabled = isOn;
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // Action buttons
      Row({ space: 15 }) {
        Button('Cancel', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(40)
          .borderRadius(10)
          .backgroundColor('#F0F0F0')
          .fontColor('#666666')
          .onClick(() => {
            this.controller?.close();
          })

        Button('Save', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(40)
          .borderRadius(10)
          .backgroundColor('#007DFF')
          .fontColor(Color.White)
          .onClick(() => {
            if (this.onSave) {
              this.onSave(this.settings);
            }
            this.controller?.close();
          })
      }
      .margin({ top: 10 })
    }
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .width('90%')
  }
}
