import { AppLanguage, ThemeMode } from '../../services/PreferencesService'
import { ColorTheme } from '../../models/ThemeColors'
import { SettingsManager } from '../../viewmodels/SettingsManager'

export class IndexSettingsSheetActionCallbacks {
  onSelectTheme: (mode: ThemeMode) => Promise<void> = async (_mode: ThemeMode): Promise<void> => {}
  onSelectLanguage: (language: AppLanguage) => Promise<void> = async (_language: AppLanguage): Promise<void> => {}
  onSelectColorTheme: (theme: ColorTheme) => void = (_theme: ColorTheme): void => {}
  onToggleHandAdaptiveEnabled: (value: boolean) => void = (_value: boolean): void => {}
  onToggleHandAdaptiveNewChat: (value: boolean) => void = (_value: boolean): void => {}
  onToggleNotifyEnabled: (value: boolean) => Promise<void> = async (_value: boolean): Promise<void> => {}
  onToggleNotifyOnComplete: (value: boolean) => Promise<void> = async (_value: boolean): Promise<void> => {}
  onToggleNotifyOnFailed: (value: boolean) => Promise<void> = async (_value: boolean): Promise<void> => {}
  onOpenSystemNotificationSettings: () => void = (): void => {}
}

export class IndexSettingsSheetCoordinatorBindOptions {
  onThemeModeUpdated: (mode: ThemeMode) => void = (_mode: ThemeMode): void => {}
  onLanguageUpdated: (language: AppLanguage) => void = (_language: AppLanguage): void => {}
  onCloseSheet: () => void = (): void => {}
  onColorThemeSelected: (theme: ColorTheme) => void = (_theme: ColorTheme): void => {}
  onHandAdaptiveEnabledChanged: (value: boolean) => void = (_value: boolean): void => {}
  onHandAdaptiveNewChatChanged: (value: boolean) => void = (_value: boolean): void => {}
  onNotifyEnabledUpdated: (value: boolean) => void = (_value: boolean): void => {}
  onNotifyOnCompleteUpdated: (value: boolean) => void = (_value: boolean): void => {}
  onNotifyOnFailedUpdated: (value: boolean) => void = (_value: boolean): void => {}
  onOpenSystemNotificationSettings: () => void = (): void => {}
}

export class IndexSettingsSheetCoordinator {
  private settingsManager: SettingsManager

  constructor(settingsManager: SettingsManager) {
    this.settingsManager = settingsManager
  }

  buildCallbacks(options: IndexSettingsSheetCoordinatorBindOptions): IndexSettingsSheetActionCallbacks {
    const callbacks = new IndexSettingsSheetActionCallbacks()

    callbacks.onSelectTheme = async (mode: ThemeMode): Promise<void> => {
      options.onThemeModeUpdated(mode)
      await this.settingsManager.setThemeMode(mode)
      options.onCloseSheet()
    }

    callbacks.onSelectLanguage = async (language: AppLanguage): Promise<void> => {
      options.onLanguageUpdated(language)
      await this.settingsManager.setLanguage(language)
      options.onCloseSheet()
    }

    callbacks.onSelectColorTheme = (theme: ColorTheme): void => {
      options.onColorThemeSelected(theme)
    }

    callbacks.onToggleHandAdaptiveEnabled = (value: boolean): void => {
      options.onHandAdaptiveEnabledChanged(value)
    }

    callbacks.onToggleHandAdaptiveNewChat = (value: boolean): void => {
      options.onHandAdaptiveNewChatChanged(value)
    }

    callbacks.onToggleNotifyEnabled = async (value: boolean): Promise<void> => {
      options.onNotifyEnabledUpdated(value)
      await this.settingsManager.setNotificationEnabled(value)
    }

    callbacks.onToggleNotifyOnComplete = async (value: boolean): Promise<void> => {
      options.onNotifyOnCompleteUpdated(value)
      await this.settingsManager.setNotifyOnCompleteEnabled(value)
    }

    callbacks.onToggleNotifyOnFailed = async (value: boolean): Promise<void> => {
      options.onNotifyOnFailedUpdated(value)
      await this.settingsManager.setNotifyOnFailedEnabled(value)
    }

    callbacks.onOpenSystemNotificationSettings = (): void => {
      options.onOpenSystemNotificationSettings()
    }

    return callbacks
  }
}
