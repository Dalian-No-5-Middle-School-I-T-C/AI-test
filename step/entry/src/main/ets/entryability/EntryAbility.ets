import { AbilityKit } from '@kit.AbilityKit'
import { PreferenceUtil } from '../utils/PreferenceUtil'

export default class EntryAbility extends AbilityKit.UIAbility {
  onCreate(want: any, launchParam: any): void {
    PreferenceUtil.setContext(this.context)
  }
}
