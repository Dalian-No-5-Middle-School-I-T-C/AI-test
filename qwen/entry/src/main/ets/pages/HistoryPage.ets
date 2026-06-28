import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { Conversation } from '../model/ChatModel';
import { StorageService } from '../service/StorageService';

@Entry
@Component
struct HistoryPage {
  @State conversations: Array<Conversation> = [];

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.loadConversations();
  }

  async loadConversations(): Promise<void> {
    try {
      let all = await StorageService.loadConversations(this.context);
      this.conversations = all.reverse();
    } catch (e) {
      this.conversations = [];
    }
  }

  formatDate(timestamp: number): string {
    let date = new Date(timestamp);
    let month = (date.getMonth() + 1).toString().padStart(2, '0');
    let day = date.getDate().toString().padStart(2, '0');
    let hours = date.getHours().toString().padStart(2, '0');
    let minutes = date.getMinutes().toString().padStart(2, '0');
    return month + '-' + day + ' ' + hours + ':' + minutes;
  }

  countMessages(conv: Conversation): number {
    let count = 0;
    for (let i = 0; i < conv.messages.length; i++) {
      if (conv.messages[i].role === 'user') {
        count++;
      }
    }
    return count;
  }

  async deleteConversation(convId: string): Promise<void> {
    try {
      await StorageService.deleteConversation(this.context, convId);
      await this.loadConversations();
      promptAction.showToast({ message: 'Deleted' });
    } catch (e) {
      // ignore
    }
  }

  selectConversation(conv: Conversation): void {
    AppStorage.setOrCreate<string>('selectedConversationId', conv.id);
    router.back();
  }

  build() {
    Column() {
      Row() {
        Button() {
          Text('< Back')
            .fontSize(14)
            .fontColor('#4A90D9')
        }
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.back();
        })

        Text('History')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank().width(70)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 2, color: '#1A000000', offsetY: 1 })

      if (this.conversations.length === 0) {
        Column() {
          Text('No conversations yet')
            .fontSize(16)
            .fontColor('#999999')
          Text('Start a new chat to begin')
            .fontSize(13)
            .fontColor('#CCCCCC')
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.conversations, (conv: Conversation) => {
            ListItem() {
              Row() {
                Column() {
                  Text(conv.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row() {
                    Text(this.formatDate(conv.timestamp))
                      .fontSize(12)
                      .fontColor('#999999')

                    Text(this.countMessages(conv).toString() + ' messages')
                      .fontSize(12)
                      .fontColor('#BBBBBB')
                      .margin({ left: 12 })
                  }
                  .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button() {
                  Text('Del')
                    .fontSize(11)
                    .fontColor('#E53935')
                }
                .type(ButtonType.Normal)
                .backgroundColor('#FFF0F0')
                .borderRadius(6)
                .height(28)
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  this.deleteConversation(conv.id);
                })
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
            }
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
            .onClick(() => {
              this.selectConversation(conv);
            })
          }, (conv: Conversation) => conv.id)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor('#F5F5F5')
        .divider({ strokeWidth: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
