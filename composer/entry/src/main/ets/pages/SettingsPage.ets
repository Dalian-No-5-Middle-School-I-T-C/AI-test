import { AppSettings, MODEL_OPTIONS, REASONING_EFFORT_OPTIONS } from '../model/ChatModels';
import { storageService } from '../service/StorageService';

@Component
export struct SettingsPage {
  @Link settings: AppSettings;
  @State apiKeyVisible: boolean = false;

  async saveSettings(): Promise<void> {
    await storageService.saveSettings(this.settings);
    AlertDialog.show({
      title: '已保存',
      message: '设置已保存到本地',
      confirm: { value: '确定', action: () => {} },
    });
  }

  build() {
    Scroll() {
      Column() {
        Text('设置')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .width('100%')
          .margin({ bottom: 20 })

        Text('API Key')
          .fontSize(14)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 8 })

        Row() {
          TextInput({
            placeholder: '输入 DeepSeek API Key',
            text: this.settings.apiKey,
          })
            .layoutWeight(1)
            .type(this.apiKeyVisible ? InputType.Normal : InputType.Password)
            .height(44)
            .borderRadius(8)
            .backgroundColor('#F5F5F5')
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.settings.apiKey = value;
            })

          Button(this.apiKeyVisible ? '🙈' : '👁')
            .width(44)
            .height(44)
            .margin({ left: 8 })
            .backgroundColor('#F0F0F0')
            .fontColor('#333333')
            .onClick(() => {
              this.apiKeyVisible = !this.apiKeyVisible;
            })
        }
        .width('100%')
        .margin({ bottom: 24 })

        Text('模型')
          .fontSize(14)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 8 })

        Column() {
          ForEach(MODEL_OPTIONS, (model: string) => {
            Row() {
              Radio({ value: model, group: 'modelGroup' })
                .checked(this.settings.model === model)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.settings.model = model;
                  }
                })
              Text(model)
                .fontSize(15)
                .fontColor('#333333')
                .margin({ left: 8 })
            }
            .width('100%')
            .height(44)
            .onClick(() => {
              this.settings.model = model;
            })
          }, (model: string) => model)
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .margin({ bottom: 24 })

        Text('思考模式')
          .fontSize(14)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 8 })

        Row() {
          Text('启用思考')
            .fontSize(15)
            .fontColor('#333333')
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.settings.thinkingEnabled })
            .onChange((isOn: boolean) => {
              this.settings.thinkingEnabled = isOn;
            })
        }
        .width('100%')
        .height(48)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .margin({ bottom: 12 })

        if (this.settings.thinkingEnabled) {
          Text('思考深度')
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')
            .margin({ bottom: 8 })

          Row() {
            ForEach(REASONING_EFFORT_OPTIONS, (effort: string) => {
              Button(effort)
                .fontSize(14)
                .height(36)
                .layoutWeight(1)
                .margin({ right: effort === 'high' ? 8 : 0 })
                .backgroundColor(this.settings.reasoningEffort === effort ? '#007AFF' : '#F0F0F0')
                .fontColor(this.settings.reasoningEffort === effort ? '#FFFFFF' : '#333333')
                .onClick(() => {
                  this.settings.reasoningEffort = effort;
                })
            }, (effort: string) => effort)
          }
          .width('100%')
          .margin({ bottom: 24 })
        }

        Text('工具')
          .fontSize(14)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 8 })

        Column() {
          Row() {
            Text('🔧 get_current_time')
              .fontSize(14)
              .fontColor('#333333')
            Blank()
            Text('已启用')
              .fontSize(12)
              .fontColor('#34C759')
          }
          .width('100%')

          Text('获取当前手机系统时间，模型可在需要时自动调用')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .margin({ top: 4 })
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .margin({ bottom: 32 })

        Button('保存设置')
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#007AFF')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .onClick(() => {
            this.saveSettings();
          })

        Text('API Key 仅保存在本地设备，不会上传到任何服务器')
          .fontSize(12)
          .fontColor('#AAAAAA')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 16, bottom: 32 })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
  }
}
