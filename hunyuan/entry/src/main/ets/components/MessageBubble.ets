// MessageBubble.ets - 消息气泡组件（布局修复版）
import { ChatMessage, MessageRole } from '../model/ChatModels';

/**
 * 单条消息气泡组件
 */
@Component
export struct MessageBubble {
  @Prop message: ChatMessage;
  @Prop showThinking: boolean = true;

  build() {
    Column({ space: 8 }) {
      // 思考过程（可折叠）
      if (this.message.reasoning_content && this.message.reasoning_content.length > 0 && this.showThinking) {
        this.buildThinkingSection()
      }

      // 主消息内容
      this.buildContentSection()
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
  }

  /**
   * 思考过程区域
   */
  @Builder
  buildThinkingSection() {
    Column() {
      // 思考标题栏
      Row() {
        Text('💭 思考过程')
          .fontSize(12)
          .fontColor('#999999')
        Blank()
        Text(`${this.message.reasoning_content?.length || 0} 字`)
          .fontSize(11)
          .fontColor('#BBBBBB')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      // 思考内容
      Text(this.message.reasoning_content || '')
        .fontSize(13)
        .fontColor('#666666')
        .lineHeight(20)
        .textAlign(TextAlign.Start)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
        .padding(10)
        .width('100%')
    }
    .backgroundColor('#F9F9F9')
    .borderRadius(12)
    .border({ width: 1, color: '#EEEEEE' })
    .margin({ bottom: 4 })
    .width('100%')
  }

  /**
   * 主消息内容区域
   */
  @Builder
  buildContentSection() {
    // 用 Row + Blank() 控制左右对齐
    Row() {
      if (this.message.role === MessageRole.User) {
        // 用户消息：Blank 推到右边
        Blank()
        this.buildBubbleContent('#007DFF', '#FFFFFF', true)
      } else if (this.message.role === MessageRole.Tool) {
        // 工具消息：左边显示
        this.buildToolContent()
        Blank()
      } else {
        // AI 消息：左边显示
        this.buildBubbleContent('#F0F0F0', '#1A1A1A', false)
        Blank()
      }
    }
    .width('100%')
  }

  /**
   * 气泡内容
   * isUser: true  → 右边（用户）；false → 左边（AI）
   */
  @Builder
  buildBubbleContent(bgColor: string, textColor: string, isUser: boolean) {
    Column() {
      Text(this.message.content || '...')
        .fontSize(15)
        .fontColor(textColor)
        .lineHeight(24)
        .textAlign(isUser ? TextAlign.End : TextAlign.Start)
        .width('100%')
    }
    .backgroundColor(bgColor)
    .borderRadius(16)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    // 关键：限制气泡最大宽度为屏幕 72%，防止短消息跑出屏幕
    .width(isUser ? '72%' : '72%')
    .alignSelf(isUser ? ItemAlign.End : ItemAlign.Start)
  }

  /**
   * 工具消息内容
   */
  @Builder
  buildToolContent() {
    Row() {
      Text('🔧')
        .fontSize(14)
        .margin({ right: 6 })
      Text(this.message.content || '')
        .fontSize(13)
        .fontColor('#888888')
        .lineHeight(20)
        .textAlign(TextAlign.Start)
    }
    .backgroundColor('#F5F5F5')
    .borderRadius(12)
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .border({ width: 1, color: '#DDDDDD' })
    .width('72%')
    .alignSelf(ItemAlign.Start)
  }
}
