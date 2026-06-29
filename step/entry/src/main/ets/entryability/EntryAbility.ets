import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit'
import { PreferenceUtil } from '../utils/PreferenceUtil'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PreferenceUtil.setContext(this)
  }
  onDestroy(): void {}
  onWindowStageCreate(windowStage): void {
    windowStage.loadContent('pages/ChatPage')
  }
  onForeground(): void {}
  onBackground(): void {}
}
