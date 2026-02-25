import { curves } from '@kit.ArkUI'
import { ConfigurationConstant, common } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { motion } from '@kit.MultimodalAwarenessKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { HdsTabs } from '@kit.UIDesignKit'
import { ChatSession, ChatMessage } from '../models/ChatModels'
import { ChatViewModel } from '../viewmodels/ChatViewModel'
import { SettingsChangeCallback } from '../viewmodels/SettingsManager'
import { ThemeMode, AppLanguage, PreferenceKeys } from '../services/PreferencesService'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { MultiSelectToolbar } from '../components/MultiSelectToolbar'
import { SharePreviewSheet } from '../components/SharePreviewSheet'
import { ColorTheme, ThemeColorConfig } from '../models/ThemeColors'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { createButtonTouchHandler, getButtonAnimation, getButtonScale } from '../utils/ButtonAnimationUtils'
import {
  countSelectedIdsInCandidates,
  mergeSelectAllIds,
  removeCandidateIds,
  toggleSelectionById
} from '../utils/SelectionHelper'
import { ChatTaskStatus } from '../models/ChatTaskModels'
import {
  getTotalUnreadCount as getTotalUnreadCountFromMap,
  getUnreadCountBySession,
  parseInAppTaskAlertPayload,
  parseOpenSessionPayload,
  parseUnreadBySessionMap
} from '../utils/TaskAlertUtils'
import { IndexBottomTabItem } from '../components/index/IndexBottomTabItem'
import { IndexFilterBar } from '../components/index/IndexFilterBar'
import { IndexEmptyStateCard } from '../components/index/IndexEmptyStateCard'
import { IndexSettingsPanel } from '../components/index/IndexSettingsPanel'
import { IndexSettingsSheetContent } from '../components/index/IndexSettingsSheetContent'
import { IndexSessionListSection } from '../components/index/IndexSessionListSection'
import { SettingsSheetType, SessionFilterType, SessionGroupData } from './index/IndexPageTypes'
import { getFilteredSessionsForIndex, buildSessionGroupsForIndex, buildSessionGroupRenderKey } from './index/IndexSessionGroupHelper'
import {
  getFabOffsetXForIndex,
  getFabOffsetYForIndex,
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

@Entry
@Component
struct Index {
  @State currentTabIndex: number = 1
  @State sessions: ChatSession[] = []
  @State isLoading: boolean = false
  @State @Watch('onSettingsSummaryStateChanged') currentThemeMode: ThemeMode = ThemeMode.SYSTEM
  @State @Watch('onSettingsSummaryStateChanged') currentLanguage: AppLanguage = AppLanguage.SYSTEM
  @State @Watch('onSettingsSummaryStateChanged') notifyEnabled: boolean = true
  @State @Watch('onSettingsSummaryStateChanged') notifyOnComplete: boolean = true
  @State @Watch('onSettingsSummaryStateChanged') notifyOnFailed: boolean = true
  @State @Watch('onSettingsSummaryStateChanged') handAdaptiveEnabled: boolean = false
  @State @Watch('onSettingsSummaryStateChanged') handAdaptiveNewChat: boolean = false
  @State @Watch('onSettingsSummaryStateChanged') handAdaptiveUnsupported: boolean = false
  @State currentHoldingHand: motion.HoldingHandStatus = motion.HoldingHandStatus.UNKNOWN_STATUS
  @State fabPressed: boolean = false
  @State @Watch('onSettingsSummaryStateChanged') currentColorTheme: ColorTheme = ColorTheme.DEFAULT
  @State showSettingsSheet: boolean = false
  @State settingsSheetType: SettingsSheetType = SettingsSheetType.NONE
  @State showSystemPromptSheet: boolean = false
  @State customSystemPrompt: string = ''
  @State searchText: string = ''
  @State isSearchExpanded: boolean = false
  @State currentSessionFilter: SessionFilterType = SessionFilterType.ALL
  // 避让区域高度
  @StorageProp('topAvoidHeight') topAvoidHeight: number = 0
  @StorageProp('bottomAvoidHeight') bottomAvoidHeight: number = 0
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_primary_light') themePrimaryLight: string = '#E6F2FF'
  // 监听从服务卡片打开新聊天的事件
  @StorageProp('openNewChat') @Watch('onOpenNewChat') openNewChatTimestamp: number = 0
  @StorageProp('openSessionPayload') @Watch('onOpenSessionPayloadChanged') openSessionPayload: string = ''
  @StorageProp('task_unread_by_session') @Watch('onTaskUnreadBySessionChanged') taskUnreadBySessionJson: string = '{}'
  @StorageProp('task_event_tick') @Watch('onTaskEventTickChanged') taskEventTick: number = 0
  @StorageProp('in_app_task_alert_payload') @Watch('onInAppTaskAlertPayloadChanged') inAppTaskAlertPayload: string = ''
  @State unreadRenderTick: number = 0
  // 监听会话列表刷新信号（标题更新、创建、删除等）
  @StorageProp('session_list_refresh_at') @Watch('onSessionListRefresh') sessionListRefreshAt: number = 0
  // 多选模式状态
  @State isMultiSelectMode: boolean = false
  @State selectedSessionIds: Array<string> = []
  // 分享预览弹窗状态
  @State showSharePreview: boolean = false
  @State shareMessages: ChatMessage[] = []
  private navPathStack: NavPathStack = new NavPathStack()
  // 返回键退出控制
  private lastBackPressTime: number = 0
  private chatViewModel: ChatViewModel = ServiceRegistry.chat()
  private chatTaskOrchestrator = ServiceRegistry.chatTaskOrchestrator()
  private settingsManager = ServiceRegistry.settings()
  private preferencesService = ServiceRegistry.preferences()
  private settingsCallback: SettingsChangeCallback | null = null
  private unreadBySession: Map<string, number> = new Map()
  private holdingHandSubscribed: boolean = false
  private handAdaptiveLoadSeq: number = 0
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

  private onSettingsSummaryStateChanged(): void {
    console.info('Index', `Settings summary state changed: theme=${this.currentThemeMode}, language=${this.currentLanguage},` +
      ` colorTheme=${this.currentColorTheme}, hand=${this.handAdaptiveEnabled}/${this.handAdaptiveNewChat}/` +
      `${this.handAdaptiveUnsupported}, notify=${this.notifyEnabled}/${this.notifyOnComplete}/${this.notifyOnFailed}`)
  }

  private safePushUrl(url: string, params?: Object): void {
    const navRouter = this.getUIContext().getRouter()
    try {
      if (params !== undefined) {
        navRouter.pushUrl({ url: url, params: params })
      } else {
        navRouter.pushUrl({ url: url })
      }
    } catch (error) {
      console.error('Index', `Router pushUrl failed: ${JSON.stringify(error)}`)
    }
  }

  onOpenNewChat(): void {
    if (this.openNewChatTimestamp > 0) {
      this.navPathStack.pushPath({ name: 'ChatPage', param: {} as ChatPageRouteParams })
    }
  }

  onOpenSessionPayloadChanged(): void {
    this.handleOpenSessionPayload(this.openSessionPayload)
  }

  onTaskUnreadBySessionChanged(): void {
    this.parseUnreadBySessionJson(this.taskUnreadBySessionJson)
  }

  onTaskEventTickChanged(): void {
    if (this.taskEventTick > 0) {
      this.loadSessions()
      this.parseUnreadBySessionJson(this.taskUnreadBySessionJson)
    }
  }

  onInAppTaskAlertPayloadChanged(): void {
    this.handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
  }

  onSessionListRefresh(): void {
    if (this.sessionListRefreshAt > 0) {
      this.loadSessions()
    }
  }

  aboutToAppear(): void {
    this.navPathStack.setInterception({
      didShow: (from: NavDestinationContext | "navBar", to: NavDestinationContext | "navBar",
        operation: NavigationOperation, isAnimated: boolean): void => {
        if (to === 'navBar') {
          // pop 完成，navPathStack.size() 已变为 0，loadSessions 不再跳过
          this.loadSessions()
          this.parseUnreadBySessionJson(this.taskUnreadBySessionJson)
        }
      }
    })

    this.loadSessions()
    this.loadSettings()
    this.registerSettingsCallback()
    this.parseUnreadBySessionJson(this.taskUnreadBySessionJson)
    this.handleOpenSessionPayload(this.openSessionPayload)
    this.handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
  }

  onPageShow(): void {
    this.loadSessions()
    this.parseUnreadBySessionJson(this.taskUnreadBySessionJson)
    this.refreshSettingsState()
    this.loadHandAdaptiveSettings()
  }

  aboutToDisappear(): void {
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
    if (this.showSettingsSheet) {
      this.showSettingsSheet = false
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
    this.syncSettingsSummaryToStorage()
  }

  private syncSettingsSummaryToStorage(): void {
    AppStorage.setOrCreate('setting_theme_mode', this.currentThemeMode)
    AppStorage.setOrCreate('setting_language', this.currentLanguage)
    AppStorage.setOrCreate(AppStorageKeys.COLOR_THEME, this.currentColorTheme)
    AppStorage.setOrCreate('setting_notify_enabled', this.notifyEnabled)
    AppStorage.setOrCreate('setting_notify_on_complete', this.notifyOnComplete)
    AppStorage.setOrCreate('setting_notify_on_failed', this.notifyOnFailed)
    AppStorage.setOrCreate('setting_hand_adaptive_enabled', this.handAdaptiveEnabled)
    AppStorage.setOrCreate('setting_hand_adaptive_new_chat', this.handAdaptiveNewChat)
    AppStorage.setOrCreate('setting_hand_adaptive_unsupported', this.handAdaptiveUnsupported)
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

  private getFabOffsetY(): number {
    return getFabOffsetYForIndex(this.px2vp(this.bottomAvoidHeight))
  }

  private getHandAdaptiveSummaryText(): Resource {
    if (!this.handAdaptiveEnabled) {
      return $r('app.string.hand_adaptive_disabled')
    }
    if (this.handAdaptiveUnsupported) {
      return $r('app.string.hand_adaptive_unsupported')
    }
    if (this.handAdaptiveNewChat) {
      return $r('app.string.hand_adaptive_summary_new_chat')
    }
    return $r('app.string.hand_adaptive_summary_none')
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

  private parseUnreadBySessionJson(jsonText: string): void {
    this.unreadBySession = parseUnreadBySessionMap(jsonText)
    this.unreadRenderTick = this.unreadRenderTick + 1
  }

  private getUnreadCountForSession(sessionId: string): number {
    if (this.unreadRenderTick < 0) {
      return 0
    }
    return getUnreadCountBySession(this.unreadBySession, sessionId)
  }

  private isSessionUnread(sessionId: string): boolean {
    return this.getUnreadCountForSession(sessionId) > 0
  }

  private getTotalUnreadCount(): number {
    if (this.unreadRenderTick < 0) {
      return 0
    }
    return getTotalUnreadCountFromMap(this.unreadBySession)
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
    this.chatTaskOrchestrator.markSessionRead(payload.sessionId)
    this.navPathStack.pushPath({ name: 'ChatPage', param: { sessionId: payload.sessionId } as ChatPageRouteParams })
    AppStorage.setOrCreate(AppStorageKeys.OPEN_SESSION_PAYLOAD, '')
  }

  private handleInAppTaskAlertPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }
    this.parseUnreadBySessionJson(this.taskUnreadBySessionJson)
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
      this.chatTaskOrchestrator.markSessionRead(payload.sessionId)
      this.navPathStack.pushPath({ name: 'ChatPage', param: { sessionId: payload.sessionId } as ChatPageRouteParams })
    }
    showSnackBar(this.getUIContext(), opts)
    AppStorage.setOrCreate(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, '')
  }

  private openSettingsSheet(type: SettingsSheetType): void {
    this.refreshSettingsState()
    if (type === SettingsSheetType.HAND_ADAPTIVE) {
      this.loadHandAdaptiveSettings()
    }
    this.settingsSheetType = type
    if (!this.showSettingsSheet) {
      this.showSettingsSheet = true
    }
  }

  async loadSessions(): Promise<void> {
    // pop 动画期间完全跳过，由 setInterception.didShow 在动画完成后统一触发
    if (this.navPathStack.size() > 0) {
      return
    }
    const isFirstLoad = this.sessions.length === 0 && !this.isLoading
    if (isFirstLoad) {
      this.isLoading = true
    }
    const newSessions = await this.chatViewModel.getAllSessions()
    this.mergeSessions(newSessions)
    this.isLoading = false
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
            existing.isFavorite = fresh.isFavorite
            existing.modelId = fresh.modelId
            existing.providerId = fresh.providerId
            reorderedSessions.push(existing)
          }
        }
        this.sessions = reorderedSessions
        return
      }
    }
    // id 列表不同（新增或删除了会话），全量替换
    this.sessions = newSessions
  }

  async deleteSession(sessionId: string): Promise<void> {
    await this.chatViewModel.deleteSession(sessionId)
    const index = this.sessions.findIndex((s: ChatSession) => s.id === sessionId)
    if (index >= 0) {
      this.sessions.splice(index, 1)
    }
    this.showIndexSnack($r('app.string.conversation_deleted'), 2000, SnackBarTone.SUCCESS)
  }

  getFilteredSessions(): ChatSession[] {
    return getFilteredSessionsForIndex(this.sessions, this.searchText, this.currentSessionFilter)
  }

  private getSessionGroups(): SessionGroupData[] {
    return buildSessionGroupsForIndex(this.getFilteredSessions())
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
    const count = this.getFilteredSessions().length
    return count.toString()
  }

  private getGroupRenderKey(group: SessionGroupData): string {
    return buildSessionGroupRenderKey(group, this.currentSessionFilter, this.searchText)
  }

  build() {
    Navigation(this.navPathStack) {
      Stack() {
        Column() {
          // 顶部状态栏占位 - 透明背景，自动继承当前 Tab 的背景色
          Column()
            .width('100%')
            .height(this.px2vp(this.topAvoidHeight))

          HdsTabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
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
          .barHeight(56 + this.px2vp(this.bottomAvoidHeight))
          .barBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .scrollable(false)
          .onChange((index: number) => {
            this.currentTabIndex = index
            if (index === 1) {
              this.loadSessions()
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))

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
            height: this.settingsSheetType === SettingsSheetType.COLOR_THEME ? SheetSize.MEDIUM :
            SheetSize.FIT_CONTENT,
            dragBar: true,
            showClose: true,
            title: { title: this.getSettingsSheetTitle() },
            onDisappear: () => {
              if (!this.showSettingsSheet) {
                this.settingsSheetType = SettingsSheetType.NONE
              }
              this.refreshSettingsState()
              this.loadHandAdaptiveSettings()
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
      label: $r('app.string.tab_chat'),
      badgeCount: this.getTotalUnreadCount()
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
        Row() {
          Text($r('app.string.tab_assistant'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
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
    })
  }

  // 搜索框收起动画
  private collapseSearch(): void {
    this.getUIContext().animateTo({
      curve: curves.interpolatingSpring(0, 1, 342, 38)
    }, () => {
      this.searchText = ''
      this.isSearchExpanded = false
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
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
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
              Row() {
                Row() {
                  SymbolGlyph($r('sys.symbol.magnifyingglass'))
                    .fontSize(18)
                    .fontColor([$r('app.color.text_tertiary')])
                }
                .width(36)
                .height(36)
                .justifyContent(FlexAlign.Center)

                TextInput({ text: this.searchText, placeholder: $r('app.string.search_sessions_placeholder') })
                  .layoutWeight(1)
                  .height(36)
                  .backgroundColor(Color.Transparent)
                  .padding({ left: 0, right: 8 })
                  .caretColor(this.themePrimary)
                  .placeholderColor($r('app.color.text_tertiary'))
                  .onChange((value: string) => {
                    this.searchText = value
                  })
                  .onSubmit(() => {
                    if (this.searchText.trim() === '') {
                      this.collapseSearch()
                    }
                  })
              }
              .layoutWeight(1)
              .height(40)
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
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)

          IndexFilterBar({
            currentFilter: this.currentSessionFilter,
            countText: this.getFilterCountText(),
            onFilterChange: (filterType: SessionFilterType): void => {
              this.currentSessionFilter = filterType
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
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
        }

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(this.themePrimary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.sessions.length === 0) {
          IndexEmptyStateCard({
            icon: $r('sys.symbol.ellipsis_message'),
            title: $r('app.string.no_sessions'),
            description: $r('app.string.start_new_chat'),
            showButton: true,
            buttonText: $r('app.string.new_chat'),
            onButtonClick: (): void => {
              this.navPathStack.pushPath({ name: 'ChatPage', param: {} as ChatPageRouteParams })
            }
          })
        } else {
          if (this.getFilteredSessions().length === 0) {
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
          } else {
            IndexSessionListSection({
              sessionGroups: this.getSessionGroups(),
              isMultiSelectMode: this.isMultiSelectMode,
              selectedSessionIds: this.selectedSessionIds,
              onGetUnreadCount: (sessionId: string): number => {
                return this.getUnreadCountForSession(sessionId)
              },
              onGetGroupTitle: (groupKey: string): Resource => {
                return this.getSessionGroupTitle(groupKey)
              },
              onGetGroupRenderKey: (group: SessionGroupData): string => {
                return this.getGroupRenderKey(group)
              },
              onToggleSelection: (sessionId: string): void => {
                this.handleSessionCardClick(sessionId)
              },
              onOpenSession: (sessionId: string): void => {
                this.navPathStack.pushPath({
                  name: 'ChatPage',
                  param: { sessionId: sessionId } as ChatPageRouteParams
                })
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
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background'))

      if (!this.isMultiSelectMode) {
        this.FloatingActionButton()
      }

      if (this.isMultiSelectMode) {
        MultiSelectToolbar({
          selectedCount: this.selectedSessionIds.length,
          totalCount: this.getFilteredSessions().length,
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
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  FloatingActionButton() {
    Column() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(20)
        .fontColor([Color.White])
    }
    .width(44)
    .height(44)
    .borderRadius(22)
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
      this.navPathStack.pushPath({ name: 'ChatPage', param: {} as ChatPageRouteParams })
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
  SettingsTab() {
    Column() {
      Row() {
        Text($r('app.string.tab_settings'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      IndexSettingsPanel({
        currentThemeMode: $currentThemeMode,
        currentLanguage: $currentLanguage,
        currentColorTheme: $currentColorTheme,
        handAdaptiveEnabled: $handAdaptiveEnabled,
        handAdaptiveNewChat: $handAdaptiveNewChat,
        handAdaptiveUnsupported: $handAdaptiveUnsupported,
        notifyEnabled: $notifyEnabled,
        notifyOnComplete: $notifyOnComplete,
        notifyOnFailed: $notifyOnFailed,
        onOpenModelManage: (): void => {
          this.safePushUrl('pages/ModelManagePage')
        },
        onOpenDefaultModel: (): void => {
          this.safePushUrl('pages/DefaultModelPage')
        },
        onOpenToolsCenter: (): void => {
          this.safePushUrl('pages/ToolsCenterPage')
        },
        onOpenSystemPrompt: (): void => {
          this.openSystemPromptSheet()
        },
        onOpenHandAdaptive: (): void => {
          this.openSettingsSheet(SettingsSheetType.HAND_ADAPTIVE)
        },
        onOpenTheme: (): void => {
          this.openSettingsSheet(SettingsSheetType.THEME)
        },
        onOpenColorTheme: (): void => {
          this.openSettingsSheet(SettingsSheetType.COLOR_THEME)
        },
        onOpenLanguage: (): void => {
          this.openSettingsSheet(SettingsSheetType.LANGUAGE)
        },
        onOpenNotification: (): void => {
          this.openSettingsSheet(SettingsSheetType.NOTIFICATION)
        },
        onOpenExportData: (): void => {
          this.safePushUrl('pages/ExportDataPage')
        },
        onOpenImportData: (): void => {
          this.safePushUrl('pages/ImportDataPage')
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  SettingsSheetBuilder() {
    IndexSettingsSheetContent({
      settingsSheetType: this.settingsSheetType,
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
      await this.settingsManager.setThemeMode(mode)
      this.showSettingsSheet = false
    }
    callbacks.onSelectLanguage = async (language: AppLanguage): Promise<void> => {
      this.currentLanguage = language
      this.syncSettingsSummaryToStorage()
      await this.settingsManager.setLanguage(language)
      this.showSettingsSheet = false
    }
    callbacks.onSelectColorTheme = (theme: ColorTheme): void => {
      this.handleColorThemeSelected(theme)
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

  // 获取设置弹窗标题
  private getSettingsSheetTitle(): Resource {
    return getSettingsSheetTitleText(this.settingsSheetType)
  }

  // 处理主题配色选择
  private async handleColorThemeSelected(theme: ColorTheme): Promise<void> {
    // 先本地更新，确保摘要先刷新，再持久化
    this.currentColorTheme = theme
    this.syncSettingsSummaryToStorage()
    await this.settingsManager.setColorTheme(theme)
    this.showSettingsSheet = false
    this.showIndexSnack($r('app.string.theme_switched'), 2000, SnackBarTone.SUCCESS)
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
  }

  // 退出多选模式
  private handleExitMultiSelectMode(): void {
    this.isMultiSelectMode = false
    this.selectedSessionIds = []
  }

  // 切换会话选中状态
  private handleToggleSessionSelection(sessionId: string): void {
    this.selectedSessionIds = toggleSelectionById(this.selectedSessionIds, sessionId)
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
  }

  private async handleToggleFavoriteSession(session: ChatSession): Promise<void> {
    const isFavorite = await this.chatViewModel.toggleSessionFavorite(session.id)
    session.isFavorite = isFavorite
    // 触发 sessions 的 @State 更新，确保 swipeAction 文案/图标立即按收藏状态重渲染
    this.sessions = [...this.sessions]
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
          // 取消
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
