// Index.ets - 应用入口页，导航至聊天页面
import { router } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  @State message: string = 'DeepSeek Chat';

  build() {
    Column() {
      // 顶部标题
      Text('DeepSeek Chat')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#007DFF')
        .margin({ top: 60, bottom: 20 })

      Text('HarmonyOS AI 聊天助手')
        .fontSize(16)
        .fontColor('#666666')
        .margin({ bottom: 60 })

      // 功能说明
      Column({ space: 12 }) {
        this.buildFeatureItem('💬', 'AI 聊天', '支持 DeepSeek V4 模型')
        this.buildFeatureItem('🧠', '思考模式', '可开关，支持 High / Max 两档')
        this.buildFeatureItem('🔄', '多轮对话', '保留上下文，连贯对话')
        this.buildFeatureItem('📜', '历史记录', '本地保存，随时查看')
        this.buildFeatureItem('🔧', '工具调用', '支持获取系统时间等工具')
        this.buildFeatureItem('🌊', '流式输出', '实时显示 AI 回复')
      }
      .width('85%')
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
      .padding(20)
      .shadow({ radius: 8, color: '#10000000', offsetX: 2, offsetY: 2 })

      Blank()

      // 开始聊天按钮
      Button('开始聊天', { type: ButtonType.Capsule })
        .width('70%')
        .height(48)
        .fontSize(18)
        .backgroundColor('#007DFF')
        .margin({ bottom: 60 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/ChatPage' });
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F6F6')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildFeatureItem(icon: string, title: string, desc: string) {
    Row({ space: 12 }) {
      Text(icon)
        .fontSize(24)
        .width(36)
        .textAlign(TextAlign.Center)

      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1A1A')
        Text(desc)
          .fontSize(12)
          .fontColor('#999999')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }
}
