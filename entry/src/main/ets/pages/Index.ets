import { curves } from '@kit.ArkUI'
import { ConfigurationConstant, common } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { motion } from '@kit.MultimodalAwarenessKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { window } from '@kit.ArkUI'
import {
  HdsNavigation,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsFloatingStyle
} from '@kit.UIDesignKit'
import {
  buildCompactTabsFloatingStyle,
  CompactTabsFloatingStyleOptions
} from '../utils/HdsTabsFloatingStyleHelper'
import { ChatSession, ChatMessage, ModelProvider } from '../models/ChatModels'
import { Assistant, DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'
import { ChatViewModel } from '../viewmodels/ChatViewModel'
import { SettingsChangeCallback } from '../viewmodels/SettingsManager'
import { ThemeMode, AppLanguage, PreferenceKeys } from '../services/PreferencesService'
import { dismissActiveSnackBarOnBack, showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { MultiSelectToolbar } from '../components/MultiSelectToolbar'
import { SharePreviewSheet } from '../components/SharePreviewSheet'
import { ColorTheme, ThemeColorConfig } from '../models/ThemeColors'
import { ServiceRegistry } from '../services/ServiceRegistry'
import {
  getToolExecutionService,
  PendingToolInteractionKind,
  PendingToolInteractionSnapshot
} from '../services/ToolExecutionService'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { SettingsRouteName } from '../config/SettingsRouteName'
import {
  CHAT_SPLIT_DETAIL_PANE_MIN_WIDTH,
  CHAT_SPLIT_LIST_PANE_MIN_WIDTH,
  clampIndexChatListPaneWidth,
  getDefaultIndexChatListPaneWidth,
  getIndexChatListPaneWidth,
  getIndexChatNavigationAvailableWidth,
  getIndexPageHorizontalPadding,
  getMaxIndexChatListPaneWidth,
  shouldUseIndexChatSplitLayout,
  LayoutSizeClass
} from '../config/LayoutProfile'
import { createButtonTouchHandler, getButtonScale } from '../utils/ButtonAnimationUtils'
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
import { IndexEmptyStateCard } from '../components/index/IndexEmptyStateCard'
import { IndexRecommendedPromptsCard } from '../components/index/IndexRecommendedPromptsCard'
import {
  getPresetPrompts,
  parseOpenNewChatWithPromptPayload,
  PresetPrompt,
  resolvePromptBody
} from '../config/PresetPrompts'
import { OnboardingOverlay } from '../components/onboarding/OnboardingOverlay'
import { getOnboardingViewModel } from '../viewmodels/OnboardingViewModel'
import { IndexSettingsPanel } from '../components/index/IndexSettingsPanel'
import { IndexSettingsSheetContent } from '../components/index/IndexSettingsSheetContent'
import { IndexSessionListSection } from '../components/index/IndexSessionListSection'
import { ChatMultiSelectToolbar } from '../components/chat/ChatMultiSelectToolbar'
import { ModelSelectorContent } from '../components/ModelSelector'
import {
  AssistantAvatarView,
  buildAssistantModelAvatarValue,
  isModelAssistantAvatar,
  normalizeAssistantAvatarValue,
  refreshAssistantAvatarCache
} from '../components/AssistantAvatar'
import { AssistantAvatarEditorSheet } from '../components/AssistantAvatarEditorSheet'
import { SettingsSheetType, SessionFilterType, SessionGroupData } from './index/IndexPageTypes'
import { getFilteredSessionsForIndex, buildSessionGroupsForIndex } from './index/IndexSessionGroupHelper'
import { SessionListGroupViewModel, rebuildSessionListGroupViewModels } from './index/IndexSessionListDataSource'
import {
  getFabOffsetXForIndex,
  getFabOffsetYForIndex,
  INDEX_NEW_CHAT_FAB_BOTTOM_SPACING,
  INDEX_NEW_CHAT_FAB_STACK_HEIGHT,
  INDEX_NEW_CHAT_FAB_SIZE,
  isHandAdaptiveActiveForIndex,
  shouldPlaceFabOnLeftForIndex
} from './index/IndexHandAdaptiveHelper'
import {
  INDEX_TAB_ASSISTANTS,
  INDEX_TAB_CHAT,
  INDEX_TAB_SETTINGS,
  shouldHideCompactTabsBarForIndex,
  shouldHideCompactTabsHostForIndex
} from './index/IndexTabsVisibilityHelper'
import {
  getSettingsSheetTitleText
} from './index/IndexSettingsTextHelper'
import { ChatPageRouteParams } from './chat/ChatPageRouteTypes'
import {
  IndexSettingsSheetActionCallbacks
} from './index/IndexSettingsSheetCoordinator'
import {
  buildHdsTopNavigationTitleBarOptions,
  getHdsTopNavigationBlurEffectiveEndOffset,
  getHdsTopNavigationMaskExtraHeight,
  HdsTopNavigationBlurOptions,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import {
  normalizeSystemPromptTemplate,
  SystemPromptTemplateDefaults
} from '../utils/SystemPromptTemplateUtils'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState, observeAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { tryHandleProviderDetailInternalBack } from '../components/ProviderDetailSheet'
import { tryHandleModelManageInternalBack } from './ModelManagePage'
import { TRANSPARENT_BG_COLOR } from '../utils/IconGeneratorUtils'
import { DEFAULT_PRIMARY_COLOR } from '../config/ThemeDefaults'

@Entry
@ComponentV2
struct Index {
  private static readonly COMPACT_TABS_BAR_HEIGHT: number = 56
  private static readonly COMPACT_TABS_FLOATING_SIDE_MARGIN: number = 16
  private static readonly TAB_ASSISTANTS: number = INDEX_TAB_ASSISTANTS
  private static readonly TAB_CHAT: number = INDEX_TAB_CHAT
  private static readonly TAB_SETTINGS: number = INDEX_TAB_SETTINGS
  @Local currentTabIndex: number = Index.TAB_CHAT
  @Local sessions: ChatSession[] = []
  @Local isLoading: boolean = false
  @Local currentThemeMode: ThemeMode = ThemeMode.SYSTEM
  @Local currentLanguage: AppLanguage = AppLanguage.SYSTEM
  @Local notifyEnabled: boolean = true
  @Local notifyOnComplete: boolean = true
  @Local notifyOnFailed: boolean = true
  // 首次启动引导。默认 true 防止 prefs 异步读取期间出现真页闪现
  @Local onboardingActive: boolean = true
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
  @Local assistants: Assistant[] = []
  @Local currentAssistantName: string = '默认助手'
  @Local currentAssistantAvatarSymbol: string = 'AI'
  @Local currentAssistantColor: string = DEFAULT_PRIMARY_COLOR
  @Local assistantProviders: ModelProvider[] = []
  @Local currentAssistantId: string = DEFAULT_ASSISTANT_ID
  @Local showAssistantSwitchSheet: boolean = false
  @Local openingAssistantId: string = ''
  @Local showAssistantEditorSheet: boolean = false
  @Local showAssistantModelSheet: boolean = false
  @Local showAssistantAvatarEditorSheet: boolean = false
  @Local assistantAvatarRenderTick: number = 0
  @Local editingAssistantId: string = ''
  @Local editingAssistantCreatedAt: number = 0
  @Local editingAssistantSortOrder: number = 0
  @Local editingAssistantIsDefault: boolean = false
  // 简化编辑器不暴露推理偏好 UI,这里仅用于在 save 时把原值回填到新 Assistant 对象避免丢失
  @Local editingAssistantReasoningLevelPreference: string = ''
  @Local assistantFormName: string = ''
  @Local assistantFormAvatarSymbol: string = 'AI'
  @Local assistantFormColor: string = DEFAULT_PRIMARY_COLOR
  @Local assistantFormSystemPrompt: string = ''
  @Local assistantFormDefaultProviderId: string = ''
  @Local assistantFormDefaultModelId: string = ''
  @Local assistantFormDefaultModelName: string = ''
  @Local assistantFormTemperatureEnabled: boolean = false
  @Local assistantFormTemperature: number = 0.7
  @Local assistantFormTopPEnabled: boolean = false
  @Local assistantFormTopP: number = 1.0
  @Local assistantFormPresencePenaltyEnabled: boolean = false
  @Local assistantFormPresencePenalty: number = 0
  @Local assistantFormFrequencyPenaltyEnabled: boolean = false
  @Local assistantFormFrequencyPenalty: number = 0
  @Local assistantFormContextMessageCount: number = 0
  @Local assistantFormMaxOutputTokens: number = 0
  @Local currentChatRouteName: string = ''
  @Local chatTabTopSessionId: string = ''
  @Local chatListPaneUserWidth: number = 0
  // 已经提示过的 pending 工具交互 id → 上次提示的时间戳。
  // 同一个 toolCall 在 cooldown 内不再重复提示, 避免用户切 Tab / tick 触发反复打扰。
  private recentlyPromptedToolInteractions: Map<string, number> = new Map()
  // 单条 SnackBar 队列: showSnackBar 是单实例(新调用直接 dismiss 旧的),
  // 多条提示 (in-app task alert + pending tool interaction) 会互相覆盖。
  // 这里把 SnackBar 串行化, 上一条播完再播下一条。
  private snackBarQueue: SnackBarDisplayOptions[] = []
  private snackBarQueueTimerId: number = -1
  private pendingToolInteractionAlertTimerId: number = -1
  private chatListPaneResizeSaveTimerId: number = -1
  private chatListPaneResizeChangeCount: number = 0
  private lastObservedChatListPaneWidth: number = 0
  private static readonly PENDING_TOOL_INTERACTION_PROMPT_COOLDOWN_MS: number = 60_000
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
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get fabShadowColor(): string {
    return this.isDarkMode ? 'rgba(0, 0, 0, 0.38)' : 'rgba(15, 23, 42, 0.18)'
  }
  @Local chatFontSize: number = 15
  @Local chatInputEnterKeySend: boolean = false
  @Local materialType: number = 100
  @Local materialLevel: number = 10
  @Local lightColorMode: string = 'default'
  // 监听从服务卡片打开新聊天的事件
  private get openNewChatTimestamp(): number {
    return getAppUiState().openNewChatTimestamp
  }
  private get openNewChatWithPromptPayload(): string {
    return getAppUiState().openNewChatWithPromptPayload
  }
  private get openSessionPayload(): string {
    return getAppUiState().openSessionPayload
  }
  private get taskEventTick(): number {
    return getAppUiState().taskEventTick
  }
  private get pendingToolInteractionTick(): number {
    return getAppUiState().pendingToolInteractionTick
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

  @Computed
  get assistantAvatarRefreshAt(): number {
    return getAppUiState().assistantAvatarRefreshAt
  }

  @Monitor('assistantAvatarRefreshAt')
  onAssistantAvatarRefreshMonitor(): void {
    if (this.assistantAvatarRefreshAt > 0 && this.assistantAvatarRefreshAt !== this.handledAssistantAvatarRefreshAt) {
      this.handledAssistantAvatarRefreshAt = this.assistantAvatarRefreshAt
      this.bumpAssistantAvatarRenderTick()
      this.loadAssistants()
    }
  }
  @Monitor('isMultiSelectMode')
  onMultiSelectModeMonitor(): void {
    this.compactMultiSelectToolbarHeightVp = 0
  }
  // 多选模式状态
  @Local isMultiSelectMode: boolean = false
  @Local selectedSessionIds: Array<string> = []
  @Local compactMultiSelectToolbarHeightVp: number = 0
  // 分享预览弹窗状态
  @Local showSharePreview: boolean = false
  @Local shareMessages: ChatMessage[] = []
  // Settings Sheet 关闭动画期间的状态机（避免“关闭回调晚到”误关新弹窗）
  private settingsSheetClosing: boolean = false
  private pendingSettingsSheetType: SettingsSheetType = SettingsSheetType.NONE
  private chatTabNavStack: NavPathStack = new NavPathStack()
  private settingsNavPathStack: NavPathStack = new NavPathStack()
  private static readonly CHAT_DETAIL_EMPTY_ROUTE: string = 'ChatDetailEmpty'
  private static readonly CHAT_PAGE_ROUTE: string = 'ChatPage'
  private settingsReturnTabIndex: number = Index.TAB_SETTINGS
  @Local currentSettingsRouteName: string = ''
  // 返回键退出控制
  private lastBackPressTime: number = 0
  private chatViewModel: ChatViewModel = ServiceRegistry.chat()
  private settingsManager = ServiceRegistry.settings()
  private preferencesService = ServiceRegistry.preferences()
  private assistantService = ServiceRegistry.assistant()
  private providerViewModel = ServiceRegistry.provider()
  private assistantListScroller: ListScroller = new ListScroller()
  private sessionListScroller: ListScroller = new ListScroller()
  private settingsRootScroller: Scroller = new Scroller()
  private settingsCallback: SettingsChangeCallback | null = null
  private holdingHandSubscribed: boolean = false
  private handAdaptiveLoadSeq: number = 0
  private sessionLoadSeq: number = 0
  private assistantLoadSeq: number = 0
  private assistantAvatarStateKey: string = ''
  private appUiStateDisposers: Array<() => void> = []
  private handledAssistantAvatarRefreshAt: number = 0
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
    this.resetChatListPaneResizeTracking()
    if (this.currentTabIndex === Index.TAB_SETTINGS && this.settingsNavPathStack.size() > 0) {
      this.syncSettingsDetailPresentationMode()
    }
    if (this.isSettingsSplitMode()) {
      this.dismissSettingsSheetForNavigation()
      if (this.currentTabIndex === Index.TAB_SETTINGS) {
        this.ensureSettingsSplitLandingRoute()
      }
      return
    }
    this.syncChatDetailPlaceholder()
    this.refreshSessionListProjection()
  }

  private isExpandedLayout(): boolean {
    return this.layoutSizeClass === LayoutSizeClass.EXPANDED && this.isLandscapeWindow()
  }

  onWindowMetricsChanged(): void {
    this.resetChatListPaneResizeTracking()
    if (this.currentTabIndex === Index.TAB_SETTINGS) {
      this.syncSettingsDetailPresentationMode()
      if (this.isSettingsSplitMode()) {
        this.dismissSettingsSheetForNavigation()
        this.ensureSettingsSplitLandingRoute()
      }
    }
    if (this.currentTabIndex === Index.TAB_CHAT) {
      this.syncChatDetailPlaceholder()
      this.refreshSessionListProjection()
    }
  }

  private isLandscapeWindow(): boolean {
    if (this.windowWidthVp <= 0 || this.windowHeightVp <= 0) {
      return false
    }
    return this.windowWidthVp > this.windowHeightVp
  }

  private getChatNavigationAvailableWidth(): number {
    return getIndexChatNavigationAvailableWidth(this.windowWidthVp, this.layoutSizeClass)
  }

  private getExpandedChatListWidth(): number {
    if (!this.isChatSplitLayout()) {
      return this.windowWidthVp
    }
    const availableWidth = this.getChatNavigationAvailableWidth()
    if (this.chatListPaneUserWidth > 0) {
      return clampIndexChatListPaneWidth(this.chatListPaneUserWidth, availableWidth)
    }
    return getDefaultIndexChatListPaneWidth(availableWidth)
  }

  private getExpandedChatListMaxWidth(): number {
    return getMaxIndexChatListPaneWidth(this.getChatNavigationAvailableWidth())
  }

  private getExpandedPageHorizontalPadding(): number {
    return getIndexPageHorizontalPadding(this.windowWidthVp)
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
    if (index !== Index.TAB_SETTINGS) {
      this.dismissSettingsSheetForNavigation()
    }
    this.currentTabIndex = index
    if (index === Index.TAB_CHAT) {
      this.loadSessions()
      this.syncChatDetailPlaceholder()
      return
    }
    if (index === Index.TAB_ASSISTANTS) {
      this.loadAssistants()
      this.loadSessions()
      return
    }
    if (index === Index.TAB_SETTINGS && shouldEnsureSettingsSplitLanding) {
      setAppUiStateValue(
        AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE,
        this.isSettingsSplitMode() ? SettingsPagePresentationMode.DETAIL_PANE : SettingsPagePresentationMode.PAGE
      )
      this.ensureSettingsSplitLandingRoute()
    }
  }

  private openChatRoute(params: ChatPageRouteParams): void {
    this.switchToTab(Index.TAB_CHAT)
    if (this.isSearchExpanded) {
      this.collapseSearchBeforeRouteChange((): void => {
        this.openChatRouteAfterSearchReset(params)
      })
      return
    }
    this.resetSearchBeforeRouteChange()
    this.openChatRouteAfterSearchReset(params)
  }

  private openChatRouteAfterSearchReset(params: ChatPageRouteParams): void {
    this.currentChatRouteName = Index.CHAT_PAGE_ROUTE
    if (this.isChatSplitLayout() && this.chatTabNavStack.size() > 0) {
      this.chatTabNavStack.replacePath({ name: Index.CHAT_PAGE_ROUTE, param: params as ChatPageRouteParams })
      return
    }
    this.chatTabNavStack.pushPath({ name: Index.CHAT_PAGE_ROUTE, param: params as ChatPageRouteParams })
  }

  private isChatSplitLayout(): boolean {
    return shouldUseIndexChatSplitLayout(this.windowWidthVp, this.windowHeightVp, this.layoutSizeClass)
  }

  private getChatNavigationMode(): NavigationMode {
    return this.isChatSplitLayout() ? NavigationMode.Split : NavigationMode.Stack
  }

  private toAreaWidthVp(width: Length): number {
    if (typeof width === 'number') {
      return width
    }
    if (typeof width === 'string') {
      const parsed = Number.parseFloat(width)
      if (Number.isNaN(parsed)) {
        return 0
      }
      return parsed
    }
    return 0
  }

  private resetChatListPaneResizeTracking(): void {
    this.chatListPaneResizeChangeCount = 0
    this.lastObservedChatListPaneWidth = 0
    this.clearChatListPaneResizeSaveTimer()
  }

  private clearChatListPaneResizeSaveTimer(): void {
    if (this.chatListPaneResizeSaveTimerId === -1) {
      return
    }
    clearTimeout(this.chatListPaneResizeSaveTimerId)
    this.chatListPaneResizeSaveTimerId = -1
  }

  private handleChatListPaneAreaChange(newArea: Area): void {
    if (!this.isChatSplitLayout()) {
      this.resetChatListPaneResizeTracking()
      return
    }
    const width = Math.round(this.toAreaWidthVp(newArea.width))
    if (width <= 0) {
      return
    }
    if (this.lastObservedChatListPaneWidth <= 0) {
      this.lastObservedChatListPaneWidth = width
      return
    }
    if (Math.abs(width - this.lastObservedChatListPaneWidth) < 1) {
      return
    }
    this.lastObservedChatListPaneWidth = width
    if (Math.abs(width - this.getExpandedChatListWidth()) < 2) {
      return
    }
    this.chatListPaneResizeChangeCount++
    if (this.chatListPaneResizeChangeCount < 3) {
      return
    }
    this.scheduleSaveChatListPaneWidth(width)
  }

  private scheduleSaveChatListPaneWidth(width: number): void {
    this.clearChatListPaneResizeSaveTimer()
    this.chatListPaneResizeSaveTimerId = setTimeout((): void => {
      this.chatListPaneResizeSaveTimerId = -1
      if (!this.isChatSplitLayout()) {
        return
      }
      const nextWidth = clampIndexChatListPaneWidth(width, this.getChatNavigationAvailableWidth())
      if (Math.abs(nextWidth - this.chatListPaneUserWidth) < 1) {
        return
      }
      this.chatListPaneUserWidth = nextWidth
      this.preferencesService.setNumber(PreferenceKeys.CHAT_SPLIT_LIST_PANE_WIDTH, nextWidth).catch((error: Object) => {
        console.error('Index', `Failed to save chat split pane width: ${JSON.stringify(error)}`)
      })
    }, 650)
  }

  private syncChatDetailPlaceholder(): void {
    if (this.currentTabIndex !== Index.TAB_CHAT) {
      return
    }
    const wantsPlaceholder = this.isChatSplitLayout()
    const stackSize = this.chatTabNavStack.size()
    if (wantsPlaceholder) {
      if (stackSize === 0) {
        this.currentChatRouteName = Index.CHAT_DETAIL_EMPTY_ROUTE
        this.chatTabNavStack.pushPath({ name: Index.CHAT_DETAIL_EMPTY_ROUTE })
      }
      return
    }
    if (stackSize === 0) {
      this.currentChatRouteName = ''
      return
    }
    if (stackSize === 1 && this.isChatTabTopPlaceholder()) {
      this.currentChatRouteName = ''
      this.chatTabNavStack.clear(false)
    }
  }

  private isChatTabTopPlaceholder(): boolean {
    const size = this.chatTabNavStack.size()
    if (size === 0) {
      return false
    }
    const names = this.chatTabNavStack.getAllPathName()
    return names[size - 1] === Index.CHAT_DETAIL_EMPTY_ROUTE
  }

  private isChatDetailRouteActive(): boolean {
    return this.currentChatRouteName === Index.CHAT_PAGE_ROUTE
  }

  private openSettingsDestination(routeName: SettingsRouteName, param: Object | null = null): void {
    this.settingsReturnTabIndex = this.currentTabIndex !== Index.TAB_SETTINGS ? this.currentTabIndex : Index.TAB_SETTINGS
    this.switchToTab(Index.TAB_SETTINGS, false)
    this.dismissSettingsSheetForNavigation()
    this.currentSettingsRouteName = routeName
    this.syncSettingsDetailPresentationMode()
    if (this.isSettingsSplitMode() && this.settingsNavPathStack.size() > 0) {
      if (param !== null) {
        this.settingsNavPathStack.replacePath({ name: routeName, param: param })
      } else {
        this.settingsNavPathStack.replacePath({ name: routeName })
      }
      return
    }
    if (param !== null) {
      this.settingsNavPathStack.pushPath({ name: routeName, param: param })
    } else {
      this.settingsNavPathStack.pushPath({ name: routeName })
    }
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

  onOpenNewChatWithPrompt(): void {
    const payload = parseOpenNewChatWithPromptPayload(this.openNewChatWithPromptPayload)
    if (payload === null || payload.ts <= 0 || payload.text === '') {
      return
    }
    this.openChatRoute({ initialDraft: payload.text } as ChatPageRouteParams)
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

  onPendingToolInteractionTickChanged(): void {
    if (this.pendingToolInteractionTick <= 0) {
      return
    }
    this.schedulePendingToolInteractionAlert()
  }

  private schedulePendingToolInteractionAlert(): void {
    if (this.pendingToolInteractionAlertTimerId !== -1) {
      clearTimeout(this.pendingToolInteractionAlertTimerId)
    }
    this.pendingToolInteractionAlertTimerId = setTimeout((): void => {
      this.pendingToolInteractionAlertTimerId = -1
      this.processPendingToolInteractionAlert(false)
    }, 0)
  }

  onSessionListRefresh(): void {
    if (this.sessionListRefreshAt > 0) {
      this.loadAssistants()
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
      observeAppUiState(AppStorageKeys.OPEN_NEW_CHAT_WITH_PROMPT, (): void => this.onOpenNewChatWithPrompt()),
      observeAppUiState(AppStorageKeys.OPEN_SESSION_PAYLOAD, (): void => this.onOpenSessionPayloadChanged()),
      observeAppUiState(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, (): void => this.onActiveChatSessionIdChanged()),
      observeAppUiState(AppStorageKeys.ASSISTANT_AVATAR_REFRESH_AT,
        (): void => this.onAssistantAvatarRefreshMonitor()),
      observeAppUiState(AppStorageKeys.TASK_EVENT_TICK, (): void => this.onTaskEventTickChanged()),
      observeAppUiState(AppStorageKeys.PENDING_TOOL_INTERACTION_TICK,
        (): void => this.onPendingToolInteractionTickChanged()),
      observeAppUiState(AppStorageKeys.SETTINGS_HAND_ADAPTIVE_CHANGED_AT,
        (): void => this.onHandAdaptiveSettingsTickChanged()),
      getToolExecutionService().addPendingInteractionChangeCallback((): void => {
        this.schedulePendingToolInteractionAlert()
      })
    ]
  }

  private unregisterAppUiStateObservers(): void {
    for (let i = 0; i < this.appUiStateDisposers.length; i++) {
      this.appUiStateDisposers[i]()
    }
    this.appUiStateDisposers = []
  }

  private clearPendingToolInteractionAlertTimer(): void {
    if (this.pendingToolInteractionAlertTimerId === -1) {
      return
    }
    clearTimeout(this.pendingToolInteractionAlertTimerId)
    this.pendingToolInteractionAlertTimerId = -1
  }

  aboutToAppear(): void {
    this.registerAppUiStateObservers()
    this.chatTabNavStack.setInterception({
      didShow: (_from: NavDestinationContext | "navBar", to: NavDestinationContext | "navBar",
        _operation: NavigationOperation, _isAnimated: boolean): void => {
        const size = this.chatTabNavStack.size()
        if (to === 'navBar' || size <= 0) {
          this.currentChatRouteName = ''
          this.chatTabTopSessionId = ''
          this.refreshSessionListProjection()
          this.loadSessions()
          this.processInAppTaskAlertPayload(this.inAppTaskAlertPayload)
          // 切回聊天列表时尊重 cooldown, 避免同一个 pending 工具调用每次切 Tab 都打扰用户。
          this.processPendingToolInteractionAlert(false)
          return
        }
        const names = this.chatTabNavStack.getAllPathName()
        const topName = names[size - 1]
        this.currentChatRouteName = topName
        if (topName === Index.CHAT_PAGE_ROUTE) {
          const topParam = this.chatTabNavStack.getParamByIndex(size - 1) as ChatPageRouteParams | undefined
          this.chatTabTopSessionId = topParam?.sessionId ?? ''
        } else {
          this.chatTabTopSessionId = ''
        }
        this.refreshSessionListProjection()
        this.processInAppTaskAlertPayload(this.inAppTaskAlertPayload)
        this.processPendingToolInteractionAlert(false)
      }
    })
    this.settingsNavPathStack.setInterception({
      didShow: (_from: NavDestinationContext | "navBar", to: NavDestinationContext | "navBar",
        _operation: NavigationOperation, _isAnimated: boolean): void => {
        if (to === 'navBar' || this.settingsNavPathStack.size() <= 0) {
          this.currentSettingsRouteName = ''
          setAppUiStateValue(AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE, SettingsPagePresentationMode.PAGE)
          const returnTabIndex = this.settingsReturnTabIndex
          this.settingsReturnTabIndex = Index.TAB_SETTINGS
          if (returnTabIndex !== Index.TAB_SETTINGS) {
            this.switchToTab(returnTabIndex, false)
          }
        }
      }
    })

    this.loadAssistants()
    this.loadSessions()
    this.loadSettings()
    this.registerSettingsCallback()
    this.handleOpenSessionPayload(this.openSessionPayload)
    this.handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
    this.processPendingToolInteractionAlert(false)
    this.initializeOnboarding()
  }

  private async initializeOnboarding(): Promise<void> {
    try {
      const completed = await this.preferencesService.getOnboardingCompleted()
      if (completed) {
        this.onboardingActive = false
        return
      }
      getOnboardingViewModel().start(this.currentThemeMode, this.currentColorTheme)
      this.onboardingActive = true
    } catch (err) {
      console.error('Index', `Failed to initialize onboarding: ${JSON.stringify(err)}`)
      // 读取失败时默认跳过 onboarding 不阻塞用户
      this.onboardingActive = false
    }
  }

  private handleOnboardingCompleted(prefillText: string): void {
    this.preferencesService.setOnboardingCompleted(true).catch((err: Object) => {
      console.error('Index', `Failed to persist onboarding flag: ${JSON.stringify(err)}`)
    })
    this.onboardingActive = false
    if (prefillText !== '') {
      this.openChatRoute({ initialDraft: prefillText } as ChatPageRouteParams)
    }
  }

  onPageShow(): void {
    this.loadAssistants()
    this.loadSessions()
    this.refreshSettingsState()
    this.loadHandAdaptiveSettings()
    this.processInAppTaskAlertPayload(this.inAppTaskAlertPayload)
    this.processPendingToolInteractionAlert(false)
  }

  aboutToDisappear(): void {
    this.unregisterAppUiStateObservers()
    this.clearPendingToolInteractionAlertTimer()
    this.clearChatListPaneResizeSaveTimer()
    this.unsubscribeHoldingHand()
    if (this.settingsCallback !== null) {
      this.settingsManager.unregisterCallback(this.settingsCallback)
      this.settingsCallback = null
    }
    if (this.snackBarQueueTimerId !== -1) {
      clearTimeout(this.snackBarQueueTimerId)
      this.snackBarQueueTimerId = -1
    }
    this.snackBarQueue = []
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

    if (this.currentTabIndex === Index.TAB_SETTINGS && this.settingsNavPathStack.size() > 0) {
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

    if (this.currentTabIndex === Index.TAB_CHAT && this.isChatSplitLayout() && this.isChatDetailRouteActive()) {
      this.currentChatRouteName = Index.CHAT_DETAIL_EMPTY_ROUTE
      this.chatTabNavStack.replacePath({ name: Index.CHAT_DETAIL_EMPTY_ROUTE })
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
      },
      onChatInputSettingsChanged: (enterKeySend: boolean): void => {
        this.chatInputEnterKeySend = enterKeySend
        this.syncSettingsSummaryToStorage()
      },
      onMaterialSettingsChanged: (materialType: number, materialLevel: number, lightColorMode: string): void => {
        this.materialType = materialType
        this.materialLevel = materialLevel
        this.lightColorMode = lightColorMode
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
    this.chatInputEnterKeySend = this.settingsManager.getChatInputEnterKeySend()
    this.materialType = this.settingsManager.getMaterialType()
    this.materialLevel = this.settingsManager.getMaterialLevel()
    this.lightColorMode = this.settingsManager.getLightColorMode()
    await this.loadChatListPaneWidthPreference()
    await this.loadHandAdaptiveSettings()
    this.syncSettingsSummaryToStorage()
  }

  private async loadChatListPaneWidthPreference(): Promise<void> {
    const width = await this.preferencesService.getNumber(PreferenceKeys.CHAT_SPLIT_LIST_PANE_WIDTH, 0)
    this.chatListPaneUserWidth = width >= CHAT_SPLIT_LIST_PANE_MIN_WIDTH ? Math.round(width) : 0
  }

  private patchAssistantInMemory(assistant: Assistant): void {
    const nextAssistants: Assistant[] = []
    let replaced = false
    const previousAvatarStateKey = this.assistantAvatarStateKey
    for (let i = 0; i < this.assistants.length; i++) {
      if (this.assistants[i].id === assistant.id) {
        nextAssistants.push(assistant)
        replaced = true
      } else {
        nextAssistants.push(this.assistants[i])
      }
    }
    if (!replaced) {
      nextAssistants.push(assistant)
    }
    this.assistants = nextAssistants
    if (assistant.id === this.currentAssistantId || this.currentAssistantId === '') {
      this.currentAssistantId = assistant.id !== '' ? assistant.id : DEFAULT_ASSISTANT_ID
      this.applyCurrentAssistantSnapshot(assistant)
    }
    this.assistantAvatarStateKey = this.buildAssistantAvatarStateKey(nextAssistants)
    if (this.assistantAvatarStateKey !== previousAvatarStateKey) {
      this.bumpAssistantAvatarRenderTick()
    }
    this.refreshSessionListProjection()
  }

  private mergeLoadedAssistants(loadedAssistants: Assistant[]): Assistant[] {
    return loadedAssistants
  }

  private applyCurrentAssistantSnapshot(assistant: Assistant | null): void {
    if (assistant === null) {
      this.currentAssistantName = '默认助手'
      this.currentAssistantAvatarSymbol = 'AI'
      this.currentAssistantColor = this.themePrimary
      return
    }
    this.currentAssistantName = assistant.name
    this.currentAssistantAvatarSymbol = this.normalizeAssistantAvatarSymbol(assistant.avatarSymbol)
    this.currentAssistantColor = assistant.color !== '' ? assistant.color : this.themePrimary
  }

  private buildAssistantAvatarStateKey(assistants: Assistant[]): string {
    const parts: string[] = []
    for (let i = 0; i < assistants.length; i++) {
      parts.push(`${assistants[i].id}:${assistants[i].avatarSymbol}:${assistants[i].color}`)
    }
    return parts.join('|')
  }

  private buildAssistantListStateKey(assistants: Assistant[]): string {
    const parts: string[] = []
    for (let i = 0; i < assistants.length; i++) {
      const assistant = assistants[i]
      parts.push(`${assistant.id}:${assistant.name}:${assistant.avatarSymbol}:${assistant.color}:` +
        `${assistant.defaultProviderId}:${assistant.defaultModelId}:${assistant.defaultModelName}:` +
        `${assistant.systemPrompt}:${assistant.temperatureEnabled ? '1' : '0'}:${assistant.temperature}:` +
        `${assistant.isDefault ? '1' : '0'}:${assistant.sortOrder}`)
    }
    return parts.join('|')
  }

  private bumpAssistantAvatarRenderTick(): void {
    this.assistantAvatarRenderTick += 1
  }

  private async loadAssistants(): Promise<void> {
    const seq = this.assistantLoadSeq + 1
    this.assistantLoadSeq = seq
    try {
      const assistants = await this.assistantService.getAllAssistants()
      const current = await this.assistantService.getCurrentAssistant()
      if (seq !== this.assistantLoadSeq) {
        return
      }
      const nextAssistants = this.mergeLoadedAssistants(assistants)
      const nextAvatarStateKey = this.buildAssistantAvatarStateKey(nextAssistants)
      const avatarStateChanged = nextAvatarStateKey !== this.assistantAvatarStateKey
      if (this.buildAssistantListStateKey(nextAssistants) !== this.buildAssistantListStateKey(this.assistants)) {
        this.assistants = nextAssistants
      }
      this.assistantAvatarStateKey = nextAvatarStateKey
      if (avatarStateChanged) {
        this.bumpAssistantAvatarRenderTick()
      }
      this.currentAssistantId = current.id !== '' ? current.id : DEFAULT_ASSISTANT_ID
      const currentAssistant = this.findAssistantById(this.currentAssistantId)
      this.applyCurrentAssistantSnapshot(currentAssistant !== null ? currentAssistant : current)
      this.refreshSessionListProjection()
    } catch (error) {
      if (seq !== this.assistantLoadSeq) {
        return
      }
      console.error('Index', `Failed to load assistants: ${JSON.stringify(error)}`)
      this.currentAssistantId = DEFAULT_ASSISTANT_ID
      this.applyCurrentAssistantSnapshot(null)
    }
  }

  private async loadAssistantProvidersIfNeeded(): Promise<void> {
    if (this.assistantProviders.length > 0) {
      return
    }
    try {
      this.assistantProviders = await this.providerViewModel.loadProviders()
    } catch (error) {
      console.error('Index', `Failed to load assistant providers: ${JSON.stringify(error)}`)
      this.assistantProviders = []
    }
  }

  private async switchAssistant(assistantId: string): Promise<void> {
    const previousAssistantId = this.currentAssistantId
    const assistant = await this.assistantService.setCurrentAssistantId(assistantId)
    this.currentAssistantId = assistant.id !== '' ? assistant.id : DEFAULT_ASSISTANT_ID
    this.patchAssistantInMemory(assistant)
    this.selectedSessionIds = []
    this.isMultiSelectMode = false
    if (this.isSearchExpanded) {
      this.searchText = ''
      this.isSearchExpanded = false
    }
    if (previousAssistantId !== this.currentAssistantId && this.isChatSplitLayout() && this.isChatDetailRouteActive()) {
      this.currentChatRouteName = Index.CHAT_DETAIL_EMPTY_ROUTE
      this.chatTabNavStack.replacePath({ name: Index.CHAT_DETAIL_EMPTY_ROUTE })
    }
    this.refreshSessionListProjection()
  }

  private refreshSettingsState(): void {
    this.currentThemeMode = this.settingsManager.getThemeMode()
    this.currentLanguage = this.settingsManager.getLanguage()
    this.currentColorTheme = this.settingsManager.getColorTheme()
    this.notifyEnabled = this.settingsManager.getNotificationEnabled()
    this.notifyOnComplete = this.settingsManager.getNotifyOnCompleteEnabled()
    this.notifyOnFailed = this.settingsManager.getNotifyOnFailedEnabled()
    this.chatFontSize = this.settingsManager.getChatFontSize()
    this.chatInputEnterKeySend = this.settingsManager.getChatInputEnterKeySend()
    this.materialType = this.settingsManager.getMaterialType()
    this.materialLevel = this.settingsManager.getMaterialLevel()
    this.lightColorMode = this.settingsManager.getLightColorMode()
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
    setAppUiStateValue(AppStorageKeys.CHAT_INPUT_ENTER_KEY_SEND, this.chatInputEnterKeySend)
    setAppUiStateValue(AppStorageKeys.MATERIAL_TYPE, this.materialType)
    setAppUiStateValue(AppStorageKeys.MATERIAL_LEVEL, this.materialLevel)
    setAppUiStateValue(AppStorageKeys.LIGHT_COLOR_MODE, this.lightColorMode)
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
    return this.getFabBaseBottomInset() + INDEX_NEW_CHAT_FAB_STACK_HEIGHT +
      INDEX_NEW_CHAT_FAB_BOTTOM_SPACING + cardBottomBreathingRoom
  }

  private getCompactMultiSelectToolbarBottomInsetVp(): number {
    return Math.max(this.px2vp(this.bottomAvoidHeight) + 10, 20)
  }

  private getSessionListBottomSpacerHeight(): number {
    if (!this.isMultiSelectMode) {
      return this.getChatListBottomSpacerHeight()
    }
    if (this.isExpandedLayout()) {
      return 16
    }
    if (this.compactMultiSelectToolbarHeightVp > 0) {
      return this.compactMultiSelectToolbarHeightVp
    }
    return this.getCompactMultiSelectToolbarBottomInsetVp() + 118
  }

  private getFabOffsetY(): number {
    return getFabOffsetYForIndex(this.getFabBaseBottomInset())
  }

  private getCompactChatHeaderDefaultHeight(): number {
    return this.px2vp(this.topAvoidHeight) + 56
  }

  private getCompactChatHeaderOverlayHeight(): number {
    return this.getCompactChatHeaderDefaultHeight()
  }

  private getChatListTopSpacerHeight(): number {
    // 顶部模糊蒙版会向下渐变 maskExtraHeight，列表第一项需让出这一段，
    // 否则会落在模糊带上（卡片时间被模糊、筛选汇总行无法点击）。
    return this.getCompactChatHeaderOverlayHeight() + this.getCompactChatTitleBarMaskExtraHeight()
  }

  private getCompactSettingsHeaderDefaultHeight(): number {
    return this.px2vp(this.topAvoidHeight) + 56
  }

  private getCompactSettingsTitleBarMaskExtraHeight(): number {
    return getHdsTopNavigationMaskExtraHeight(this.windowWidthVp, this.windowHeightVp)
  }

  private getSettingsListTopSpacerHeight(): number {
    if (this.isSettingsSplitMode()) {
      return 0
    }
    return this.getCompactSettingsHeaderDefaultHeight() + this.getCompactSettingsTitleBarMaskExtraHeight()
  }

  private readMeasuredAreaHeight(area: Area): number {
    const height = area.height
    if (typeof height !== 'number' || Number.isNaN(height)) {
      return 0
    }
    return height
  }

  private handleCompactMultiSelectToolbarAreaChange(area: Area): void {
    const nextHeight = this.readMeasuredAreaHeight(area)
    if (nextHeight <= 0 || Math.abs(nextHeight - this.compactMultiSelectToolbarHeightVp) < 0.5) {
      return
    }
    this.compactMultiSelectToolbarHeightVp = nextHeight
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
    this.enqueueSnackBar(opts)
    setAppUiStateValue(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, '')
  }

  private buildPendingToolInteractionMessage(interaction: PendingToolInteractionSnapshot): string {
    const title = interaction.sessionTitle.trim() !== '' ? interaction.sessionTitle.trim() : '新对话'
    if (interaction.kind === PendingToolInteractionKind.ASK_USER) {
      return `会话「${title}」需要你回答一个问题`
    }
    return `会话「${title}」需要确认工具调用`
  }

  private shouldPromptPendingToolInteraction(interaction: PendingToolInteractionSnapshot,
    forcePrompt: boolean): boolean {
    if (interaction.sessionId === '') {
      return false
    }
    if (this.activeChatSessionId === interaction.sessionId) {
      return false
    }
    if (forcePrompt) {
      return true
    }
    const lastPromptedAt = this.recentlyPromptedToolInteractions.get(interaction.id) ?? 0
    if (lastPromptedAt === 0) {
      return true
    }
    return Date.now() - lastPromptedAt >= Index.PENDING_TOOL_INTERACTION_PROMPT_COOLDOWN_MS
  }

  private prunePromptedToolInteractionsAgainst(currentIds: Set<string>): void {
    const stale: string[] = []
    this.recentlyPromptedToolInteractions.forEach((_value: number, key: string) => {
      if (!currentIds.has(key)) {
        stale.push(key)
      }
    })
    for (let i = 0; i < stale.length; i++) {
      this.recentlyPromptedToolInteractions.delete(stale[i])
    }
  }

  private processPendingToolInteractionAlert(forcePrompt: boolean): void {
    const interactions = ServiceRegistry.toolExecution().getPendingInteractions()
    const currentIds: Set<string> = new Set<string>()
    for (let i = 0; i < interactions.length; i++) {
      currentIds.add(interactions[i].id)
    }
    this.prunePromptedToolInteractionsAgainst(currentIds)
    if (interactions.length === 0) {
      return
    }
    let interaction: PendingToolInteractionSnapshot | null = null
    for (let i = 0; i < interactions.length; i++) {
      if (this.shouldPromptPendingToolInteraction(interactions[i], forcePrompt)) {
        interaction = interactions[i]
        break
      }
    }
    if (interaction === null) {
      return
    }
    const targetSessionId = interaction.sessionId
    this.recentlyPromptedToolInteractions.set(interaction.id, Date.now())
    const opts = new SnackBarDisplayOptions()
    opts.message = this.buildPendingToolInteractionMessage(interaction)
    opts.duration = 6000
    opts.tone = SnackBarTone.DEFAULT
    opts.actionText = $r('app.string.task_alert_view')
    opts.onAction = (): void => {
      this.openChatRoute({ sessionId: targetSessionId } as ChatPageRouteParams)
    }
    this.enqueueSnackBar(opts)
  }

  // 把 SnackBar 串行化:
  // - 队列空闲 → 立即播第一条, 并按 duration 调度 shift 队列;
  // - 队列在播 → 入队, 等当前一条播完再播下一条。
  // 由此 task alert 与 pending tool interaction 不再互相覆盖。
  private enqueueSnackBar(opts: SnackBarDisplayOptions): void {
    this.snackBarQueue.push(opts)
    if (this.snackBarQueueTimerId !== -1) {
      return
    }
    this.playNextSnackBar()
  }

  private playNextSnackBar(): void {
    if (this.snackBarQueue.length === 0) {
      this.snackBarQueueTimerId = -1
      return
    }
    const next = this.snackBarQueue.shift()
    if (next === undefined) {
      this.snackBarQueueTimerId = -1
      return
    }
    showSnackBar(this.getUIContext(), next)
    const dwell = next.duration > 0 ? next.duration + 200 : 2200
    this.snackBarQueueTimerId = setTimeout((): void => {
      this.snackBarQueueTimerId = -1
      this.playNextSnackBar()
    }, dwell)
  }

  private shouldHandleInAppTaskAlert(): boolean {
    if (this.isChatDetailRouteActive()) {
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
    if (!this.isChatSplitLayout() && this.isChatDetailRouteActive()) {
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
            existing.assistantId = this.normalizeSessionAssistantId(fresh.assistantId)
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
    if (this.chatTabTopSessionId === sessionId) {
      if (this.isChatSplitLayout()) {
        this.currentChatRouteName = Index.CHAT_DETAIL_EMPTY_ROUTE
        this.chatTabNavStack.replacePath({ name: Index.CHAT_DETAIL_EMPTY_ROUTE })
      } else {
        this.currentChatRouteName = ''
        this.chatTabNavStack.clear(false)
      }
    }
    if (this.activeChatSessionId === sessionId) {
      setAppUiStateValue(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, '')
    }
    this.refreshSessionListProjection()
    this.showIndexSnack($r('app.string.conversation_deleted'), 2000, SnackBarTone.SUCCESS)
  }

  getFilteredSessions(): ChatSession[] {
    return getFilteredSessionsForIndex(this.getAssistantScopedSessions(), this.searchText, this.currentSessionFilter)
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
    if (!this.isChatSplitLayout()) {
      return ''
    }
    if (this.activeChatSessionId !== '') {
      return this.activeChatSessionId
    }
    return this.chatTabTopSessionId
  }

  build() {
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
          backgroundColor: this.themeBackground,
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
          backgroundColor: this.themeBackground,
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.showSystemPromptSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAssistantSwitchSheet, this.AssistantSwitchSheetBuilder(), {
          height: SheetSize.MEDIUM,
          dragBar: true,
          showClose: true,
          backgroundColor: this.themeBackground,
          preferType: SheetType.BOTTOM,
          title: { title: $r('app.string.assistant_switch_title') },
          onDisappear: () => {
            this.showAssistantSwitchSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAssistantEditorSheet, this.AssistantEditorSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          backgroundColor: this.themeBackground,
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.showAssistantEditorSheet = false
            this.showAssistantModelSheet = false
            this.showAssistantAvatarEditorSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAssistantAvatarEditorSheet, this.AssistantAvatarEditorSheetBuilder(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          backgroundColor: this.themeBackground,
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.showAssistantAvatarEditorSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAssistantModelSheet, this.AssistantModelSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: true,
          backgroundColor: this.themeBackground,
          preferType: SheetType.BOTTOM,
          title: { title: $r('app.string.assistant_default_model') }
        })

      if (this.onboardingActive) {
        OnboardingOverlay({
          onCompleted: (prefillText: string): void => {
            this.handleOnboardingCompleted(prefillText)
          }
        })
      }

    }
    .width('100%')
    .height('100%')
  }

  @Builder
  CompactRoot() {
    Column() {
      if (this.shouldApplyCompactContentTopInset()) {
        Column()
          .width('100%')
          .height(this.px2vp(this.topAvoidHeight))
      }

      if (this.shouldHideCompactTabsHost()) {
        Column() {
          this.CompactCurrentTabContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsTabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
          TabContent() {
            this.AssistantsTab()
          }
          .tabBar(this.TabBarAssistants())

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
        .barHeight(this.getCompactTabsHostBarHeight())
        .barOverlap(true)
        .barBackgroundColor(Color.Transparent)
        .barBackgroundBlurStyle(BlurStyle.COMPONENT_THIN)
        .barFloatingStyle(this.buildBottomTabsFloatingStyle())
        .scrollable(false)
        .cachedMaxCount(3, TabsCacheMode.CACHE_LATEST_SWITCHED)
        .onChange((index: number) => {
          if (this.currentTabIndex !== index) {
            this.switchToTab(index)
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  private shouldHideCompactTabsHost(): boolean {
    return shouldHideCompactTabsHostForIndex(this.currentTabIndex, this.isMultiSelectMode)
  }

  private shouldHideCompactTabsBar(): boolean {
    return shouldHideCompactTabsBarForIndex(this.currentTabIndex, this.currentSettingsRouteName,
      this.isChatDetailRouteActive())
  }

  @Builder
  private CompactCurrentTabContent() {
    if (this.currentTabIndex === Index.TAB_CHAT) {
      this.ChatTab()
    } else if (this.currentTabIndex === Index.TAB_ASSISTANTS) {
      this.AssistantsTab()
    } else {
      this.SettingsTab()
    }
  }

  private getCompactTabsHostBarHeight(): number {
    return this.shouldHideCompactTabsBar() ? 0 : this.getCompactTabsBarHeight()
  }

  @Builder
  ExpandedRoot() {
    Row() {
      this.ExpandedNavigationRail()

        Column() {
          // ChatTab 由 HdsNavigation 自己处理 statusBar avoid（默认 expandSafeArea），
          // 在这里不再让一次 24vp，避免叠加。
          // AssistantsTab / SettingsTab 自身没有 HdsNavigation 包裹，仍需外层让出 statusBar。
          if (this.currentTabIndex === Index.TAB_CHAT) {
            Column() {
              this.ChatTab()
            }
            .width('100%')
            .layoutWeight(1)
            .padding({
              left: this.getExpandedPageHorizontalPadding(),
              right: this.getExpandedPageHorizontalPadding(),
              bottom: 12
            })
          } else if (this.currentTabIndex === Index.TAB_ASSISTANTS) {
            Column()
              .width('100%')
              .height(this.px2vp(this.topAvoidHeight))
            this.ExpandedAssistantsTab()
          } else {
            Column()
              .width('100%')
              .height(this.px2vp(this.topAvoidHeight))
            this.ExpandedSettingsTab()
          }
        }
        .layoutWeight(1)
      .height('100%')
      .backgroundColor(this.themeBackground)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  @Builder
  ExpandedNavigationRail() {
    Column({ space: 6 }) {
      Column()
        .width('100%')
        .height(this.px2vp(this.topAvoidHeight))

      this.RailTabButton(Index.TAB_ASSISTANTS, $r('sys.symbol.person_fill'), $r('sys.symbol.person'),
        $r('app.string.tab_assistants'))
      this.RailTabButton(Index.TAB_CHAT, $r('sys.symbol.message_fill'), $r('sys.symbol.message'), $r('app.string.tab_chat'))
      this.RailTabButton(Index.TAB_SETTINGS, $r('sys.symbol.gearshape_fill'), $r('sys.symbol.gearshape'), $r('app.string.tab_settings'))

      Blank()
    }
    .width(88)
    .height('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 12 })
    .backgroundColor(this.themeSurface)
    .border({
      width: { right: 1 },
      color: $r('app.color.divider')
    })
  }

  @Builder
  ExpandedSettingsTab() {
    Column() {
      this.SettingsTab()
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(this.themeBackground)
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

  private normalizeSessionAssistantId(assistantId: string): string {
    return assistantId !== '' ? assistantId : DEFAULT_ASSISTANT_ID
  }

  private getAssistantScopedSessions(): ChatSession[] {
    const scopedSessions: ChatSession[] = []
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.normalizeSessionAssistantId(this.sessions[i].assistantId) === this.currentAssistantId) {
        scopedSessions.push(this.sessions[i])
      }
    }
    return scopedSessions
  }

  private findAssistantById(assistantId: string): Assistant | null {
    for (let i = 0; i < this.assistants.length; i++) {
      if (this.assistants[i].id === assistantId) {
        return this.assistants[i]
      }
    }
    return null
  }

  private getCurrentAssistantName(): string {
    return this.currentAssistantName
  }

  private getCurrentAssistantSymbol(): string {
    return this.currentAssistantAvatarSymbol
  }

  private getCurrentAssistantColor(): string {
    return this.currentAssistantColor !== '' ? this.currentAssistantColor : this.themePrimary
  }

  private normalizeAssistantAvatarSymbol(value: string): string {
    return normalizeAssistantAvatarValue(value)
  }

  private getAssistantRenderKey(assistant: Assistant): string {
    return `${assistant.id}:${assistant.name}:${assistant.avatarSymbol}:${assistant.color}:` +
      `${assistant.defaultProviderId}:${assistant.defaultModelId}:${assistant.defaultModelName}:` +
      `${assistant.systemPrompt}:${assistant.temperatureEnabled ? '1' : '0'}:${assistant.temperature}:` +
      `${assistant.isDefault ? '1' : '0'}:${assistant.sortOrder}:${this.assistantAvatarRenderTick}`
  }

  private getAssistantAvatarRenderKey(symbol: string, color: string, size: number, radius: number,
    fontSize: number, providerId: string = '', modelId: string = '', modelName: string = ''): string {
    return `${symbol}:${color}:${size}:${radius}:${fontSize}:${providerId}:${modelId}:${modelName}:` +
      `${this.assistantAvatarRenderTick}`
  }

  private getCurrentAssistantSwitchRenderKey(): string {
    return `${this.currentAssistantId}:${this.currentAssistantName}:${this.currentAssistantAvatarSymbol}:` +
      `${this.currentAssistantColor}:${this.assistantAvatarRenderTick}`
  }

  private getAssistantSwitchMaxWidth(): number {
    if (this.windowWidthVp <= 0) {
      return 260
    }
    return Math.max(140, this.windowWidthVp - 104)
  }

  private getAssistantSwitchNameMaxWidth(): number {
    return Math.max(72, this.getAssistantSwitchMaxWidth() - 82)
  }

  private isTabActive(index: number): boolean {
    return this.currentTabIndex === index
  }

  private getCompactTabsBottomInset(): number {
    return this.getCompactTabsHostBarHeight() + this.getCompactTabsFloatingBottomMargin()
  }

  private getCompactTabsFloatingBottomMargin(): number {
    if (this.shouldHideCompactTabsBar()) {
      return 0
    }
    return this.px2vp(this.bottomAvoidHeight) > 0 ? 24 : 12
  }

  private buildBottomTabsFloatingStyle(): HdsTabsFloatingStyle {
    const opts = new CompactTabsFloatingStyleOptions()
    opts.materialType = this.materialType
    opts.materialLevel = this.materialLevel
    opts.lightColorMode = this.lightColorMode
    opts.themePrimary = this.themePrimary
    opts.barSideMargin = Index.COMPACT_TABS_FLOATING_SIDE_MARGIN
    opts.barBottomMargin = this.getCompactTabsFloatingBottomMargin()
    return buildCompactTabsFloatingStyle(opts)
  }

  @Builder
  TabBarChat() {
    IndexBottomTabItem({
      active: this.isTabActive(Index.TAB_CHAT),
      activeIcon: $r('sys.symbol.ellipsis_message_fill'),
      inactiveIcon: $r('sys.symbol.ellipsis_message'),
      label: $r('app.string.tab_chat')
    })
  }

  @Builder
  TabBarAssistants() {
    IndexBottomTabItem({
      active: this.isTabActive(Index.TAB_ASSISTANTS),
      activeIcon: $r('sys.symbol.person_fill'),
      inactiveIcon: $r('sys.symbol.person'),
      label: $r('app.string.tab_assistants')
    })
  }

  @Builder
  TabBarSettings() {
    IndexBottomTabItem({
      active: this.isTabActive(Index.TAB_SETTINGS),
      activeIcon: $r('sys.symbol.gearshape_fill'),
      inactiveIcon: $r('sys.symbol.gearshape'),
      label: $r('app.string.tab_settings')
    })
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

  private resetSearchBeforeRouteChange(): void {
    if (!this.isSearchExpanded && this.searchText === '') {
      return
    }
    this.searchText = ''
    this.isSearchExpanded = false
    this.refreshSessionListProjection()
    try {
      this.getUIContext().getFocusController().clearFocus()
    } catch (error) {
    }
  }

  private collapseSearchBeforeRouteChange(onFinish: () => void): void {
    try {
      this.getUIContext().getFocusController().clearFocus()
    } catch (error) {
    }
    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.EaseOut
    }, () => {
      this.searchText = ''
      this.isSearchExpanded = false
      this.refreshSessionListProjection()
    })
    setTimeout(() => {
      onFinish()
    }, 190)
  }

  private isFavoriteFilterActive(): boolean {
    return this.currentSessionFilter === SessionFilterType.FAVORITE
  }

  private setSessionFilter(filterType: SessionFilterType): void {
    if (this.currentSessionFilter === filterType) {
      return
    }
    this.currentSessionFilter = filterType
    this.refreshSessionListProjection()
  }

  private toggleFavoriteFilter(): void {
    this.setSessionFilter(this.isFavoriteFilterActive() ? SessionFilterType.ALL : SessionFilterType.FAVORITE)
  }

  @Builder
  FavoriteFilterActionButton() {
    Row() {
      SymbolGlyph(this.isFavoriteFilterActive() ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
        .fontSize(21)
        .fontColor([this.isFavoriteFilterActive() ? this.themePrimary : $r('app.color.text_primary')])
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .backgroundColor(this.isFavoriteFilterActive() ? this.themePrimaryLight : this.themeSurface)
    .border({
      width: this.isFavoriteFilterActive() ? 1 : 0,
      color: this.isFavoriteFilterActive() ? this.themePrimary : Color.Transparent
    })
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY)
    .onClick(() => {
      this.toggleFavoriteFilter()
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
    .backgroundColor(this.themeSurface)
    .justifyContent(FlexAlign.Center)
    .geometryTransition('SEARCH_BAR_ID', { follow: true })
    .transition(TransitionEffect.OPACITY)
    .onClick(() => {
      this.expandSearch()
    })
  }

  @Builder
  ChatTab() {
    HdsNavigation(this.chatTabNavStack) {
      Column() {
        this.ChatListPanel()
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.handleChatListPaneAreaChange(newArea)
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
    .titleBar(this.getCompactChatTitleBarOptions())
    .bindToScrollable([this.sessionListScroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .systemBarStyle(
      { statusBarContentColor: getHdsStatusBarContentColor() },
      { statusBarContentColor: getHdsStatusBarContentColor() }
    )
    .hideBackButton(true)
    .hideToolBar(true)
    .mode(this.getChatNavigationMode())
    .navBarWidth(this.isChatSplitLayout() ? this.getExpandedChatListWidth() : this.windowWidthVp)
    .navBarWidthRange({
      minWidth: CHAT_SPLIT_LIST_PANE_MIN_WIDTH,
      maxWidth: this.getExpandedChatListMaxWidth()
    })
    .minContentWidth(CHAT_SPLIT_DETAIL_PANE_MIN_WIDTH)
    .enableDragBar(this.isChatSplitLayout())
    .enableModeChangeAnimation(false)
    .onNavigationModeChange((_mode: NavigationMode) => {
      this.resetChatListPaneResizeTracking()
    })
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
  }

  private getCompactChatTitleBarOptions(): HdsNavigationTitleBarOptions {
    const options = new HdsTopNavigationBlurOptions()
    options.materialType = this.materialType
    options.materialLevel = this.materialLevel
    options.windowWidthVp = this.windowWidthVp
    options.windowHeightVp = this.windowHeightVp
    options.maskExtraHeightVp = this.getCompactChatTitleBarMaskExtraHeight()
    options.blurEffectiveEndOffsetVp = getHdsTopNavigationBlurEffectiveEndOffset(this.windowWidthVp,
      this.windowHeightVp)
    options.stackBuilder = (): void => this.CompactChatTitleStackBuilder()
    return buildHdsTopNavigationTitleBarOptions(options)
  }

  private getCompactChatTitleBarMaskExtraHeight(): number {
    // 大屏分栏下削减模糊蒙版向下渐变带的视觉占位，让 titleBar 与列表更紧凑；
    // 手机/竖屏维持 HDS 推荐值（横屏 16 / 竖屏 20）。
    if (this.isChatSplitLayout()) {
      return 8
    }
    return getHdsTopNavigationMaskExtraHeight(this.windowWidthVp, this.windowHeightVp)
  }

  @Builder
  private CompactChatTitleStackBuilder() {
    Column() {
      this.ChatListHeaderMainRow()
    }
    .width('100%')
    .height(56)
    .translate({ y: -2 })
    .renderGroup(false)
  }

  private getAssistantSessionCount(assistantId: string): number {
    const normalizedId = this.normalizeSessionAssistantId(assistantId)
    let count = 0
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.normalizeSessionAssistantId(this.sessions[i].assistantId) === normalizedId) {
        count++
      }
    }
    return count
  }

  private getAssistantLastChatTimestamp(assistantId: string): number {
    const normalizedId = this.normalizeSessionAssistantId(assistantId)
    let timestamp = 0
    for (let i = 0; i < this.sessions.length; i++) {
      const session = this.sessions[i]
      if (this.normalizeSessionAssistantId(session.assistantId) === normalizedId && session.updatedAt > timestamp) {
        timestamp = session.updatedAt
      }
    }
    return timestamp
  }

  private getAssistantAccentColor(assistant: Assistant): string {
    return assistant.color !== '' && assistant.color !== TRANSPARENT_BG_COLOR ? assistant.color : this.themePrimary
  }

  private getAssistantAvatarColor(assistant: Assistant): string {
    return assistant.color !== '' ? assistant.color : this.themePrimary
  }

  private getAssistantPromptPreviewText(assistant: Assistant): ResourceStr {
    return assistant.systemPrompt.trim() !== '' ? assistant.systemPrompt.trim() : $r('app.string.assistant_prompt_empty')
  }
  private getRelativeDiff(timestamp: number): number {
    const now = Date.now()
    return now > timestamp ? now - timestamp : 0
  }

  private isJustNow(timestamp: number): boolean {
    return timestamp > 0 && this.getRelativeDiff(timestamp) < 60 * 1000
  }

  private isMinutesAgo(timestamp: number): boolean {
    const diff = this.getRelativeDiff(timestamp)
    return timestamp > 0 && diff >= 60 * 1000 && diff < 60 * 60 * 1000
  }

  private isHoursAgo(timestamp: number): boolean {
    const diff = this.getRelativeDiff(timestamp)
    return timestamp > 0 && diff >= 60 * 60 * 1000 && diff < 24 * 60 * 60 * 1000
  }

  private isDaysAgo(timestamp: number): boolean {
    const diff = this.getRelativeDiff(timestamp)
    return timestamp > 0 && diff >= 24 * 60 * 60 * 1000 && diff < 7 * 24 * 60 * 60 * 1000
  }

  private getMinutesAgoValue(timestamp: number): string {
    return `${Math.floor(this.getRelativeDiff(timestamp) / (60 * 1000))}`
  }

  private getHoursAgoValue(timestamp: number): string {
    return `${Math.floor(this.getRelativeDiff(timestamp) / (60 * 60 * 1000))}`
  }

  private getDaysAgoValue(timestamp: number): string {
    return `${Math.floor(this.getRelativeDiff(timestamp) / (24 * 60 * 60 * 1000))}`
  }

  private formatDateMMDD(timestamp: number): string {
    const date = new Date(timestamp)
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const dayNum = date.getDate().toString().padStart(2, '0')
    return `${month}-${dayNum}`
  }

  private getAssistantDefaultModelText(assistant: Assistant): ResourceStr {
    return assistant.defaultModelName !== '' ? assistant.defaultModelName : $r('app.string.assistant_model_follow_global')
  }

  private getAssistantTabBottomSpacerHeight(): number {
    // 助手 tab 右下角浮着加号 FAB,列表底部要让出 FAB 高度+间距,
    // 否则最后一张卡片的更多按钮会被遮住、且无法上滑避让。
    return this.getChatListBottomSpacerHeight()
  }

  private getAssistantsListHorizontalPadding(): number {
    return this.isExpandedLayout() ? 20 : 16
  }

  private openAssistantManageForNew(): void {
    this.openAssistantEditorForNew()
  }

  private async openAssistantSessions(assistant: Assistant): Promise<void> {
    if (this.openingAssistantId !== '') {
      return
    }
    this.getUIContext().animateTo({
      duration: 120,
      curve: Curve.EaseOut
    }, () => {
      this.openingAssistantId = assistant.id
    })
    setTimeout(async () => {
      try {
        await this.switchAssistant(assistant.id)
        this.getUIContext().animateTo({
          duration: 240,
          curve: Curve.EaseOut
        }, () => {
          this.switchToTab(Index.TAB_CHAT)
        })
      } finally {
        setTimeout(() => {
          this.openingAssistantId = ''
        }, 260)
      }
    }, 90)
  }

  private async openAssistantNewChat(assistant: Assistant): Promise<void> {
    await this.switchAssistant(assistant.id)
    this.openChatRoute({} as ChatPageRouteParams)
  }

  private resetAssistantEditorForm(): void {
    this.editingAssistantId = ''
    this.editingAssistantCreatedAt = 0
    this.editingAssistantSortOrder = 0
    this.editingAssistantIsDefault = false
    this.assistantFormName = ''
    this.assistantFormAvatarSymbol = 'AI'
    this.assistantFormColor = DEFAULT_PRIMARY_COLOR
    this.assistantFormSystemPrompt = ''
    this.assistantFormDefaultProviderId = ''
    this.assistantFormDefaultModelId = ''
    this.assistantFormDefaultModelName = ''
    this.assistantFormTemperatureEnabled = false
    this.assistantFormTemperature = 0.7
    this.assistantFormTopPEnabled = false
    this.assistantFormTopP = 1.0
    this.assistantFormPresencePenaltyEnabled = false
    this.assistantFormPresencePenalty = 0
    this.assistantFormFrequencyPenaltyEnabled = false
    this.assistantFormFrequencyPenalty = 0
    this.assistantFormContextMessageCount = 0
    this.assistantFormMaxOutputTokens = 0
    this.editingAssistantReasoningLevelPreference = ''
  }

  private fillAssistantEditorForm(assistant: Assistant): void {
    // 先重置一次, 把所有 @Local form 字段拉回默认值再覆盖。
    // 不这么做时, 同一个 sheet 被重复打开 → V2 reactivity 在某些边界 (例如保存后再次进入)
    // 偶发不会感知到字段从旧值赋同值的"变化", 出现 maxOutputTokens 等数值 Slider 显示
    // 跟入参 assistant 字段不一致的问题。
    this.resetAssistantEditorForm()
    this.editingAssistantId = assistant.id
    this.editingAssistantCreatedAt = assistant.createdAt
    this.editingAssistantSortOrder = assistant.sortOrder
    this.editingAssistantIsDefault = assistant.id === DEFAULT_ASSISTANT_ID || assistant.isDefault
    this.assistantFormName = assistant.name
    this.assistantFormAvatarSymbol = this.normalizeAssistantAvatarSymbol(assistant.avatarSymbol)
    this.assistantFormColor = assistant.color !== '' ? assistant.color : DEFAULT_PRIMARY_COLOR
    this.assistantFormSystemPrompt = assistant.systemPrompt
    this.assistantFormDefaultProviderId = assistant.defaultProviderId
    this.assistantFormDefaultModelId = assistant.defaultModelId
    this.assistantFormDefaultModelName = assistant.defaultModelName
    this.assistantFormTemperatureEnabled = assistant.temperatureEnabled
    this.assistantFormTemperature = assistant.temperature
    this.assistantFormTopPEnabled = assistant.topPEnabled
    this.assistantFormTopP = assistant.topP
    this.assistantFormPresencePenaltyEnabled = assistant.presencePenaltyEnabled
    this.assistantFormPresencePenalty = assistant.presencePenalty
    this.assistantFormFrequencyPenaltyEnabled = assistant.frequencyPenaltyEnabled
    this.assistantFormFrequencyPenalty = assistant.frequencyPenalty
    this.assistantFormContextMessageCount = assistant.contextMessageCount
    this.assistantFormMaxOutputTokens = assistant.maxOutputTokens
    this.editingAssistantReasoningLevelPreference = assistant.reasoningLevelPreference || ''
  }

  private setAssistantFormAvatarSymbol(value: string): void {
    this.assistantFormAvatarSymbol = this.normalizeAssistantAvatarSymbol(value)
    this.bumpAssistantAvatarRenderTick()
    refreshAssistantAvatarCache(this.assistantFormAvatarSymbol)
  }

  private setAssistantFormAvatarColor(value: string): void {
    this.assistantFormColor = value !== '' ? value : this.themePrimary
    this.bumpAssistantAvatarRenderTick()
  }

  private async openAssistantEditorForNew(): Promise<void> {
    this.resetAssistantEditorForm()
    this.showAssistantEditorSheet = true
    await this.loadAssistantProvidersIfNeeded()
  }

  private async openAssistantEditor(assistant: Assistant): Promise<void> {
    // 防御性: 强制从 AssistantService 拉一次最新数据再回填表单, 避免 ForEach 列表里
    // 因为 buildAssistantListStateKey 指纹差异 / 内存竞争导致拿到的是过期引用,
    // 出现"用户改了 maxOutputTokens 等字段保存后, 重新打开仍显示旧值"的情况。
    let target: Assistant = assistant
    try {
      const latest = await this.assistantService.getAssistant(assistant.id)
      if (latest !== null) {
        target = latest
      }
    } catch (error) {
      console.warn('Index', `openAssistantEditor: refresh failed, fallback to in-memory: ${JSON.stringify(error)}`)
    }
    this.fillAssistantEditorForm(target)
    this.showAssistantEditorSheet = true
    await this.loadAssistantProvidersIfNeeded()
  }

  private getAssistantEditorTitle(): Resource {
    return this.editingAssistantId === '' ? $r('app.string.new_assistant') : $r('app.string.edit_assistant')
  }

  private getAssistantFormDefaultModelText(): ResourceStr {
    return this.assistantFormDefaultModelName !== '' ? this.assistantFormDefaultModelName :
      $r('app.string.assistant_model_follow_global')
  }

  private clearAssistantDefaultModel(): void {
    this.assistantFormDefaultProviderId = ''
    this.assistantFormDefaultModelId = ''
    this.assistantFormDefaultModelName = ''
    if (isModelAssistantAvatar(this.assistantFormAvatarSymbol)) {
      this.assistantFormAvatarSymbol = buildAssistantModelAvatarValue('', '')
      this.bumpAssistantAvatarRenderTick()
    }
  }

  private selectAssistantDefaultModel(providerId: string, modelId: string, modelName: string): void {
    this.assistantFormDefaultProviderId = providerId
    this.assistantFormDefaultModelId = modelId
    this.assistantFormDefaultModelName = modelName !== '' ? modelName : modelId
    if (isModelAssistantAvatar(this.assistantFormAvatarSymbol)) {
      this.assistantFormAvatarSymbol = buildAssistantModelAvatarValue(providerId, modelId)
      this.bumpAssistantAvatarRenderTick()
    }
    this.showAssistantModelSheet = false
  }

  private async saveAssistantEditor(): Promise<void> {
    const name = this.assistantFormName.trim()
    if (name === '') {
      this.showIndexSnack($r('app.string.assistant_name_required'), 2000, SnackBarTone.ERROR)
      return
    }

    const assistant = new Assistant(this.editingAssistantId, name)
    assistant.avatarSymbol = isModelAssistantAvatar(this.assistantFormAvatarSymbol) ?
      buildAssistantModelAvatarValue(this.assistantFormDefaultProviderId, this.assistantFormDefaultModelId) :
      this.normalizeAssistantAvatarSymbol(this.assistantFormAvatarSymbol)
    assistant.color = this.assistantFormColor
    assistant.systemPrompt = this.assistantFormSystemPrompt.trim()
    assistant.defaultProviderId = this.assistantFormDefaultProviderId
    assistant.defaultModelId = this.assistantFormDefaultModelId
    assistant.defaultModelName = this.assistantFormDefaultModelName
    assistant.temperatureEnabled = this.assistantFormTemperatureEnabled
    assistant.temperature = this.assistantFormTemperature
    assistant.topPEnabled = this.assistantFormTopPEnabled
    assistant.topP = this.assistantFormTopP
    assistant.presencePenaltyEnabled = this.assistantFormPresencePenaltyEnabled
    assistant.presencePenalty = this.assistantFormPresencePenalty
    assistant.frequencyPenaltyEnabled = this.assistantFormFrequencyPenaltyEnabled
    assistant.frequencyPenalty = this.assistantFormFrequencyPenalty
    assistant.contextMessageCount = this.assistantFormContextMessageCount
    assistant.maxOutputTokens = this.assistantFormMaxOutputTokens
    assistant.reasoningLevelPreference = this.editingAssistantReasoningLevelPreference
    assistant.createdAt = this.editingAssistantCreatedAt
    assistant.sortOrder = this.editingAssistantSortOrder
    assistant.isDefault = this.editingAssistantIsDefault

    if (assistant.id === '') {
      await this.assistantService.createAssistant(assistant)
    } else {
      await this.assistantService.saveAssistant(assistant)
    }
    this.assistantLoadSeq = this.assistantLoadSeq + 1
    this.patchAssistantInMemory(assistant)
    await this.loadAssistants()
    this.showAssistantEditorSheet = false
    this.showIndexSnack($r('app.string.assistant_saved'), 1500, SnackBarTone.SUCCESS)
  }

  private async deleteAssistantNow(assistant: Assistant): Promise<void> {
    const deleted = await this.assistantService.deleteAssistant(assistant.id)
    await this.loadAssistants()
    this.showIndexSnack(deleted ? $r('app.string.assistant_deleted') : $r('app.string.assistant_delete_failed'), 1800,
      deleted ? SnackBarTone.SUCCESS : SnackBarTone.ERROR)
  }

  private async deleteAssistantFromTab(assistant: Assistant): Promise<void> {
    if (assistant.id === DEFAULT_ASSISTANT_ID || assistant.isDefault) {
      return
    }
    if (this.getAssistantSessionCount(assistant.id) <= 0) {
      await this.deleteAssistantNow(assistant)
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.assistant_delete_with_chats_title'),
      message: $r('app.string.assistant_delete_with_chats_message'),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: $r('app.color.status_error'),
        action: async () => {
          await this.deleteAssistantNow(assistant)
        }
      }
    })
  }

  @Builder
  private AssistantsTabContent(applyTopInset: boolean) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        if (applyTopInset) {
          Column()
            .width('100%')
            .height(this.px2vp(this.topAvoidHeight))
        }

        this.AssistantsHeader()
        this.AssistantsList()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBackground)

      this.AssistantFloatingActionButton()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AssistantsTab() {
    this.AssistantsTabContent(!this.isExpandedLayout())
  }

  @Builder
  ExpandedAssistantsTab() {
    Row() {
      Column() {
        this.AssistantsTabContent(false)
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 720 })
      .backgroundColor(this.themeBackground)
      .borderRadius(24)
      .clip(true)
      .border({
        width: 1,
        color: $r('app.color.divider')
      })
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
  private AssistantsHeader() {
    Column() {
      Row() {
        Text($r('app.string.assistant_manage_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        this.AssistantHeaderPill(this.assistants.length.toString(), $r('app.string.assistant_total_label'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private AssistantHeaderPill(value: string, label: ResourceStr) {
    Row({ space: 4 }) {
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .height(30)
    .padding({ left: 10, right: 10 })
    .backgroundColor(this.themeSurface)
    .borderRadius(15)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private AssistantStatusBadge(label: ResourceStr, color: ResourceColor) {
    Row({ space: 5 }) {
      Circle()
        .width(6)
        .height(6)
        .fill(color)
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(22)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.themeBackground)
    .borderRadius(11)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private AssistantsList() {
    if (this.assistants.length === 0) {
      Column() {
        IndexEmptyStateCard({
          icon: $r('sys.symbol.person'),
          title: $r('app.string.assistant_manage_title'),
          description: $r('app.string.loading')
        })
      }
      .width('100%')
      .layoutWeight(1)
    } else {
      List({ space: 8, scroller: this.assistantListScroller }) {
        ForEach(this.assistants, (assistant: Assistant) => {
          ListItem({ style: ListItemStyle.NONE }) {
            this.AssistantJumpCard(assistant, assistant.id === this.currentAssistantId)
          }
          .swipeAction({
            end: this.AssistantEndSwipePanel(assistant)
          })
          .borderRadius(16)
          .clip(true)
          .dragPreview(this.AssistantDragPreview(assistant))
        }, (assistant: Assistant) => this.getAssistantRenderKey(assistant))
          .onMove((from: number, to: number) => {
            if (from === to || from < 0 || to < 0 || from >= this.assistants.length ||
              to >= this.assistants.length) {
              return
            }
            this.assistantListScroller.closeAllSwipeActions()
            const next: Assistant[] = this.assistants.slice()
            const moved = next.splice(from, 1)[0]
            next.splice(to, 0, moved)
            this.assistants = next
            this.assistantService.reorderAssistants(next).catch((err: Object) => {
              console.error('Index', `reorderAssistants failed: ${JSON.stringify(err)}`)
            })
          })

        ListItem() {
          Column()
            .height(this.getAssistantTabBottomSpacerHeight())
        }
        .focusable(false)
        .selectable(false)
      }
      .width('100%')
      .height(0)
      .layoutWeight(1)
      .padding({ left: this.getAssistantsListHorizontalPadding(), right: this.getAssistantsListHorizontalPadding(), top: 2 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(4)
    }
  }

  @Builder
  private AssistantEndSwipePanel(assistant: Assistant) {
    if (assistant.id !== DEFAULT_ASSISTANT_ID && !assistant.isDefault) {
      Row() {
        this.AssistantSwipeButton($r('sys.symbol.trash'), $r('app.string.delete'), $r('app.color.status_error'),
          72, (): void => {
            this.assistantListScroller.closeAllSwipeActions()
            this.deleteAssistantFromTab(assistant)
          })
      }
      .height('100%')
      .borderRadius({ topRight: 12, bottomRight: 12 })
      .clip(true)
    }
  }

  @Builder
  private AssistantSwipeButton(symbol: Resource, label: ResourceStr, backgroundColor: ResourceColor, width: number,
    onTap: () => void) {
    Button() {
      Column() {
        SymbolGlyph(symbol)
          .fontSize(18)
          .fontColor([Color.White])

        Text(label)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ top: 2 })
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(width)
    .height('100%')
    .borderRadius(0)
    .backgroundColor(backgroundColor)
    .onClick(() => {
      onTap()
    })
  }

  @Builder
  private AssistantFloatingActionButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(24)
        .fontColor([Color.White])
    }
    .width(INDEX_NEW_CHAT_FAB_SIZE)
    .height(INDEX_NEW_CHAT_FAB_SIZE)
    .borderRadius(INDEX_NEW_CHAT_FAB_SIZE / 2)
    .backgroundColor(this.themePrimary)
    .type(ButtonType.Circle)
    .stateEffect(false)
    .padding(0)
    .position({ x: this.shouldPlaceFabOnLeft() ? 0 : '100%', y: '100%' })
    .translate({ x: this.getFabOffsetX(), y: this.getFabOffsetY() })
    .scale(getButtonScale(this.fabPressed))
    .animation({
      duration: 420,
      curve: curves.springMotion(0.75, 0.86)
    })
    .shadow({
      radius: this.fabPressed ? 20 : 14,
      color: this.fabShadowColor,
      offsetX: 0,
      offsetY: 8
    })
    .onTouch(createButtonTouchHandler((pressed: boolean) => {
      this.fabPressed = pressed
    }))
    .onClick(() => {
      this.fabPressed = false
      this.openAssistantManageForNew()
    })
  }

  private getAssistantsDragPreviewWidth(): number {
    const padding = this.getAssistantsListHorizontalPadding()
    const inner = this.windowWidthVp - padding * 2
    return inner > 0 ? inner : 320
  }

  @Builder
  private AssistantDragPreview(assistant: Assistant) {
    Column() {
      this.AssistantJumpCard(assistant, assistant.id === this.currentAssistantId)
    }
    .width(this.getAssistantsDragPreviewWidth())
    .shadow({
      radius: 24,
      color: 'rgba(0,0,0,0.18)',
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder
  private AssistantJumpCard(assistant: Assistant, featured: boolean = false) {
    Column() {
      this.AssistantJumpCardContent(assistant, featured)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: featured ? 14 : 12, bottom: featured ? 14 : 12 })
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
    .border({
      width: assistant.id === this.currentAssistantId || this.openingAssistantId === assistant.id ? 1.5 : 1,
      color: assistant.id === this.currentAssistantId || this.openingAssistantId === assistant.id ? this.themePrimary :
      $r('app.color.divider')
    })
    .scale({
      x: this.openingAssistantId === assistant.id ? 0.985 : 1,
      y: this.openingAssistantId === assistant.id ? 0.985 : 1
    })
    .opacity(this.openingAssistantId === assistant.id ? 0.92 : 1)
    .animation({ duration: 180, curve: Curve.EaseOut })
    .onClick(() => {
      this.openAssistantSessions(assistant)
    })
  }

  @Builder
  private AssistantJumpCardContent(assistant: Assistant, featured: boolean) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        this.AssistantAvatarBadge(assistant.avatarSymbol, this.getAssistantAvatarColor(assistant), featured ? 48 : 44,
          featured ? 16 : 15, featured ? 25 : 23, assistant.defaultProviderId, assistant.defaultModelId,
          assistant.defaultModelName)

        Row({ space: 6 }) {
          Text(assistant.name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (assistant.id === this.currentAssistantId) {
            this.AssistantStatusBadge($r('app.string.assistant_active_badge'), this.getAssistantAccentColor(assistant))
          }
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)

        Button() {
          SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .stateEffect(true)
        .bindMenu(this.AssistantCardMoreMenu(assistant), {
          placement: Placement.BottomRight,
          offset: { x: 0, y: 8 },
          backgroundColor: this.themeSurface,
          backgroundBlurStyle: BlurStyle.Regular
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.getAssistantPromptPreviewText(assistant))
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(18)
        .width('100%')

      Row({ space: 8 }) {
        this.AssistantCardFooterMeta(assistant)

        this.AssistantCardActionButton($r('sys.symbol.message'), $r('app.string.assistant_view_chats'), false,
          (): void => {
            this.openAssistantSessions(assistant)
          })

        this.AssistantCardActionButton($r('sys.symbol.plus'), $r('app.string.new_chat'), true, (): void => {
          this.openAssistantNewChat(assistant)
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

  @Builder
  private AssistantCardFooterMeta(assistant: Assistant) {
    Row() {
      Text(this.getAssistantDefaultModelText(assistant))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Text(' · ')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))

      Row({ space: 3 }) {
        Text(this.getAssistantSessionCount(assistant.id).toString())
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text($r('app.string.assistant_sessions_label'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(VerticalAlign.Center)

      if (this.getAssistantLastChatTimestamp(assistant.id) > 0) {
        Text(' · ')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))

        this.AssistantRelativeTimeText(this.getAssistantLastChatTimestamp(assistant.id))
      }
    }
    .layoutWeight(1)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private AssistantCardActionButton(symbol: Resource, label: ResourceStr, primary: boolean, onTap: () => void) {
    Button() {
      Row({ space: 5 }) {
        SymbolGlyph(symbol)
          .fontSize(14)
          .fontColor([primary ? Color.White : this.themePrimary])

        Text(label)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(primary ? Color.White : this.themePrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .height(32)
    .borderRadius(16)
    .padding({ left: 12, right: 12 })
    .backgroundColor(primary ? this.themePrimary : this.themePrimaryLight)
    .stateEffect(true)
    .onClick(() => {
      onTap()
    })
  }

  @Builder
  private AssistantCardMoreMenu(assistant: Assistant) {
    Menu() {
      MenuItem({
        startIcon: $r('sys.symbol.square_and_pencil'),
        content: $r('app.string.edit_assistant_short')
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.openAssistantEditor(assistant)
        })

      if (assistant.id !== DEFAULT_ASSISTANT_ID && !assistant.isDefault) {
        MenuItem({
          startIcon: $r('sys.symbol.trash'),
          content: $r('app.string.delete')
        })
          .contentFont({ size: 14 })
          .contentFontColor($r('app.color.status_error'))
          .onClick(() => {
            this.deleteAssistantFromTab(assistant)
          })
      }
    }
  }

  @Builder
  private AssistantRelativeTimeText(timestamp: number) {
    Row({ space: 0 }) {
      if (timestamp <= 0) {
        Text($r('app.string.assistant_no_chat_time'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.isJustNow(timestamp)) {
        Text($r('app.string.time_just_now'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.isMinutesAgo(timestamp)) {
        Text(this.getMinutesAgoValue(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text($r('app.string.time_minutes_ago_suffix'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.isHoursAgo(timestamp)) {
        Text(this.getHoursAgoValue(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text($r('app.string.time_hours_ago_suffix'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.isDaysAgo(timestamp)) {
        Text(this.getDaysAgoValue(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text($r('app.string.time_days_ago_suffix'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else {
        Text(this.formatDateMMDD(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .justifyContent(FlexAlign.End)
  }

  @Builder
  private AssistantEditorSheetBuilder() {
    Column() {
      this.AssistantEditorHeader()

      Scroll() {
        Row() {
          Column({ space: 14 }) {
            this.AssistantEditorSectionHeader($r('app.string.assistant_editor_identity_section'),
              $r('app.string.assistant_editor_identity_desc'))
            this.AssistantNameAvatarRow()

            this.AssistantEditorSectionHeader($r('app.string.assistant_editor_prompt_section'),
              $r('app.string.assistant_editor_prompt_desc'))
            this.AssistantPromptEditor()

            this.AssistantEditorSectionHeader($r('app.string.assistant_editor_model_section'),
              $r('app.string.assistant_editor_model_desc'))
            this.AssistantDefaultModelRow()
            this.AssistantReasoningLevelRow()

            this.AssistantEditorSectionHeader($r('app.string.assistant_editor_sampling_section'),
              $r('app.string.assistant_editor_sampling_desc'))
            this.AssistantTemperatureRow()
            this.AssistantTopPRow()
            this.AssistantPresencePenaltyRow()
            this.AssistantFrequencyPenaltyRow()

            this.AssistantEditorSectionHeader($r('app.string.assistant_editor_context_section'),
              $r('app.string.assistant_editor_context_desc'))
            this.AssistantContextMessageCountRow()
            this.AssistantMaxOutputTokensRow()
          }
          .width('100%')
          .constraintSize({ maxWidth: 640 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: 16, right: 16, bottom: 28 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  @Builder
  private AssistantEditorHeader() {
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
        this.showAssistantEditorSheet = false
      })

      Text(this.getAssistantEditorTitle())
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Button() {
        SymbolGlyph($r('sys.symbol.save'))
          .fontSize(18)
          .fontColor([Color.White])
      }
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .backgroundColor(this.themePrimary)
      .onClick(() => {
        this.saveAssistantEditor()
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  private AssistantEditorSectionHeader(title: ResourceStr, description: ResourceStr) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text(description)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 2 })
  }

  @Builder
  private AssistantAvatarBadge(symbol: string, color: string, size: number, radius: number, fontSize: number,
    modelProviderId: string = '', modelId: string = '', modelName: string = '') {
    Stack() {
      ForEach([this.getAssistantAvatarRenderKey(symbol, color, size, radius, fontSize, modelProviderId, modelId,
        modelName)], (_renderKey: string) => {
        AssistantAvatarView({
          value: symbol,
          color: color,
          avatarSize: size,
          radius: radius,
          fontSize: fontSize,
          cacheKey: this.assistantAvatarRenderTick,
          modelProviderId: modelProviderId,
          modelId: modelId,
          modelName: modelName
        })
      }, (renderKey: string) => renderKey)
    }
    .width(size)
    .height(size)
  }

  @Builder
  private AssistantFormAvatarBadge(size: number, radius: number, fontSize: number) {
    Stack() {
      ForEach([this.getAssistantAvatarRenderKey(this.assistantFormAvatarSymbol, this.assistantFormColor, size, radius,
        fontSize, this.assistantFormDefaultProviderId, this.assistantFormDefaultModelId,
        this.assistantFormDefaultModelName)], (_renderKey: string) => {
        AssistantAvatarView({
          value: this.assistantFormAvatarSymbol,
          color: this.assistantFormColor,
          avatarSize: size,
          radius: radius,
          fontSize: fontSize,
          cacheKey: this.assistantAvatarRenderTick,
          modelProviderId: this.assistantFormDefaultProviderId,
          modelId: this.assistantFormDefaultModelId,
          modelName: this.assistantFormDefaultModelName
        })
      }, (renderKey: string) => renderKey)
    }
    .width(size)
    .height(size)
  }

  @Builder
  private AssistantNameAvatarRow() {
    Column({ space: 8 }) {
      Text($r('app.string.assistant_name'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row({ space: 12 }) {
        TextInput({ text: this.assistantFormName, placeholder: $r('app.string.assistant_name_placeholder') })
          .layoutWeight(1)
          .height(52)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor(this.themeSurface)
          .borderRadius(18)
          .padding({ left: 14, right: 14 })
          .onChange((text: string) => {
            this.assistantFormName = text
          })

        Button() {
          this.AssistantFormAvatarBadge(60, 20, 34)
        }
        .width(60)
        .height(60)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(20)
        .onClick(() => {
          this.showAssistantAvatarEditorSheet = true
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

  @Builder
  private AssistantAvatarEditorSheetBuilder() {
    AssistantAvatarEditorSheet({
      avatarValue: this.assistantFormAvatarSymbol,
      $avatarValue: (value: string): void => {
        this.setAssistantFormAvatarSymbol(value)
      },
      avatarColor: this.assistantFormColor !== '' ? this.assistantFormColor : this.themePrimary,
      $avatarColor: (value: string): void => {
        this.setAssistantFormAvatarColor(value)
      },
      defaultProviderId: this.assistantFormDefaultProviderId,
      defaultModelId: this.assistantFormDefaultModelId,
      defaultModelName: this.assistantFormDefaultModelName,
      onClose: (): void => {
        this.showAssistantAvatarEditorSheet = false
      }
    })
  }

  @Builder
  private AssistantPromptEditor() {
    Column({ space: 8 }) {
      Text($r('app.string.assistant_prompt'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextArea({ text: this.assistantFormSystemPrompt, placeholder: $r('app.string.assistant_prompt_placeholder') })
        .width('100%')
        .height(150)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor(this.themeSurface)
        .borderRadius(16)
        .padding(14)
        .onChange((value: string) => {
          this.assistantFormSystemPrompt = value
        })
    }
    .width('100%')
  }

  @Builder
  private AssistantDefaultModelRow() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text($r('app.string.assistant_default_model'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.getAssistantFormDefaultModelText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.assistantFormDefaultModelId !== '') {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor(this.themeBackground)
        .onClick(() => {
          this.clearAssistantDefaultModel()
        })
      }

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
    .onClick(() => {
      this.showAssistantModelSheet = true
      this.loadAssistantProvidersIfNeeded()
    })
  }

  @Builder
  private AssistantTemperatureRow() {
    Column({ space: 10 }) {
      Row() {
        Text($r('app.string.assistant_temperature_override'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.assistantFormTemperatureEnabled })
          .selectedColor(this.themePrimary)
          .onChange((value: boolean) => {
            this.assistantFormTemperatureEnabled = value
          })
      }
      .width('100%')

      if (this.assistantFormTemperatureEnabled) {
        Row({ space: 10 }) {
          Slider({ value: this.assistantFormTemperature, min: 0, max: 2, step: 0.1, style: SliderStyle.InSet })
            .layoutWeight(1)
            .selectedColor(this.themePrimary)
            .onChange((value: number, _mode: SliderChangeMode) => {
              this.assistantFormTemperature = Math.round(value * 10) / 10
            })
          Text(this.assistantFormTemperature.toFixed(1))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width(34)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
  }

  @Builder
  private AssistantContextMessageCountRow() {
    Column({ space: 10 }) {
      Row() {
        Text($r('app.string.assistant_context_message_count'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.assistantFormContextMessageCount > 0 ? `${this.assistantFormContextMessageCount} 条` :
          $r('app.string.assistant_context_unlimited'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      Slider({ value: this.assistantFormContextMessageCount, min: 0, max: 128, step: 2, style: SliderStyle.InSet })
        .width('100%')
        .selectedColor(this.themePrimary)
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.assistantFormContextMessageCount = Math.round(value)
        })

      Text($r('app.string.assistant_context_message_hint'))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
  }

  @Builder
  private AssistantMaxOutputTokensRow() {
    Column({ space: 10 }) {
      Row() {
        Text($r('app.string.assistant_max_output_tokens'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.assistantFormMaxOutputTokens > 0 ? `${this.assistantFormMaxOutputTokens}` :
          $r('app.string.assistant_max_output_default'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      Slider({ value: this.assistantFormMaxOutputTokens, min: 0, max: 65536, step: 256, style: SliderStyle.InSet })
        .width('100%')
        .selectedColor(this.themePrimary)
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.assistantFormMaxOutputTokens = Math.round(value)
        })

      Text($r('app.string.assistant_max_output_hint'))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
  }

  @Builder
  private AssistantTopPRow() {
    Column({ space: 10 }) {
      Row() {
        Text('Top P')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.assistantFormTopPEnabled })
          .selectedColor(this.themePrimary)
          .onChange((value: boolean) => { this.assistantFormTopPEnabled = value })
      }
      .width('100%')

      if (this.assistantFormTopPEnabled) {
        Row({ space: 10 }) {
          Slider({ value: this.assistantFormTopP, min: 0, max: 1, step: 0.05, style: SliderStyle.InSet })
            .layoutWeight(1)
            .selectedColor(this.themePrimary)
            .onChange((value: number, _mode: SliderChangeMode) => {
              this.assistantFormTopP = Math.round(value * 100) / 100
            })
          Text(this.assistantFormTopP.toFixed(2))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width(40)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
  }

  @Builder
  private AssistantPresencePenaltyRow() {
    Column({ space: 10 }) {
      Row() {
        Text('存在惩罚')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.assistantFormPresencePenaltyEnabled })
          .selectedColor(this.themePrimary)
          .onChange((value: boolean) => { this.assistantFormPresencePenaltyEnabled = value })
      }
      .width('100%')

      if (this.assistantFormPresencePenaltyEnabled) {
        Row({ space: 10 }) {
          Slider({ value: this.assistantFormPresencePenalty, min: -2, max: 2, step: 0.1, style: SliderStyle.InSet })
            .layoutWeight(1)
            .selectedColor(this.themePrimary)
            .onChange((value: number, _mode: SliderChangeMode) => {
              this.assistantFormPresencePenalty = Math.round(value * 10) / 10
            })
          Text(this.assistantFormPresencePenalty.toFixed(1))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width(40)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
  }

  @Builder
  private AssistantFrequencyPenaltyRow() {
    Column({ space: 10 }) {
      Row() {
        Text('频率惩罚')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.assistantFormFrequencyPenaltyEnabled })
          .selectedColor(this.themePrimary)
          .onChange((value: boolean) => { this.assistantFormFrequencyPenaltyEnabled = value })
      }
      .width('100%')

      if (this.assistantFormFrequencyPenaltyEnabled) {
        Row({ space: 10 }) {
          Slider({ value: this.assistantFormFrequencyPenalty, min: -2, max: 2, step: 0.1, style: SliderStyle.InSet })
            .layoutWeight(1)
            .selectedColor(this.themePrimary)
            .onChange((value: number, _mode: SliderChangeMode) => {
              this.assistantFormFrequencyPenalty = Math.round(value * 10) / 10
            })
          Text(this.assistantFormFrequencyPenalty.toFixed(1))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width(40)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
  }

  @Builder
  private AssistantReasoningLevelRow() {
    Column({ space: 10 }) {
      Row() {
        Text('推理强度')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.getReasoningLevelDisplayText())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      Text('新会话默认使用的推理强度，空为跟随全局')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
    .onClick(() => {
      this.cycleReasoningLevel()
    })
  }

  private getReasoningLevelDisplayText(): string {
    const level = this.editingAssistantReasoningLevelPreference
    if (level === '' || level === 'off') { return '跟随全局' }
    if (level === 'auto') { return '自动' }
    if (level === 'low') { return '低' }
    if (level === 'medium') { return '中' }
    if (level === 'high') { return '高' }
    return level
  }

  private cycleReasoningLevel(): void {
    const levels: string[] = ['', 'auto', 'low', 'medium', 'high']
    const current = levels.indexOf(this.editingAssistantReasoningLevelPreference)
    this.editingAssistantReasoningLevelPreference = levels[(current + 1) % levels.length]
  }

  @Builder
  private AssistantModelSheetBuilder() {
    Column() {
      ModelSelectorContent({
        currentModelId: this.assistantFormDefaultModelId,
        currentProviderId: this.assistantFormDefaultProviderId,
        providers: this.assistantProviders,
        showEditEntry: false,
        showFavoriteActions: false,
        showFavoriteFilter: false,
        showClearSelectionOption: true,
        clearSelectionText: $r('app.string.assistant_model_follow_global'),
        emptyStateMode: 'settings',
        onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
          this.selectAssistantDefaultModel(providerId, modelId, modelName)
        },
        onClearSelection: (): void => {
          this.clearAssistantDefaultModel()
          this.showAssistantModelSheet = false
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  @Builder
  private AssistantSwitchPill() {
    Stack() {
      ForEach([this.getCurrentAssistantSwitchRenderKey()], (_renderKey: string) => {
        Row({ space: 8 }) {
          this.AssistantAvatarBadge(this.getCurrentAssistantSymbol(), this.getCurrentAssistantColor(), 36, 12, 20)

          Text(this.getCurrentAssistantName())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: this.getAssistantSwitchNameMaxWidth() })

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(13)
            .fontColor([$r('app.color.text_secondary')])
        }
        .alignItems(VerticalAlign.Center)
      }, (renderKey: string) => renderKey)
    }
    .height(44)
    .padding({ left: 0, right: 10 })
    .constraintSize({ maxWidth: this.getAssistantSwitchMaxWidth() })
    .onClick(() => {
      this.showAssistantSwitchSheet = true
    })
    .transition(TransitionEffect.OPACITY.animation({
      duration: 200,
      curve: Curve.EaseOut
    }))
  }

  @Builder
  private AssistantSwitchSheetBuilder() {
    Column() {
      if (this.assistants.length === 0) {
        Column() {
          IndexEmptyStateCard({
            icon: $r('sys.symbol.person'),
            title: $r('app.string.assistant_manage_title'),
            description: $r('app.string.loading')
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.assistants, (assistant: Assistant) => {
            ListItem({ style: ListItemStyle.NONE }) {
              this.AssistantSwitchSheetRow(assistant)
            }
          }, (assistant: Assistant) => this.getAssistantRenderKey(assistant))

          ListItem() {
            Column()
              .height(24)
          }
          .focusable(false)
          .selectable(false)
        }
        .width('100%')
        .height(0)
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 6 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(4)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  @Builder
  private AssistantSwitchSheetRow(assistant: Assistant) {
    Row({ space: 12 }) {
      this.AssistantAvatarBadge(assistant.avatarSymbol, this.getAssistantAvatarColor(assistant), 42, 14, 22,
        assistant.defaultProviderId, assistant.defaultModelId, assistant.defaultModelName)

      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(assistant.name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (assistant.id === this.currentAssistantId) {
            this.AssistantStatusBadge($r('app.string.assistant_active_badge'), this.getAssistantAccentColor(assistant))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row({ space: 8 }) {
          Text(this.getAssistantDefaultModelText(assistant))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Row({ space: 3 }) {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(11)
              .fontColor([$r('app.color.text_tertiary')])
            Text(this.getAssistantSessionCount(assistant.id).toString())
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph(assistant.id === this.currentAssistantId ? $r('sys.symbol.checkmark_circle_fill') :
      $r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([assistant.id === this.currentAssistantId ? this.getAssistantAccentColor(assistant) :
        $r('app.color.text_tertiary')])
    }
    .width('100%')
    .constraintSize({ minHeight: 70 })
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.divider') })
    .onClick(() => {
      this.showAssistantSwitchSheet = false
      if (assistant.id !== this.currentAssistantId) {
        this.getUIContext().animateTo({
          duration: 180,
          curve: Curve.EaseOut
        }, () => {
          this.switchAssistant(assistant.id)
        })
      }
    })
  }

  @Builder
  private ChatListHeaderMainRow() {
    if (!this.isMultiSelectMode) {
      Row() {
        if (!this.isSearchExpanded) {
          this.AssistantSwitchPill()
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
          .backgroundColor(this.themeSurface)
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
          Blank()
          Row({ space: 8 }) {
            this.FavoriteFilterActionButton()
            this.CollapsedSearchActionButton()
          }
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
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
      } else if (this.getAssistantScopedSessions().length === 0) {
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

          IndexRecommendedPromptsCard({
            prompts: getPresetPrompts(),
            onPromptClick: (prompt: PresetPrompt): void => {
              const bodyText = resolvePromptBody(prompt, getContext(this) as common.Context)
              if (bodyText === '') {
                return
              }
              this.openChatRoute({ initialDraft: bodyText } as ChatPageRouteParams)
            }
          })
            .margin({ bottom: 24 })
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
            sessionListScroller: this.sessionListScroller,
            isMultiSelectMode: this.isMultiSelectMode,
            topSpacerHeight: topSpacerHeight,
            bottomSpacerHeight: this.getSessionListBottomSpacerHeight(),
            showFavoriteFilterSummary: this.isFavoriteFilterActive(),
            favoriteFilterCountText: this.getFilterCountText(),
            onClearFavoriteFilter: (): void => {
              this.setSessionFilter(SessionFilterType.ALL)
            },
            onGetGroupTitle: (groupKey: string): Resource => {
              return this.getSessionGroupTitle(groupKey)
            },
            onToggleSelection: (sessionId: string): void => {
              this.handleSessionCardClick(sessionId)
            },
            onOpenSession: (session: ChatSession): void => {
              this.openChatRoute({
                sessionId: session.id,
                sessionTitle: session.title,
                modelId: session.modelId,
                providerId: session.providerId
              } as ChatPageRouteParams)
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
    .backgroundColor(this.themeBackground)
  }

  @Builder
  private ChatListViewportContent() {
    Column() {
      this.ChatListPanelContent(this.getChatListTopSpacerHeight())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  @Builder
  private CompactChatListViewport() {
    Column() {
      this.ChatListViewportContent()
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
        .backgroundColor(this.themeBackground)
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
        Stack({ alignContent: Alignment.Bottom }) {
          this.CompactChatListViewport()

          Column() {
            ChatMultiSelectToolbar({
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
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 12, right: 12, bottom: this.getCompactMultiSelectToolbarBottomInsetVp() })
          .position({ x: 0, y: '100%' })
          .translate({ y: '-100%', x: 0 })
          .hitTestBehavior(HitTestMode.Default)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.handleCompactMultiSelectToolbarAreaChange(newArea)
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackground)
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
  FloatingActionButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(24)
        .fontColor([Color.White])
    }
    .width(INDEX_NEW_CHAT_FAB_SIZE)
    .height(INDEX_NEW_CHAT_FAB_SIZE)
    .borderRadius(INDEX_NEW_CHAT_FAB_SIZE / 2)
    .backgroundColor(this.themePrimary)
    .type(ButtonType.Circle)
    .stateEffect(false)
    .padding(0)
    .position({ x: this.shouldPlaceFabOnLeft() ? 0 : '100%', y: '100%' })
    .translate({ x: this.getFabOffsetX(), y: this.getFabOffsetY() })
    .scale(getButtonScale(this.fabPressed))
    .animation({
      duration: 420,
      curve: curves.springMotion(0.75, 0.86)
    })
    .shadow({
      radius: this.fabPressed ? 20 : 14,
      color: this.fabShadowColor,
      offsetX: 0,
      offsetY: 8
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
      onOpenChatInput: (): void => {
        this.openSettingsPanelEntry(SettingsRouteName.CHAT_INPUT, SettingsSheetType.CHAT_INPUT)
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
      onOpenWebDAVSync: (): void => {
        this.openSettingsDestination(SettingsRouteName.WEBDAV_SYNC)
      },
      onOpenUsageStats: (): void => {
        this.openSettingsDestination(SettingsRouteName.USAGE_STATS)
      },
      onOpenAbout: (): void => {
        this.openSettingsDestination(SettingsRouteName.ABOUT)
      },
      onOpenInvitation: (): void => {
        this.openSettingsDestination(SettingsRouteName.INVITATION)
      },
      onOpenSupportDevelopment: (): void => {
        this.openSettingsDestination(SettingsRouteName.SUPPORT_DEVELOPMENT)
      },
      onOpenPrivacy: (): void => {
        this.openPrivacyPolicy()
      },
      onOpenReplayOnboarding: (): void => {
        this.handleReplayOnboarding()
      }
    })
  }

  private handleReplayOnboarding(): void {
    // 关掉设置 sheet,免得 overlay 被 sheet 盖住
    if (this.showSettingsSheet) {
      this.showSettingsSheet = false
    }
    this.preferencesService.setOnboardingCompleted(false).catch((err: Object) => {
      console.error('Index', `Failed to reset onboarding flag: ${JSON.stringify(err)}`)
    })
    getOnboardingViewModel().start(this.currentThemeMode, this.currentColorTheme)
    this.onboardingActive = true
  }

  @Builder
  private SettingsNavigationScrollableContent() {
    Scroll(this.settingsRootScroller) {
      Column() {
        if (!this.isSettingsSplitMode()) {
          Blank()
            .width('100%')
            .height(this.getSettingsListTopSpacerHeight())
        }

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
    .backgroundColor(this.themeBackground)
  }

  @Builder
  private CompactSettingsTitleStackBuilder() {
    Row() {
      Text($r('app.string.tab_settings'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      this.AccountAvatarEntry()
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
    .renderGroup(false)
  }

  private getCompactSettingsTitleBarOptions(): HdsNavigationTitleBarOptions {
    const options = new HdsTopNavigationBlurOptions()
    options.materialType = this.materialType
    options.materialLevel = this.materialLevel
    options.windowWidthVp = this.windowWidthVp
    options.windowHeightVp = this.windowHeightVp
    options.maskExtraHeightVp = this.getCompactSettingsTitleBarMaskExtraHeight()
    options.blurEffectiveEndOffsetVp = getHdsTopNavigationBlurEffectiveEndOffset(this.windowWidthVp,
      this.windowHeightVp)
    options.stackBuilder = (): void => this.CompactSettingsTitleStackBuilder()
    return buildHdsTopNavigationTitleBarOptions(options)
  }

  @Builder
  private CompactSettingsRootContent() {
    Column() {
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
    return Index.COMPACT_TABS_BAR_HEIGHT
  }

  @Builder
  SettingsTab() {
    if (this.isSettingsSplitMode()) {
      Navigation(this.settingsNavPathStack) {
        this.SettingsNavigationScrollableContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBackground)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .title($r('app.string.tab_settings'))
      .titleMode(NavigationTitleMode.Mini)
      .menus(this.SettingsNavigationMenus)
      .mode(NavigationMode.Split)
      .navBarWidth(this.getExpandedSettingsListWidth())
      .hideBackButton(true)
      .hideToolBar(true)
      .onAppear(() => {
        this.ensureSettingsSplitLandingRoute()
      })
    } else {
      HdsNavigation(this.settingsNavPathStack) {
        this.CompactSettingsRootContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBackground)
      .titleBar(this.getCompactSettingsTitleBarOptions())
      .bindToScrollable([this.settingsRootScroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .systemBarStyle(
        { statusBarContentColor: getHdsStatusBarContentColor() },
        { statusBarContentColor: getHdsStatusBarContentColor() }
      )
      .ignoreLayoutSafeArea(
        [LayoutSafeAreaType.SYSTEM],
        this.shouldIgnoreCompactSettingsTopSafeArea() ? [LayoutSafeAreaEdge.TOP] : []
      )
      .mode(NavigationMode.Stack)
      .navBarWidth(this.windowWidthVp)
      .hideBackButton(true)
      .hideToolBar(true)
    }
  }

  private getActiveSettingsSheetHeight(): SheetSize {
    return SheetSize.FIT_CONTENT
  }

  private getSettingsSheetBackgroundColor(): ResourceColor {
    return this.themeSurface
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
          chatInputEnterKeySend: this.chatInputEnterKeySend,
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
      chatInputEnterKeySend: this.chatInputEnterKeySend,
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
      chatInputEnterKeySend: this.chatInputEnterKeySend,
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
      chatInputEnterKeySend: this.chatInputEnterKeySend,
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
    callbacks.onToggleChatInputEnterKeySend = async (value: boolean): Promise<void> => {
      this.chatInputEnterKeySend = value
      this.syncSettingsSummaryToStorage()
      await this.settingsManager.setChatInputEnterKeySend(value)
    }
    callbacks.onOpenSystemNotificationSettings = (): void => {
      this.openSystemNotificationSettings()
    }
    return callbacks
  }

  // ========== 系统提示词 ==========

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
          .backgroundColor(this.themeSurface)
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

  // ========== 华为账号登录态 UI ==========

  /**
   * 设置页右上方账号头像入口。
   * - 有 avatarUri 时用 Image 加载，加载失败降级为系统 SymbolGlyph
   * - 仅登录态展示；未登录（极少出现，正常已在登录页）也给兜底
   * 点击弹退出登录确认。
   */
  @Builder
  private AccountAvatarEntry() {
    Button() {
      if (getAppUiState().hwAccountAvatarUri !== '') {
        Image(getAppUiState().hwAccountAvatarUri)
          .width(36)
          .height(36)
          .borderRadius(18)
          .objectFit(ImageFit.Cover)
          .alt($r('sys.symbol.person_crop_circle_fill'))
      } else {
        SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
          .fontSize(30)
          .fontColor([this.themePrimary])
      }
    }
    .type(ButtonType.Circle)
    .width(36)
    .height(36)
    .backgroundColor(Color.Transparent)
    .padding(0)
    .margin({ left: 8 })
    .onClick((): void => {
      this.showLogoutConfirm()
    })
  }

  @Builder
  private SettingsNavigationMenus() {
    Row() {
      this.AccountAvatarEntry()
    }
    .padding({ right: 4 })
  }

  private showLogoutConfirm(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.hw_logout_confirm_title'),
      message: $r('app.string.hw_logout_confirm_message'),
      primaryButton: {
        value: $r('app.string.hw_logout_confirm_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.hw_logout_confirm_ok'),
        fontColor: $r('app.color.status_error'),
        action: (): void => {
          this.performLogout()
        }
      }
    })
  }

  private performLogout(): void {
    ServiceRegistry.account().clearLoginState().then((): void => {
      const stage: window.WindowStage | undefined =
        AppStorage.get<window.WindowStage>(AppStorageKeys.MAIN_WINDOW_STAGE)
      if (stage === undefined) {
        this.showIndexSnack($r('app.string.hw_login_error_generic'), 2000, SnackBarTone.ERROR)
        return
      }
      // debug+模拟器环境下 LoginPage 会自动跳回主页，退出登录前先置一次性 flag 让它放行
      AppStorage.setOrCreate(AppStorageKeys.HW_PREVENT_AUTO_SKIP_ONCE, true)
      stage.loadContent('pages/LoginPage', (err: BusinessError): void => {
        if (err !== null && err !== undefined && err.code !== 0) {
          this.showIndexSnack($r('app.string.hw_login_error_generic'), 2000, SnackBarTone.ERROR)
        }
      })
    }).catch((): void => {
      this.showIndexSnack($r('app.string.hw_login_error_generic'), 2000, SnackBarTone.ERROR)
    })
  }
}
