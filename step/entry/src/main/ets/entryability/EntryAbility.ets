import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit'
import { PreferenceUtil } from '../utils/PreferenceUtil'

export default class EntryAbility extends UIAbility {
  onCreate(param1: Want, param2: AbilityConstant.LaunchParam): void {
    PreferenceUtil.setContext(this.context)
  }

  onWindowStageCreate(windowStage: object): void {
    windowStage.loadContent('pages/ChatPage')
  }

  onDestroy(): void {}
  onForeground(): void {}
  onBackground(): void {}
}
