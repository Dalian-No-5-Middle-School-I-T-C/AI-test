import { router } from '@kit.ArkUI'
import { storageService } from '../services/StorageService'
import { AppSettings, DEFAULT_SETTINGS, ModelType, ReasoningEffort } from '../models/Message'
import { Context } from '@kit.AbilityKit'

@Entry
@Component
struct SettingsPage {
  @State settings: AppSettings = DEFAULT_SETTINGS
  @State apiKey: string = ''
  @State model: string = 'deepseek-v4-pro'
  @State thinkingEnabled: boolean = true
  @State reasoningEffort: string = 'high'
  @State systemPrompt: string = ''

  async aboutToAppear() {
    const context = getContext(this) as Context
    await storageService.init(context)
    this.settings = await storageService.getSettings()
    this.apiKey = this.settings.apiKey
    this.model = this.settings.model
    this.thinkingEnabled = this.settings.thinkingEnabled
    this.reasoningEffort = this.settings.reasoningEffort
    this.systemPrompt = this.settings.systemPrompt
  }

  async saveSettings() {
    const newSettings: AppSettings = {
      apiKey: this.apiKey,
      model: this.model as ModelType,
      thinkingEnabled: this.thinkingEnabled,
      reasoningEffort: this.reasoningEffort as ReasoningEffort,
      systemPrompt: this.systemPrompt
    }
    await storageService.saveSettings(newSettings)
    router.back()
  }

  build() {
    Column() {
      this.Header()

      Scroll() {
        Column() {
          this.ApiKeySection()
          this.ModelSection()
          this.ThinkingSection()
          this.SystemPromptSection()
          this.SaveButton()
        }
        .padding(16)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  Header() {
    Row() {
      Text('←')
        .fontSize(24)
        .onClick(() => {
          router.back()
        })

      Text('设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ left: 12 })

      Blank()
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  ApiKeySection() {
    Column() {
      Text('API Key')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 })

      TextInput({ text: this.apiKey, placeholder: '请输入DeepSeek API Key' })
        .width('100%')
        .height(44)
        .onChange((value: string) => {
          this.apiKey = value
        })

      Text('请在DeepSeek官网获取API Key')
        .fontSize(12)
        .fontColor('#999999')
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  ModelSection() {
    Column() {
      Text('模型选择')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 })

      Row() {
        this.ModelOption('deepseek-v4-pro', 'DeepSeek V4 Pro', '更强的推理能力')
        this.ModelOption('deepseek-v4-flash', 'DeepSeek V4 Flash', '更快的响应速度')
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  ModelOption(modelId: string, title: string, description: string) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(this.model === modelId ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.model === modelId ? '#007DFF' : '#333333')

      Text(description)
        .fontSize(12)
        .fontColor('#666666')
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor(this.model === modelId ? '#F0F7FF' : '#F5F5F5')
    .borderRadius(8)
    .margin({ right: 8 })
    .onClick(() => {
      this.model = modelId
    })
  }

  @Builder
  ThinkingSection() {
    Column() {
      Text('思考模式')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 })

      Row() {
        Text('启用思考')
          .fontSize(14)

        Blank()

        Toggle({ type: ToggleType.Switch, isOn: this.thinkingEnabled })
          .onChange((isOn: boolean) => {
            this.thinkingEnabled = isOn
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      if (this.thinkingEnabled) {
        Text('思考深度')
          .fontSize(14)
          .margin({ bottom: 8 })

        Row() {
          this.EffortOption('high', 'High', '标准深度')
          this.EffortOption('max', 'Max', '最大深度')
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  EffortOption(effort: string, title: string, description: string) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(this.reasoningEffort === effort ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.reasoningEffort === effort ? '#007DFF' : '#333333')

      Text(description)
        .fontSize(12)
        .fontColor('#666666')
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor(this.reasoningEffort === effort ? '#F0F7FF' : '#F5F5F5')
    .borderRadius(8)
    .margin({ right: 8 })
    .onClick(() => {
      this.reasoningEffort = effort
    })
  }

  @Builder
  SystemPromptSection() {
    Column() {
      Text('系统提示词')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 })

      TextInput({ text: this.systemPrompt, placeholder: '请输入系统提示词' })
        .width('100%')
        .height(100)
        .onChange((value: string) => {
          this.systemPrompt = value
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  SaveButton() {
    Button('保存设置')
      .width('100%')
      .height(48)
      .onClick(() => {
        this.saveSettings()
      })
  }
}