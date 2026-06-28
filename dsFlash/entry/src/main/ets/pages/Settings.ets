import { router } from '@kit.AbilityKit';
import { STORAGE_KEY_API } from '../common/constants';

@Entry
@Component
struct Settings {
  @StorageLink(STORAGE_KEY_API) apiKey: string = '';
  @State inputKey: string = '';
  @State showKey: boolean = false;
  @State saved: boolean = false;

  aboutToAppear(): void {
    this.inputKey = this.apiKey;
  }

  build() {
    Column() {
      Row() {
        Button() {
          Text('< Back')
            .fontSize(16)
        }
        .onClick(() => {
          router.back();
        })
        .backgroundColor(Color.Transparent)
        .fontColor(Color.Blue)

        Blank()

        Text('Settings')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)

        Blank()

        Text('')
          .width(60)
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 12, bottom: 12 })
      .backgroundColor('#f5f5f5')

      Scroll() {
        Column() {
          Text('DeepSeek API Configuration')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 24, bottom: 8 })

          Text('Enter your DeepSeek API Key to enable chat functionality.')
            .fontSize(14)
            .fontColor('#666666')
            .margin({ bottom: 16 })
            .lineHeight(20)

          Text('API Key')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 8 })

          Row() {
            TextInput({ placeholder: 'sk-...', text: this.inputKey })
              .type(this.showKey ? InputType.Normal : InputType.Password)
              .onChange((value: string) => {
                this.inputKey = value;
                this.saved = false;
              })
              .layoutWeight(1)

            Button() {
              Text(this.showKey ? 'Hide' : 'Show')
                .fontSize(12)
            }
            .onClick(() => {
              this.showKey = !this.showKey;
            })
            .margin({ left: 8 })
            .backgroundColor('#e0e0e0')
            .fontColor('#333333')
          }
          .width('100%')

          Text('Your API key is stored locally on your device and never shared.')
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 4, bottom: 16 })

          Button() {
            Text('Save')
              .fontSize(16)
              .fontColor(Color.White)
          }
          .width('100%')
          .height(44)
          .backgroundColor('#007aff')
          .borderRadius(8)
          .onClick(() => {
            if (this.inputKey.trim().length === 0) {
              return;
            }
            this.apiKey = this.inputKey.trim();
            this.saved = true;
          })

          if (this.saved) {
            Text('API Key saved successfully!')
              .fontSize(14)
              .fontColor('#34c759')
              .margin({ top: 12 })
          }

          Divider()
            .margin({ top: 32, bottom: 24 })

          Text('Models')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 8 })

          Text('deepseek-v4-flash: Fast lightweight model for everyday tasks')
            .fontSize(14)
            .fontColor('#666666')
            .margin({ bottom: 4 })
          Text('deepseek-v4-pro: Powerful model for complex reasoning')
            .fontSize(14)
            .fontColor('#666666')
            .margin({ bottom: 4 })

          Divider()
            .margin({ top: 24, bottom: 24 })

          Text('Thinking')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 8 })

          Text('When enabled, the model shows its reasoning process before answering. Use "high" for standard reasoning and "max" for deeper, more thorough reasoning.')
            .fontSize(14)
            .fontColor('#666666')
            .lineHeight(20)

          Divider()
            .margin({ top: 24, bottom: 24 })

          Text('Tool Calling')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 8 })

          Text('This app supports tool calling. The AI can use the get_system_time tool to retrieve the current phone system time when needed.')
            .fontSize(14)
            .fontColor('#666666')
            .lineHeight(20)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
  }
}
