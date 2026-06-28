import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppSettings, ThinkingType, ReasoningEffort, ModelId } from '../model/Types';
import { loadSettings, saveSettings } from '../model/ChatStore';

@Entry
@Component
struct Settings {
  @State apiKey: string = '';
  @State model: ModelId = 'deepseek-v4-pro';
  @State thinkingType: ThinkingType = 'enabled';
  @State reasoningEffort: ReasoningEffort = 'high';
  @State systemPrompt: string = 'You are a helpful assistant.';
  @State hideKey: boolean = true;

  aboutToAppear() {
    this.init();
  }

  async init() {
    const ctx: common.Context = getContext(this) as common.Context;
    const s: AppSettings = await loadSettings(ctx);
    this.apiKey = s.apiKey;
    this.model = s.model;
    this.thinkingType = s.thinkingType;
    this.reasoningEffort = s.reasoningEffort;
    this.systemPrompt = s.systemPrompt;
  }

  build() {
    Column() {
      Row() {
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#222222')
        Blank()
        Button('保存')
          .fontSize(14)
          .height(32)
          .onClick(() => this.onSave())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column() {
          this.SectionTitle('API Key')
          Row() {
            TextInput({ text: this.apiKey, placeholder: 'sk-...' })
              .type(this.hideKey ? InputType.Password : InputType.Normal)
              .fontSize(16)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.apiKey = v;
              })
            Button(this.hideKey ? '显示' : '隐藏')
              .fontSize(13)
              .height(36)
              .margin({ left: 8 })
              .onClick(() => {
                this.hideKey = !this.hideKey;
              })
          }
          .width('100%')
          .margin({ top: 8 })

          this.SectionTitle('模型')
          Row() {
            Radio({ value: 'deepseek-v4-pro', group: 'model' })
              .checked(this.model === 'deepseek-v4-pro')
              .onChange((isChecked: boolean) => {
                if (isChecked) {
                  this.model = 'deepseek-v4-pro';
                }
              })
            Text('deepseek-v4-pro')
              .fontSize(15)
              .margin({ left: 4, right: 16 })
            Radio({ value: 'deepseek-v4-flash', group: 'model' })
              .checked(this.model === 'deepseek-v4-flash')
              .onChange((isChecked: boolean) => {
                if (isChecked) {
                  this.model = 'deepseek-v4-flash';
                }
              })
            Text('deepseek-v4-flash')
              .fontSize(15)
              .margin({ left: 4 })
          }
          .width('100%')
          .margin({ top: 8 })

          Row() {
            Column() {
              Text('开启思考')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
              Text('启用后模型会先进行推理再回答')
                .fontSize(12)
                .fontColor('#999999')
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.thinkingType === 'enabled' })
              .onChange((isOn: boolean) => {
                this.thinkingType = isOn ? 'enabled' : 'disabled';
              })
          }
          .width('100%')
          .margin({ top: 20 })
          .padding(12)
          .backgroundColor('#F5F5F7')
          .borderRadius(10)

          if (this.thinkingType === 'enabled') {
            this.SectionTitle('思考深度')
            Row() {
              Radio({ value: 'high', group: 'effort' })
                .checked(this.reasoningEffort === 'high')
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.reasoningEffort = 'high';
                  }
                })
              Text('high（较快）')
                .fontSize(15)
                .margin({ left: 4, right: 16 })
              Radio({ value: 'max', group: 'effort' })
                .checked(this.reasoningEffort === 'max')
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.reasoningEffort = 'max';
                  }
                })
              Text('max（更深）')
                .fontSize(15)
                .margin({ left: 4 })
            }
            .width('100%')
            .margin({ top: 8 })
          }

          this.SectionTitle('系统提示词')
          TextArea({ text: this.systemPrompt, placeholder: '设定助手的行为...' })
            .fontSize(15)
            .constraintSize({ maxHeight: 160, minHeight: 60 })
            .width('100%')
            .margin({ top: 8 })
            .onChange((v: string) => {
              this.systemPrompt = v;
            })

          Text('API Key 仅保存在本机，不会上传到任何服务器。')
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 20 })
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor('#333333')
      .margin({ top: 20 })
  }

  async onSave() {
    const ctx: common.Context = getContext(this) as common.Context;
    const s: AppSettings = {
      apiKey: this.apiKey,
      model: this.model,
      thinkingType: this.thinkingType,
      reasoningEffort: this.reasoningEffort,
      systemPrompt: this.systemPrompt
    };
    await saveSettings(ctx, s);
    promptAction.showToast({ message: '设置已保存' });
    router.back();
  }
}
