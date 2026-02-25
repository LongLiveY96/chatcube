import { ColorTheme } from '../../models/ThemeColors'
import { SettingsSheetType } from './IndexPageTypes'

export function getSettingsSheetTitleText(sheetType: SettingsSheetType): Resource {
  if (sheetType === SettingsSheetType.THEME) {
    return $r('app.string.settings_dark_mode')
  }
  if (sheetType === SettingsSheetType.LANGUAGE) {
    return $r('app.string.settings_language')
  }
  if (sheetType === SettingsSheetType.COLOR_THEME) {
    return $r('app.string.settings_color_theme')
  }
  if (sheetType === SettingsSheetType.HAND_ADAPTIVE) {
    return $r('app.string.hand_adaptive_title')
  }
  if (sheetType === SettingsSheetType.NOTIFICATION) {
    return $r('app.string.settings_notifications')
  }
  return $r('app.string.tab_settings')
}

export function getColorThemeDisplayTextForIndex(theme: ColorTheme): Resource {
  if (theme === ColorTheme.DEFAULT) {
    return $r('app.string.theme_color_default')
  }
  if (theme === ColorTheme.YUANBAO) {
    return $r('app.string.theme_color_yuanbao')
  }
  if (theme === ColorTheme.CLAUDE) {
    return $r('app.string.theme_color_claude')
  }
  if (theme === ColorTheme.CHATGPT) {
    return $r('app.string.theme_color_chatgpt')
  }
  if (theme === ColorTheme.VIOLET) {
    return $r('app.string.theme_color_violet')
  }
  if (theme === ColorTheme.MINT) {
    return $r('app.string.theme_color_mint')
  }
  if (theme === ColorTheme.SUNSET) {
    return $r('app.string.theme_color_sunset')
  }
  return $r('app.string.theme_color_default')
}

export function getNotificationSummaryTextForIndex(notifyEnabled: boolean, notifyOnComplete: boolean,
  notifyOnFailed: boolean): Resource {
  if (!notifyEnabled) {
    return $r('app.string.notification_disabled')
  }
  if (notifyOnComplete && notifyOnFailed) {
    return $r('app.string.notification_summary_all')
  }
  if (notifyOnComplete) {
    return $r('app.string.notification_summary_complete')
  }
  if (notifyOnFailed) {
    return $r('app.string.notification_summary_failed')
  }
  return $r('app.string.notification_summary_none')
}
