import { AppSettings, DEFAULT_SETTINGS } from '../model/ChatModels';
import { ChatPage } from './ChatPage';
import { HistoryPage } from './HistoryPage';
import { SettingsPage } from './SettingsPage';
import { storageService } from '../service/StorageService';

@Entry
@Component
struct Index {
  @State settings: AppSettings = DEFAULT_SETTINGS;
  @State currentTabIndex: number = 0;
  @State chatRefreshKey: number = 0;
  @State historyRefreshTrigger: number = 0;

  aboutToAppear(): void {
    this.loadSettings();
  }

  async loadSettings(): Promise<void> {
    this.settings = await storageService.getSettings();
  }


  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
      TabContent() {
        ChatPage({ settings: $settings, refreshKey: this.chatRefreshKey })
      }
      .tabBar(this.TabItem('💬', '对话'))

      TabContent() {
        HistoryPage({
          refreshTrigger: this.historyRefreshTrigger,
          currentTabIndex: $currentTabIndex,
          chatRefreshKey: $chatRefreshKey,
        })
      }
      .tabBar(this.TabItem('📋', '历史'))

      TabContent() {
        SettingsPage({ settings: $settings })
      }
      .tabBar(this.TabItem('⚙️', '设置'))
    }
    .barMode(BarMode.Fixed)
    .onChange((index: number) => {
      this.currentTabIndex = index;
      if (index === 1) {
        this.historyRefreshTrigger++;
      }
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  TabItem(icon: string, label: string) {
    Column() {
      Text(icon)
        .fontSize(22)
      Text(label)
        .fontSize(11)
        .margin({ top: 2 })
    }
    .justifyContent(FlexAlign.Center)
    .height('100%')
  }
}
