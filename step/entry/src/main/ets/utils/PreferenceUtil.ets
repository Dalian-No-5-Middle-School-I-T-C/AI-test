import { UIAbilityContext, getContext } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'

const PREFERENCES_NAME = 'ds_chat_prefs'

let appContext: UIAbilityContext | null = null
let prefInstance: preferences.Preferences | null = null

export function initAppContext(ability: any): void {
  appContext = getContext(ability) as UIAbilityContext
}

function getPref(): preferences.Preferences {
  if (prefInstance) return prefInstance
  if (!appContext) {
    throw new Error('AppContext not initialized, call initAppContext first')
  }
  prefInstance = preferences.getPreferencesSync(appContext, PREFERENCES_NAME)
  return prefInstance
}

export class PreferenceUtil {
  static setStringSync(key: string, value: string): void {
    getPref().putSync(key, value)
  }

  static getStringSync(key: string, def: string): string {
    try {
      return getPref().getSync(key, def)
    } catch (e) {
      return def
    }
  }
}
