import { ChatController } from '../common/ChatController';
import { Conversation } from '../common/Storage';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct History {
  controller: ChatController = ChatController.get();
  @State list: Conversation[] = [];

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    this.list = this.controller.conversations.slice();
  }

  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(20)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.back();
          })
        Text('历史记录')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .margin({ left: 4 })
        Text('新建')
          .fontColor('#0A59F7')
          .fontSize(16)
          .margin({ right: 8 })
          .onClick(() => {
            this.controller.startNewConversation();
            router.back();
          })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 12, bottom: 12 })

      if (this.list.length === 0) {
        Column() {
          Text('暂无历史对话')
            .fontSize(16)
            .fontColor('#999999')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.list, (item: Conversation) => {
            ListItem() {
              Row() {
                Column() {
                  Text(item.title)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${item.model} · ${this.formatTime(item.updatedAt)}`)
                    .fontSize(12)
                    .fontColor('#888888')
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text('删除')
                  .fontSize(14)
                  .fontColor('#FF4D4F')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .onClick(() => {
                    this.controller.deleteConversation(item.id);
                    this.refresh();
                  })
              }
              .width('100%')
              .padding(16)
              .backgroundColor(Color.White)
              .onClick(() => {
                this.controller.setCurrentById(item.id);
                router.back();
              })
            }
          }, (item: Conversation) => item.id)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: '#F0F0F0' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8FA')
  }

  private formatTime(ts: number): string {
    const d = new Date(ts);
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
}