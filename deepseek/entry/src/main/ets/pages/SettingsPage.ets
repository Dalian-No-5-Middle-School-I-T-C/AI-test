import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { StorageService } from '../services/StorageService';

@Entry
@Component
struct SettingsPage {
  @State apiKey: string = '';
  @State modelIndex: number = 0;
  @State thinkingEnabled: boolean = true;
  @State reasoningEffortIndex: number = 0;
  private models: string[] = ['deepseek-v4-pro', 'deepseek-v4-flash'];
  private modelLabels: string[] = ['Pro (更强)', 'Flash (更快)'];
  private effortValues: string[] = ['high', 'max'];
  private effortLabels: string[] = ['High (高)', 'Max (最大)'];

  aboutToAppear(): void {
    this.apiKey = StorageService.getApiKey();
    let savedModel = StorageService.getModel();
    this.modelIndex = savedModel === 'deepseek-v4-flash' ? 1 : 0;
    this.thinkingEnabled = StorageService.getThinkingEnabled();
    let savedEffort = StorageService.getReasoningEffort();
    this.reasoningEffortIndex = savedEffort === 'max' ? 1 : 0;
  }

  build() {
    Column() {
      // Title bar
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
          this.saveAndGoBack();
        })

        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button() {
          Text('保存')
            .fontSize(15)
            .fontColor('#4A90D9')
        }
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.saveAndGoBack();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      .backgroundColor('#FFFFFF')

      Divider().strokeWidth(1).color('#EEEEEE')

      Scroll() {
        Column() {
          // API Key section
          Text('API Key')
            .fontSize(13)
            .fontColor('#999999')
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 8 })

          TextInput({ text: this.apiKey, placeholder: '输入你的 DeepSeek API Key' })
            .type(InputType.Password)
            .fontSize(14)
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 16 })
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .onChange((value: string) => {
              this.apiKey = value;
            })

          Text('在 https://platform.deepseek.com 获取 API Key')
            .fontSize(12)
            .fontColor('#BBBBBB')
            .width('100%')
            .padding({ left: 16, right: 16, top: 6, bottom: 0 })

          Divider().strokeWidth(1).color('#EEEEEE').margin({ top: 16 })

          // Model section
          Text('模型选择')
            .fontSize(13)
            .fontColor('#999999')
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 8 })

          Row() {
            ForEach(this.modelLabels, (label: string, index: number) => {
              Column() {
                Text(label)
                  .fontSize(14)
                  .fontColor(this.modelIndex === index ? '#FFFFFF' : '#333333')
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              }
              .backgroundColor(this.modelIndex === index ? '#4A90D9' : '#F0F0F0')
              .borderRadius(8)
              .margin({ right: 8 })
              .onClick(() => {
                this.modelIndex = index;
              })
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Divider().strokeWidth(1).color('#EEEEEE').margin({ top: 16 })

          // Thinking section
          Text('思考模式')
            .fontSize(13)
            .fontColor('#999999')
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 10 })

          Row() {
            Text('启用思考')
              .fontSize(15)
              .fontColor('#333333')
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.thinkingEnabled })
              .onChange((isOn: boolean) => {
                this.thinkingEnabled = isOn;
              })
          }
          .width('100%')
          .height(50)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center)
          .margin({ left: 16, right: 16 })

          if (this.thinkingEnabled) {
            Text('思考深度')
              .fontSize(13)
              .fontColor('#999999')
              .fontWeight(FontWeight.Medium)
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 8 })

            Row() {
              ForEach(this.effortLabels, (label: string, index: number) => {
                Column() {
                  Text(label)
                    .fontSize(14)
                    .fontColor(this.reasoningEffortIndex === index ? '#FFFFFF' : '#333333')
                    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                }
                .backgroundColor(this.reasoningEffortIndex === index ? '#4A90D9' : '#F0F0F0')
                .borderRadius(8)
                .margin({ right: 8 })
                .onClick(() => {
                  this.reasoningEffortIndex = index;
                })
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
          }

          Divider().strokeWidth(1).color('#EEEEEE').margin({ top: 16 })

          // Info section
          Text('关于')
            .fontSize(13)
            .fontColor('#999999')
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 8 })

          Text('DeepSeek Chat v1.0.0\n基于 DeepSeek API 的聊天工具\n支持流式输出、思考模式和工具调用')
            .fontSize(13)
            .fontColor('#666666')
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .lineHeight(20)

          Blank().height(40)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
  }

  private saveAndGoBack(): void {
    StorageService.setApiKey(this.apiKey);
    StorageService.setModel(this.models[this.modelIndex]);
    StorageService.setThinkingEnabled(this.thinkingEnabled);
    StorageService.setReasoningEffort(this.effortValues[this.reasoningEffortIndex]);

    promptAction.showToast({ message: '设置已保存', duration: 1500 });
    router.back();
  }
}
