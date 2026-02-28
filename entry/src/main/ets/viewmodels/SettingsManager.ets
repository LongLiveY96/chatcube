import { ConfigurationConstant } from '@kit.AbilityKit'
import { getPreferencesService, ThemeMode, AppLanguage } from '../services/PreferencesService'
import { ColorTheme, ThemeColorConfig } from '../models/ThemeColors'
import { getThemeService } from '../services/ThemeService'

// 设置变化回调接口
export interface SettingsChangeCallback {
  onThemeModeChanged: (mode: ThemeMode, colorMode: ConfigurationConstant.ColorMode) => void
  onLanguageChanged: (language: AppLanguage) => void
  onColorThemeChanged?: (theme: ColorTheme, colors: ThemeColorConfig) => void
  onNotificationSettingsChanged?: (enabled: boolean, notifyOnComplete: boolean, notifyOnFailed: boolean) => void
}

// 设置管理器 - 单例模式
export class SettingsManager {
  private static instance: SettingsManager | null = null
  private currentThemeMode: ThemeMode = ThemeMode.SYSTEM
  private currentLanguage: AppLanguage = AppLanguage.SYSTEM
  private notificationEnabled: boolean = true
  private notifyOnComplete: boolean = true
  private notifyOnFailed: boolean = true
  private callbacks: SettingsChangeCallback[] = []
  private isInitialized: boolean = false
  private initPromise: Promise<void> | null = null

  private constructor() {
  }

  static getInstance(): SettingsManager {
    if (SettingsManager.instance === null) {
      SettingsManager.instance = new SettingsManager()
    }
    return SettingsManager.instance
  }

  // 初始化设置
  async initialize(): Promise<void> {
    if (this.isInitialized) {
      return
    }

    if (this.initPromise !== null) {
      return this.initPromise
    }

    this.initPromise = this.doInitialize()
    return this.initPromise
  }

  private async doInitialize(): Promise<void> {
    const preferencesService = getPreferencesService()
    this.currentThemeMode = await preferencesService.getThemeMode()
    this.currentLanguage = await preferencesService.getLanguage()
    this.notificationEnabled = await preferencesService.getNotifyEnabled()
    this.notifyOnComplete = await preferencesService.getNotifyOnComplete()
    this.notifyOnFailed = await preferencesService.getNotifyOnFailed()
    this.isInitialized = true
  }

  // 重新加载设置（导入后刷新用）
  async reload(): Promise<void> {
    const preferencesService = getPreferencesService()
    this.currentThemeMode = await preferencesService.getThemeMode()
    this.currentLanguage = await preferencesService.getLanguage()
    this.notificationEnabled = await preferencesService.getNotifyEnabled()
    this.notifyOnComplete = await preferencesService.getNotifyOnComplete()
    this.notifyOnFailed = await preferencesService.getNotifyOnFailed()
  }

  // 等待初始化完成
  async waitForInitialization(): Promise<void> {
    if (this.isInitialized) {
      return
    }
    if (this.initPromise !== null) {
      return this.initPromise
    }
    // 如果还没开始初始化，等待一小段时间后重试
    return new Promise((resolve) => {
      const checkInit = (): void => {
        if (this.isInitialized) {
          resolve()
        } else {
          setTimeout(checkInit, 50)
        }
      }
      checkInit()
    })
  }

  // 注册设置变化回调
  registerCallback(callback: SettingsChangeCallback): void {
    this.callbacks.push(callback)
  }

  // 取消注册回调
  unregisterCallback(callback: SettingsChangeCallback): void {
    const index = this.callbacks.indexOf(callback)
    if (index >= 0) {
      this.callbacks.splice(index, 1)
    }
  }

  // 获取当前主题模式
  getThemeMode(): ThemeMode {
    return this.currentThemeMode
  }

  // 设置主题模式
  async setThemeMode(mode: ThemeMode): Promise<void> {
    if (this.currentThemeMode === mode) {
      return
    }

    this.currentThemeMode = mode
    await getPreferencesService().setThemeMode(mode)

    // 计算实际的颜色模式
    const colorMode = this.getColorModeFromTheme(mode)

    // 通知所有监听者
    for (let i = 0; i < this.callbacks.length; i++) {
      this.callbacks[i].onThemeModeChanged(mode, colorMode)
    }
  }

  // 根据主题模式获取系统颜色模式
  getColorModeFromTheme(mode: ThemeMode): ConfigurationConstant.ColorMode {
    if (mode === ThemeMode.LIGHT) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    } else if (mode === ThemeMode.DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    } else {
      return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    }
  }

  // 获取当前语言
  getLanguage(): AppLanguage {
    return this.currentLanguage
  }

  // 设置语言
  async setLanguage(language: AppLanguage): Promise<void> {
    if (this.currentLanguage === language) {
      return
    }

    this.currentLanguage = language
    await getPreferencesService().setLanguage(language)

    // 通知所有监听者
    for (let i = 0; i < this.callbacks.length; i++) {
      this.callbacks[i].onLanguageChanged(language)
    }
  }

  // 获取主题模式显示文本
  getThemeModeDisplayText(mode: ThemeMode): Resource {
    if (mode === ThemeMode.LIGHT) {
      return $r('app.string.theme_light')
    } else if (mode === ThemeMode.DARK) {
      return $r('app.string.theme_dark')
    } else {
      return $r('app.string.theme_system')
    }
  }

  // 获取语言显示文本
  getLanguageDisplayText(language: AppLanguage): Resource {
    if (language === AppLanguage.ZH_CN) {
      return $r('app.string.language_zh_cn')
    } else if (language === AppLanguage.EN_US) {
      return $r('app.string.language_en_us')
    } else {
      return $r('app.string.language_system')
    }
  }

  // ========== 通知设置相关方法 ==========

  getNotificationEnabled(): boolean {
    return this.notificationEnabled
  }

  getNotifyOnCompleteEnabled(): boolean {
    return this.notifyOnComplete
  }

  getNotifyOnFailedEnabled(): boolean {
    return this.notifyOnFailed
  }

  async setNotificationEnabled(enabled: boolean): Promise<void> {
    if (this.notificationEnabled === enabled) {
      return
    }

    this.notificationEnabled = enabled
    await getPreferencesService().setNotifyEnabled(enabled)
    this.notifyNotificationSettingsChanged()
  }

  async setNotifyOnCompleteEnabled(enabled: boolean): Promise<void> {
    if (this.notifyOnComplete === enabled) {
      return
    }

    this.notifyOnComplete = enabled
    await getPreferencesService().setNotifyOnComplete(enabled)
    this.notifyNotificationSettingsChanged()
  }

  async setNotifyOnFailedEnabled(enabled: boolean): Promise<void> {
    if (this.notifyOnFailed === enabled) {
      return
    }

    this.notifyOnFailed = enabled
    await getPreferencesService().setNotifyOnFailed(enabled)
    this.notifyNotificationSettingsChanged()
  }

  private notifyNotificationSettingsChanged(): void {
    for (let i = 0; i < this.callbacks.length; i++) {
      const callback = this.callbacks[i]
      if (callback.onNotificationSettingsChanged !== undefined) {
        callback.onNotificationSettingsChanged(
          this.notificationEnabled,
          this.notifyOnComplete,
          this.notifyOnFailed
        )
      }
    }
  }

  // ========== 主题配色相关方法 ==========

  // 获取当前主题配色
  getColorTheme(): ColorTheme {
    return getThemeService().getColorTheme()
  }

  // 设置主题配色
  async setColorTheme(theme: ColorTheme): Promise<void> {
    await getThemeService().setColorTheme(theme)

    // 通知所有监听者
    const colors = getThemeService().getCurrentColors()
    for (let i = 0; i < this.callbacks.length; i++) {
      const callback = this.callbacks[i]
      if (callback.onColorThemeChanged !== undefined) {
        callback.onColorThemeChanged(theme, colors)
      }
    }
  }

  // 获取主题配色显示文本
  getColorThemeDisplayText(theme: ColorTheme): Resource {
    if (theme === ColorTheme.DEFAULT) {
      return $r('app.string.theme_color_default')
    } else if (theme === ColorTheme.YUANBAO) {
      return $r('app.string.theme_color_yuanbao')
    } else if (theme === ColorTheme.CLAUDE) {
      return $r('app.string.theme_color_claude')
    } else if (theme === ColorTheme.CHATGPT) {
      return $r('app.string.theme_color_chatgpt')
    } else if (theme === ColorTheme.VIOLET) {
      return $r('app.string.theme_color_violet')
    } else if (theme === ColorTheme.MINT) {
      return $r('app.string.theme_color_mint')
    } else if (theme === ColorTheme.SUNSET) {
      return $r('app.string.theme_color_sunset')
    } else {
      return $r('app.string.theme_color_default')
    }
  }
}

// 导出单例获取方法
export function getSettingsManager(): SettingsManager {
  return SettingsManager.getInstance()
}
