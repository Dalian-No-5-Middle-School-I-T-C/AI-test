import { UIAbility } from '@kit.AbilityKit'

export default class EntryAbility extends UIAbility {
  onCreate(): void {}
  onWindowStageCreate(windowStage: object): void {
    windowStage.loadContent('pages/ChatPage')
  }
  onDestroy(): void {}
}
