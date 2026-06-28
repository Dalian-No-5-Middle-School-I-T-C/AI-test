import { AppSettings, DEFAULT_SETTINGS, MODELS, REASONING_EFFORTS } from '../model/ChatModels';
import { saveSettings } from '../util/PreferencesUtil';
import { router } from '@kit.ArkUI';

interface SettingsPageParams {
  settings: AppSettings;
  onSaved: (s: AppSettings) => void;
}

@Entry
@Component
struct SettingsPage {
  @State apiKey: string = '';
  @State baseUrl: string = 'https://api.deepseek.com';
  @State model: string = 'deepseek-v4-flash';
  @State thinkingEnabled: boolean = true;
  @State reasoningEffort: string = 'high';
  @State apiKeyVisible: boolean = false;
  private onSettingsSaved?: (s: AppSettings) => void;

  aboutToAppear(): void {
    const p = AppStorage.get<SettingsPageParams>('settingsParams');
    if (p) {
      this.apiKey = p.settings.apiKey;
      this.baseUrl = p.settings.baseUrl;
      this.model = p.settings.model;
      this.thinkingEnabled = p.settings.thinkingEnabled;
      this.reasoningEffort = p.settings.reasoningEffort;
      this.onSettingsSaved = p.onSaved;
    } else {
      this.apiKey = DEFAULT_SETTINGS.apiKey;
      this.baseUrl = DEFAULT_SETTINGS.baseUrl;
      this.model = DEFAULT_SETTINGS.model;
      this.thinkingEnabled = DEFAULT_SETTINGS.thinkingEnabled;
      this.reasoningEffort = DEFAULT_SETTINGS.reasoningEffort;
    }
  }

  private collectSettings(): AppSettings {
    const s: AppSettings = {
      apiKey: this.apiKey,
      baseUrl: this.baseUrl,
      model: this.model,
      thinkingEnabled: this.thinkingEnabled,
      reasoningEffort: this.reasoningEffort
    };
    return s;
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor('#4A90D9')
          .onClick(() => {
            router.back();
          })
        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank()
          .width(56)
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#FFFFFF')

      Scroll() {
        Column({ space: 0 }) {
          this.sectionHeader('API 配置')

          this.inputField('API Key', this.apiKey, '请输入 DeepSeek API Key', (v: string) => {
            this.apiKey = v;
          }, true)

          this.inputField('Base URL', this.baseUrl, 'https://api.deepseek.com', (v: string) => {
            this.baseUrl = v;
          }, false)

          this.sectionHeader('模型选择')

          this.chipField('模型', this.model, MODELS, (v: string) => {
            this.model = v;
          })

          this.sectionHeader('思考模式')

          Row() {
            Column() {
              Text('启用思考')
                .fontSize(15)
                .fontColor('#333333')
              Text('让模型在回答前进行深度推理')
                .fontSize(12)
                .fontColor('#999999')
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.thinkingEnabled })
              .onChange((isOn: boolean) => {
                this.thinkingEnabled = isOn;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor('#FFFFFF')

          if (this.thinkingEnabled) {
            this.chipField('思考深度', this.reasoningEffort, REASONING_EFFORTS, (v: string) => {
              this.reasoningEffort = v;
            })
          }

          Button('保存设置')
            .width('100%')
            .height(48)
            .margin({ top: 32, left: 16, right: 16 })
            .backgroundColor('#4A90D9')
            .borderRadius(12)
            .fontSize(16)
            .fontColor(Color.White)
            .onClick(async () => {
              const s = this.collectSettings();
              await saveSettings(s);
              if (this.onSettingsSaved) {
                this.onSettingsSaved(s);
              }
              router.back();
            })
        }
        .width('100%')
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
  sectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor('#888888')
      .width('100%')
      .padding({ left: 16, top: 20, bottom: 6, right: 16 })
  }

  @Builder
  inputField(label: string, value: string, placeholder: string, onChangeCb: (v: string) => void, isPassword: boolean) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor('#666666')
        .margin({ bottom: 6 })
      Row() {
        TextInput({
          text: value,
          placeholder: placeholder
        })
          .layoutWeight(1)
          .fontSize(15)
          .backgroundColor(Color.Transparent)
          .padding({ left: 0, right: 0, top: 0, bottom: 0 })
          .type(isPassword && !this.apiKeyVisible ? InputType.Password : InputType.Normal)
          .onChange((v: string) => {
            onChangeCb(v);
          })
        if (isPassword) {
          Text(this.apiKeyVisible ? '隐藏' : '显示')
            .fontSize(13)
            .fontColor('#4A90D9')
            .margin({ left: 8 })
            .onClick(() => {
              this.apiKeyVisible = !this.apiKeyVisible;
            })
        }
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  chipField(label: string, value: string, options: string[], onSelect: (v: string) => void) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor('#666666')
        .margin({ bottom: 8 })
      Row({ space: 10 }) {
        ForEach(options, (opt: string) => {
          Text(opt)
            .fontSize(14)
            .fontColor(value === opt ? '#FFFFFF' : '#333333')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(value === opt ? '#4A90D9' : '#F0F0F0')
            .borderRadius(16)
            .onClick(() => {
              onSelect(opt);
            })
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
  }
}
