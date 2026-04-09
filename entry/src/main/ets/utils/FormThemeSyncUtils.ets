import { Context, Want } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { formBindingData, formInfo, formProvider } from '@kit.FormKit'
import resourceManager from '@ohos.resourceManager'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { ColorTheme, ThemeColorConfig, getThemeColors } from '../models/ThemeColors'
import { getPreferencesService, PreferenceKeys, ThemeMode } from '../services/PreferencesService'

const FORM_IDS_PREF_KEY = 'entry_form_ids_json'
const PREFERENCES_NAME = 'chatbox_preferences'
const DEFAULT_THEME_PRIMARY = '#0A59F7'
const LIGHT_FORM_TEXT_COLOR = '#191919'
const DARK_FORM_TEXT_COLOR = '#F5F5F7'

class NewChatFormData {
  title: string = '新对话'
  subtitle: string = '点击开始聊天'
  themePrimary: string = DEFAULT_THEME_PRIMARY
  surfaceColor: string = '#FFFFFF'
  textPrimary: string = '#191919'
  textColor: string = ''
  glassBgColor: string = 'rgba(255,255,255,0.55)'
  shadowColor: string = 'rgba(0,0,0,0.1)'
  borderColor: string = 'rgba(255,255,255,0.2)'
}

function parseStoredFormIds(rawValue: string): string[] {
  try {
    const parsed = JSON.parse(rawValue) as Array<string>
    if (!Array.isArray(parsed)) {
      return []
    }
    const formIds: string[] = []
    for (let i = 0; i < parsed.length; i++) {
      const formId: string = parsed[i]
      if (formId !== '' && !formIds.includes(formId)) {
        formIds.push(formId)
      }
    }
    return formIds
  } catch (error) {
    console.error('FormThemeSyncUtils', `Failed to parse stored form ids: ${JSON.stringify(error)}`)
    return []
  }
}

async function getFormPreferences(context: Context): Promise<preferences.Preferences> {
  return await preferences.getPreferences(context, PREFERENCES_NAME)
}

async function readRegisteredFormIdsWithContext(context: Context): Promise<string[]> {
  const store = await getFormPreferences(context)
  const rawValue = await store.get(FORM_IDS_PREF_KEY, '[]') as string
  return parseStoredFormIds(rawValue)
}

async function writeRegisteredFormIds(context: Context, formIds: string[]): Promise<void> {
  const store = await getFormPreferences(context)
  await store.put(FORM_IDS_PREF_KEY, JSON.stringify(formIds))
  await store.flush()
}

export function readFormIdFromWant(want: Want): string {
  const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string | undefined
  return formId ?? ''
}

export function createNewChatFormBindingData(colors: ThemeColorConfig, isSystemDarkMode?: boolean): formBindingData.FormBindingData {
  const formData = new NewChatFormData()
  formData.themePrimary = colors.primary
  formData.surfaceColor = colors.surface
  formData.textPrimary = colors.textPrimary
  // 玻璃色跟随系统深浅色，不跟随应用主题
  if (isSystemDarkMode === true) {
    formData.textColor = DARK_FORM_TEXT_COLOR
    // 深色模式提高青色占比并略提不透明度，避免发灰。
    formData.glassBgColor = 'rgba(46,77,81,0.80)'
    formData.shadowColor = 'rgba(0,0,0,0.10)'
    formData.borderColor = 'rgba(226,242,244,0.14)'
  } else {
    formData.textColor = LIGHT_FORM_TEXT_COLOR
    // 浅色模式向运动健康的浅青玻璃靠近，同时避免纯白发飘。
    formData.glassBgColor = 'rgba(224,243,245,0.52)'
    formData.shadowColor = 'rgba(40,66,79,0.06)'
    formData.borderColor = 'rgba(255,255,255,0.78)'
  }
  return formBindingData.createFormBindingData(formData)
}

export async function registerThemeAwareFormId(context: Context, formId: string): Promise<void> {
  if (formId === '') {
    return
  }
  const formIds = await readRegisteredFormIdsWithContext(context)
  if (formIds.includes(formId)) {
    return
  }
  formIds.push(formId)
  await writeRegisteredFormIds(context, formIds)
}

export async function unregisterThemeAwareFormId(context: Context, formId: string): Promise<void> {
  if (formId === '') {
    return
  }
  const formIds = await readRegisteredFormIdsWithContext(context)
  const nextFormIds: string[] = []
  for (let i = 0; i < formIds.length; i++) {
    if (formIds[i] !== formId) {
      nextFormIds.push(formIds[i])
    }
  }
  await writeRegisteredFormIds(context, nextFormIds)
}

async function resolveWidgetIsDarkMode(context: Context): Promise<boolean> {
  const store = await getFormPreferences(context)
  const themeMode = await store.get(PreferenceKeys.THEME_MODE, ThemeMode.SYSTEM) as string
  if (themeMode === ThemeMode.DARK) {
    return true
  }
  if (themeMode === ThemeMode.LIGHT) {
    return false
  }
  const configuration = context.resourceManager.getConfigurationSync()
  return configuration.colorMode === resourceManager.ColorMode.DARK
}

export async function loadWidgetThemeColors(context: Context): Promise<ThemeColorConfig> {
  const store = await getFormPreferences(context)
  const themeId = await store.get(AppStorageKeys.COLOR_THEME, ColorTheme.DEFAULT) as string
  const isDarkMode = await resolveWidgetIsDarkMode(context)
  return getThemeColors(themeId as ColorTheme, isDarkMode)
}

export async function refreshThemeAwareForm(formId: string, colors: ThemeColorConfig, isSystemDarkMode?: boolean): Promise<void> {
  if (formId === '') {
    return
  }
  await formProvider.updateForm(formId, createNewChatFormBindingData(colors, isSystemDarkMode))
}

export async function refreshThemeAwareFormWithStoredTheme(context: Context, formId: string): Promise<void> {
  const colors = await loadWidgetThemeColors(context)
  const isSystemDarkMode = context.resourceManager.getConfigurationSync().colorMode === resourceManager.ColorMode.DARK
  await refreshThemeAwareForm(formId, colors, isSystemDarkMode)
}

export async function refreshAllThemeAwareForms(colors: ThemeColorConfig, isSystemDarkMode?: boolean): Promise<void> {
  const rawValue = await getPreferencesService().getString(FORM_IDS_PREF_KEY, '[]')
  const formIds = parseStoredFormIds(rawValue)
  for (let i = 0; i < formIds.length; i++) {
    try {
      await refreshThemeAwareForm(formIds[i], colors, isSystemDarkMode)
    } catch (error) {
      console.error('FormThemeSyncUtils', `Failed to refresh form ${formIds[i]}: ${JSON.stringify(error)}`)
    }
  }
}
