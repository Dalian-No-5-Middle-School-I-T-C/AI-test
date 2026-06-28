import { Message, ToolCall } from '../models/Message'

@Component
export struct ChatMessageComponent {
  @Prop message: Message

  build() {
    Column() {
      if (this.message.role === 'user') {
        this.UserMessage()
      } else if (this.message.role === 'assistant') {
        this.AssistantMessage()
      } else if (this.message.role === 'tool') {
        this.ToolMessage()
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  @Builder
  UserMessage() {
    Row() {
      Blank()
      Text(this.message.content)
        .fontSize(16)
        .padding(12)
        .backgroundColor('#007DFF')
        .fontColor('#FFFFFF')
        .borderRadius(16)
    }
    .width('100%')
  }

  @Builder
  AssistantMessage() {
    Column() {
      if (this.message.thinking) {
        Column() {
          Row() {
            Text('思考过程')
              .fontSize(12)
              .fontColor('#999999')
            Text('▼')
              .fontSize(12)
              .fontColor('#999999')
          }

          Text(this.message.thinking)
            .fontSize(14)
            .fontColor('#666666')
            .padding(8)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .width('100%')
        }
        .padding(8)
        .backgroundColor('#FAFAFA')
        .borderRadius(12)
        .width('100%')
        .margin({ bottom: 8 })
      }

      if (this.message.toolCalls && this.message.toolCalls.length > 0) {
        ForEach(this.message.toolCalls, (toolCall: ToolCall) => {
          Row() {
            Text(`调用工具: ${toolCall.function.name}`)
              .fontSize(12)
              .fontColor('#666666')
            LoadingProgress()
              .width(16)
              .height(16)
              .color('#007DFF')
          }
          .padding(8)
          .backgroundColor('#F0F7FF')
          .borderRadius(8)
          .width('100%')
          .margin({ bottom: 4 })
        })
      }

      if (this.message.content) {
        Text(this.message.content)
          .fontSize(16)
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(16)
      }
    }
    .width('100%')
  }

  @Builder
  ToolMessage() {
    Column() {
      Row() {
        Text('工具结果')
          .fontSize(12)
          .fontColor('#999999')
      }

      Text(this.message.content)
        .fontSize(14)
        .padding(8)
        .backgroundColor('#FFF7E6')
        .borderRadius(8)
        .width('100%')
    }
    .padding(8)
    .backgroundColor('#FFFBE6')
    .borderRadius(12)
    .width('100%')
  }
}