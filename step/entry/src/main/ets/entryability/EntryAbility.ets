import { UIAbility, Want, window, AbilityConstant, ConfigurationConstant } from '@kit.AbilityKit'
import { initAppContext } from '../utils/PreferenceUtil'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    initAppContext(this)
  }

  onDestroy(): void {}

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/ChatPage', (err) => {})
  }

  onWindowStageDestroy(): void {}

  onForeground(): void {}

  onBackground(): void {}
}
