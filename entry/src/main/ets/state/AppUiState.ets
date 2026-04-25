import { AppStorageV2, UIUtils } from '@kit.ArkUI'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { ThemeColorConfig } from '../models/ThemeColors'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'

const APP_UI_STATE_KEY = 'chatbox_app_ui_state'

@ObservedV2
export class AppUiState {
  @Trace openNewChatTimestamp: number = 0
  @Trace openSessionPayload: string = ''
  @Trace sessionListRefreshAt: number = 0
  @Trace taskEventTick: number = 0
  @Trace inAppTaskAlertPayload: string = ''
  @Trace appInBackground: boolean = false
  @Trace activeChatSessionId: string = ''
  @Trace isDarkMode: boolean = false
  @Trace topAvoidHeight: number = 0
  @Trace bottomAvoidHeight: number = 0
  @Trace speakingMessageId: string = ''
  @Trace windowWidthVp: number = 0
  @Trace windowHeightVp: number = 0
  @Trace layoutSizeClass: string = LayoutSizeClass.COMPACT
  @Trace settingsDetailPresentationMode: string = SettingsPagePresentationMode.PAGE
  @Trace settingsHandAdaptiveChangedAt: number = 0
  @Trace colorTheme: string = ''
  @Trace themePrimary: string = '#0A59F7'
  @Trace themePrimaryLight: string = '#EDF4FF'
  @Trace themeBackground: string = '#F7F9FC'
  @Trace themeSurface: string = '#FFFFFF'
  @Trace themeDivider: string = '#E7EBF0'
  @Trace themeUserBubble: string = '#0B57D0'
  @Trace themeUserBubbleText: string = '#FFFFFF'
  @Trace themeAiBubble: string = '#FFFFFF'
  @Trace themeTextPrimary: string = '#1C1C1E'
  @Trace themeTextSecondary: string = '#6B7280'
  @Trace themeTextTertiary: string = '#8691A3'
  @Trace themeMarkdownTitle: string = '#1C1C1E'
  @Trace themeMarkdownText: string = '#333333'
  @Trace themeMarkdownLink: string = '#0A59F7'
  @Trace themeMarkdownLinkBg: string = '#EDF4FF'
  @Trace themeMarkdownCodeBg: string = '#F5F7FA'
  @Trace themeMarkdownCodeText: string = '#D63384'
  @Trace themeMarkdownQuoteBg: string = '#F5F7FA'
  @Trace themeMarkdownTableBg: string = '#FFFFFF'
  @Trace themeMarkdownTableHeaderBg: string = '#F5F7FA'
  @Trace themeMarkdownTableAltBg: string = '#FBFCFE'
  @Trace themeMarkdownTableBorder: string = '#E7EBF0'
  @Trace chatFontSize: number = 15
  @Trace chatInputEnterKeySend: boolean = false
  @Trace materialType: number = 100   // ADAPTIVE
  @Trace materialLevel: number = 10   // ADAPTIVE
  @Trace lightColorMode: string = 'default'
}

function readStorageValue<T>(key: string, fallback: T): T {
  const value = AppStorage.get<T>(key)
  if (value === undefined || value === null) {
    return fallback
  }
  return value
}

function applyAppUiStateValue<T extends string | number | boolean>(state: AppUiState, key: string, value: T): void {
  switch (key) {
    case AppStorageKeys.OPEN_NEW_CHAT:
      state.openNewChatTimestamp = value as number
      return
    case AppStorageKeys.OPEN_SESSION_PAYLOAD:
      state.openSessionPayload = value as string
      return
    case AppStorageKeys.SESSION_LIST_REFRESH_AT:
      state.sessionListRefreshAt = value as number
      return
    case AppStorageKeys.TASK_EVENT_TICK:
      state.taskEventTick = value as number
      return
    case AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD:
      state.inAppTaskAlertPayload = value as string
      return
    case AppStorageKeys.APP_IN_BACKGROUND:
      state.appInBackground = value as boolean
      return
    case AppStorageKeys.ACTIVE_CHAT_SESSION_ID:
      state.activeChatSessionId = value as string
      return
    case AppStorageKeys.IS_DARK_MODE:
      state.isDarkMode = value as boolean
      return
    case AppStorageKeys.TOP_AVOID_HEIGHT:
      state.topAvoidHeight = value as number
      return
    case AppStorageKeys.BOTTOM_AVOID_HEIGHT:
      state.bottomAvoidHeight = value as number
      return
    case AppStorageKeys.SPEAKING_MESSAGE_ID:
      state.speakingMessageId = value as string
      return
    case AppStorageKeys.WINDOW_WIDTH_VP:
      state.windowWidthVp = value as number
      return
    case AppStorageKeys.WINDOW_HEIGHT_VP:
      state.windowHeightVp = value as number
      return
    case AppStorageKeys.LAYOUT_SIZE_CLASS:
      state.layoutSizeClass = value as string
      return
    case AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE:
      state.settingsDetailPresentationMode = value as string
      return
    case AppStorageKeys.SETTINGS_HAND_ADAPTIVE_CHANGED_AT:
      state.settingsHandAdaptiveChangedAt = value as number
      return
    case AppStorageKeys.COLOR_THEME:
      state.colorTheme = value as string
      return
    case AppStorageKeys.THEME_PRIMARY:
      state.themePrimary = value as string
      return
    case AppStorageKeys.THEME_PRIMARY_LIGHT:
      state.themePrimaryLight = value as string
      return
    case AppStorageKeys.THEME_BACKGROUND:
      state.themeBackground = value as string
      return
    case AppStorageKeys.THEME_SURFACE:
      state.themeSurface = value as string
      return
    case AppStorageKeys.THEME_DIVIDER:
      state.themeDivider = value as string
      return
    case AppStorageKeys.THEME_USER_BUBBLE:
      state.themeUserBubble = value as string
      return
    case AppStorageKeys.THEME_USER_BUBBLE_TEXT:
      state.themeUserBubbleText = value as string
      return
    case AppStorageKeys.THEME_AI_BUBBLE:
      state.themeAiBubble = value as string
      return
    case AppStorageKeys.THEME_TEXT_PRIMARY:
      state.themeTextPrimary = value as string
      return
    case AppStorageKeys.THEME_TEXT_SECONDARY:
      state.themeTextSecondary = value as string
      return
    case AppStorageKeys.THEME_TEXT_TERTIARY:
      state.themeTextTertiary = value as string
      return
    case AppStorageKeys.THEME_MARKDOWN_TITLE:
      state.themeMarkdownTitle = value as string
      return
    case AppStorageKeys.THEME_MARKDOWN_TEXT:
      state.themeMarkdownText = value as string
      return
    case AppStorageKeys.THEME_MARKDOWN_LINK:
      state.themeMarkdownLink = value as string
      return
    case AppStorageKeys.THEME_MARKDOWN_LINK_BG:
      state.themeMarkdownLinkBg = value as string
      return
    case AppStorageKeys.THEME_MARKDOWN_CODE_BG:
      state.themeMarkdownCodeBg = value as string
      return
    case AppStorageKeys.THEME_MARKDOWN_CODE_TEXT:
      state.themeMarkdownCodeText = value as string
      return
    case AppStorageKeys.THEME_MARKDOWN_QUOTE_BG:
      state.themeMarkdownQuoteBg = value as string
      return
    case AppStorageKeys.THEME_MARKDOWN_TABLE_BG:
      state.themeMarkdownTableBg = value as string
      return
    case AppStorageKeys.THEME_MARKDOWN_TABLE_HEADER_BG:
      state.themeMarkdownTableHeaderBg = value as string
      return
    case AppStorageKeys.THEME_MARKDOWN_TABLE_ALT_BG:
      state.themeMarkdownTableAltBg = value as string
      return
    case AppStorageKeys.THEME_MARKDOWN_TABLE_BORDER:
      state.themeMarkdownTableBorder = value as string
      return
    case AppStorageKeys.CHAT_FONT_SIZE:
      state.chatFontSize = value as number
      return
    case AppStorageKeys.CHAT_INPUT_ENTER_KEY_SEND:
      state.chatInputEnterKeySend = value as boolean
      return
    case AppStorageKeys.MATERIAL_TYPE:
      state.materialType = value as number
      return
    case AppStorageKeys.MATERIAL_LEVEL:
      state.materialLevel = value as number
      return
    case AppStorageKeys.LIGHT_COLOR_MODE:
      state.lightColorMode = value as string
      return
    default:
      return
  }
}

function createAppUiStateFromStorage(): AppUiState {
  const state = new AppUiState()
  applyAppUiStateValue(state, AppStorageKeys.OPEN_NEW_CHAT, readStorageValue<number>(AppStorageKeys.OPEN_NEW_CHAT, 0))
  applyAppUiStateValue(state, AppStorageKeys.OPEN_SESSION_PAYLOAD,
    readStorageValue<string>(AppStorageKeys.OPEN_SESSION_PAYLOAD, ''))
  applyAppUiStateValue(state, AppStorageKeys.SESSION_LIST_REFRESH_AT,
    readStorageValue<number>(AppStorageKeys.SESSION_LIST_REFRESH_AT, 0))
  applyAppUiStateValue(state, AppStorageKeys.TASK_EVENT_TICK, readStorageValue<number>(AppStorageKeys.TASK_EVENT_TICK, 0))
  applyAppUiStateValue(state, AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD,
    readStorageValue<string>(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, ''))
  applyAppUiStateValue(state, AppStorageKeys.APP_IN_BACKGROUND,
    readStorageValue<boolean>(AppStorageKeys.APP_IN_BACKGROUND, false))
  applyAppUiStateValue(state, AppStorageKeys.ACTIVE_CHAT_SESSION_ID,
    readStorageValue<string>(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, ''))
  applyAppUiStateValue(state, AppStorageKeys.IS_DARK_MODE, readStorageValue<boolean>(AppStorageKeys.IS_DARK_MODE, false))
  applyAppUiStateValue(state, AppStorageKeys.TOP_AVOID_HEIGHT, readStorageValue<number>(AppStorageKeys.TOP_AVOID_HEIGHT, 0))
  applyAppUiStateValue(state, AppStorageKeys.BOTTOM_AVOID_HEIGHT,
    readStorageValue<number>(AppStorageKeys.BOTTOM_AVOID_HEIGHT, 0))
  applyAppUiStateValue(state, AppStorageKeys.SPEAKING_MESSAGE_ID,
    readStorageValue<string>(AppStorageKeys.SPEAKING_MESSAGE_ID, ''))
  applyAppUiStateValue(state, AppStorageKeys.WINDOW_WIDTH_VP, readStorageValue<number>(AppStorageKeys.WINDOW_WIDTH_VP, 0))
  applyAppUiStateValue(state, AppStorageKeys.WINDOW_HEIGHT_VP,
    readStorageValue<number>(AppStorageKeys.WINDOW_HEIGHT_VP, 0))
  applyAppUiStateValue(state, AppStorageKeys.LAYOUT_SIZE_CLASS,
    readStorageValue<string>(AppStorageKeys.LAYOUT_SIZE_CLASS, LayoutSizeClass.COMPACT))
  applyAppUiStateValue(state, AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE,
    readStorageValue<string>(AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE, SettingsPagePresentationMode.PAGE))
  applyAppUiStateValue(state, AppStorageKeys.SETTINGS_HAND_ADAPTIVE_CHANGED_AT,
    readStorageValue<number>(AppStorageKeys.SETTINGS_HAND_ADAPTIVE_CHANGED_AT, 0))
  applyAppUiStateValue(state, AppStorageKeys.COLOR_THEME, readStorageValue<string>(AppStorageKeys.COLOR_THEME, ''))
  applyAppUiStateValue(state, AppStorageKeys.THEME_PRIMARY,
    readStorageValue<string>(AppStorageKeys.THEME_PRIMARY, state.themePrimary))
  applyAppUiStateValue(state, AppStorageKeys.THEME_PRIMARY_LIGHT,
    readStorageValue<string>(AppStorageKeys.THEME_PRIMARY_LIGHT, state.themePrimaryLight))
  applyAppUiStateValue(state, AppStorageKeys.THEME_BACKGROUND,
    readStorageValue<string>(AppStorageKeys.THEME_BACKGROUND, state.themeBackground))
  applyAppUiStateValue(state, AppStorageKeys.THEME_SURFACE,
    readStorageValue<string>(AppStorageKeys.THEME_SURFACE, state.themeSurface))
  applyAppUiStateValue(state, AppStorageKeys.THEME_DIVIDER,
    readStorageValue<string>(AppStorageKeys.THEME_DIVIDER, state.themeDivider))
  applyAppUiStateValue(state, AppStorageKeys.THEME_USER_BUBBLE,
    readStorageValue<string>(AppStorageKeys.THEME_USER_BUBBLE, state.themeUserBubble))
  applyAppUiStateValue(state, AppStorageKeys.THEME_USER_BUBBLE_TEXT,
    readStorageValue<string>(AppStorageKeys.THEME_USER_BUBBLE_TEXT, state.themeUserBubbleText))
  applyAppUiStateValue(state, AppStorageKeys.THEME_AI_BUBBLE,
    readStorageValue<string>(AppStorageKeys.THEME_AI_BUBBLE, state.themeAiBubble))
  applyAppUiStateValue(state, AppStorageKeys.THEME_TEXT_PRIMARY,
    readStorageValue<string>(AppStorageKeys.THEME_TEXT_PRIMARY, state.themeTextPrimary))
  applyAppUiStateValue(state, AppStorageKeys.THEME_TEXT_SECONDARY,
    readStorageValue<string>(AppStorageKeys.THEME_TEXT_SECONDARY, state.themeTextSecondary))
  applyAppUiStateValue(state, AppStorageKeys.THEME_TEXT_TERTIARY,
    readStorageValue<string>(AppStorageKeys.THEME_TEXT_TERTIARY, state.themeTextTertiary))
  applyAppUiStateValue(state, AppStorageKeys.THEME_MARKDOWN_TITLE,
    readStorageValue<string>(AppStorageKeys.THEME_MARKDOWN_TITLE, state.themeMarkdownTitle))
  applyAppUiStateValue(state, AppStorageKeys.THEME_MARKDOWN_TEXT,
    readStorageValue<string>(AppStorageKeys.THEME_MARKDOWN_TEXT, state.themeMarkdownText))
  applyAppUiStateValue(state, AppStorageKeys.THEME_MARKDOWN_LINK,
    readStorageValue<string>(AppStorageKeys.THEME_MARKDOWN_LINK, state.themeMarkdownLink))
  applyAppUiStateValue(state, AppStorageKeys.THEME_MARKDOWN_LINK_BG,
    readStorageValue<string>(AppStorageKeys.THEME_MARKDOWN_LINK_BG, state.themeMarkdownLinkBg))
  applyAppUiStateValue(state, AppStorageKeys.THEME_MARKDOWN_CODE_BG,
    readStorageValue<string>(AppStorageKeys.THEME_MARKDOWN_CODE_BG, state.themeMarkdownCodeBg))
  applyAppUiStateValue(state, AppStorageKeys.THEME_MARKDOWN_CODE_TEXT,
    readStorageValue<string>(AppStorageKeys.THEME_MARKDOWN_CODE_TEXT, state.themeMarkdownCodeText))
  applyAppUiStateValue(state, AppStorageKeys.THEME_MARKDOWN_QUOTE_BG,
    readStorageValue<string>(AppStorageKeys.THEME_MARKDOWN_QUOTE_BG, state.themeMarkdownQuoteBg))
  applyAppUiStateValue(state, AppStorageKeys.THEME_MARKDOWN_TABLE_BG,
    readStorageValue<string>(AppStorageKeys.THEME_MARKDOWN_TABLE_BG, state.themeMarkdownTableBg))
  applyAppUiStateValue(state, AppStorageKeys.THEME_MARKDOWN_TABLE_HEADER_BG,
    readStorageValue<string>(AppStorageKeys.THEME_MARKDOWN_TABLE_HEADER_BG, state.themeMarkdownTableHeaderBg))
  applyAppUiStateValue(state, AppStorageKeys.THEME_MARKDOWN_TABLE_ALT_BG,
    readStorageValue<string>(AppStorageKeys.THEME_MARKDOWN_TABLE_ALT_BG, state.themeMarkdownTableAltBg))
  applyAppUiStateValue(state, AppStorageKeys.THEME_MARKDOWN_TABLE_BORDER,
    readStorageValue<string>(AppStorageKeys.THEME_MARKDOWN_TABLE_BORDER, state.themeMarkdownTableBorder))
  applyAppUiStateValue(state, AppStorageKeys.CHAT_FONT_SIZE, readStorageValue<number>(AppStorageKeys.CHAT_FONT_SIZE, 15))
  applyAppUiStateValue(state, AppStorageKeys.CHAT_INPUT_ENTER_KEY_SEND,
    readStorageValue<boolean>(AppStorageKeys.CHAT_INPUT_ENTER_KEY_SEND, false))
  applyAppUiStateValue(state, AppStorageKeys.MATERIAL_TYPE,
    readStorageValue<number>(AppStorageKeys.MATERIAL_TYPE, 100))
  applyAppUiStateValue(state, AppStorageKeys.MATERIAL_LEVEL,
    readStorageValue<number>(AppStorageKeys.MATERIAL_LEVEL, 10))
  applyAppUiStateValue(state, AppStorageKeys.LIGHT_COLOR_MODE,
    readStorageValue<string>(AppStorageKeys.LIGHT_COLOR_MODE, 'default'))
  return state
}

export function getAppUiState(): AppUiState {
  return AppStorageV2.connect(AppUiState, APP_UI_STATE_KEY, createAppUiStateFromStorage) ?? createAppUiStateFromStorage()
}

export function setAppUiStateValue<T extends string | number | boolean>(key: string, value: T): void {
  AppStorage.setOrCreate(key, value)
  applyAppUiStateValue(getAppUiState(), key, value)
}

export function syncAppUiStateFromStorage(): void {
  const state = getAppUiState()
  const freshState = createAppUiStateFromStorage()
  state.openNewChatTimestamp = freshState.openNewChatTimestamp
  state.openSessionPayload = freshState.openSessionPayload
  state.sessionListRefreshAt = freshState.sessionListRefreshAt
  state.taskEventTick = freshState.taskEventTick
  state.inAppTaskAlertPayload = freshState.inAppTaskAlertPayload
  state.appInBackground = freshState.appInBackground
  state.activeChatSessionId = freshState.activeChatSessionId
  state.isDarkMode = freshState.isDarkMode
  state.topAvoidHeight = freshState.topAvoidHeight
  state.bottomAvoidHeight = freshState.bottomAvoidHeight
  state.speakingMessageId = freshState.speakingMessageId
  state.windowWidthVp = freshState.windowWidthVp
  state.windowHeightVp = freshState.windowHeightVp
  state.layoutSizeClass = freshState.layoutSizeClass
  state.settingsDetailPresentationMode = freshState.settingsDetailPresentationMode
  state.settingsHandAdaptiveChangedAt = freshState.settingsHandAdaptiveChangedAt
  state.colorTheme = freshState.colorTheme
  state.themePrimary = freshState.themePrimary
  state.themePrimaryLight = freshState.themePrimaryLight
  state.themeBackground = freshState.themeBackground
  state.themeSurface = freshState.themeSurface
  state.themeDivider = freshState.themeDivider
  state.themeUserBubble = freshState.themeUserBubble
  state.themeUserBubbleText = freshState.themeUserBubbleText
  state.themeAiBubble = freshState.themeAiBubble
  state.themeTextPrimary = freshState.themeTextPrimary
  state.themeTextSecondary = freshState.themeTextSecondary
  state.themeTextTertiary = freshState.themeTextTertiary
  state.themeMarkdownTitle = freshState.themeMarkdownTitle
  state.themeMarkdownText = freshState.themeMarkdownText
  state.themeMarkdownLink = freshState.themeMarkdownLink
  state.themeMarkdownLinkBg = freshState.themeMarkdownLinkBg
  state.themeMarkdownCodeBg = freshState.themeMarkdownCodeBg
  state.themeMarkdownCodeText = freshState.themeMarkdownCodeText
  state.themeMarkdownQuoteBg = freshState.themeMarkdownQuoteBg
  state.themeMarkdownTableBg = freshState.themeMarkdownTableBg
  state.themeMarkdownTableHeaderBg = freshState.themeMarkdownTableHeaderBg
  state.themeMarkdownTableAltBg = freshState.themeMarkdownTableAltBg
  state.themeMarkdownTableBorder = freshState.themeMarkdownTableBorder
  state.chatFontSize = freshState.chatFontSize
  state.chatInputEnterKeySend = freshState.chatInputEnterKeySend
  state.materialType = freshState.materialType
  state.materialLevel = freshState.materialLevel
  state.lightColorMode = freshState.lightColorMode
}

export function applyThemeToAppUiState(themeId: string, colors: ThemeColorConfig): void {
  setAppUiStateValue(AppStorageKeys.COLOR_THEME, themeId)
  setAppUiStateValue(AppStorageKeys.THEME_PRIMARY, colors.primary)
  setAppUiStateValue(AppStorageKeys.THEME_PRIMARY_LIGHT, colors.primaryLight)
  setAppUiStateValue(AppStorageKeys.THEME_BACKGROUND, colors.background)
  setAppUiStateValue(AppStorageKeys.THEME_SURFACE, colors.surface)
  setAppUiStateValue(AppStorageKeys.THEME_DIVIDER, colors.divider)
  setAppUiStateValue(AppStorageKeys.THEME_USER_BUBBLE, colors.userBubble)
  setAppUiStateValue(AppStorageKeys.THEME_USER_BUBBLE_TEXT, colors.userBubbleText)
  setAppUiStateValue(AppStorageKeys.THEME_AI_BUBBLE, colors.aiBubble)
  setAppUiStateValue(AppStorageKeys.THEME_TEXT_PRIMARY, colors.textPrimary)
  setAppUiStateValue(AppStorageKeys.THEME_TEXT_SECONDARY, colors.textSecondary)
  setAppUiStateValue(AppStorageKeys.THEME_TEXT_TERTIARY, colors.textTertiary)
  setAppUiStateValue(AppStorageKeys.THEME_MARKDOWN_TITLE, colors.markdownTitle)
  setAppUiStateValue(AppStorageKeys.THEME_MARKDOWN_TEXT, colors.markdownText)
  setAppUiStateValue(AppStorageKeys.THEME_MARKDOWN_LINK, colors.markdownLink)
  setAppUiStateValue(AppStorageKeys.THEME_MARKDOWN_LINK_BG, colors.markdownLinkBg)
  setAppUiStateValue(AppStorageKeys.THEME_MARKDOWN_CODE_BG, colors.markdownCodeBg)
  setAppUiStateValue(AppStorageKeys.THEME_MARKDOWN_CODE_TEXT, colors.markdownCodeText)
  setAppUiStateValue(AppStorageKeys.THEME_MARKDOWN_QUOTE_BG, colors.markdownQuoteBg)
  setAppUiStateValue(AppStorageKeys.THEME_MARKDOWN_TABLE_BG, colors.markdownTableBg)
  setAppUiStateValue(AppStorageKeys.THEME_MARKDOWN_TABLE_HEADER_BG, colors.markdownTableHeaderBg)
  setAppUiStateValue(AppStorageKeys.THEME_MARKDOWN_TABLE_ALT_BG, colors.markdownTableAltBg)
  setAppUiStateValue(AppStorageKeys.THEME_MARKDOWN_TABLE_BORDER, colors.markdownTableBorder)
}

function resolveAppUiStatePath(path: string): string {
  switch (path) {
    case AppStorageKeys.OPEN_NEW_CHAT:
      return 'openNewChatTimestamp'
    case AppStorageKeys.OPEN_SESSION_PAYLOAD:
      return 'openSessionPayload'
    case AppStorageKeys.SESSION_LIST_REFRESH_AT:
      return 'sessionListRefreshAt'
    case AppStorageKeys.TASK_EVENT_TICK:
      return 'taskEventTick'
    case AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD:
      return 'inAppTaskAlertPayload'
    case AppStorageKeys.APP_IN_BACKGROUND:
      return 'appInBackground'
    case AppStorageKeys.ACTIVE_CHAT_SESSION_ID:
      return 'activeChatSessionId'
    case AppStorageKeys.IS_DARK_MODE:
      return 'isDarkMode'
    case AppStorageKeys.TOP_AVOID_HEIGHT:
      return 'topAvoidHeight'
    case AppStorageKeys.BOTTOM_AVOID_HEIGHT:
      return 'bottomAvoidHeight'
    case AppStorageKeys.SPEAKING_MESSAGE_ID:
      return 'speakingMessageId'
    case AppStorageKeys.WINDOW_WIDTH_VP:
      return 'windowWidthVp'
    case AppStorageKeys.WINDOW_HEIGHT_VP:
      return 'windowHeightVp'
    case AppStorageKeys.LAYOUT_SIZE_CLASS:
      return 'layoutSizeClass'
    case AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE:
      return 'settingsDetailPresentationMode'
    case AppStorageKeys.SETTINGS_HAND_ADAPTIVE_CHANGED_AT:
      return 'settingsHandAdaptiveChangedAt'
    case AppStorageKeys.COLOR_THEME:
      return 'colorTheme'
    case AppStorageKeys.THEME_PRIMARY:
      return 'themePrimary'
    case AppStorageKeys.THEME_PRIMARY_LIGHT:
      return 'themePrimaryLight'
    case AppStorageKeys.THEME_BACKGROUND:
      return 'themeBackground'
    case AppStorageKeys.THEME_SURFACE:
      return 'themeSurface'
    case AppStorageKeys.THEME_DIVIDER:
      return 'themeDivider'
    case AppStorageKeys.THEME_USER_BUBBLE:
      return 'themeUserBubble'
    case AppStorageKeys.THEME_USER_BUBBLE_TEXT:
      return 'themeUserBubbleText'
    case AppStorageKeys.THEME_AI_BUBBLE:
      return 'themeAiBubble'
    case AppStorageKeys.THEME_TEXT_PRIMARY:
      return 'themeTextPrimary'
    case AppStorageKeys.THEME_TEXT_SECONDARY:
      return 'themeTextSecondary'
    case AppStorageKeys.THEME_TEXT_TERTIARY:
      return 'themeTextTertiary'
    case AppStorageKeys.THEME_MARKDOWN_TITLE:
      return 'themeMarkdownTitle'
    case AppStorageKeys.THEME_MARKDOWN_TEXT:
      return 'themeMarkdownText'
    case AppStorageKeys.THEME_MARKDOWN_LINK:
      return 'themeMarkdownLink'
    case AppStorageKeys.THEME_MARKDOWN_LINK_BG:
      return 'themeMarkdownLinkBg'
    case AppStorageKeys.THEME_MARKDOWN_CODE_BG:
      return 'themeMarkdownCodeBg'
    case AppStorageKeys.THEME_MARKDOWN_CODE_TEXT:
      return 'themeMarkdownCodeText'
    case AppStorageKeys.THEME_MARKDOWN_QUOTE_BG:
      return 'themeMarkdownQuoteBg'
    case AppStorageKeys.THEME_MARKDOWN_TABLE_BG:
      return 'themeMarkdownTableBg'
    case AppStorageKeys.THEME_MARKDOWN_TABLE_HEADER_BG:
      return 'themeMarkdownTableHeaderBg'
    case AppStorageKeys.THEME_MARKDOWN_TABLE_ALT_BG:
      return 'themeMarkdownTableAltBg'
    case AppStorageKeys.THEME_MARKDOWN_TABLE_BORDER:
      return 'themeMarkdownTableBorder'
    case AppStorageKeys.CHAT_FONT_SIZE:
      return 'chatFontSize'
    case AppStorageKeys.CHAT_INPUT_ENTER_KEY_SEND:
      return 'chatInputEnterKeySend'
    case AppStorageKeys.MATERIAL_TYPE:
      return 'materialType'
    case AppStorageKeys.MATERIAL_LEVEL:
      return 'materialLevel'
    case AppStorageKeys.LIGHT_COLOR_MODE:
      return 'lightColorMode'
    default:
      return path
  }
}

export function observeAppUiState(paths: string | string[], callback: () => void): () => void {
  const monitorPaths = Array.isArray(paths)
    ? paths.map((path: string): string => resolveAppUiStatePath(path))
    : resolveAppUiStatePath(paths)
  const monitorCallback = (_monitorValue: Object): void => {
    callback()
  }
  UIUtils.addMonitor(getAppUiState(), monitorPaths, monitorCallback)
  return (): void => {
    UIUtils.clearMonitor(getAppUiState(), monitorPaths, monitorCallback)
  }
}
