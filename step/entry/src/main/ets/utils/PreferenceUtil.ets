import { UIAbility, Context } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'

const PREFS_NAME: string = 'ds_chat_prefs'

let ctx: Context | null = null
let pref: preferences.Preferences | null = null

export function setContext(c: Context): void {
  ctx = c
}

function getPref(): preferences.Preferences {
  if (pref) return pref
  if (!ctx) {
    throw new Error('Context not set')
  }
  pref = preferences.getPreferencesSync(ctx, PREFS_NAME)
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
