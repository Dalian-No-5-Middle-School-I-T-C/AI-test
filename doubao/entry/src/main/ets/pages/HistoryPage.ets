import { ChatSession } from '../model/ChatModels';
import { router } from '@kit.ArkUI';
import { saveSessions } from '../util/PreferencesUtil';
import { promptAction } from '@kit.ArkUI';

interface HistoryPageParams {
  sessions: ChatSession[];
  onSelect: (s: ChatSession) => void;
  onDelete: (id: string) => void;
  onNewChat: () => void;
}

@Entry
@Component
struct HistoryPage {
  @State sessions: ChatSession[] = [];
  private onSelect?: (session: ChatSession) => void;
  private onDelete?: (sessionId: string) => void;
  private onNewChat?: () => void;

  aboutToAppear(): void {
    const p = AppStorage.get<HistoryPageParams>('historyParams');
    if (p) {
      this.sessions = p.sessions;
      this.onSelect = p.onSelect;
      this.onDelete = p.onDelete;
      this.onNewChat = p.onNewChat;
    }
  }

  private formatTime(ts: number): string {
    const d = new Date(ts);
    const now = new Date();
    const sameDay = d.getFullYear() === now.getFullYear() &&
      d.getMonth() === now.getMonth() &&
      d.getDate() === now.getDate();
    const pad = (n: number): string => n < 10 ? '0' + n : n.toString();
    if (sameDay) {
      return pad(d.getHours()) + ':' + pad(d.getMinutes());
    }
    return (d.getMonth() + 1).toString() + '/' + d.getDate().toString();
  }

  private getPreview(session: ChatSession): string {
    for (let i = session.messages.length - 1; i >= 0; i--) {
      if (session.messages[i].content.length > 0 && session.messages[i].role !== 'tool') {
        const c = session.messages[i].content;
        return c.length > 40 ? c.substring(0, 40) + '...' : c;
      }
    }
    return '空对话';
  }

  private deleteSession(id: string): void {
    const newList: ChatSession[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id !== id) {
        newList.push(this.sessions[i]);
      }
    }
    this.sessions = newList;
    saveSessions(this.sessions.slice());
    if (this.onDelete) {
      this.onDelete(id);
    }
    promptAction.showToast({ message: '已删除', duration: 1000 });
  }

  private confirmDelete(session: ChatSession): void {
    AlertDialog.show({
      title: '删除对话',
      message: '确定删除「' + session.title + '」吗？',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#FF4444',
        action: () => {
          this.deleteSession(session.id);
        }
      }
    });
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor('#4A90D9')
          .onClick(() => {
            router.back();
          })
        Text('历史对话')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button('新建')
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor('#4A90D9')
          .onClick(() => {
            if (this.onNewChat) this.onNewChat();
            router.back();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#FFFFFF')

      if (this.sessions.length === 0) {
        Column() {
          Text('暂无历史对话')
            .fontSize(15)
            .fontColor('#999999')
          Button('开始新对话')
            .fontSize(14)
            .margin({ top: 16 })
            .backgroundColor('#4A90D9')
            .fontColor(Color.White)
            .borderRadius(20)
            .onClick(() => {
              if (this.onNewChat) this.onNewChat();
              router.back();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.sessions, (session: ChatSession) => {
            ListItem() {
              Row() {
                Column() {
                  Text(session.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(this.getPreview(session))
                    .fontSize(13)
                    .fontColor('#999999')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Column() {
                  Text(this.formatTime(session.updatedAt))
                    .fontSize(12)
                    .fontColor('#BBBBBB')
                  Button('删除')
                    .fontSize(11)
                    .fontColor('#FF4444')
                    .backgroundColor(Color.Transparent)
                    .padding(0)
                    .margin({ top: 4 })
                    .onClick(() => {
                      this.confirmDelete(session);
                    })
                }
                .alignItems(HorizontalAlign.End)
                .margin({ left: 8 })
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .onClick(() => {
                if (this.onSelect) this.onSelect(session);
                router.back();
              })
            }
          }, (session: ChatSession) => session.id)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: '#F0F0F0' })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
