import { router } from '@kit.ArkUI';
import { StorageService } from '../services/StorageService';
import { ConversationSummary } from '../models/ChatModels';

@Entry
@Component
struct Index {
  @State conversations: ConversationSummary[] = [];
  @State hasApiKey: boolean = false;

  aboutToAppear(): void {
    let context = getContext(this);
    StorageService.init(context);
    this.refreshList();
    this.hasApiKey = StorageService.getApiKey().length > 0;
  }

  onPageShow(): void {
    this.refreshList();
    this.hasApiKey = StorageService.getApiKey().length > 0;
  }

  refreshList(): void {
    this.conversations = StorageService.loadConversationList();
  }

  build() {
    Column() {
      // Title bar
      Row() {
        Text('DeepSeek Chat')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
        Blank()
        Button() {
          Text('⚙')
            .fontSize(22)
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.pushUrl({ url: 'pages/SettingsPage' });
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      Divider().strokeWidth(1).color('#EEEEEE')

      // Content area
      if (!this.hasApiKey) {
        Column() {
          Text('请先设置 API Key')
            .fontSize(16)
            .fontColor('#999999')
            .margin({ bottom: 12 })
          Button('前往设置')
            .fontSize(15)
            .padding({ left: 24, right: 24 })
            .borderRadius(20)
            .backgroundColor('#4A90D9')
            .onClick(() => {
              router.pushUrl({ url: 'pages/SettingsPage' });
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.conversations.length === 0) {
        Column() {
          Text('暂无对话')
            .fontSize(16)
            .fontColor('#999999')
            .margin({ bottom: 8 })
          Text('点击下方按钮开始新对话')
            .fontSize(14)
            .fontColor('#BBBBBB')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.conversations, (item: ConversationSummary, index: number) => {
            ListItem() {
              Column() {
                Row() {
                  Text(item.title)
                    .fontSize(16)
                    .fontColor('#333333')
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(this.formatTime(item.updatedAt))
                    .fontSize(12)
                    .fontColor('#BBBBBB')
                }
                .width('100%')

                Row() {
                  Text(item.lastMessage ? item.lastMessage : '新对话')
                    .fontSize(13)
                    .fontColor('#999999')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(item.model === 'deepseek-v4-pro' ? 'Pro' : 'Flash')
                    .fontSize(10)
                    .fontColor('#4A90D9')
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .backgroundColor('#EBF3FC')
                    .borderRadius(4)
                }
                .width('100%')
                .margin({ top: 4 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .onClick(() => {
                router.pushUrl({ url: 'pages/ChatPage', params: { conversationId: item.id } });
              })
              .gesture(
                LongPressGesture({ repeat: false, duration: 600 })
                  .onAction(() => {
                    this.showDeleteDialog(item);
                  })
              )
            }
            .width('100%')
          }, (item: ConversationSummary) => item.id)

          ListItem() {
            Column() {
              Blank().height(80)
            }
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: '#F0F0F0' })
      }

      Divider().strokeWidth(1).color('#EEEEEE')

      // New chat button
      Button('+ 新建对话')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .height(52)
        .backgroundColor(this.hasApiKey ? '#4A90D9' : '#CCCCCC')
        .enabled(this.hasApiKey)
        .onClick(() => {
          router.pushUrl({ url: 'pages/ChatPage', params: { conversationId: '' } });
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
  }

  private formatTime(timestamp: number): string {
    let d = new Date(timestamp);
    let now = new Date();
    let month = String(d.getMonth() + 1).padStart(2, '0');
    let day = String(d.getDate()).padStart(2, '0');
    if (d.getFullYear() === now.getFullYear() &&
      d.getMonth() === now.getMonth() &&
      d.getDate() === now.getDate()) {
      return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    }
    return `${month}-${day}`;
  }

  private showDeleteDialog(item: ConversationSummary): void {
    AlertDialog.show({
      title: '删除对话',
      message: `确定要删除"${item.title}"吗？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#FF3B30',
        action: () => {
          StorageService.deleteConversation(item.id);
          this.refreshList();
        }
      }
    });
  }
}
