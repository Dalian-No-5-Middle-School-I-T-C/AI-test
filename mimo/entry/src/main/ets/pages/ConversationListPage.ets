import { router } from '@kit.ArkUI'
import { storageService } from '../services/StorageService'
import { Conversation } from '../models/Message'
import { Context } from '@kit.AbilityKit'

@Entry
@Component
struct ConversationListPage {
  @State conversations: Conversation[] = []

  async aboutToAppear() {
    const context = getContext(this) as Context
    await storageService.init(context)
    await this.loadConversations()
  }

  async loadConversations() {
    this.conversations = await storageService.getConversations()
  }

  async deleteConversation(conversation: Conversation) {
    await storageService.deleteConversation(conversation.id)
    await this.loadConversations()
  }

  formatDate(timestamp: number): string {
    const date = new Date(timestamp)
    return date.toLocaleDateString('zh-CN', {
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  build() {
    Column() {
      this.Header()

      if (this.conversations.length === 0) {
        this.EmptyState()
      } else {
        this.ConversationList()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  Header() {
    Row() {
      Text('←')
        .fontSize(24)
        .onClick(() => {
          router.back()
        })

      Text('历史会话')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ left: 12 })

      Blank()
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  EmptyState() {
    Column() {
      Text('暂无历史会话')
        .fontSize(16)
        .fontColor('#999999')

      Button('开始新对话')
        .margin({ top: 16 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/ChatPage' })
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ConversationList() {
    List() {
      ForEach(this.conversations, (conversation: Conversation) => {
        ListItem() {
          this.ConversationItem(conversation)
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .padding(12)
  }

  @Builder
  ConversationItem(conversation: Conversation) {
    Row() {
      Column() {
        Text(conversation.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`${conversation.messages.length}条消息 · ${this.formatDate(conversation.updatedAt)}`)
          .fontSize(12)
          .fontColor('#999999')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('🗑️')
        .fontSize(20)
        .fontColor('#FF4D4F')
        .onClick(() => {
          this.deleteConversation(conversation)
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 8 })
    .onClick(() => {
      router.pushUrl({
        url: 'pages/ChatPage',
        params: { conversationId: conversation.id }
      })
    })
  }
}