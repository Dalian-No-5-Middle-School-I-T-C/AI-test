import { AbilityKit } from '@kit.AbilityKit'
import { ArkData } from '@kit.ArkData'

const PREFS_NAME = 'ds_chat_prefs'

let ctx: AbilityKit.Context | null = null
let pref: ArkData.Preferences | null = null

export function setContext(c: AbilityKit.Context): void {
  ctx = c
}

export function getPref(): ArkData.Preferences {
  if (pref) return pref
  if (!ctx) {
    throw new Error('Context not set')
  }
  pref = ArkData.preferences.getPreferencesSync(ctx, PREFS_NAME)
  return pref
}

export class PreferenceUtil {
  static setString(key: string, value: string): void {
    getPref().putSync(key, value)
  }

  static getString(key: string, def: string): string {
    try {
      return getPref().getSync(key, def)
    } catch (e) {
      return def
    }
  }
}
