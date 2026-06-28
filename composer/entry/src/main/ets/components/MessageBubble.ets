import { DisplayMessage, ToolCall } from '../model/ChatModels';

@Component
export struct MessageBubble {
  @Prop message: DisplayMessage;
  @State thinkingExpanded: boolean = false;

  build() {
    if (this.message.role === 'user') {
      this.UserBubble()
    } else if (this.message.role === 'assistant') {
      this.AssistantBubble()
    } else if (this.message.role === 'tool') {
      this.ToolBubble()
    }
  }

  @Builder
  UserBubble() {
    Row() {
      Blank()
      Column() {
        Text(this.message.content)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .lineHeight(22)
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor('#007AFF')
      .borderRadius({
        topLeft: 16,
        topRight: 4,
        bottomLeft: 16,
        bottomRight: 16,
      })
      .constraintSize({ maxWidth: '78%' })
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  @Builder
  AssistantBubble() {
    Row() {
      Column() {
        Row() {
          Text('🤖')
            .fontSize(18)
          Text(' DeepSeek')
            .fontSize(12)
            .fontColor('#888888')
            .margin({ left: 4 })
          if (this.message.isStreaming) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color('#007AFF')
              .margin({ left: 8 })
          }
        }
        .margin({ bottom: 6 })

        if (this.message.reasoningContent.length > 0) {
          Column() {
            Row() {
              Text('💭 思考过程')
                .fontSize(12)
                .fontColor('#666666')
                .fontWeight(FontWeight.Medium)
              Blank()
              Text(this.thinkingExpanded ? '收起 ▲' : '展开 ▼')
                .fontSize(11)
                .fontColor('#007AFF')
                .onClick(() => {
                  this.thinkingExpanded = !this.thinkingExpanded;
                })
            }
            .width('100%')
            .margin({ bottom: 4 })

            if (this.thinkingExpanded || this.message.isStreaming) {
              Text(this.message.reasoningContent)
                .fontSize(13)
                .fontColor('#666666')
                .lineHeight(20)
                .fontStyle(FontStyle.Italic)
            } else {
              Text(this.message.reasoningContent.substring(0, 80) +
                (this.message.reasoningContent.length > 80 ? '...' : ''))
                .fontSize(13)
                .fontColor('#999999')
                .lineHeight(20)
                .fontStyle(FontStyle.Italic)
            }
          }
          .width('100%')
          .padding(10)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .margin({ bottom: 8 })
        }

        if (this.message.toolCalls && this.message.toolCalls.length > 0) {
          this.ToolCallBadge(this.message.toolCalls)
        }

        if (this.message.content.length > 0) {
          Text(this.message.content)
            .fontSize(15)
            .fontColor('#333333')
            .lineHeight(22)
        } else if (this.message.isStreaming && this.message.reasoningContent.length > 0) {
          Text('正在生成回答...')
            .fontSize(13)
            .fontColor('#AAAAAA')
            .fontStyle(FontStyle.Italic)
        }
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor('#FFFFFF')
      .borderRadius({
        topLeft: 4,
        topRight: 16,
        bottomLeft: 16,
        bottomRight: 16,
      })
      .constraintSize({ maxWidth: '85%' })
      .shadow({ radius: 4, color: '#10000000', offsetY: 1 })

      Blank()
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 12 })
  }

  @Builder
  ToolCallBadge(toolCalls: ToolCall[]) {
    Column() {
      ForEach(toolCalls, (tc: ToolCall) => {
        Row() {
          Text('🔧')
            .fontSize(14)
          Text(` ${tc.function.name}`)
            .fontSize(12)
            .fontColor('#FF9500')
            .fontWeight(FontWeight.Medium)
        }
        .margin({ bottom: 2 })
      }, (tc: ToolCall) => tc.id)
    }
    .width('100%')
    .padding(8)
    .backgroundColor('#FFF8E7')
    .borderRadius(6)
    .margin({ bottom: 8 })
  }

  @Builder
  ToolBubble() {
    Row() {
      Column() {
        Row() {
          Text('🔧')
            .fontSize(14)
          Text(` 工具结果: ${this.message.toolName ?? 'unknown'}`)
            .fontSize(12)
            .fontColor('#888888')
        }
        .margin({ bottom: 4 })

        Text(this.message.content)
          .fontSize(13)
          .fontColor('#555555')
          .lineHeight(20)
          .fontFamily('monospace')
      }
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor('#F0F0F0')
      .borderRadius(8)
      .constraintSize({ maxWidth: '85%' })

      Blank()
    }
    .width('100%')
    .margin({ bottom: 8 })
  }
}
