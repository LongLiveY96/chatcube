import { ColorTheme, ThemeColorConfig, getThemeColors, getThemeById, ThemeInfo, ALL_THEMES } from '../models/ThemeColors'
import { getPreferencesService } from './PreferencesService'
import { AppStorageKeys } from '../config/AppStorageKeys'

// 主题变化回调接口
export interface ThemeColorChangeCallback {
  onColorThemeChanged: (theme: ColorTheme, colors: ThemeColorConfig) => void
}

// AppStorage 中的主题颜色键名
export class ThemeStorageKeys {
  static readonly COLOR_THEME: string = AppStorageKeys.COLOR_THEME
  static readonly THEME_PRIMARY: string = AppStorageKeys.THEME_PRIMARY
  static readonly THEME_PRIMARY_LIGHT: string = AppStorageKeys.THEME_PRIMARY_LIGHT
  static readonly THEME_BACKGROUND: string = AppStorageKeys.THEME_BACKGROUND
  static readonly THEME_SURFACE: string = AppStorageKeys.THEME_SURFACE
  static readonly THEME_DIVIDER: string = AppStorageKeys.THEME_DIVIDER
  static readonly THEME_USER_BUBBLE: string = AppStorageKeys.THEME_USER_BUBBLE
  static readonly THEME_USER_BUBBLE_TEXT: string = AppStorageKeys.THEME_USER_BUBBLE_TEXT
  static readonly THEME_AI_BUBBLE: string = AppStorageKeys.THEME_AI_BUBBLE
  static readonly THEME_TEXT_PRIMARY: string = AppStorageKeys.THEME_TEXT_PRIMARY
  static readonly THEME_TEXT_SECONDARY: string = AppStorageKeys.THEME_TEXT_SECONDARY
  static readonly THEME_TEXT_TERTIARY: string = AppStorageKeys.THEME_TEXT_TERTIARY
  static readonly THEME_MARKDOWN_TITLE: string = AppStorageKeys.THEME_MARKDOWN_TITLE
  static readonly THEME_MARKDOWN_TEXT: string = AppStorageKeys.THEME_MARKDOWN_TEXT
  static readonly THEME_MARKDOWN_LINK: string = AppStorageKeys.THEME_MARKDOWN_LINK
  static readonly THEME_MARKDOWN_LINK_BG: string = AppStorageKeys.THEME_MARKDOWN_LINK_BG
  static readonly THEME_MARKDOWN_CODE_BG: string = AppStorageKeys.THEME_MARKDOWN_CODE_BG
  static readonly THEME_MARKDOWN_CODE_TEXT: string = AppStorageKeys.THEME_MARKDOWN_CODE_TEXT
  static readonly THEME_MARKDOWN_QUOTE_BG: string = AppStorageKeys.THEME_MARKDOWN_QUOTE_BG
  static readonly THEME_MARKDOWN_TABLE_BG: string = AppStorageKeys.THEME_MARKDOWN_TABLE_BG
  static readonly THEME_MARKDOWN_TABLE_HEADER_BG: string = AppStorageKeys.THEME_MARKDOWN_TABLE_HEADER_BG
  static readonly THEME_MARKDOWN_TABLE_ALT_BG: string = AppStorageKeys.THEME_MARKDOWN_TABLE_ALT_BG
  static readonly THEME_MARKDOWN_TABLE_BORDER: string = AppStorageKeys.THEME_MARKDOWN_TABLE_BORDER
}

// 偏好设置键名
const PREF_KEY_COLOR_THEME = AppStorageKeys.COLOR_THEME

// 主题服务 - 单例模式
export class ThemeService {
  private static instance: ThemeService | null = null
  private currentTheme: ColorTheme = ColorTheme.DEFAULT
  private currentIsDarkMode: boolean = false
  private callbacks: ThemeColorChangeCallback[] = []
  private isInitialized: boolean = false

  private constructor() {
  }

  static getInstance(): ThemeService {
    if (ThemeService.instance === null) {
      ThemeService.instance = new ThemeService()
    }
    return ThemeService.instance
  }

  // 初始化主题服务
  async initialize(isDarkMode: boolean): Promise<void> {
    if (this.isInitialized) {
      // 如果已初始化，只更新深浅模式
      if (this.currentIsDarkMode !== isDarkMode) {
        this.currentIsDarkMode = isDarkMode
        this.applyThemeToStorage()
        this.notifyCallbacks()
      }
      return
    }

    this.currentIsDarkMode = isDarkMode

    // 从偏好设置加载保存的主题
    const savedTheme = await getPreferencesService().getString(PREF_KEY_COLOR_THEME, ColorTheme.DEFAULT)
    this.currentTheme = savedTheme as ColorTheme

    // 验证主题是否有效
    const validTheme = getThemeById(this.currentTheme)
    if (validTheme.id !== this.currentTheme) {
      this.currentTheme = ColorTheme.DEFAULT
    }

    // 应用主题到 AppStorage
    this.applyThemeToStorage()

    this.isInitialized = true
    console.info('ThemeService', `Initialized with theme: ${this.currentTheme}, isDarkMode: ${isDarkMode}`)
  }

  // 获取当前主题
  getColorTheme(): ColorTheme {
    return this.currentTheme
  }

  // 获取当前主题信息
  getThemeInfo(): ThemeInfo {
    return getThemeById(this.currentTheme)
  }

  // 获取所有主题列表
  getAllThemes(): ThemeInfo[] {
    return ALL_THEMES
  }

  // 获取当前颜色配置
  getCurrentColors(): ThemeColorConfig {
    return getThemeColors(this.currentTheme, this.currentIsDarkMode)
  }

  // 设置主题
  async setColorTheme(theme: ColorTheme): Promise<void> {
    if (this.currentTheme === theme) {
      return
    }

    this.currentTheme = theme

    // 保存到偏好设置
    await getPreferencesService().setString(PREF_KEY_COLOR_THEME, theme)

    // 应用主题到 AppStorage
    this.applyThemeToStorage()

    // 通知回调
    this.notifyCallbacks()

    console.info('ThemeService', `Theme changed to: ${theme}`)
  }

  // 更新深浅模式（由系统或用户设置触发）
  updateDarkMode(isDarkMode: boolean): void {
    if (this.currentIsDarkMode === isDarkMode) {
      return
    }

    this.currentIsDarkMode = isDarkMode

    // 重新应用主题到 AppStorage
    this.applyThemeToStorage()

    // 通知回调
    this.notifyCallbacks()

    console.info('ThemeService', `Dark mode updated: ${isDarkMode}`)
  }

  // 注册主题变化回调
  registerCallback(callback: ThemeColorChangeCallback): void {
    this.callbacks.push(callback)
  }

  // 取消注册回调
  unregisterCallback(callback: ThemeColorChangeCallback): void {
    const index = this.callbacks.indexOf(callback)
    if (index >= 0) {
      this.callbacks.splice(index, 1)
    }
  }

  // 应用主题颜色到 AppStorage
  private applyThemeToStorage(): void {
    const colors = this.getCurrentColors()

    AppStorage.setOrCreate(ThemeStorageKeys.COLOR_THEME, this.currentTheme)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_PRIMARY, colors.primary)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_PRIMARY_LIGHT, colors.primaryLight)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_BACKGROUND, colors.background)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_SURFACE, colors.surface)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_DIVIDER, colors.divider)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_USER_BUBBLE, colors.userBubble)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_USER_BUBBLE_TEXT, colors.userBubbleText)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_AI_BUBBLE, colors.aiBubble)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_TEXT_PRIMARY, colors.textPrimary)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_TEXT_SECONDARY, colors.textSecondary)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_TEXT_TERTIARY, colors.textTertiary)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_MARKDOWN_TITLE, colors.markdownTitle)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_MARKDOWN_TEXT, colors.markdownText)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_MARKDOWN_LINK, colors.markdownLink)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_MARKDOWN_LINK_BG, colors.markdownLinkBg)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_MARKDOWN_CODE_BG, colors.markdownCodeBg)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_MARKDOWN_CODE_TEXT, colors.markdownCodeText)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_MARKDOWN_QUOTE_BG, colors.markdownQuoteBg)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_MARKDOWN_TABLE_BG, colors.markdownTableBg)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_MARKDOWN_TABLE_HEADER_BG, colors.markdownTableHeaderBg)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_MARKDOWN_TABLE_ALT_BG, colors.markdownTableAltBg)
    AppStorage.setOrCreate(ThemeStorageKeys.THEME_MARKDOWN_TABLE_BORDER, colors.markdownTableBorder)
  }

  // 通知所有回调
  private notifyCallbacks(): void {
    const colors = this.getCurrentColors()
    for (let i = 0; i < this.callbacks.length; i++) {
      this.callbacks[i].onColorThemeChanged(this.currentTheme, colors)
    }
  }
}

// 导出单例获取方法
export function getThemeService(): ThemeService {
  return ThemeService.getInstance()
}
