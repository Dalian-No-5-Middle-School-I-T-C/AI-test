import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { StorageService, AppSettings } from '../service/StorageService';

@Entry
@Component
struct SettingsPage {
  @StorageLink('apiKey') apiKey: string = '';
  @StorageLink('model') model: string = 'deepseek-v4-pro';
  @StorageLink('thinkingEnabled') thinkingEnabled: boolean = true;
  @StorageLink('reasoningEffort') reasoningEffort: string = 'high';

  @State showApiKey: boolean = false;
  @State localApiKey: string = '';
  @State localModel: string = 'deepseek-v4-pro';
  @State localThinkingEnabled: boolean = true;
  @State localReasoningEffort: string = 'high';

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.localApiKey = this.apiKey;
    this.localModel = this.model;
    this.localThinkingEnabled = this.thinkingEnabled;
    this.localReasoningEffort = this.reasoningEffort;
  }

  build() {
    Column() {
      Row() {
        Button() {
          Text('< Back')
            .fontSize(14)
            .fontColor('#4A90D9')
        }
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.back();
        })

        Text('Settings')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank().width(70)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 2, color: '#1A000000', offsetY: 1 })

      Scroll() {
        Column() {
          Text('API Configuration')
            .fontSize(13)
            .fontColor('#999999')
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 8 })

          Column() {
            Text('API Key')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')

            Row() {
              TextInput({
                text: this.localApiKey,
                placeholder: 'sk-...'
              })
                .type(this.showApiKey ? InputType.Normal : InputType.Password)
                .layoutWeight(1)
                .height(40)
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .fontSize(14)
                .onChange((value: string) => {
                  this.localApiKey = value;
                })

              Button() {
                Text(this.showApiKey ? 'Hide' : 'Show')
                  .fontSize(12)
                  .fontColor('#4A90D9')
              }
              .type(ButtonType.Normal)
              .backgroundColor(Color.Transparent)
              .margin({ left: 8 })
              .onClick(() => {
                this.showApiKey = !this.showApiKey;
              })
            }
            .width('100%')
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)

          Text('Model')
            .fontSize(13)
            .fontColor('#999999')
            .fontWeight(FontWeight.Medium)
            .margin({ top: 24, bottom: 8 })

          Column() {
            this.ModelOption('deepseek-v4-pro', 'DeepSeek V4 Pro', 'Most capable model')
            Divider().margin({ left: 16, right: 16 }).color('#F0F0F0')
            this.ModelOption('deepseek-v4-flash', 'DeepSeek V4 Flash', 'Fast and efficient')
          }
          .width('100%')
          .backgroundColor('#FFFFFF')
          .borderRadius(12)

          Text('Thinking Mode')
            .fontSize(13)
            .fontColor('#999999')
            .fontWeight(FontWeight.Medium)
            .margin({ top: 24, bottom: 8 })

          Column() {
            Row() {
              Column() {
                Text('Enable Thinking')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#333333')
                Text('Show reasoning process')
                  .fontSize(12)
                  .fontColor('#999999')
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.localThinkingEnabled })
                .selectedColor('#4A90D9')
                .onChange((isOn: boolean) => {
                  this.localThinkingEnabled = isOn;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            if (this.localThinkingEnabled) {
              Divider().margin({ left: 16, right: 16 }).color('#F0F0F0')

              Column() {
                Text('Reasoning Effort')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#333333')
                  .margin({ bottom: 10 })

                Row() {
                  this.EffortOption('high', 'High', 'Balanced reasoning')
                  Blank().width(12)
                  this.EffortOption('max', 'Max', 'Maximum depth')
                }
                .width('100%')
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            }
          }
          .width('100%')
          .backgroundColor('#FFFFFF')
          .borderRadius(12)

          Button('Save Settings')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .backgroundColor('#4A90D9')
            .borderRadius(12)
            .margin({ top: 32 })
            .onClick(() => {
              this.saveSettings();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor('#F5F5F5')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  ModelOption(value: string, title: string, subtitle: string) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
        Text(subtitle)
          .fontSize(12)
          .fontColor('#999999')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Radio({ value: value, group: 'model' })
        .checked(this.localModel === value)
        .onChange((isChecked: boolean) => {
          if (isChecked) {
            this.localModel = value;
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(() => {
      this.localModel = value;
    })
  }

  @Builder
  EffortOption(value: string, title: string, subtitle: string) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.localReasoningEffort === value ? '#4A90D9' : '#333333')
      Text(subtitle)
        .fontSize(11)
        .fontColor('#999999')
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor(this.localReasoningEffort === value ? '#EBF3FC' : '#F5F5F5')
    .borderRadius(8)
    .border({
      width: this.localReasoningEffort === value ? 1.5 : 0,
      color: this.localReasoningEffort === value ? '#4A90D9' : Color.Transparent
    })
    .onClick(() => {
      this.localReasoningEffort = value;
    })
  }

  async saveSettings(): Promise<void> {
    this.apiKey = this.localApiKey;
    this.model = this.localModel;
    this.thinkingEnabled = this.localThinkingEnabled;
    this.reasoningEffort = this.localReasoningEffort;

    let settings = new AppSettings();
    settings.apiKey = this.localApiKey;
    settings.model = this.localModel;
    settings.thinkingEnabled = this.localThinkingEnabled;
    settings.reasoningEffort = this.localReasoningEffort;
    await StorageService.saveSettings(this.context, settings);
    promptAction.showToast({ message: 'Settings saved' });
    router.back();
  }
}
