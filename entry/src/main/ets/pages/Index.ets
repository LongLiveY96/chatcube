import { curves } from '@kit.ArkUI'
import { ConfigurationConstant, common } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { motion } from '@kit.MultimodalAwarenessKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { HdsTabs, HdsTabsController, HdsBarStyle, HdsTabsFloatingStyle } from '@kit.UIDesignKit'
import { ChatSession, ChatMessage } from '../models/ChatModels'
import { ChatViewModel } from '../viewmodels/ChatViewModel'
import { SettingsChangeCallback } from '../viewmodels/SettingsManager'
import { ThemeMode, AppLanguage, PreferenceKeys } from '../services/PreferencesService'
import { dismissActiveSnackBarOnBack, showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { MultiSelectToolbar } from '../components/MultiSelectToolbar'
import { SharePreviewSheet } from '../components/SharePreviewSheet'
import { ColorTheme, ThemeColorConfig } from '../models/ThemeColors'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { SettingsRouteName } from '../config/SettingsRouteName'
import {
  getCenteredPageMaxWidth,
  getIndexChatListPaneWidth,
  getIndexPageHorizontalPadding,
  LayoutSizeClass
} from '../config/LayoutProfile'
import { createButtonTouchHandler, getButtonAnimation, getButtonScale } from '../utils/ButtonAnimationUtils'
import {
  countSelectedIdsInCandidates,
  mergeSelectAllIds,
  removeCandidateIds,
  toggleSelectionById
} from '../utils/SelectionHelper'
import { ChatTaskStatus } from '../models/ChatTaskModels'
import {
  parseInAppTaskAlertPayload,
  parseOpenSessionPayload
} from '../utils/TaskAlertUtils'
import { IndexBottomTabItem } from '../components/index/IndexBottomTabItem'
import { IndexFilterBar } from '../components/index/IndexFilterBar'
import { IndexEmptyStateCard } from '../components/index/IndexEmptyStateCard'
import { IndexSettingsPanel } from '../components/index/IndexSettingsPanel'
import { IndexSettingsSheetContent } from '../components/index/IndexSettingsSheetContent'
import { IndexSessionListSection } from '../components/index/IndexSessionListSection'
import { SettingsSheetType, SessionFilterType, SessionGroupData } from './index/IndexPageTypes'
import { getFilteredSessionsForIndex, buildSessionGroupsForIndex } from './index/IndexSessionGroupHelper'
import { SessionListGroupViewModel, rebuildSessionListGroupViewModels } from './index/IndexSessionListDataSource'
import {
  getFabOffsetXForIndex,
  getFabOffsetYForIndex,
  INDEX_NEW_CHAT_FAB_BOTTOM_SPACING,
  INDEX_NEW_CHAT_FAB_SIZE,
  isHandAdaptiveActiveForIndex,
  shouldPlaceFabOnLeftForIndex
} from './index/IndexHandAdaptiveHelper'
import {
  getSettingsSheetTitleText
} from './index/IndexSettingsTextHelper'
import { ChatPageRouteParams } from './chat/ChatPageRouteTypes'
import {
  IndexSettingsSheetActionCallbacks
} from './index/IndexSettingsSheetCoordinator'
import {
  normalizeSystemPromptTemplate,
  SystemPromptTemplateDefaults
} from '../utils/SystemPromptTemplateUtils'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState, observeAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { tryHandleProviderDetailInternalBack } from '../components/ProviderDetailSheet'
import { tryHandleModelManageInternalBack } from './ModelManagePage'
import { getCompactTabsBarHeightForIndex } from '../utils/SettingsPageLayoutHelper'

@Entry
@ComponentV2
struct Index {
  private static readonly COMPACT_TABS_FLOATING_SIDE_MARGIN: number = 12
  private static readonly COMPACT_TABS_FLOATING_BOTTOM_MARGIN: number = 8
  @Local currentTabIndex: number = 1
  @Local sessions: ChatSession[] = []
  @Local isLoading: boolean = false
  @Local currentThemeMode: ThemeMode = ThemeMode.SYSTEM
  @Local currentLanguage: AppLanguage = AppLanguage.SYSTEM
  @Local notifyEnabled: boolean = true
  @Local notifyOnComplete: boolean = true
  @Local notifyOnFailed: boolean = true
  @Local handAdaptiveEnabled: boolean = false
  @Local handAdaptiveNewChat: boolean = false
  @Local handAdaptiveUnsupported: boolean = false
  private get handAdaptiveSettingsChangedAt(): number {
    return getAppUiState().settingsHandAdaptiveChangedAt
  }
  @Local currentHoldingHand: motion.HoldingHandStatus = motion.HoldingHandStatus.UNKNOWN_STATUS
  @Local fabPressed: boolean = false
  @Local currentColorTheme: ColorTheme = ColorTheme.DEFAULT
  @Local showSettingsSheet: boolean = false
  @Local activeSettingsSheetType: SettingsSheetType = SettingsSheetType.NONE
  @Local showSystemPromptSheet: boolean = false
  @Local customSystemPrompt: string = ''
  @Local searchText: string = ''
  @Local isSearchExpanded: boolean = false
  @Local currentSessionFilter: SessionFilterType = SessionFilterType.ALL
  @Local compactChatHeaderHeight: number = 0
  @Local tabletDetailSessionId: string = ''
  private get activeChatSessionId(): string {
    return getAppUiState().activeChatSessionId
  }
  // 避让区域高度
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get bottomAvoidHeight(): number {
    return getAppUiState().bottomAvoidHeight
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  // 主题颜色
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get sessionListThemeRenderKey(): string {
    const uiState = getAppUiState()
    return `${this.currentColorTheme}_${uiState.isDarkMode ? '1' : '0'}`
  }
  @Local chatFontSize: number = 15
  // 监听从服务卡片打开新聊天的事件
  private get openNewChatTimestamp(): number {
    return getAppUiState().openNewChatTimestamp
  }
  private get openSessionPayload(): string {
    return getAppUiState().openSessionPayload
  }
  private get taskEventTick(): number {
    return getAppUiState().taskEventTick
  }
  @Computed
  get inAppTaskAlertPayload(): string {
    return getAppUiState().inAppTaskAlertPayload
  }

  @Monitor('inAppTaskAlertPayload')
  onInAppAlertPayloadMonitor(): void {
    const payload = this.inAppTaskAlertPayload
    if (payload === '') {
      return
    }
    this.handleInAppTaskAlertPayload(payload)
  }
  @Local filteredSessionCount: number = 0
  @Local sessionListGroups: SessionListGroupViewModel[] = []
  // 监听会话列表刷新信号（标题更新、创建、删除等）
  @Computed
  get sessionListRefreshAt(): number {
    return getAppUiState().sessionListRefreshAt
  }

  @Monitor('sessionListRefreshAt')
  onSessionListRefreshMonitor(): void {
    this.onSessionListRefresh()
  }
  @Monitor('isMultiSelectMode')
  onMultiSelectModeMonitor(): void {
    this.compactChatHeaderHeight = 0
  }
  // 多选模式状态
  @Local isMultiSelectMode: boolean = false
  @Local selectedSessionIds: Array<string> = []
  // 分享预览弹窗状态
  @Local showSharePreview: boolean = false
  @Local shareMessages: ChatMessage[] = []
  // Settings Sheet 关闭动画期间的状态机（避免“关闭回调晚到”误关新弹窗）
  private settingsSheetClosing: boolean = false
  private pendingSettingsSheetType: SettingsSheetType = SettingsSheetType.NONE
  private compactTabsController: HdsTabsController = new HdsTabsController()
  @Local compactTabsBarStyle: HdsBarStyle = HdsBarStyle.EXPAND
  private navPathStack: NavPathStack = new NavPathStack()
  private tabletChatDetailPathStack: NavPathStack = new NavPathStack()
  private settingsNavPathStack: NavPathStack = new NavPathStack()
  private currentTabletDetailParams: ChatPageRouteParams | null = null
  @Local currentSettingsRouteName: string = ''
  // 返回键退出控制
  private lastBackPressTime: number = 0
  private chatViewModel: ChatViewModel = ServiceRegistry.chat()
  private settingsManager = ServiceRegistry.settings()
  private preferencesService = ServiceRegistry.preferences()
  private settingsCallback: SettingsChangeCallback | null = null
  private holdingHandSubscribed: boolean = false
  private handAdaptiveLoadSeq: number = 0
  private sessionLoadSeq: number = 0
  private appUiStateDisposers: Array<() => void> = []
  private searchInputFocusId: string = 'index_session_search_input'
  private holdingHandCallback: (status: motion.HoldingHandStatus) => void = (status: motion.HoldingHandStatus): void => {
    this.currentHoldingHand = status
  }

  private showIndexSnack(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  onLayoutSizeClassChanged(): void {
    if (this.currentTabIndex === 2 && this.settingsNavPathStack.size() > 0) {
      this.syncSettingsDetailPresentationMode()
    }
    if (this.isSettingsSplitMode()) {
      this.dismissSettingsSheetForNavigation()
      if (this.currentTabIndex === 2) {
        this.ensureSettingsSplitLandingRoute()
      }
      return
    }
    if (this.currentTabIndex === 1 && this.currentTabletDetailParams !== null && this.navPathStack.size() === 0) {
      const params = this.currentTabletDetailParams
      this.clearTabletChatDetail(false)
      this.navPathStack.pushPath({ name: 'ChatPage', param: params as ChatPageRouteParams })
      return
    }
    this.refreshSessionListProjection()
  }

  private isExpandedLayout(): boolean {
    return this.layoutSizeClass === LayoutSizeClass.EXPANDED
  }

  onWindowMetricsChanged(): void {
    if (this.currentTabIndex !== 2) {
      return
    }
    this.syncSettingsDetailPresentationMode()
    if (this.isSettingsSplitMode()) {
      this.dismissSettingsSheetForNavigation()
      this.ensureSettingsSplitLandingRoute()
    }
  }

  private isLandscapeWindow(): boolean {
    if (this.windowWidthVp <= 0 || this.windowHeightVp <= 0) {
      return false
    }
    return this.windowWidthVp > this.windowHeightVp
  }

  private getExpandedChatListWidth(): number {
    return getIndexChatListPaneWidth(this.windowWidthVp)
  }

  private getExpandedPageHorizontalPadding(): number {
    return getIndexPageHorizontalPadding(this.windowWidthVp)
  }

  private getExpandedCenterColumnMaxWidth(): number {
    return getCenteredPageMaxWidth(this.windowWidthVp)
  }

  private getExpandedSettingsListWidth(): number {
    return getIndexChatListPaneWidth(this.windowWidthVp)
  }

  private isSettingsSplitMode(): boolean {
    return this.isExpandedLayout() && this.isLandscapeWindow()
  }

  private syncSettingsDetailPresentationMode(): void {
    setAppUiStateValue(
      AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE,
      this.isSettingsSplitMode() ? SettingsPagePresentationMode.DETAIL_PANE : SettingsPagePresentationMode.PAGE
    )
  }

  private dismissSettingsSheetForNavigation(): void {
    this.pendingSettingsSheetType = SettingsSheetType.NONE
    if (this.showSettingsSheet) {
      this.settingsSheetClosing = true
      this.showSettingsSheet = false
      return
    }
    if (!this.settingsSheetClosing) {
      this.activeSettingsSheetType = SettingsSheetType.NONE
    }
  }

  private openSettingsPanelEntry(routeName: SettingsRouteName, sheetType: SettingsSheetType): void {
    if (this.isSettingsSplitMode()) {
      this.openSettingsDestination(routeName)
      return
    }
    this.openSettingsSheet(sheetType)
  }

  private getDefaultSettingsSplitRoute(): SettingsRouteName {
    return SettingsRouteName.MODEL_MANAGE
  }

  private ensureSettingsSplitLandingRoute(): void {
    if (!this.isSettingsSplitMode()) {
      return
    }
    if (this.currentSettingsRouteName !== '' || this.settingsNavPathStack.size() > 0) {
      return
    }
    const routeName = this.getDefaultSettingsSplitRoute()
    this.currentSettingsRouteName = routeName
    this.syncSettingsDetailPresentationMode()
    this.settingsNavPathStack.pushPath({ name: routeName })
  }

  private switchToTab(index: number, shouldEnsureSettingsSplitLanding: boolean = true): void {
    if (index !== 2) {
      this.dismissSettingsSheetForNavigation()
    }
    this.compactTabsBarStyle = HdsBarStyle.EXPAND
    this.currentTabIndex = index
    if (index === 1) {
      this.loadSessions()
      return
    }
    if (index === 2 && shouldEnsureSettingsSplitLanding) {
      setAppUiStateValue(
        AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE,
        this.isSettingsSplitMode() ? SettingsPagePresentationMode.DETAIL_PANE : SettingsPagePresentationMode.PAGE
      )
      this.ensureSettingsSplitLandingRoute()
    }
  }

  private openChatRoute(params: ChatPageRouteParams): void {
    this.switchToTab(1)
    if (this.isExpandedLayout()) {
      this.openTabletChatDetail(params)
      return
    }
    this.navPathStack.pushPath({ name: 'ChatPage', param: params as ChatPageRouteParams })
  }

  private openTabletChatDetail(params: ChatPageRouteParams): void {
    this.currentTabletDetailParams = params
    this.tabletDetailSessionId = params.sessionId ?? ''
    this.refreshSessionListProjection()
    if (this.tabletChatDetailPathStack.size() > 0) {
      this.tabletChatDetailPathStack.replacePath({ name: 'ChatPage', param: params as ChatPageRouteParams })
      return
    }
    this.tabletChatDetailPathStack.pushPath({ name: 'ChatPage', param: params as ChatPageRouteParams })
  }

  private clearTabletChatDetail(animated: boolean = false): void {
    if (this.tabletChatDetailPathStack.size() > 0) {
      this.tabletChatDetailPathStack.clear(animated)
    }
    this.currentTabletDetailParams = null
    this.tabletDetailSessionId = ''
    this.refreshSessionListProjection()
  }

  private openSettingsDestination(routeName: SettingsRouteName): void {
    this.switchToTab(2, false)
    this.dismissSettingsSheetForNavigation()
    this.currentSettingsRouteName = routeName
    this.syncSettingsDetailPresentationMode()
    if (this.isSettingsSplitMode() && this.settingsNavPathStack.size() > 0) {
      this.settingsNavPathStack.replacePath({ name: routeName })
      return
    }
    this.settingsNavPathStack.pushPath({ name: routeName })
  }

  private openPrivacyPolicy(): void {
    this.openSettingsDestination(SettingsRouteName.PRIVACY_POLICY)
  }

  private clearSettingsDestination(animated: boolean = false): void {
    if (this.settingsNavPathStack.size() > 0) {
      this.settingsNavPathStack.clear(animated)
    }
    this.currentSettingsRouteName = ''
    setAppUiStateValue(AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE, SettingsPagePresentationMode.PAGE)
  }

  onOpenNewChat(): void {
    if (this.openNewChatTimestamp > 0) {
      this.openChatRoute({} as ChatPageRouteParams)
    }
  }

  onOpenSessionPayloadChanged(): void {
    this.handleOpenSessionPayload(this.openSessionPayload)
  }

  onActiveChatSessionIdChanged(): void {
    this.refreshSessionListProjection()
  }

  onTaskEventTickChanged(): void {
    if (this.taskEventTick > 0) {
      this.loadSessions()
    }
  }

  onSessionListRefresh(): void {
    if (this.sessionListRefreshAt > 0) {
      this.loadSessions()
    }
  }

  onHandAdaptiveSettingsTickChanged(): void {
    if (this.handAdaptiveSettingsChangedAt > 0) {
      this.loadHandAdaptiveSettings()
    }
  }

  private registerAppUiStateObservers(): void {
    if (this.appUiStateDisposers.length > 0) {
      return
    }
    this.appUiStateDisposers = [
      observeAppUiState(AppStorageKeys.LAYOUT_SIZE_CLASS, (): void => this.onLayoutSizeClassChanged()),
      observeAppUiState([AppStorageKeys.WINDOW_WIDTH_VP, AppStorageKeys.WINDOW_HEIGHT_VP],
        (): void => this.onWindowMetricsChanged()),
      observeAppUiState(AppStorageKeys.OPEN_NEW_CHAT, (): void => this.onOpenNewChat()),
      observeAppUiState(AppStorageKeys.OPEN_SESSION_PAYLOAD, (): void => this.onOpenSessionPayloadChanged()),
      observeAppUiState(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, (): void => this.onActiveChatSessionIdChanged()),
      observeAppUiState(AppStorageKeys.TASK_EVENT_TICK, (): void => this.onTaskEventTickChanged()),
      observeAppUiState(AppStorageKeys.SETTINGS_HAND_ADAPTIVE_CHANGED_AT,
        (): void => this.onHandAdaptiveSettingsTickChanged())
    ]
  }

  private unregisterAppUiStateObservers(): void {
    for (let i = 0; i < this.appUiStateDisposers.length; i++) {
      this.appUiStateDisposers[i]()
    }
    this.appUiStateDisposers = []
  }

  aboutToAppear(): void {
    this.registerAppUiStateObservers()
    this.navPathStack.setInterception({
      didShow: (from: NavDestinationContext | "navBar", to: NavDestinationContext | "navBar",
        operation: NavigationOperation, isAnimated: boolean): void => {
        if (to === 'navBar') {
          // pop 完成，navPathStack.size() 已变为 0，loadSessions 不再跳过
          this.loadSessions()
          // 补偿 pop 动画期间被 shouldHandleInAppTaskAlert 拦截的 alert（直接处理，不走守卫）
          this.processInAppTaskAlertPayload(this.inAppTaskAlertPayload)
        }
      }
    })
    this.tabletChatDetailPathStack.setInterception({
      didShow: (from: NavDestinationContext | "navBar", to: NavDestinationContext | "navBar",
        operation: NavigationOperation, isAnimated: boolean): void => {
        if (to === 'navBar' || this.tabletChatDetailPathStack.size() <= 0) {
          this.currentTabletDetailParams = null
          this.tabletDetailSessionId = ''
          this.refreshSessionListProjection()
          this.processInAppTaskAlertPayload(this.inAppTaskAlertPayload)
          return
        }
        const topParam = this.tabletChatDetailPathStack.getParamByIndex(
          this.tabletChatDetailPathStack.size() - 1
        ) as ChatPageRouteParams | undefined
        this.currentTabletDetailParams = topParam ?? null
        this.tabletDetailSessionId = topParam?.sessionId ?? ''
        this.refreshSessionListProjection()
      }
    })
    this.settingsNavPathStack.setInterception({
      didShow: (from: NavDestinationContext | "navBar", to: NavDestinationContext | "navBar",
        operation: NavigationOperation, isAnimated: boolean): void => {
        if (to === 'navBar' || this.settingsNavPathStack.size() <= 0) {
          this.currentSettingsRouteName = ''
          setAppUiStateValue(AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE, SettingsPagePresentationMode.PAGE)
        }
      }
    })

    this.loadSessions()
    this.loadSettings()
    this.registerSettingsCallback()
    this.handleOpenSessionPayload(this.openSessionPayload)
    this.handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
  }

  onPageShow(): void {
    this.loadSessions()
    this.refreshSettingsState()
    this.loadHandAdaptiveSettings()
    this.processInAppTaskAlertPayload(this.inAppTaskAlertPayload)
  }

  aboutToDisappear(): void {
    this.unregisterAppUiStateObservers()
    this.unsubscribeHoldingHand()
    if (this.settingsCallback !== null) {
      this.settingsManager.unregisterCallback(this.settingsCallback)
      this.settingsCallback = null
    }
  }

  // 处理返回键/返回手势
  onBackPress(): boolean {
    // 如果分享预览弹窗打开，关闭弹窗
    if (this.showSharePreview) {
      this.showSharePreview = false
      return true
    }

    // 如果系统提示词弹窗打开，关闭弹窗
    if (this.showSystemPromptSheet) {
      this.showSystemPromptSheet = false
      return true
    }

    // 如果设置弹窗打开，关闭弹窗
    if (this.isAnySettingsSheetOpen()) {
      this.closeAllSettingsSheets()
      return true
    }

    if (this.currentTabIndex === 2 && this.settingsNavPathStack.size() > 0) {
      const topSettingsRouteName = this.getTopSettingsRouteName()
      if (topSettingsRouteName === 'ProviderDetailPage' && tryHandleProviderDetailInternalBack()) {
        return true
      }
      if (topSettingsRouteName === SettingsRouteName.MODEL_MANAGE &&
        tryHandleModelManageInternalBack()) {
        return true
      }
      if (this.isSettingsSplitMode()) {
        this.clearSettingsDestination(false)
      } else {
        this.settingsNavPathStack.pop()
      }
      return true
    }

    // 如果在多选模式，退出多选模式
    if (this.isMultiSelectMode) {
      this.handleExitMultiSelectMode()
      return true
    }

    // 如果搜索框展开，收起搜索框
    if (this.isSearchExpanded) {
      this.collapseSearch()
      return true
    }

    if (this.isExpandedLayout() && this.currentTabIndex === 1 && this.tabletChatDetailPathStack.size() > 0) {
      this.clearTabletChatDetail(false)
      return true
    }

    if (dismissActiveSnackBarOnBack()) {
      return true
    }

    // 双击返回退出应用
    const currentTime = Date.now()
    if (currentTime - this.lastBackPressTime < 2000) {
      // 两次返回间隔小于 2 秒，退出应用
      return false
    } else {
      // 第一次返回，提示再按一次退出
      this.lastBackPressTime = currentTime
      this.showIndexSnack($r('app.string.back_press_exit_hint'), 2000)
      return true
    }
  }

  private getTopSettingsRouteName(): string {
    const routeNames = this.settingsNavPathStack.getAllPathName()
    if (routeNames.length <= 0) {
      return ''
    }
    return routeNames[routeNames.length - 1]
  }

  private registerSettingsCallback(): void {
    if (this.settingsCallback !== null) {
      return
    }

    this.settingsCallback = {
      onThemeModeChanged: (mode: ThemeMode, _colorMode: ConfigurationConstant.ColorMode): void => {
        this.currentThemeMode = mode
        this.syncSettingsSummaryToStorage()
      },
      onLanguageChanged: (language: AppLanguage): void => {
        this.currentLanguage = language
        this.syncSettingsSummaryToStorage()
      },
      onColorThemeChanged: (theme: ColorTheme, _colors: ThemeColorConfig): void => {
        this.currentColorTheme = theme
        this.syncSettingsSummaryToStorage()
      },
      onNotificationSettingsChanged: (enabled: boolean, notifyOnComplete: boolean, notifyOnFailed: boolean): void => {
        this.notifyEnabled = enabled
        this.notifyOnComplete = notifyOnComplete
        this.notifyOnFailed = notifyOnFailed
        this.syncSettingsSummaryToStorage()
      },
      onChatFontSizeChanged: (size: number): void => {
        this.chatFontSize = size
        this.syncSettingsSummaryToStorage()
      }
    }
    this.settingsManager.registerCallback(this.settingsCallback)
  }

  async loadSettings(): Promise<void> {
    // 等待 SettingsManager 初始化完成
    await this.settingsManager.waitForInitialization()
    this.currentThemeMode = this.settingsManager.getThemeMode()
    this.currentLanguage = this.settingsManager.getLanguage()
    this.currentColorTheme = this.settingsManager.getColorTheme()
    this.notifyEnabled = this.settingsManager.getNotificationEnabled()
    this.notifyOnComplete = this.settingsManager.getNotifyOnCompleteEnabled()
    this.notifyOnFailed = this.settingsManager.getNotifyOnFailedEnabled()
    this.chatFontSize = this.settingsManager.getChatFontSize()
    await this.loadHandAdaptiveSettings()
    this.syncSettingsSummaryToStorage()
  }

  private refreshSettingsState(): void {
    this.currentThemeMode = this.settingsManager.getThemeMode()
    this.currentLanguage = this.settingsManager.getLanguage()
    this.currentColorTheme = this.settingsManager.getColorTheme()
    this.notifyEnabled = this.settingsManager.getNotificationEnabled()
    this.notifyOnComplete = this.settingsManager.getNotifyOnCompleteEnabled()
    this.notifyOnFailed = this.settingsManager.getNotifyOnFailedEnabled()
    this.chatFontSize = this.settingsManager.getChatFontSize()
    this.syncSettingsSummaryToStorage()
  }

  private syncSettingsSummaryToStorage(): void {
    AppStorage.setOrCreate('setting_theme_mode', this.currentThemeMode)
    AppStorage.setOrCreate('setting_language', this.currentLanguage)
    setAppUiStateValue(AppStorageKeys.COLOR_THEME, this.currentColorTheme)
    AppStorage.setOrCreate('setting_notify_enabled', this.notifyEnabled)
    AppStorage.setOrCreate('setting_notify_on_complete', this.notifyOnComplete)
    AppStorage.setOrCreate('setting_notify_on_failed', this.notifyOnFailed)
    AppStorage.setOrCreate(AppStorageKeys.SETTING_HAND_ADAPTIVE_ENABLED, this.handAdaptiveEnabled)
    AppStorage.setOrCreate(AppStorageKeys.SETTING_HAND_ADAPTIVE_NEW_CHAT, this.handAdaptiveNewChat)
    AppStorage.setOrCreate(AppStorageKeys.SETTING_HAND_ADAPTIVE_UNSUPPORTED, this.handAdaptiveUnsupported)
    setAppUiStateValue(AppStorageKeys.CHAT_FONT_SIZE, this.chatFontSize)
  }

  private async loadHandAdaptiveSettings(): Promise<void> {
    const seq = this.handAdaptiveLoadSeq + 1
    this.handAdaptiveLoadSeq = seq
    const enabled = await this.preferencesService.getBoolean(PreferenceKeys.HAND_ADAPTIVE_ENABLED, false)
    const newChatEnabled = await this.preferencesService.getBoolean(PreferenceKeys.HAND_ADAPTIVE_NEW_CHAT, enabled)
    if (seq !== this.handAdaptiveLoadSeq) {
      return
    }

    this.handAdaptiveEnabled = enabled
    if (!enabled) {
      this.handAdaptiveNewChat = false
      this.handAdaptiveUnsupported = false
      this.currentHoldingHand = motion.HoldingHandStatus.UNKNOWN_STATUS
    } else {
      this.handAdaptiveNewChat = newChatEnabled
    }

    this.updateHoldingHandSubscription()
    this.syncSettingsSummaryToStorage()
  }

  private isHandAdaptiveActive(): boolean {
    return isHandAdaptiveActiveForIndex(this.handAdaptiveEnabled, this.handAdaptiveNewChat)
  }

  private updateHoldingHandSubscription(): void {
    if (!this.isHandAdaptiveActive()) {
      this.unsubscribeHoldingHand()
      return
    }
    this.subscribeHoldingHand()
  }

  private subscribeHoldingHand(): void {
    if (this.holdingHandSubscribed || this.handAdaptiveUnsupported) {
      return
    }
    try {
      motion.on('holdingHandChanged', this.holdingHandCallback)
      this.holdingHandSubscribed = true
      this.currentHoldingHand = motion.HoldingHandStatus.UNKNOWN_STATUS
    } catch (err) {
      const error = err as BusinessError
      if (error.code === 801) {
        this.handAdaptiveUnsupported = true
      }
      console.error('Index', `Failed to subscribe holdingHandChanged, code: ${error.code}`)
      this.holdingHandSubscribed = false
      this.currentHoldingHand = motion.HoldingHandStatus.UNKNOWN_STATUS
    }
  }

  private unsubscribeHoldingHand(): void {
    if (!this.holdingHandSubscribed) {
      return
    }
    try {
      motion.off('holdingHandChanged', this.holdingHandCallback)
    } catch (err) {
      const error = err as BusinessError
      console.error('Index', `Failed to unsubscribe holdingHandChanged, code: ${error.code}`)
    }
    this.holdingHandSubscribed = false
    this.currentHoldingHand = motion.HoldingHandStatus.UNKNOWN_STATUS
  }

  private shouldPlaceFabOnLeft(): boolean {
    return shouldPlaceFabOnLeftForIndex(this.handAdaptiveEnabled, this.handAdaptiveNewChat, this.handAdaptiveUnsupported,
      this.currentHoldingHand)
  }

  private getFabOffsetX(): number {
    return getFabOffsetXForIndex(this.shouldPlaceFabOnLeft())
  }

  private getFabBaseBottomInset(): number {
    if (!this.isExpandedLayout()) {
      return this.getCompactTabsBottomInset()
    }
    return this.px2vp(this.bottomAvoidHeight)
  }

  private getChatListBottomSpacerHeight(): number {
    const cardBottomBreathingRoom = 12
    return this.getFabBaseBottomInset() + INDEX_NEW_CHAT_FAB_SIZE +
      INDEX_NEW_CHAT_FAB_BOTTOM_SPACING + cardBottomBreathingRoom
  }

  private getFabOffsetY(): number {
    return getFabOffsetYForIndex(this.getFabBaseBottomInset())
  }

  private getCompactChatHeaderDefaultHeight(): number {
    return this.px2vp(this.topAvoidHeight) + (this.isMultiSelectMode ? 56 : 92)
  }

  private getCompactChatHeaderOverlayHeight(): number {
    return this.compactChatHeaderHeight > 0 ? this.compactChatHeaderHeight : this.getCompactChatHeaderDefaultHeight()
  }

  private getChatListTopSpacerHeight(): number {
    return this.isExpandedLayout() ? 0 : this.getCompactChatHeaderOverlayHeight()
  }

  private readMeasuredAreaHeight(area: Area): number {
    const height = area.height
    if (typeof height !== 'number' || Number.isNaN(height)) {
      return 0
    }
    return height
  }

  private handleCompactChatHeaderAreaChange(area: Area): void {
    const nextHeight = this.readMeasuredAreaHeight(area)
    if (nextHeight <= 0 || Math.abs(nextHeight - this.compactChatHeaderHeight) < 0.5) {
      return
    }
    this.compactChatHeaderHeight = nextHeight
  }

  private async persistHandAdaptiveSettings(): Promise<void> {
    await this.preferencesService.setBoolean(PreferenceKeys.HAND_ADAPTIVE_ENABLED, this.handAdaptiveEnabled)
    await this.preferencesService.setBoolean(PreferenceKeys.HAND_ADAPTIVE_NEW_CHAT, this.handAdaptiveNewChat)
  }

  private async handleHandAdaptiveEnabledChanged(value: boolean): Promise<void> {
    this.handAdaptiveLoadSeq = this.handAdaptiveLoadSeq + 1
    this.handAdaptiveEnabled = value
    if (value) {
      this.handAdaptiveUnsupported = false
      this.handAdaptiveNewChat = true
    } else {
      this.handAdaptiveNewChat = false
      this.handAdaptiveUnsupported = false
      this.currentHoldingHand = motion.HoldingHandStatus.UNKNOWN_STATUS
    }
    this.syncSettingsSummaryToStorage()
    await this.persistHandAdaptiveSettings()
    this.updateHoldingHandSubscription()
  }

  private async handleHandAdaptiveNewChatChanged(value: boolean): Promise<void> {
    this.handAdaptiveLoadSeq = this.handAdaptiveLoadSeq + 1
    this.handAdaptiveNewChat = value
    this.syncSettingsSummaryToStorage()
    await this.persistHandAdaptiveSettings()
    this.updateHoldingHandSubscription()
  }

  private handleOpenSessionPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }
    const payload = parseOpenSessionPayload(payloadText)
    if (payload === null) {
      console.error('Index', 'Failed to parse openSession payload')
      return
    }
    this.openChatRoute({ sessionId: payload.sessionId } as ChatPageRouteParams)
    setAppUiStateValue(AppStorageKeys.OPEN_SESSION_PAYLOAD, '')
  }

  private handleInAppTaskAlertPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }
    if (!this.shouldHandleInAppTaskAlert()) {
      return
    }
    this.processInAppTaskAlertPayload(payloadText)
  }

  // 不含 shouldHandleInAppTaskAlert 守卫的处理逻辑，供 didShow 等确定可见的时机直接调用
  private processInAppTaskAlertPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }
    const payload = parseInAppTaskAlertPayload(payloadText)
    if (payload === null) {
      console.error('Index', 'Failed to parse in-app alert payload')
      return
    }
    const opts = new SnackBarDisplayOptions()
    opts.message = payload.message
    opts.duration = 5000
    opts.tone = payload.status === ChatTaskStatus.FAILED ? SnackBarTone.ERROR : SnackBarTone.SUCCESS
    opts.actionText = $r('app.string.task_alert_view')
    opts.onAction = (): void => {
      this.openChatRoute({ sessionId: payload.sessionId } as ChatPageRouteParams)
    }
    showSnackBar(this.getUIContext(), opts)
    setAppUiStateValue(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, '')
  }

  private shouldHandleInAppTaskAlert(): boolean {
    if (this.navPathStack.size() > 0) {
      return false
    }
    if (this.tabletChatDetailPathStack.size() > 0) {
      return false
    }
    return true
  }

  private openSettingsSheet(type: SettingsSheetType): void {
    if (type === SettingsSheetType.NONE) {
      return
    }
    // 关闭动画期间的点击：排队到 onDisappear 后再打开，避免 show 状态与可见状态不同步。
    if (this.settingsSheetClosing) {
      this.pendingSettingsSheetType = type
      return
    }
    // 弹窗已打开时，直接切换内容类型，避免“先关后开”造成的点击延迟/吞点击。
    if (this.showSettingsSheet) {
      this.activeSettingsSheetType = type
      return
    }

    this.activeSettingsSheetType = type
    this.showSettingsSheet = true
  }

  private closeAllSettingsSheets(): void {
    if (!this.showSettingsSheet) {
      return
    }
    // 仅当弹窗当前处于打开状态时进入 Closing，避免重复 close 干扰排队打开逻辑。
    this.settingsSheetClosing = true
    this.showSettingsSheet = false
  }

  private isAnySettingsSheetOpen(): boolean {
    return this.showSettingsSheet || this.settingsSheetClosing
  }

  private handleSettingsSheetWillDismiss(dismissAction: DismissSheetAction): void {
    if (dismissAction.reason === DismissReason.PRESS_BACK || dismissAction.reason === DismissReason.SLIDE_DOWN) {
      dismissAction.dismiss()
    }
  }

  private handleSettingsSheetWillSpringBackWhenDismiss(_springBackAction: SpringBackAction): void {
    // ArkUI defaults to a spring-back before dismiss once onWillDismiss is registered.
    // Keep drag-to-close single-phase for this compact settings sheet.
  }

  async loadSessions(): Promise<void> {
    // pop 动画期间完全跳过，由 setInterception.didShow 在动画完成后统一触发
    if (this.navPathStack.size() > 0) {
      return
    }
    this.sessionLoadSeq = this.sessionLoadSeq + 1
    const loadSeq = this.sessionLoadSeq
    const isFirstLoad = this.sessions.length === 0 && !this.isLoading
    if (isFirstLoad) {
      this.isLoading = true
    }
    try {
      const newSessions = await this.chatViewModel.getAllSessions()
      if (loadSeq !== this.sessionLoadSeq) {
        return
      }
      this.mergeSessions(newSessions)
    } catch (error) {
      console.error('Index', `Failed to load sessions: ${JSON.stringify(error)}`)
    } finally {
      if (loadSeq === this.sessionLoadSeq) {
        this.isLoading = false
      }
    }
  }

  /**
   * 合并 sessions：
   * 1) id 集合相同：复用旧对象并按新顺序重建数组，保证排序变化可见；
   * 2) id 集合不同：全量替换。
   */
  private mergeSessions(newSessions: ChatSession[]): void {
    if (this.sessions.length === newSessions.length) {
      const oldMap: Map<string, ChatSession> = new Map()
      for (let i = 0; i < this.sessions.length; i++) {
        oldMap.set(this.sessions[i].id, this.sessions[i])
      }
      let allExist = true
      for (let i = 0; i < newSessions.length; i++) {
        if (!oldMap.has(newSessions[i].id)) {
          allExist = false
          break
        }
      }
      if (allExist) {
        const reorderedSessions: ChatSession[] = []
        for (let i = 0; i < newSessions.length; i++) {
          const fresh = newSessions[i]
          const existing = oldMap.get(fresh.id)
          if (existing !== undefined) {
            existing.title = fresh.title
            existing.updatedAt = fresh.updatedAt
            existing.lastMessagePreview = fresh.lastMessagePreview
            existing.messageCount = fresh.messageCount
            existing.draftText = fresh.draftText
            existing.draftAttachments = [...fresh.draftAttachments]
            existing.isFavorite = fresh.isFavorite
            existing.modelId = fresh.modelId
            existing.providerId = fresh.providerId
            reorderedSessions.push(existing)
          }
        }
        this.sessions = reorderedSessions
        this.refreshSessionListProjection()
        return
      }
    }
    // id 列表不同（新增或删除了会话），全量替换
    this.sessions = newSessions
    this.refreshSessionListProjection()
  }

  async deleteSession(sessionId: string): Promise<void> {
    await this.chatViewModel.deleteSession(sessionId)
    this.sessions = this.sessions.filter((session: ChatSession): boolean => session.id !== sessionId)
    this.selectedSessionIds = this.selectedSessionIds.filter((selectedId: string): boolean => selectedId !== sessionId)
    if (this.tabletDetailSessionId === sessionId) {
      this.clearTabletChatDetail(false)
    }
    if (this.activeChatSessionId === sessionId) {
      setAppUiStateValue(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, '')
    }
    this.refreshSessionListProjection()
    this.showIndexSnack($r('app.string.conversation_deleted'), 2000, SnackBarTone.SUCCESS)
  }

  getFilteredSessions(): ChatSession[] {
    return getFilteredSessionsForIndex(this.sessions, this.searchText, this.currentSessionFilter)
  }

  private refreshSessionListProjection(): void {
    const filteredSessions = this.getFilteredSessions()
    const nextSessionGroups: SessionGroupData[] = buildSessionGroupsForIndex(filteredSessions)
    this.filteredSessionCount = filteredSessions.length
    this.sessionListGroups = rebuildSessionListGroupViewModels(
      this.sessionListGroups,
      nextSessionGroups,
      this.selectedSessionIds,
      this.isMultiSelectMode,
      this.getActiveSessionIdForChatList()
    )
  }

  private getSessionGroupTitle(key: string): Resource {
    if (key === 'today') {
      return $r('app.string.group_today')
    } else if (key === 'yesterday') {
      return $r('app.string.group_yesterday')
    } else if (key === 'last7days') {
      return $r('app.string.group_last_7_days')
    }
    return $r('app.string.group_older')
  }

  private getFilterCountText(): string {
    return this.filteredSessionCount.toString()
  }

  private shouldApplyCompactContentTopInset(): boolean {
    return false
  }

  private shouldApplyExpandedContentTopInset(): boolean {
    return true
  }

  private getActiveSessionIdForChatList(): string {
    if (!this.isExpandedLayout()) {
      return ''
    }
    if (this.activeChatSessionId !== '') {
      return this.activeChatSessionId
    }
    return this.tabletDetailSessionId
  }

  build() {
    Navigation(this.navPathStack) {
      Stack() {
        if (this.isExpandedLayout()) {
          this.ExpandedRoot()
        } else {
          this.CompactRoot()
        }

        // bindSheet 宿主：每个 bindSheet 必须挂在独立组件上，避免多 bindSheet 冲突
        Column()
          .width(0)
          .height(0)
          .bindSheet($$this.showSharePreview, this.SharePreviewBuilder(), {
            height: SheetSize.LARGE,
            dragBar: true,
            showClose: false,
            backgroundColor: $r('app.color.background'),
            blurStyle: BlurStyle.Thick,
            preferType: SheetType.BOTTOM,
            onDisappear: () => {
              this.showSharePreview = false
            }
          })

        Column()
          .width(0)
          .height(0)
          .bindSheet($$this.showSettingsSheet, this.SettingsSheetBuilder(), {
            height: this.getActiveSettingsSheetHeight(),
            dragBar: true,
            showClose: false,
            backgroundColor: this.getSettingsSheetBackgroundColor(),
            blurStyle: BlurStyle.Thin,
            preferType: SheetType.BOTTOM,
            maskColor: '#66000000',
            onWillDismiss: (dismissAction: DismissSheetAction) => {
              this.handleSettingsSheetWillDismiss(dismissAction)
            },
            onWillSpringBackWhenDismiss: (springBackAction: SpringBackAction) => {
              this.handleSettingsSheetWillSpringBackWhenDismiss(springBackAction)
            },
            onDisappear: () => {
              // Closing 结束：如果有排队的打开请求，直接重开并切换内容。
              this.settingsSheetClosing = false
              if (this.pendingSettingsSheetType !== SettingsSheetType.NONE) {
                const nextType = this.pendingSettingsSheetType
                this.pendingSettingsSheetType = SettingsSheetType.NONE
                this.activeSettingsSheetType = nextType
                this.showSettingsSheet = true
                return
              }
              this.activeSettingsSheetType = SettingsSheetType.NONE
            }
          })

        Column()
          .width(0)
          .height(0)
          .bindSheet($$this.showSystemPromptSheet, this.SystemPromptSheetBuilder(), {
            height: SheetSize.LARGE,
            dragBar: true,
            showClose: false,
            backgroundColor: $r('app.color.background'),
            preferType: SheetType.BOTTOM,
            onDisappear: () => {
              this.showSystemPromptSheet = false
            }
          })

      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
  }

  @Builder
  CompactRoot() {
    Column() {
      if (this.shouldApplyCompactContentTopInset()) {
        Column()
          .width('100%')
          .height(this.px2vp(this.topAvoidHeight))
      }

      HdsTabs({
        controller: this.compactTabsController,
        barPosition: BarPosition.End,
        index: this.currentTabIndex
      }) {
        TabContent() {
          this.AssistantTab()
        }
        .tabBar(this.TabBarAssistant())

        TabContent() {
          this.ChatTab()
        }
        .tabBar(this.TabBarChat())

        TabContent() {
          this.SettingsTab()
        }
        .tabBar(this.TabBarSettings())
      }
      .width('100%')
      .layoutWeight(1)
      .barMode(BarMode.Fixed)
      .barHeight(this.getCompactTabsBarHeight())
      .barOverlap(true)
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .barFloatingStyle(this.getCompactTabsFloatingStyle())
      .scrollable(false)
      .cachedMaxCount(3, TabsCacheMode.CACHE_LATEST_SWITCHED)
      .onTabBarClick((index: number) => {
        if (index === this.currentTabIndex) {
          this.applyCompactTabsBarStyle(HdsBarStyle.COLLAPSE)
        } else {
          this.applyCompactTabsBarStyle(HdsBarStyle.EXPAND)
        }
      })
      .onSelected((index: number) => {
        if (this.currentTabIndex !== index) {
          this.switchToTab(index)
        }
      })
      .onChange((index: number) => {
        if (this.currentTabIndex !== index) {
          this.switchToTab(index)
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  ExpandedRoot() {
    Row() {
      this.ExpandedNavigationRail()

        Column() {
          if (this.shouldApplyExpandedContentTopInset()) {
            Column()
              .width('100%')
              .height(this.px2vp(this.topAvoidHeight))
          }

          if (this.currentTabIndex === 0) {
            this.ExpandedAssistantTab()
          } else if (this.currentTabIndex === 1) {
            this.ExpandedChatTab()
          } else {
            this.ExpandedSettingsTab()
          }
        }
        .layoutWeight(1)
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  ExpandedNavigationRail() {
    Column({ space: 6 }) {
      Column()
        .width('100%')
        .height(this.px2vp(this.topAvoidHeight))

      this.RailTabButton(0, $r('sys.symbol.person_fill'), $r('sys.symbol.person'), $r('app.string.tab_assistant'))
      this.RailTabButton(1, $r('sys.symbol.message_fill'), $r('sys.symbol.message'), $r('app.string.tab_chat'))
      this.RailTabButton(2, $r('sys.symbol.gearshape_fill'), $r('sys.symbol.gearshape'), $r('app.string.tab_settings'))

      Blank()
    }
    .width(88)
    .height('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 12 })
    .backgroundColor($r('app.color.surface'))
    .border({
      width: { right: 1 },
      color: $r('app.color.divider')
    })
  }

  @Builder
  ExpandedAssistantTab() {
    Row() {
      Column() {
        this.AssistantTab()
      }
      .width('100%')
      .constraintSize({ maxWidth: this.getExpandedCenterColumnMaxWidth() })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({
      left: this.getExpandedPageHorizontalPadding(),
      right: this.getExpandedPageHorizontalPadding(),
      bottom: 12
    })
  }

  @Builder
  ExpandedSettingsTab() {
    Column() {
      this.SettingsTab()
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.background'))
    .borderRadius(24)
    .clip(true)
    .border({
      width: 1,
      color: $r('app.color.divider')
    })
    .padding({
      left: this.getExpandedPageHorizontalPadding(),
      right: this.getExpandedPageHorizontalPadding()
    })
  }

  @Builder
  RailTabButton(index: number, activeIcon: Resource, inactiveIcon: Resource, label: Resource, badgeCount: number = 0) {
    Column() {
      IndexBottomTabItem({
        active: this.isTabActive(index),
        activeIcon: activeIcon,
        inactiveIcon: inactiveIcon,
        label: label,
        badgeCount: badgeCount
      })
    }
    .width('100%')
    .height(64)
    .borderRadius(18)
    .backgroundColor(this.isTabActive(index) ? this.themePrimaryLight : Color.Transparent)
    .onClick(() => {
      this.switchToTab(index)
    })
  }

  @Builder
  SharePreviewBuilder() {
    SharePreviewSheet({
      messages: this.shareMessages,
      onClose: () => {
        this.showSharePreview = false
      }
    })
  }

  // px 转 vp
  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private isTabActive(index: number): boolean {
    return this.currentTabIndex === index
  }

  private getCompactTabsBottomInset(): number {
    return this.getCompactTabsBarHeight() + Index.COMPACT_TABS_FLOATING_BOTTOM_MARGIN
  }

  private applyCompactTabsBarStyle(style: HdsBarStyle): void {
    if (this.compactTabsBarStyle === style) {
      return
    }
    this.compactTabsBarStyle = style
    this.compactTabsController.applyMiniBarStyle(style)
  }

  private getCompactTabsFloatingStyle(): HdsTabsFloatingStyle {
    return {
      barSideMargin: Index.COMPACT_TABS_FLOATING_SIDE_MARGIN,
      barBottomMargin: Index.COMPACT_TABS_FLOATING_BOTTOM_MARGIN,
      miniBar: {
        miniBarBuilder: (): void => {
          this.CompactMiniTabBar()
        },
        miniBarStyle: this.compactTabsBarStyle
      }
    }
  }

  @Builder
  private CompactMiniTabBarSummary() {
    Row({ space: 6 }) {
      if (this.currentTabIndex === 0) {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(18)
          .fontColor([this.themePrimary])

        Text($r('app.string.tab_assistant'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
      } else if (this.currentTabIndex === 1) {
        SymbolGlyph($r('sys.symbol.ellipsis_message_fill'))
          .fontSize(18)
          .fontColor([this.themePrimary])

        Text($r('app.string.tab_chat'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
      } else {
        SymbolGlyph($r('sys.symbol.gearshape_fill'))
          .fontSize(18)
          .fontColor([this.themePrimary])

        Text($r('app.string.tab_settings'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
      }
    }
    .padding({ left: 12, right: 10, top: 9, bottom: 9 })
    .borderRadius(18)
    .backgroundColor($r('app.color.surface'))
    .onClick(() => {
      this.applyCompactTabsBarStyle(HdsBarStyle.EXPAND)
    })
  }

  @Builder
  private CompactMiniTabBar() {
    Row({ space: 8 }) {
      this.CompactMiniTabBarSummary()

      Row() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(16)
          .fontColor([Color.White])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.themePrimary)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.applyCompactTabsBarStyle(HdsBarStyle.EXPAND)
        this.openChatRoute({} as ChatPageRouteParams)
      })
    }
    .padding(4)
    .borderRadius(22)
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  TabBarAssistant() {
    IndexBottomTabItem({
      active: this.isTabActive(0),
      activeIcon: $r('sys.symbol.person_fill'),
      inactiveIcon: $r('sys.symbol.person'),
      label: $r('app.string.tab_assistant')
    })
  }

  @Builder
  TabBarChat() {
    IndexBottomTabItem({
      active: this.isTabActive(1),
      activeIcon: $r('sys.symbol.ellipsis_message_fill'),
      inactiveIcon: $r('sys.symbol.ellipsis_message'),
      label: $r('app.string.tab_chat')
    })
  }

  @Builder
  TabBarSettings() {
    IndexBottomTabItem({
      active: this.isTabActive(2),
      activeIcon: $r('sys.symbol.gearshape_fill'),
      inactiveIcon: $r('sys.symbol.gearshape'),
      label: $r('app.string.tab_settings')
    })
  }

  @Builder
  AssistantTab() {
    Navigation() {
      Column() {
        if (!this.isExpandedLayout()) {
          Column()
            .width('100%')
            .height(this.px2vp(this.topAvoidHeight))
        }

        Row() {
          Text($r('app.string.tab_assistant'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Center)

        Column() {
          Text($r('app.string.assistant_coming_soon'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .hideTitleBar(true)
    .hideBackButton(true)
    .backgroundColor($r('app.color.background'))
  }

  // 搜索框展开动画
  private expandSearch(): void {
    this.getUIContext().animateTo({
      curve: curves.interpolatingSpring(0, 1, 342, 38)
    }, () => {
      this.isSearchExpanded = true
      // 输入框是动态挂载的，等一帧再抢焦点，系统才会跟着弹软键盘。
      setTimeout(() => {
        if (this.isSearchExpanded) {
          this.getUIContext().getFocusController().requestFocus(this.searchInputFocusId)
        }
      }, 60)
    })
  }

  // 搜索框收起动画
  private collapseSearch(): void {
    this.getUIContext().animateTo({
      curve: curves.interpolatingSpring(0, 1, 342, 38)
    }, () => {
      this.searchText = ''
      this.isSearchExpanded = false
      this.refreshSessionListProjection()
    })
  }

  @Builder
  CollapsedSearchActionButton() {
    Row() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(22)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .backgroundColor($r('app.color.surface'))
    .justifyContent(FlexAlign.Center)
    .geometryTransition('SEARCH_BAR_ID', { follow: true })
    .transition(TransitionEffect.OPACITY)
    .onClick(() => {
      this.expandSearch()
    })
  }

  @Builder
  ChatTab() {
    Column() {
      this.ChatListPanel()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private ChatListHeaderContent(applyTopInset: boolean = false) {
    Column() {
      if (applyTopInset) {
        Column()
          .width('100%')
          .height(this.px2vp(this.topAvoidHeight))
      }

      if (!this.isMultiSelectMode) {
        Row() {
          if (!this.isSearchExpanded) {
            Text($r('app.string.tab_chat'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .transition(TransitionEffect.OPACITY.animation({
                duration: 200,
                curve: Curve.EaseOut
              }))
          }

          if (this.isSearchExpanded) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(18)
                .fontColor([$r('app.color.text_tertiary')])

              TextInput({ text: this.searchText, placeholder: $r('app.string.search_sessions_placeholder') })
                .id(this.searchInputFocusId)
                .layoutWeight(1)
                .height(36)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor(Color.Transparent)
                .padding({ left: 2, right: 0 })
                .caretColor(this.themePrimary)
                .placeholderColor($r('app.color.text_tertiary'))
                .onChange((value: string) => {
                  this.searchText = value
                  this.refreshSessionListProjection()
                })
                .onSubmit(() => {
                  if (this.searchText.trim() === '') {
                    this.collapseSearch()
                  }
                })
            }
            .layoutWeight(1)
            .height(40)
            .padding({ left: 12, right: 12 })
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(20)
            .geometryTransition('SEARCH_BAR_ID', { follow: true })
            .transition(TransitionEffect.OPACITY)

            Text($r('app.string.cancel'))
              .fontSize(15)
              .fontColor(this.themePrimary)
              .margin({ left: 12 })
              .onClick(() => {
                this.collapseSearch()
              })
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 20 }))
                  .animation({ duration: 250, curve: Curve.EaseOut }),
                TransitionEffect.OPACITY.animation({ duration: 150 })
              ))
          } else {
            this.CollapsedSearchActionButton()
          }
        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Center)

        IndexFilterBar({
          currentFilter: this.currentSessionFilter,
          countText: this.getFilterCountText(),
          onFilterChange: (filterType: SessionFilterType): void => {
            this.currentSessionFilter = filterType
            this.refreshSessionListProjection()
          }
        })
      } else {
        Row() {
          Text($r('app.string.select_conversations'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Blank()

          Text($r('app.string.cancel'))
            .fontSize(15)
            .fontColor(this.themePrimary)
            .onClick(() => {
              this.handleExitMultiSelectMode()
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
  }

  @Builder
  private CompactChatHeaderOverlay() {
    Column() {
      this.ChatListHeaderContent(true)
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.handleCompactChatHeaderAreaChange(newArea)
    })
  }

  @Builder
  private ChatListPanelContent(topSpacerHeight: number = 0) {
    Column() {
      if (this.isLoading) {
        Column() {
          if (topSpacerHeight > 0) {
            Column()
              .width('100%')
              .height(topSpacerHeight)
          }

          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(this.themePrimary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.sessions.length === 0) {
        Column() {
          if (topSpacerHeight > 0) {
            Column()
              .width('100%')
              .height(topSpacerHeight)
          }

          IndexEmptyStateCard({
            icon: $r('sys.symbol.ellipsis_message'),
            title: $r('app.string.no_sessions'),
            description: $r('app.string.start_new_chat'),
            showButton: true,
            buttonText: $r('app.string.new_chat'),
            onButtonClick: (): void => {
              this.openChatRoute({} as ChatPageRouteParams)
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.filteredSessionCount === 0) {
        Column() {
          if (topSpacerHeight > 0) {
            Column()
              .width('100%')
              .height(topSpacerHeight)
          }

          if (this.searchText.trim() !== '') {
            IndexEmptyStateCard({
              icon: $r('sys.symbol.magnifyingglass'),
              title: $r('app.string.no_search_results'),
              description: $r('app.string.try_different_keyword')
            })
          } else {
            IndexEmptyStateCard({
              icon: $r('sys.symbol.heart'),
              title: $r('app.string.no_favorite_sessions'),
              description: $r('app.string.favorite_sessions_hint')
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column() {
          IndexSessionListSection({
            sessionGroups: this.sessionListGroups,
            isMultiSelectMode: this.isMultiSelectMode,
            topSpacerHeight: topSpacerHeight,
            bottomSpacerHeight: this.isMultiSelectMode ? 16 : this.getChatListBottomSpacerHeight(),
            themeRenderKey: this.sessionListThemeRenderKey,
            onGetGroupTitle: (groupKey: string): Resource => {
              return this.getSessionGroupTitle(groupKey)
            },
            onToggleSelection: (sessionId: string): void => {
              this.handleSessionCardClick(sessionId)
            },
            onOpenSession: (sessionId: string): void => {
              this.openChatRoute({ sessionId: sessionId } as ChatPageRouteParams)
            },
            onDeleteSession: (sessionId: string): void => {
              this.deleteSession(sessionId)
            },
            onEnterMultiSelect: (sessionId: string): void => {
              this.handleEnterMultiSelectMode(sessionId)
            },
            onShareSession: (session: ChatSession): void => {
              this.handleShareSession(session)
            },
            onToggleFavorite: (session: ChatSession): void => {
              this.handleToggleFavoriteSession(session)
            }
          })
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private ChatListViewportContent() {
    Column() {
      if (this.isExpandedLayout()) {
        this.ChatListHeaderContent(false)
        this.ChatListPanelContent(0)
      } else {
        this.ChatListPanelContent(this.getChatListTopSpacerHeight())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private CompactChatListViewport() {
    Stack({ alignContent: Alignment.Top }) {
      this.ChatListViewportContent()
      this.CompactChatHeaderOverlay()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ChatListPanel() {
    if (this.isExpandedLayout()) {
      if (this.isMultiSelectMode) {
        Column() {
          this.ChatListViewportContent()
          MultiSelectToolbar({
            selectedCount: this.selectedSessionIds.length,
            totalCount: this.filteredSessionCount,
            onSelectAll: () => {
              this.handleSelectAllSessions()
            },
            onDelete: () => {
              this.handleDeleteSelectedSessions()
            },
            onShare: () => {
              this.handleShareSelectedSessions()
            },
            onCancel: () => {
              this.handleExitMultiSelectMode()
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
      } else {
        Stack({ alignContent: Alignment.BottomEnd }) {
          this.ChatListViewportContent()
          this.FloatingActionButton()
        }
        .width('100%')
        .height('100%')
      }
    } else {
      if (this.isMultiSelectMode) {
        Column() {
          Column() {
            this.CompactChatListViewport()
          }
          .width('100%')
          .layoutWeight(1)
          MultiSelectToolbar({
            selectedCount: this.selectedSessionIds.length,
            totalCount: this.filteredSessionCount,
            onSelectAll: () => {
              this.handleSelectAllSessions()
            },
            onDelete: () => {
              this.handleDeleteSelectedSessions()
            },
            onShare: () => {
              this.handleShareSelectedSessions()
            },
            onCancel: () => {
              this.handleExitMultiSelectMode()
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
      } else {
        Stack({ alignContent: Alignment.BottomEnd }) {
          this.CompactChatListViewport()
          this.FloatingActionButton()
        }
        .width('100%')
        .height('100%')
      }
    }
  }

  @Builder
  ExpandedChatTab() {
    Row({ space: 16 }) {
      Column() {
        this.ChatListPanel()
      }
      .width(this.getExpandedChatListWidth())
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .borderRadius(24)
      .clip(true)
      .border({
        width: 1,
        color: $r('app.color.divider')
      })

      Column() {
        this.TabletChatDetailPane()
      }
      .layoutWeight(1)
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .borderRadius(24)
      .clip(true)
      .border({
        width: 1,
        color: $r('app.color.divider')
      })
    }
    .width('100%')
    .layoutWeight(1)
    .padding({
      left: this.getExpandedPageHorizontalPadding(),
      right: this.getExpandedPageHorizontalPadding(),
      bottom: 12
    })
  }

  @Builder
  TabletChatDetailPane() {
    Navigation(this.tabletChatDetailPathStack) {
      Stack() {
        if (this.tabletChatDetailPathStack.size() === 0) {
          this.TabletChatDetailEmptyState()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
  }

  @Builder
  TabletChatDetailEmptyState() {
    IndexEmptyStateCard({
      icon: $r('sys.symbol.ellipsis_message'),
      title: $r('app.string.tablet_chat_detail_empty_title'),
      description: $r('app.string.tablet_chat_detail_empty_desc'),
      showButton: true,
      buttonText: $r('app.string.new_chat'),
      onButtonClick: (): void => {
        this.openChatRoute({} as ChatPageRouteParams)
      }
    })
  }

  @Builder
  FloatingActionButton() {
    Column() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(22)
        .fontColor([Color.White])
    }
    .width(48)
    .height(48)
    .borderRadius(24)
    .backgroundColor(this.themePrimary)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .position({ x: this.shouldPlaceFabOnLeft() ? 0 : '100%', y: '100%' })
    .translate({ x: this.getFabOffsetX(), y: this.getFabOffsetY() })
    .scale(getButtonScale(this.fabPressed))
    .animation(getButtonAnimation())
    .shadow({
      radius: 10,
      color: this.themePrimary + '4D',
      offsetX: 0,
      offsetY: 4
    })
    .onTouch(createButtonTouchHandler((pressed: boolean) => {
      this.fabPressed = pressed
    }))
    .onClick(() => {
      this.fabPressed = false
      this.openChatRoute({} as ChatPageRouteParams)
    })
  }

  // 多选模式下点击防抖
  private isProcessingClick: boolean = false

  private handleSessionCardClick(sessionId: string): void {
    // 防止重复点击
    if (this.isProcessingClick) {
      return
    }
    this.isProcessingClick = true

    // 执行切换
    this.handleToggleSessionSelection(sessionId)

    // 100ms 后重置标志
    setTimeout(() => {
      this.isProcessingClick = false
    }, 100)
  }

  @Builder
  SettingsNavigationContent() {
    IndexSettingsPanel({
      sidebarMode: this.isSettingsSplitMode(),
      selectedRouteName: this.currentSettingsRouteName,
      highlightSelection: this.isSettingsSplitMode(),
      onOpenModelManage: (): void => {
        this.openSettingsDestination(SettingsRouteName.MODEL_MANAGE)
      },
      onOpenDefaultModel: (): void => {
        this.openSettingsDestination(SettingsRouteName.DEFAULT_MODEL)
      },
      onOpenToolsCenter: (): void => {
        this.openSettingsDestination(SettingsRouteName.TOOLS_CENTER)
      },
      onOpenSystemPrompt: (): void => {
        this.openSettingsDestination(SettingsRouteName.SYSTEM_PROMPT)
      },
      onOpenHandAdaptive: (): void => {
        this.openSettingsPanelEntry(SettingsRouteName.HAND_ADAPTIVE, SettingsSheetType.HAND_ADAPTIVE)
      },
      onOpenTheme: (): void => {
        this.openSettingsDestination(SettingsRouteName.THEME_MODE)
      },
      onOpenLanguage: (): void => {
        this.openSettingsPanelEntry(SettingsRouteName.LANGUAGE, SettingsSheetType.LANGUAGE)
      },
      onOpenNotification: (): void => {
        this.openSettingsPanelEntry(SettingsRouteName.NOTIFICATION, SettingsSheetType.NOTIFICATION)
      },
      onOpenExportData: (): void => {
        this.openSettingsDestination(SettingsRouteName.EXPORT_DATA)
      },
      onOpenImportData: (): void => {
        this.openSettingsDestination(SettingsRouteName.IMPORT_DATA)
      },
      onOpenAbout: (): void => {
        this.openSettingsDestination(SettingsRouteName.ABOUT)
      },
      onOpenSupportDevelopment: (): void => {
        this.openSettingsDestination(SettingsRouteName.SUPPORT_DEVELOPMENT)
      },
      onOpenPrivacy: (): void => {
        this.openPrivacyPolicy()
      }
    })
  }

  @Builder
  private SettingsNavigationScrollableContent() {
    Scroll() {
      Column() {
        this.SettingsNavigationContent()

        if (!this.isSettingsSplitMode()) {
          Blank()
            .width('100%')
            .height(this.getCompactTabsBottomInset() + 12)
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private CompactSettingsHeader() {
    Column() {
      Column()
        .width('100%')
        .height(this.px2vp(this.topAvoidHeight))

      Row() {
        Text($r('app.string.tab_settings'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private CompactSettingsRootContent() {
    Column() {
      this.CompactSettingsHeader()
      Column() {
        this.SettingsNavigationScrollableContent()
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  private shouldIgnoreCompactSettingsTopSafeArea(): boolean {
    return true
  }

  private getCompactTabsBarHeight(): number {
    return getCompactTabsBarHeightForIndex(this.px2vp(this.bottomAvoidHeight))
  }

  @Builder
  SettingsTab() {
    if (this.isSettingsSplitMode()) {
      Navigation(this.settingsNavPathStack) {
        this.SettingsNavigationScrollableContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .title($r('app.string.tab_settings'))
      .titleMode(NavigationTitleMode.Mini)
      .mode(NavigationMode.Split)
      .navBarWidth(this.getExpandedSettingsListWidth())
      .hideBackButton(true)
      .hideToolBar(true)
      .onAppear(() => {
        this.ensureSettingsSplitLandingRoute()
      })
    } else {
      Navigation(this.settingsNavPathStack) {
        this.CompactSettingsRootContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .ignoreLayoutSafeArea(
        [LayoutSafeAreaType.SYSTEM],
        this.shouldIgnoreCompactSettingsTopSafeArea() ? [LayoutSafeAreaEdge.TOP] : []
      )
      .mode(NavigationMode.Stack)
      .navBarWidth(this.windowWidthVp)
      .hideTitleBar(true)
      .hideBackButton(true)
      .hideToolBar(true)
    }
  }

  private getActiveSettingsSheetHeight(): SheetSize {
    return SheetSize.FIT_CONTENT
  }

  private getSettingsSheetBackgroundColor(): Resource {
    return $r('app.color.surface')
  }

  @Builder
  SettingsSheetBuilder() {
    Column() {
      Column() {
        // 自绘标题栏：唯一关闭入口，避免系统遮罩/拖拽关闭造成“点快了自己收缩/吞点击”。
        Row() {
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
          }
          .type(ButtonType.Circle)
          .width(36)
          .height(36)
          .backgroundColor($r('app.color.divider'))
          .onClick(() => {
            this.closeAllSettingsSheets()
          })

          Text(getSettingsSheetTitleText(this.activeSettingsSheetType))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          // 占位，保持标题居中
          Column()
            .width(36)
            .height(36)
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        IndexSettingsSheetContent({
          settingsSheetType: this.activeSettingsSheetType,
          currentThemeMode: this.currentThemeMode,
          currentLanguage: this.currentLanguage,
          notifyEnabled: this.notifyEnabled,
          notifyOnComplete: this.notifyOnComplete,
          notifyOnFailed: this.notifyOnFailed,
          handAdaptiveEnabled: this.handAdaptiveEnabled,
          handAdaptiveNewChat: this.handAdaptiveNewChat,
          handAdaptiveUnsupported: this.handAdaptiveUnsupported,
          callbacks: this.buildSettingsSheetCallbacks()
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .backgroundColor(this.getSettingsSheetBackgroundColor())
      .borderRadius({ topLeft: 28, topRight: 28, bottomLeft: 28, bottomRight: 28 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(this.getSettingsSheetBackgroundColor())
  }

  @Builder
  ThemeSheetBuilder() {
    IndexSettingsSheetContent({
      settingsSheetType: SettingsSheetType.THEME,
      currentThemeMode: this.currentThemeMode,
      currentLanguage: this.currentLanguage,
      notifyEnabled: this.notifyEnabled,
      notifyOnComplete: this.notifyOnComplete,
      notifyOnFailed: this.notifyOnFailed,
      handAdaptiveEnabled: this.handAdaptiveEnabled,
      handAdaptiveNewChat: this.handAdaptiveNewChat,
      handAdaptiveUnsupported: this.handAdaptiveUnsupported,
      callbacks: this.buildSettingsSheetCallbacks()
    })
  }

  @Builder
  NotificationSheetBuilder() {
    IndexSettingsSheetContent({
      settingsSheetType: SettingsSheetType.NOTIFICATION,
      currentThemeMode: this.currentThemeMode,
      currentLanguage: this.currentLanguage,
      notifyEnabled: this.notifyEnabled,
      notifyOnComplete: this.notifyOnComplete,
      notifyOnFailed: this.notifyOnFailed,
      handAdaptiveEnabled: this.handAdaptiveEnabled,
      handAdaptiveNewChat: this.handAdaptiveNewChat,
      handAdaptiveUnsupported: this.handAdaptiveUnsupported,
      callbacks: this.buildSettingsSheetCallbacks()
    })
  }

  @Builder
  HandAdaptiveSheetBuilder() {
    IndexSettingsSheetContent({
      settingsSheetType: SettingsSheetType.HAND_ADAPTIVE,
      currentThemeMode: this.currentThemeMode,
      currentLanguage: this.currentLanguage,
      notifyEnabled: this.notifyEnabled,
      notifyOnComplete: this.notifyOnComplete,
      notifyOnFailed: this.notifyOnFailed,
      handAdaptiveEnabled: this.handAdaptiveEnabled,
      handAdaptiveNewChat: this.handAdaptiveNewChat,
      handAdaptiveUnsupported: this.handAdaptiveUnsupported,
      callbacks: this.buildSettingsSheetCallbacks()
    })
  }

  private buildSettingsSheetCallbacks(): IndexSettingsSheetActionCallbacks {
    const callbacks = new IndexSettingsSheetActionCallbacks()
    callbacks.onSelectTheme = async (mode: ThemeMode): Promise<void> => {
      this.currentThemeMode = mode
      this.syncSettingsSummaryToStorage()
      this.closeAllSettingsSheets()
      try {
        await this.settingsManager.setThemeMode(mode)
      } catch (error) {
        console.error('Index', `Failed to set theme mode: ${JSON.stringify(error)}`)
        this.refreshSettingsState()
      }
    }
    callbacks.onSelectLanguage = async (language: AppLanguage): Promise<void> => {
      this.currentLanguage = language
      this.syncSettingsSummaryToStorage()
      this.closeAllSettingsSheets()
      try {
        await this.settingsManager.setLanguage(language)
      } catch (error) {
        console.error('Index', `Failed to set language: ${JSON.stringify(error)}`)
        this.refreshSettingsState()
      }
    }
    callbacks.onToggleHandAdaptiveEnabled = (value: boolean): void => {
      this.handleHandAdaptiveEnabledChanged(value)
    }
    callbacks.onToggleHandAdaptiveNewChat = (value: boolean): void => {
      this.handleHandAdaptiveNewChatChanged(value)
    }
    callbacks.onToggleNotifyEnabled = async (value: boolean): Promise<void> => {
      this.notifyEnabled = value
      this.syncSettingsSummaryToStorage()
      await this.settingsManager.setNotificationEnabled(value)
    }
    callbacks.onToggleNotifyOnComplete = async (value: boolean): Promise<void> => {
      this.notifyOnComplete = value
      this.syncSettingsSummaryToStorage()
      await this.settingsManager.setNotifyOnCompleteEnabled(value)
    }
    callbacks.onToggleNotifyOnFailed = async (value: boolean): Promise<void> => {
      this.notifyOnFailed = value
      this.syncSettingsSummaryToStorage()
      await this.settingsManager.setNotifyOnFailedEnabled(value)
    }
    callbacks.onOpenSystemNotificationSettings = (): void => {
      this.openSystemNotificationSettings()
    }
    return callbacks
  }

  // ========== 系统提示词 ==========

  private async openSystemPromptSheet(): Promise<void> {
    const saved = await this.preferencesService.getString(
      PreferenceKeys.CUSTOM_SYSTEM_PROMPT,
      SystemPromptTemplateDefaults.DEFAULT_TEMPLATE
    )
    this.customSystemPrompt = normalizeSystemPromptTemplate(saved)
    this.showSystemPromptSheet = true
  }

  private async saveSystemPrompt(): Promise<void> {
    const normalizedTemplate = normalizeSystemPromptTemplate(this.customSystemPrompt)
    this.customSystemPrompt = normalizedTemplate
    await this.preferencesService.setString(PreferenceKeys.CUSTOM_SYSTEM_PROMPT, normalizedTemplate)
    this.showIndexSnack($r('app.string.system_prompt_saved'), 2000, SnackBarTone.SUCCESS)
    this.showSystemPromptSheet = false
  }

  private resetSystemPrompt(): void {
    this.customSystemPrompt = SystemPromptTemplateDefaults.DEFAULT_TEMPLATE
  }

  @Builder
  SystemPromptSheetBuilder() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.showSystemPromptSheet = false
        })

        Text($r('app.string.system_prompt_edit_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor(this.themePrimary)
        .onClick(() => {
          this.saveSystemPrompt()
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Text($r('app.string.system_prompt_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 16, right: 16, bottom: 8 })
        .width('100%')

      Text($r('app.string.system_prompt_variables_hint'))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .padding({ left: 16, right: 16, bottom: 12 })
        .width('100%')

      TextArea({ text: this.customSystemPrompt, placeholder: $r('app.string.system_prompt_placeholder') })
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .onChange((value: string) => {
          this.customSystemPrompt = value
        })

      Row() {
        Button($r('app.string.system_prompt_clear'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius(20)
          .height(40)
          .padding({ left: 18, right: 18 })
          .onClick(() => {
            this.resetSystemPrompt()
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 12, bottom: 12 + this.px2vp(this.bottomAvoidHeight) })
    }
    .width('100%')
    .height('100%')
  }

  // ========== 多选模式相关方法 ==========

  // 处理主题配色选择
  private async handleColorThemeSelected(theme: ColorTheme): Promise<void> {
    // 先本地更新，确保摘要先刷新，再持久化
    this.currentColorTheme = theme
    this.syncSettingsSummaryToStorage()
    this.closeAllSettingsSheets()
    try {
      await this.settingsManager.setColorTheme(theme)
      this.showIndexSnack($r('app.string.theme_switched'), 2000, SnackBarTone.SUCCESS)
    } catch (error) {
      console.error('Index', `Failed to set color theme: ${JSON.stringify(error)}`)
      this.refreshSettingsState()
    }
  }

  private async openSystemNotificationSettings(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await notificationManager.openNotificationSettings(context)
    } catch (error) {
      console.error('Index', `Failed to open notification settings: ${JSON.stringify(error)}`)
      this.showIndexSnack($r('app.string.notification_open_settings_failed'), 2000, SnackBarTone.ERROR)
    }
  }

  // 进入多选模式
  private handleEnterMultiSelectMode(sessionId: string): void {
    this.isMultiSelectMode = true
    this.selectedSessionIds = [sessionId]
    this.refreshSessionListProjection()
  }

  // 退出多选模式
  private handleExitMultiSelectMode(): void {
    this.isMultiSelectMode = false
    this.selectedSessionIds = []
    this.refreshSessionListProjection()
  }

  // 切换会话选中状态
  private handleToggleSessionSelection(sessionId: string): void {
    this.selectedSessionIds = toggleSelectionById(this.selectedSessionIds, sessionId)
    this.refreshSessionListProjection()
  }

  // 全选/取消全选
  private handleSelectAllSessions(): void {
    const filteredSessions = this.getFilteredSessions()
    if (filteredSessions.length === 0) {
      return
    }

    const filteredIds: string[] = []
    for (let i = 0; i < filteredSessions.length; i++) {
      filteredIds.push(filteredSessions[i].id)
    }
    const selectedFilteredCount = countSelectedIdsInCandidates(this.selectedSessionIds, filteredIds)

    if (selectedFilteredCount === filteredSessions.length) {
      this.selectedSessionIds = removeCandidateIds(this.selectedSessionIds, filteredIds)
    } else {
      this.selectedSessionIds = mergeSelectAllIds(this.selectedSessionIds, filteredIds)
    }
    this.refreshSessionListProjection()
  }

  private async handleToggleFavoriteSession(session: ChatSession): Promise<void> {
    const isFavorite = await this.chatViewModel.toggleSessionFavorite(session.id)
    session.isFavorite = isFavorite
    // 触发 sessions 的 @State 更新，确保 swipeAction 文案/图标立即按收藏状态重渲染
    this.sessions = [...this.sessions]
    this.refreshSessionListProjection()
    this.showIndexSnack(isFavorite ? $r('app.string.conversation_favorited') :
    $r('app.string.conversation_unfavorited'), 2000, SnackBarTone.SUCCESS)
    await this.loadSessions()
  }

  // 删除选中的会话
  private async handleDeleteSelectedSessions(): Promise<void> {
    if (this.selectedSessionIds.length === 0) {
      return
    }

    this.getUIContext().showAlertDialog({
      title: $r('app.string.delete_chat'),
      message: $r('app.string.delete_selected_conversations_confirm'),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: '#FF3B30',
        action: async () => {
          // 批量删除
          for (let i = 0; i < this.selectedSessionIds.length; i++) {
            await this.chatViewModel.deleteSession(this.selectedSessionIds[i])
          }

          // 更新列表
          await this.loadSessions()

          // 退出多选模式
          this.handleExitMultiSelectMode()

          this.showIndexSnack($r('app.string.conversations_deleted'), 2000, SnackBarTone.SUCCESS)
        }
      }
    })
  }

  // 分享选中的会话
  private async handleShareSelectedSessions(): Promise<void> {
    if (this.selectedSessionIds.length === 0) {
      return
    }

    // 目前只支持单个会话分享，多个会话分享比较复杂
    if (this.selectedSessionIds.length > 1) {
      this.showIndexSnack($r('app.string.single_session_share_only'), 2000, SnackBarTone.ERROR)
      return
    }

    // 获取选中的会话
    const sessionId = this.selectedSessionIds[0]
    const session = this.sessions.find(s => s.id === sessionId)

    if (session === undefined) {
      return
    }

    // 加载会话消息
    const fullSession = await this.chatViewModel.loadSession(sessionId)
    if (fullSession === null || fullSession.messages.length === 0) {
      this.showIndexSnack($r('app.string.conversation_content_empty'), 2000, SnackBarTone.ERROR)
      return
    }

    // 设置分享消息并打开分享预览
    this.shareMessages = fullSession.messages
    this.showSharePreview = true
  }

  // 分享单个会话
  private async handleShareSession(session: ChatSession): Promise<void> {
    // 加载会话消息
    const fullSession = await this.chatViewModel.loadSession(session.id)
    if (fullSession === null || fullSession.messages.length === 0) {
      this.showIndexSnack($r('app.string.conversation_content_empty'), 2000, SnackBarTone.ERROR)
      return
    }

    // 设置分享消息并打开分享预览
    this.shareMessages = fullSession.messages
    this.showSharePreview = true
  }
}
