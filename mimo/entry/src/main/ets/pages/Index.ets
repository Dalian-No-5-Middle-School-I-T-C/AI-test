import { router } from '@kit.ArkUI'
import { storageService } from '../services/StorageService'
import { AppSettings, DEFAULT_SETTINGS } from '../models/Message'
import { Context } from '@kit.AbilityKit'

@Entry
@Component
struct Index {
  @State settings: AppSettings = DEFAULT_SETTINGS

  async aboutToAppear() {
    const context = getContext(this) as Context
    await storageService.init(context)
    this.settings = await storageService.getSettings()
  }

  build() {
    Column() {
      this.Header()
      this.WelcomeSection()
      this.ActionButtons()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  Header() {
    Row() {
      Text('DeepSeek AI 助手')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')

      Blank()

      Text('⚙️')
        .fontSize(24)
        .onClick(() => {
          router.pushUrl({ url: 'pages/SettingsPage' })
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  WelcomeSection() {
    Column() {
      Text('欢迎使用 DeepSeek AI 助手')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 })

      Text('使用DeepSeek强大的AI模型进行对话，支持思考模式和工具调用')
        .fontSize(14)
        .fontColor('#666666')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 16 })

      if (!this.settings.apiKey) {
        Text('请先设置API Key')
          .fontSize(16)
          .fontColor('#FF4D4F')
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(32)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ActionButtons() {
    Column() {
      Button('开始新对话')
        .width('100%')
        .height(48)
        .fontSize(16)
        .onClick(() => {
          router.pushUrl({ url: 'pages/ChatPage' })
        })

      Button('历史会话')
        .width('100%')
        .height(48)
        .fontSize(16)
        .margin({ top: 12 })
        .type(ButtonType.Normal)
        .backgroundColor('#FFFFFF')
        .fontColor('#007DFF')
        .onClick(() => {
          router.pushUrl({ url: 'pages/ConversationListPage' })
        })

      Button('设置')
        .width('100%')
        .height(48)
        .fontSize(16)
        .margin({ top: 12 })
        .type(ButtonType.Normal)
        .backgroundColor('#FFFFFF')
        .fontColor('#007DFF')
        .onClick(() => {
          router.pushUrl({ url: 'pages/SettingsPage' })
        })
    }
    .width('100%')
    .padding(16)
  }
}