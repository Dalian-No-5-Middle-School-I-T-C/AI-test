import { UIAbility } from '@kit.AbilityKit'

export default class EntryAbility extends UIAbility {
  onCreate(): void {}
  onWindowStageCreate(windowStage: any): void {
    windowStage.loadContent('pages/ChatPage')
  }
  onDestroy(): void {}
}
