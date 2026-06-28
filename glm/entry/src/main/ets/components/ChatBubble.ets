import { ChatMessage } from '../model/Types';

@Component
export struct ChatBubble {
  @ObjectLink msg: ChatMessage;

  build() {
    if (this.msg.role === 'user') {
      Row() {
        Column() {
          Text(this.msg.content)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.Start)
        }
        .padding(12)
        .backgroundColor('#3366FF')
        .borderRadius(14)
        .constraintSize({ maxWidth: '80%' })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    } else if (this.msg.role === 'tool') {
      Row() {
        Column() {
          Text('工具调用结果')
            .fontSize(11)
            .fontColor('#999999')
          Text(this.msg.content)
            .fontSize(13)
            .fontColor('#555555')
            .maxLines(6)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .padding(10)
        .backgroundColor('#EEEEEE')
        .borderRadius(10)
        .constraintSize({ maxWidth: '85%' })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
    } else {
      Row() {
        Column() {
          if (this.msg.reasoningContent.length > 0 || this.msg.isThinking) {
            ThinkingBlock({ msg: this.msg })
          }

          if (this.msg.isToolCall && this.msg.toolCalls.length > 0) {
            Row() {
              Text('调用工具: ' + this.msg.toolCalls[0].function.name)
                .fontSize(12)
                .fontColor('#888888')
            }
            .margin({ top: 4 })
          }

          if (this.msg.content.length > 0) {
            Text(this.msg.content)
              .fontSize(16)
              .fontColor(this.msg.isError ? '#CC0000' : '#222222')
              .textAlign(TextAlign.Start)
          }

          if (this.msg.isThinking && this.msg.content.length === 0 && this.msg.reasoningContent.length === 0) {
            Row() {
              LoadingProgress().width(18).height(18)
              Text('正在思考...')
                .fontSize(13)
                .fontColor('#999999')
                .margin({ left: 6 })
            }
            .margin({ top: 4 })
          }
        }
        .padding(12)
        .backgroundColor('#F5F5F7')
        .borderRadius(14)
        .constraintSize({ maxWidth: '85%' })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    }
  }
}

@Component
struct ThinkingBlock {
  @ObjectLink msg: ChatMessage;
  @State expanded: boolean = true;

  build() {
    Column() {
      Row() {
        Text(this.msg.isThinking ? '思考中' : '已思考')
          .fontSize(12)
          .fontColor('#666666')
          .fontWeight(FontWeight.Medium)
        if (this.msg.reasoningContent.length > 0) {
          Text(this.expanded ? '收起' : '展开')
            .fontSize(12)
            .fontColor('#3366FF')
            .margin({ left: 8 })
            .onClick(() => {
              this.expanded = !this.expanded;
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      if (this.expanded && this.msg.reasoningContent.length > 0) {
        Text(this.msg.reasoningContent)
          .fontSize(13)
          .fontColor('#888888')
          .margin({ top: 6 })
          .width('100%')
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor('#EAEAEE')
    .borderRadius(8)
    .margin({ bottom: 6 })
    .alignItems(HorizontalAlign.Start)
  }
}
