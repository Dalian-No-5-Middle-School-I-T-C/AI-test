// MessageBubble.ets - 消息气泡组件
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
  }

  /**
   * 主消息内容区域
   */
  @Builder
  buildContentSection() {
    Row() {
      if (this.message.role === MessageRole.User) {
        // 用户消息：右对齐
        Blank()
        this.buildBubbleContent('#007DFF', '#FFFFFF', TextAlign.End)
      } else {
        // AI 消息：左对齐
        this.buildBubbleContent('#F0F0F0', '#1A1A1A', TextAlign.Start)
        Blank()
      }
    }
    .width('100%')
  }

  /**
   * 气泡内容
   */
  @Builder
  buildBubbleContent(bgColor: string, textColor: string, align: TextAlign) {
    Column() {
      if (this.message.role === MessageRole.Tool) {
        Text(`🔧 工具结果: ${this.message.content}`)
          .fontSize(13)
          .fontColor('#888888')
          .textAlign(TextAlign.Start)
      } else {
        Text(this.message.content || '...')
          .fontSize(15)
          .fontColor(textColor)
          .lineHeight(24)
          .textAlign(align)
          .width('100%')
      }
    }
    .backgroundColor(bgColor)
    .borderRadius(16)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .constraintSize({ maxWidth: '78%' })
  }
}
