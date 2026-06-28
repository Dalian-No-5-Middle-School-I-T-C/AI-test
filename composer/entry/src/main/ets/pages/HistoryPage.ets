import { Conversation } from '../model/ChatModels';
import { chatManager } from '../service/ChatManager';
import { storageService } from '../service/StorageService';

@Component
export struct HistoryPage {
  @Prop @Watch('onRefreshTriggerChange') refreshTrigger: number = 0;
  @Link currentTabIndex: number;
  @Link chatRefreshKey: number;
  @State conversations: Conversation[] = [];

  aboutToAppear(): void {
    this.loadHistory();
  }

  onRefreshTriggerChange(): void {
    this.loadHistory();
  }

  async loadHistory(): Promise<void> {
    this.conversations = await storageService.getConversations();
  }

  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    return `${month}-${day} ${hours}:${minutes}`;
  }

  getPreview(conv: Conversation): string {
    const userMsg = conv.messages.find((m) => m.role === 'user');
    if (userMsg) {
      return userMsg.content.length > 50 ?
        userMsg.content.substring(0, 50) + '...' : userMsg.content;
    }
    return '空对话';
  }

  async deleteConversation(id: string): Promise<void> {
    AlertDialog.show({
      title: '删除对话',
      message: '确定要删除这条对话记录吗？',
      primaryButton: {
        value: '取消',
        action: () => {},
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#FF3B30',
        action: async () => {
          await chatManager.deleteConversation(id);
          await this.loadHistory();
        },
      },
    });
  }

  build() {
    Column() {
      Row() {
        Text('历史记录')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
        Blank()
        Button('刷新')
          .fontSize(13)
          .height(32)
          .backgroundColor('#F0F0F0')
          .fontColor('#007AFF')
          .onClick(() => {
            this.loadHistory();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      if (this.conversations.length === 0) {
        Column() {
          Text('📋')
            .fontSize(48)
            .margin({ bottom: 16 })
          Text('暂无历史记录')
            .fontSize(16)
            .fontColor('#999999')
          Text('开始对话后会自动保存')
            .fontSize(13)
            .fontColor('#CCCCCC')
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.conversations, (conv: Conversation) => {
            ListItem() {
              Row() {
                Column() {
                  Text(conv.title)
                    .fontSize(16)
                    .fontColor('#333333')
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(this.getPreview(conv))
                    .fontSize(13)
                    .fontColor('#999999')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })

                  Text(this.formatTime(conv.updatedAt))
                    .fontSize(11)
                    .fontColor('#CCCCCC')
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button('删除')
                  .fontSize(12)
                  .height(28)
                  .backgroundColor('#FFEBEB')
                  .fontColor('#FF3B30')
                  .onClick(() => {
                    this.deleteConversation(conv.id);
                  })
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .onClick(async () => {
                await chatManager.loadConversation(conv.id);
                this.currentTabIndex = 0;
                this.chatRefreshKey++;
              })
            }
            .margin({ bottom: 8 })
          }, (conv: Conversation) => conv.id)
        }
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
  }
}
