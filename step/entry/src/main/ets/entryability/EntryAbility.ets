import { UIAbility } from '@kit.AbilityKit'
import { PreferenceUtil } from '../utils/PreferenceUtil'

export default class EntryAbility extends UIAbility {
  onCreate(param1: any, param2: any): void {
    PreferenceUtil.setContext(this)
  }
  onWindowStageCreate(windowStage: any): void {
    windowStage.loadContent('pages/ChatPage')
  }
  onDestroy(): void {}
  onForeground(): void {}
  onBackground(): void {}
}
