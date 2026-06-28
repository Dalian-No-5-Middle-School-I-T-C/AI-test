@Component
export struct MessageBubble {
  @Prop role: string = 'user';
  @Prop content: string = '';
  @Prop reasoningContent: string = '';
  @Prop toolCalls: string = '';
  @Prop timestamp: number = 0;
  @State thinkingExpanded: boolean = true;

  build() {
    Column() {
      // Reasoning / thinking block
      if (this.reasoningContent.length > 0) {
        Column() {
          Row() {
            Text('思考过程')
              .fontSize(12)
              .fontColor('#888888')
            Blank()
            Text(this.thinkingExpanded ? '收起' : '展开')
              .fontSize(12)
              .fontColor('#4A90D9')
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.thinkingExpanded = !this.thinkingExpanded;
          })
          .backgroundColor('#F0F0F5')
          .borderRadius({ topLeft: 8, topRight: 8 })

          if (this.thinkingExpanded) {
            Text(this.reasoningContent)
              .fontSize(13)
              .fontColor('#666666')
              .width('100%')
              .padding({ left: 8, right: 8, bottom: 8 })
              .backgroundColor('#F5F5FA')
              .borderRadius({ bottomLeft: 8, bottomRight: 8 })
          }
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      // Tool calls
      if (this.toolCalls.length > 0) {
        Column() {
          Row() {
            Text('🔧 工具调用')
              .fontSize(12)
              .fontColor('#888888')
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#FFF3E0')
          .borderRadius(8)

          Text(this.toolCalls)
            .fontSize(12)
            .fontColor('#666666')
            .width('100%')
            .padding({ left: 8, right: 8, bottom: 4 })
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      // Main content
      if (this.content.length > 0) {
        Text(this.content)
          .fontSize(15)
          .fontColor(this.role === 'user' ? '#FFFFFF' : '#333333')
          .padding(10)
          .borderRadius(12)
          .backgroundColor(this.role === 'user' ? '#4A90D9' : '#F0F0F0')
          .constraintSize({ maxWidth: '80%' })
      }
    }
    .width('100%')
    .alignItems(this.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
  }
}
