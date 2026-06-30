import { Context } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'

interface Prefs {
  putSync(key: string, value: string): void
  getSync(key: string, def: string): string
}

const PREFS_NAME = 'ds_chat_prefs'

let ctx: Context | null = null
let pref: Prefs | null = null

export function setContext(c: Context): void {
  ctx = c
}

function getPref(): Prefs {
  if (pref != null) {
    return pref
  }
  if (ctx == null) {
    throw new Error('Context not set')
  }
  pref = preferences.getPreferencesSync(ctx, PREFS_NAME) as Prefs
  return pref
}

export class PreferenceUtil {
  static setString(key: string, value: string): void {
    getPref().putSync(key, value)
  }

  static getString(key: string, def: string): string {
    try {
      return getPref().getSync(key, def)
    } catch (err) {
      return def
    }
  }
}