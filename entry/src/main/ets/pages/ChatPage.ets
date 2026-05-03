import { KeyboardAvoidMode } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigationTitleBarOptions
} from '@kit.UIDesignKit'
import {
  ChatMessage,
  MessageRole,
  ModelProvider,
  ModelInfo,
  ModelInfoExtendedJson,
  MessageAttachment,
  ReasoningLevel,
  ModelRole,
  ToolCall,
  ToolConfig,
  ToolSourceType
} from '../models/ChatModels'
import { Assistant, DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'
import { AttachmentPicker } from '../components/AttachmentPicker'
import { ImagePreview } from '../components/ImagePreview'
import { ScrollToBottomButton } from '../components/ScrollToBottomButton'
import { ScrollToBottomLoadingButton } from '../components/ScrollToBottomLoadingButton'
import { SharePreviewSheet } from '../components/SharePreviewSheet'
import { ChatViewModel, TitleGenerationCallbacks } from '../viewmodels/ChatViewModel'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { AppStateManager } from '../viewmodels/AppStateManager'
import { AITaskService } from '../services/AITaskService'
import { WebSearchService } from '../services/WebSearchService'
import { DefaultModelService } from '../services/DefaultModelService'
import { PreferenceKeys, PreferencesService } from '../services/PreferencesService'
import { TTSService } from '../services/TTSService'
import { McpService } from '../services/McpService'
import { ToolRegistry } from '../services/ToolRegistry'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { registerBuiltinTools } from '../config/BuiltinTools'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { inputMethod } from '@kit.IMEKit'
import { webview } from '@kit.ArkWeb'
import { dismissActiveSnackBarOnBack, showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { ChatModelSelectorSheetContent } from '../components/chat/ChatModelSelectorSheetContent'
import { ChatInputAreaSection } from '../components/chat/ChatInputAreaSection'
import { ChatMultiSelectToolbar } from '../components/chat/ChatMultiSelectToolbar'
import { ChatMessageListSection } from '../components/chat/ChatMessageListSection'
import { ChatToolPickerSheetContent } from '../components/chat/ChatToolPickerSheetContent'
import { ChatToolExecutionApprovalSheetContent } from '../components/chat/ChatToolExecutionApprovalSheetContent'
import {
  ChatNavigationTitleContent,
  CHAT_NAVIGATION_TITLE_STACK_BUILDER_HEIGHT
} from '../components/ChatNavigationTitleContent'
import {
  ReasoningControlMode,
  normalizeReasoningLevelForControl,
  resolveReasoningControlMode,
  supportsReasoningXhighControl
} from '../services/ProviderCompatibilityRegistry'
import {
  getListBottomPaddingForChat,
  getPreviewTimeTextForChat,
  shouldShowScrollToTopButtonForChat,
  shouldShowToolSelectionChipForChat
} from './chat/ChatPageUiHelper'
import { parseToolIdsFromRouteRaw } from './chat/ChatToolIdHelper'
import { ChatManualSearchFlow, ChatManualSearchFlowDependencies } from './chat/ChatManualSearchFlow'
import { ChatSendFlow, ChatSendFlowDependencies } from './chat/ChatSendFlow'
import { ChatStopFlow, ChatStopFlowDependencies } from './chat/ChatStopFlow'
import { ChatInlineEditFlow, ChatInlineEditFlowDependencies } from './chat/ChatInlineEditFlow'
import { ChatSelectionFlow, ChatSelectionFlowDependencies } from './chat/ChatSelectionFlow'
import { ChatPageLoadFlow, ChatPageLoadFlowDependencies, ChatPageLoadResult } from './chat/ChatPageLoadFlow'
import { ChatTaskAlertFlow, ChatTaskAlertFlowDependencies } from './chat/ChatTaskAlertFlow'
import { ChatScrollUiFlow, ChatScrollUiFlowDependencies } from './chat/ChatScrollUiFlow'
import { buildHdsTopNavigationTitleBarOptions, HdsTopNavigationBlurOptions } from '../utils/HdsVisualEffectUtil'
import {
  collectTailMessageIds,
  findMessageIndexById,
  resolveUserMessageIndexForRegenerate,
  toListScrollIndexForMessage
} from './chat/ChatMessageActionHelper'
import { ChatPageRouteParams } from './chat/ChatPageRouteTypes'
import { resolveModelSwitchReasoningLevel } from './chat/ChatReasoningStateHelper'
import { getChatContentMaxWidth, LayoutSizeClass } from '../config/LayoutProfile'
import { getAppUiState, observeAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { applyModelDraft } from '../utils/ModelDraftUtils'
import { ToolPreviewEntry, buildToolArgumentsPreview } from '../utils/ToolPayloadSummaryUtils'
import { DEFAULT_PRIMARY_COLOR } from '../config/ThemeDefaults'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { normalizeAssistantAvatarValue } from '../components/AssistantAvatar'

const DOMAIN = 0x0003
const TAG = 'ChatPage'

class ProviderModelSelection {
  provider: ModelProvider
  model: ModelInfo

  constructor(provider: ModelProvider, model: ModelInfo) {
    this.provider = provider
    this.model = model
  }
}

class EditedMessageToolContext {
  webSearchEnabled: boolean = false
  selectedToolIds: string[] = []
}

const HDS_NAV_DESTINATION_MINI_TITLE_BAR_HEIGHT: number = 56
const HDS_NAV_TITLE_LEFT_ACTION_LANE_WIDTH: number = 44
const HDS_NAV_TITLE_RIGHT_ACTION_LANE_WIDTH_SINGLE: number = 44
const HDS_NAV_TITLE_RIGHT_ACTION_LANE_WIDTH_DOUBLE: number = 80

@ComponentV2
export struct ChatPage {
  @Local navPathStack: NavPathStack = new NavPathStack()
  @Param routeParamsSeed: ChatPageRouteParams | null = null
  @Local routeParams: ChatPageRouteParams | null = null
  @Local messages: ChatMessage[] = []
  @Local inputText: string = ''
  @Local currentModel: string = ''
  @Local currentModelId: string = ''
  @Local currentAssistantId: string = DEFAULT_ASSISTANT_ID
  @Local currentAssistantAvatarSymbol: string = 'AI'
  @Local currentAssistantColor: string = DEFAULT_PRIMARY_COLOR
  @Local assistantAvatarRenderTick: number = 0
  @Local isModelSelectorVisible: boolean = false
  @Local modelSheetActivePanel: string = 'selector'
  @Local editingModel: ModelInfo | null = null
  @Local editingModelProvider: ModelProvider | null = null
  @Local isLoading: boolean = false
  @Local isSending: boolean = false
  // 应用是否退到后台（用于处理生成中返回桌面/关闭应用）
  private get appInBackground(): boolean {
    return getAppUiState().appInBackground
  }
  private get inAppTaskAlertPayload(): string {
    return getAppUiState().inAppTaskAlertPayload
  }
  private get openSessionPayload(): string {
    return getAppUiState().openSessionPayload
  }
  @Local providers: ModelProvider[] = []
  // 附件相关状态
  @Local pendingAttachments: MessageAttachment[] = []
  @Local showAttachmentPicker: boolean = false
  @Local attachmentPanelHeightVp: number = 0
  private readonly ATTACHMENT_PANEL_EXPANDED_HEIGHT: number = 130
  // 是否在列表底部
  @Local isAtBottom: boolean = false
  // 是否在列表顶部
  @Local isAtTop: boolean = false
  @Local currentScrollOffsetVp: number = 0
  @Local scrollProgress: number = 0
  private firstVisibleListIndex: number = 0
  private lastVisibleListIndex: number = 0
  // 输入框显示状态（true=显示，false=隐藏）
  @Local isInputBarVisible: boolean = true
  @Local inputAreaHeightVp: number = 0
  @Local multiSelectToolbarHeightVp: number = 0
  // 输入框是否处于焦点状态（用于控制预览气泡显示）
  @Local isInputFocused: boolean = false
  // 计算滚动偏移
  private lastScrollOffset: number = 0
  private readonly inputBarShowThreshold: number = 6
  private readonly inputBarHideThreshold: number = 18
  @Local pendingInitialBottomAlignment: boolean = false
  // 会话标题相关状态
  @Local sessionTitle: string = ''
  @Local isTitleGenerating: boolean = false
  @Local titleGenerateFailed: boolean = false
  // 图片预览状态
  @Local showImagePreview: boolean = false
  @Local previewImages: Array<string> = []
  @Local previewImageIndex: number = 0
  @Local showMessageWebSheet: boolean = false
  @Local messageWebSheetUrl: string = ''
  @Local messageWebSheetTitle: string = ''
  private messageSheetWebController: webview.WebviewController = new webview.WebviewController()
  private hasInitializedRoute: boolean = false
  // 当前正在朗读的消息ID
  private get speakingMessageId(): string {
    return getAppUiState().speakingMessageId
  }
  // 是否为通过"新建对话"创建的空会话（返回时需要删除）
  private isNewEmptySession: boolean = false
  // 搜索取消标志（用于取消正在进行的联网查询）
  private isSearchCancelled: boolean = false
  private pendingToolExecutionApprovalResolver: ((approved: boolean) => void) | null = null
  // 联网查询全局可用状态（工具中心控制）
  @Local webSearchAvailable: boolean = false
  @Local webSearchConversationEnabled: boolean = false
  @Local selectedToolIds: string[] = []
  @Local availableChatTools: ToolConfig[] = []
  @Local isRefreshingMcpToolAvailability: boolean = false
  @Local showToolPickerSheet: boolean = false
  @Local showToolExecutionApprovalSheet: boolean = false
  @Local toolExecutionApprovalSourceLabel: string = ''
  @Local toolExecutionApprovalName: string = ''
  @Local toolExecutionApprovalArgumentSummary: string = ''
  @Local toolExecutionApprovalArgumentEntries: ToolPreviewEntry[] = []
  @Local toolExecutionApprovalArgumentsPreview: string = '{}'
  @Local toolExecutionApprovalArgumentsTruncated: boolean = false
  @Local showRawToolExecutionApprovalArguments: boolean = false
  // 推理级别状态
  @Local reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  // 最近截图检测状态（由 ChatInputBar 回调设置，ScreenshotBanner 独立渲染）
  @Local hasRecentScreenshot: boolean = false
  // 是否为新建对话（用于加载和自动发送策略）
  @Local isNewChatTransition: boolean = false
  // 是否自动聚焦输入框
  @Local autoFocusInput: boolean = false
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
  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }
  private get themeUserBubbleText(): string {
    return getAppUiState().themeUserBubbleText
  }
  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get chatFontSize(): number {
    return getAppUiState().chatFontSize
  }
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }
  private get messageThemeRenderKey(): string {
    const uiState = getAppUiState()
    return `${uiState.colorTheme}_${uiState.isDarkMode ? '1' : '0'}`
  }
  // 多选模式状态
  @Local isMultiSelectMode: boolean = false
  @Local selectedMessageIds: Array<string> = []
  @Local selectableTextMessageId: string = ''
  // 分享预览弹窗状态
  @Local showSharePreview: boolean = false
  @Local shareMessages: ChatMessage[] = []
  // 编辑消息相关状态（内联编辑模式）
  @Local isEditingMessage: boolean = false // 是否处于消息编辑模式
  @Local editingMessageId: string = '' // 正在编辑的消息ID
  @Local editingOriginalContent: string = '' // 原始内容（用于取消编辑）
  @Local editingOriginalAttachments: MessageAttachment[] = [] // 原始附件
  @Local editingMessageIsUser: boolean = true // 是否为用户消息（决定是否显示"保存并发送"）
  @Local editingWebSearchEnabled: boolean = false
  @Local editingSelectedToolIds: string[] = []
  @Local editingReasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  @Local messageListSyncVersion: number = 0
  private scroller: Scroller = new Scroller()
  private maxScrollOffset: number = 0
  private readonly floatingScrollButtonBottomOffsetVp: number = 128
  private readonly scrollOffsetUiSyncStepVp: number = 96
  private mcpToolAvailabilityRefreshTask: Promise<void> | null = null
  private chatViewModel: ChatViewModel = ServiceRegistry.chat()
  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()
  private appStateManager: AppStateManager = ServiceRegistry.appState()
  private webSearchService: WebSearchService = ServiceRegistry.webSearch()
  private defaultModelService: DefaultModelService = ServiceRegistry.defaultModel()
  private preferencesService: PreferencesService = ServiceRegistry.preferences()
  private aiTaskService: AITaskService = ServiceRegistry.aiTask()
  private toolRegistry: ToolRegistry = ServiceRegistry.toolRegistry()
  private mcpService: McpService = ServiceRegistry.mcp()
  private chatTaskOrchestrator = ServiceRegistry.chatTaskOrchestrator()
  private ttsService: TTSService = new TTSService()
  // 当前服务商配置
  private currentProvider: ModelProvider | null = null
  private sessionId: string = ''
  private pendingInitialPrompt: string = ''
  private pendingInitialToolIds: string[] = []
  private initialPromptAutoSent: boolean = false
  private forcedToolIdsOnce: string[] = []
  private currentTaskId: string = ''
  private isSendDispatching: boolean = false
  private lastHandledAlertTimestamp: number = 0
  private isPageVisible: boolean = false
  // 兜底 watcher：页面切换时可能错过一次任务完成事件，这里只负责回收发送态，不碰消息内容同步
  private runtimeStateWatchdogTimerId: number = -1
  private manualSearchFlow: ChatManualSearchFlow | null = null
  private sendFlow: ChatSendFlow | null = null
  private stopFlow: ChatStopFlow | null = null
  private inlineEditFlow: ChatInlineEditFlow | null = null
  private selectionFlow: ChatSelectionFlow | null = null
  private loadFlow: ChatPageLoadFlow | null = null
  private taskAlertFlow: ChatTaskAlertFlow | null = null
  private scrollUiFlow: ChatScrollUiFlow | null = null
  private draftAutosaveTimerId: number = -1
  private readonly draftAutosaveDelayMs: number = 400
  private appUiStateDisposers: Array<() => void> = []
  private initialBottomAlignmentRetryTimerIds: number[] = []
  private initialBottomAlignmentCompletionTimerId: number = -1
  private assistantAvatarReloadToken: number = 0

  private showChatSnack(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  aboutToAppear(): void {
    if (this.routeParams === null && this.routeParamsSeed !== null) {
      this.routeParams = this.routeParamsSeed
      this.applyRouteDisplaySeed(this.routeParamsSeed)
    }
    if (this.sessionTitle === '') {
      this.sessionTitle = this.getDefaultSessionTitle()
    }
    if (this.toolExecutionApprovalArgumentSummary === '') {
      this.toolExecutionApprovalArgumentSummary = this.getNoToolArgumentsText()
    }
    this.registerAppUiStateObservers()
    // 设置键盘避让模式
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)

    // 注册内置工具
    registerBuiltinTools()
    ServiceRegistry.toolExecution().setApprovalCallback(async (toolCall, tool) => {
      return await this.requestToolExecutionApproval(tool.config.name, tool.config.sourceLabel, toolCall.arguments)
    })

    // 设置标题生成回调
    const titleCallbacks: TitleGenerationCallbacks = {
      onTitleUpdated: (title: string): void => {
        this.sessionTitle = title
        this.titleGenerateFailed = false
      },
      onTitleGenerating: (isGenerating: boolean): void => {
        this.isTitleGenerating = isGenerating
      },
      onTitleFailed: (): void => {
        this.titleGenerateFailed = true
        this.showChatSnack($r('app.string.title_generate_failed_config'), 2000, SnackBarTone.ERROR)
      }
    }
    this.chatViewModel.setTitleCallbacks(titleCallbacks)

    // 初始化TTS服务
    this.initTTSService()

    // 如果通过 navDestination builder 传入了 routeParams，直接初始化
    // 否则等 onReady 回调设置 routeParams 后再初始化
    if (this.routeParams !== null) {
      this.tryInitWithParams(this.routeParams)
    }
  }

  private tryInitWithParams(params: ChatPageRouteParams | null): void {
    if (this.hasInitializedRoute) {
      return
    }
    this.hasInitializedRoute = true
    this.initWithParams(params)
  }

  // 从路由参数初始化页面（aboutToAppear 或 onReady 触发）
  private initWithParams(params: ChatPageRouteParams | null): void {
    this.applyRouteDisplaySeed(params)
    if (params !== null && params !== undefined) {
      console.info('ChatPage', `[initWithParams] sessionId=${params.sessionId ?? ''}`)
      if (params.sessionId !== undefined && params.sessionId !== '') {
        this.isNewChatTransition = false
      } else {
        this.isNewChatTransition = true
      }
    } else {
      console.info('ChatPage', '[initWithParams] params is null, treating as new chat')
      this.isNewChatTransition = true
    }
    this.loadData()
  }

  private applyRouteDisplaySeed(params: ChatPageRouteParams | null): void {
    if (params === null || params === undefined) {
      return
    }
    if (params.sessionTitle !== undefined && params.sessionTitle.trim() !== '') {
      this.sessionTitle = params.sessionTitle.trim()
    }
    if (this.currentModel === '' && params.modelId !== undefined && params.modelId.trim() !== '') {
      this.currentModelId = params.modelId.trim()
      this.currentModel = params.modelId.trim()
    }
  }

  // 修复页面恢复时可能的不一致状态
  private fixInconsistentState(): void {
    const hasActiveRequestForCurrentSession = this.sessionId !== '' &&
      this.chatViewModel.hasActiveRequestForSession(this.sessionId)

    // 如果 isSending 为 true 但没有活跃请求，重置状态
    if (this.isSending && !hasActiveRequestForCurrentSession) {
      this.isSending = false
      this.currentTaskId = ''
      console.info('ChatPage', '[fixInconsistentState] 重置 isSending 状态')
    }

    // 检查最后一条消息的 isGenerating 和 isSearching 状态
    if (this.messages.length > 0) {
      const lastMessage = this.messages[this.messages.length - 1]
      if (lastMessage.role === MessageRole.ASSISTANT) {
        // 如果没有活跃请求，重置生成状态
        if (lastMessage.isGenerating && !hasActiveRequestForCurrentSession) {
          lastMessage.isGenerating = false
          console.info('ChatPage', '[fixInconsistentState] 重置最后一条消息的 isGenerating 状态')
        }
        // 如果没有活跃请求，重置搜索状态
        if (lastMessage.isSearching && !hasActiveRequestForCurrentSession) {
          lastMessage.isSearching = false
          console.info('ChatPage', '[fixInconsistentState] 重置最后一条消息的 isSearching 状态')
        }
      }
    }
  }

  /**
   * 状态栏联动：仅图片预览时隐藏状态栏。
   * 输入框、标题栏、状态栏始终显示（用户要求）。
   */
  private updateStatusBar(): void {
    this.setChatStatusBarVisible(!this.showImagePreview)
  }

  private setChatStatusBarVisible(visible: boolean): void {
    const hostContext = this.getUIContext().getHostContext()
    if (hostContext === undefined || hostContext === null) {
      return
    }
    const context = hostContext as common.UIAbilityContext
    const mainWindow = context.windowStage.getMainWindowSync()
    mainWindow.setSpecificSystemBarEnabled('status', visible).catch((): void => {})
  }

  aboutToDisappear(): void {
    this.isPageVisible = false
    ServiceRegistry.toolExecution().setApprovalCallback(null)
    // 释放TTS资源
    this.ttsService.destroy()
    this.clearInitialBottomAlignmentRetries()
    this.clearRuntimeStateWatchdog()
    this.flushDraftAutosave(true).catch((error: Error): void => {
      console.error('ChatPage', `Failed to flush draft on disappear: ${JSON.stringify(error)}`)
    })
    this.unregisterAppUiStateObservers()
    this.syncActiveSessionBinding()
    // 离开页面时确保状态栏恢复
    this.setChatStatusBarVisible(true)

    if (this.shouldDeleteEmptySessionOnDisappear()) {
      this.chatViewModel.deleteSession(this.sessionId)
      console.info('ChatPage', '删除空会话: ' + this.sessionId)
    }
  }

  // 初始化TTS服务
  private async initTTSService(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await this.ttsService.init(context)
    } catch (error) {
      console.error('ChatPage', 'TTS初始化失败: ' + error)
    }
  }

  async loadData(): Promise<void> {
    const startTime = Date.now()
    hilog.info(DOMAIN, TAG, '📂 开始加载聊天页面数据...')
    this.resetScrollStateForSessionLoad()

    // 新建对话时不显示加载动画，让用户无感
    // 只有打开现有对话时才显示加载动画
    if (!this.isNewChatTransition) {
      this.isLoading = true
    }

    const loadResult = await this.getLoadFlow().loadPageData(this.routeParams, this.sessionTitle)

    this.webSearchAvailable = loadResult.webSearchEnabled
    await this.syncToolAvailabilityFromPreferences()
    console.info(
      'ChatPage',
      `[loadData] 联网可用=${this.webSearchAvailable}, 联网查询=${this.webSearchConversationEnabled}, 已选工具=${this.selectedToolIds.join(',')}`
    )

    this.applyLoadedSessionData(loadResult)
    await this.applyLoadedProviders(loadResult.providers)

    this.isLoading = false

    const elapsed = Date.now() - startTime
    hilog.info(DOMAIN, TAG, '✅ 聊天页面数据加载完成 (耗时: %{public}dms)', elapsed)

    this.triggerPostLoadActions()
    this.activateCurrentSessionRuntimeState()
    this.refreshMcpToolAvailabilityInBackground(false)
  }

  private async applyLoadedProviders(providers: ModelProvider[]): Promise<void> {
    this.providers = providers
    console.info('ChatPage', `[loadData] Loaded ${this.providers.length} providers`)

    if (this.providers.length === 0) {
      this.currentModel = ''
      this.currentModelId = ''
      this.currentProvider = null
      return
    }
    await this.validateAndSetCurrentModel()
  }

  private replaceMessages(nextMessages: ChatMessage[]): void {
    this.messages.splice(0, this.messages.length, ...nextMessages)
    this.markMessageListChanged()
  }

  private clearMessages(): void {
    this.messages.splice(0, this.messages.length)
    this.markMessageListChanged()
  }

  private markMessageListChanged(): void {
    this.messageListSyncVersion = this.messageListSyncVersion + 1
  }

  private applyLoadedSessionData(loadResult: ChatPageLoadResult): void {
    this.pendingInitialBottomAlignment = false
    this.pendingInitialPrompt = loadResult.pendingInitialPrompt
    this.pendingInitialToolIds = loadResult.pendingInitialToolIds
    this.initialPromptAutoSent = loadResult.initialPromptAutoSent
    this.sessionId = loadResult.sessionId
    this.sessionTitle = loadResult.sessionTitle
    this.webSearchConversationEnabled = loadResult.webSearchEnabled && loadResult.webSearchConversationEnabled
    this.reasoningLevel = loadResult.reasoningLevel
    this.inputText = loadResult.draftText
    this.pendingAttachments = [...loadResult.draftAttachments]
    this.isNewChatTransition = loadResult.isNewChatTransition
    this.isNewEmptySession = loadResult.isNewEmptySession
    this.applyAssistantSnapshot(loadResult.assistantId, loadResult.assistantAvatarSymbol, loadResult.assistantColor)

    if (!this.isNewChatTransition) {
      this.replaceMessages(loadResult.messages)
      this.pendingInitialBottomAlignment = this.messages.length > 0
      hilog.info(DOMAIN, TAG, '📨 加载会话消息: %{public}d 条', this.messages.length)
      return
    }

    this.clearMessages()
  }

  private applyAssistantSnapshot(assistantId: string, avatarSymbol: string, color: string): void {
    this.currentAssistantId = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    this.currentAssistantAvatarSymbol = normalizeAssistantAvatarValue(avatarSymbol)
    this.currentAssistantColor = color.trim() !== '' ? color.trim() : DEFAULT_PRIMARY_COLOR
    this.bumpAssistantAvatarRenderTick()
  }

  private bumpAssistantAvatarRenderTick(): void {
    this.assistantAvatarRenderTick += 1
  }

  private getCurrentSessionAssistantId(): string {
    const currentSession = this.chatViewModel.getCurrentSession()
    if (currentSession !== null && currentSession.id === this.sessionId && currentSession.assistantId !== '') {
      return currentSession.assistantId
    }
    return this.currentAssistantId !== '' ? this.currentAssistantId : DEFAULT_ASSISTANT_ID
  }

  private async reloadCurrentAssistantAvatarSnapshot(): Promise<void> {
    const token = this.assistantAvatarReloadToken + 1
    this.assistantAvatarReloadToken = token
    const assistantId = this.getCurrentSessionAssistantId()
    let assistant: Assistant | null = await ServiceRegistry.assistant().getAssistant(assistantId)
    if (assistant === null && assistantId !== DEFAULT_ASSISTANT_ID) {
      assistant = await ServiceRegistry.assistant().getAssistant(DEFAULT_ASSISTANT_ID)
    }
    if (token !== this.assistantAvatarReloadToken) {
      return
    }
    if (assistant === null) {
      this.applyAssistantSnapshot(DEFAULT_ASSISTANT_ID, 'AI', DEFAULT_PRIMARY_COLOR)
      return
    }
    this.applyAssistantSnapshot(assistant.id, assistant.avatarSymbol, assistant.color)
  }

  private triggerPostLoadActions(): void {
    if (this.isNewChatTransition) {
      setTimeout(() => {
        this.autoFocusInput = true
      }, 50)
    } else if (this.messages.length > 0) {
      this.requestInitialBottomAlignment()
    }

    if (this.isNewChatTransition && this.pendingInitialPrompt !== '' && !this.initialPromptAutoSent) {
      setTimeout(() => {
        this.autoSendInitialPrompt()
      }, 120)
    }
  }

  onInAppTaskAlertPayloadChanged(): void {
    this.getTaskAlertFlow().handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
  }

  onOpenSessionPayloadChanged(): void {
    this.getTaskAlertFlow().handleOpenSessionPayload(this.openSessionPayload)
  }

  onTaskEventTickChanged(): void {
    if (!this.isPageVisible || this.sessionId === '') {
      return
    }
    this.syncSendingStateFromRuntime()
    this.fixInconsistentState()
    this.updateRuntimeStateWatchdog()
  }

  private registerAppUiStateObservers(): void {
    if (this.appUiStateDisposers.length > 0) {
      return
    }
    this.appUiStateDisposers = [
      observeAppUiState(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, (): void => this.onInAppTaskAlertPayloadChanged()),
      observeAppUiState(AppStorageKeys.OPEN_SESSION_PAYLOAD, (): void => this.onOpenSessionPayloadChanged()),
      observeAppUiState(AppStorageKeys.TASK_EVENT_TICK, (): void => this.onTaskEventTickChanged()),
      observeAppUiState(AppStorageKeys.ASSISTANT_AVATAR_REFRESH_AT, (): void => this.onAssistantAvatarRefreshChanged()),
      observeAppUiState(AppStorageKeys.APP_IN_BACKGROUND, (): void => this.onAppBackgroundChanged())
    ]
  }

  private onAssistantAvatarRefreshChanged(): void {
    this.reloadCurrentAssistantAvatarSnapshot().catch((error: Error): void => {
      console.error('ChatPage', `Failed to reload assistant avatar snapshot: ${JSON.stringify(error)}`)
    })
  }

  private unregisterAppUiStateObservers(): void {
    for (let i = 0; i < this.appUiStateDisposers.length; i++) {
      this.appUiStateDisposers[i]()
    }
    this.appUiStateDisposers = []
  }

  private syncActiveSessionBinding(): void {
    const activeSessionId = this.isPageVisible && this.sessionId !== '' ? this.sessionId : ''
    setAppUiStateValue(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, activeSessionId)
  }

  private onAppBackgroundChanged(): void {
    if (this.appInBackground) {
      this.selectableTextMessageId = ''
      if (this.isMultiSelectMode) {
        this.handleExitMultiSelectMode()
      }
    }
  }

  private handlePageShown(): void {
    this.isPageVisible = true
    this.syncActiveSessionBinding()
    if (this.isLoading || this.sessionId === '') {
      return
    }
    this.refreshToolAvailabilityOnShown()
    this.syncSendingStateFromRuntime()
    this.fixInconsistentState()
    this.refreshProviders()
    this.updateRuntimeStateWatchdog()
    // 检查在页面切换间隙到达的 in-app alert
    this.getTaskAlertFlow().handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
  }

  private activateCurrentSessionRuntimeState(): void {
    this.syncActiveSessionBinding()
    this.syncSendingStateFromRuntime()
    this.fixInconsistentState()
    this.getTaskAlertFlow().handleOpenSessionPayload(this.openSessionPayload)
    this.getTaskAlertFlow().handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
    this.updateRuntimeStateWatchdog()
  }

  private clearInitialBottomAlignmentRetries(): void {
    for (let i = 0; i < this.initialBottomAlignmentRetryTimerIds.length; i++) {
      clearTimeout(this.initialBottomAlignmentRetryTimerIds[i])
    }
    this.initialBottomAlignmentRetryTimerIds.splice(0, this.initialBottomAlignmentRetryTimerIds.length)
    if (this.initialBottomAlignmentCompletionTimerId >= 0) {
      clearTimeout(this.initialBottomAlignmentCompletionTimerId)
      this.initialBottomAlignmentCompletionTimerId = -1
    }
  }

  private hasScheduledInitialBottomAlignment(): boolean {
    return this.initialBottomAlignmentRetryTimerIds.length > 0 || this.initialBottomAlignmentCompletionTimerId >= 0
  }

  private cancelPendingInitialBottomAlignment(): void {
    this.pendingInitialBottomAlignment = false
    this.clearInitialBottomAlignmentRetries()
  }

  private resetScrollStateForSessionLoad(): void {
    this.clearInitialBottomAlignmentRetries()
    this.pendingInitialBottomAlignment = false
    this.lastScrollOffset = 0
    this.currentScrollOffsetVp = 0
    this.isAtTop = false
    this.isAtBottom = false
    this.scrollProgress = 0
    this.firstVisibleListIndex = 0
    this.lastVisibleListIndex = 0
    this.maxScrollOffset = 0
    this.scroller = new Scroller()
    this.scrollUiFlow = null
  }

  private shouldSyncScrollOffsetToUi(value: number): boolean {
    if (this.isAtTop || this.isAtBottom) {
      return true
    }
    return Math.abs(this.currentScrollOffsetVp - value) >= this.scrollOffsetUiSyncStepVp
  }

  private handleMessageLinkOpen(title: string, url: string): void {
    this.messageWebSheetTitle = title
    this.messageWebSheetUrl = url
    this.showMessageWebSheet = true
  }

  @Builder
  private MessageWebSheetBuilder() {
    Column() {
      if (this.messageWebSheetUrl !== '') {
        Web({ src: this.messageWebSheetUrl, controller: this.messageSheetWebController })
          .width('100%')
          .layoutWeight(1)
      } else {
        Column() {
          Text($r('app.string.common_invalid_link'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  private scheduleInitialBottomAlignmentRetries(force: boolean = false): void {
    if (!this.pendingInitialBottomAlignment || this.messages.length <= 0) {
      return
    }
    if (!force && this.hasScheduledInitialBottomAlignment()) {
      return
    }
    this.clearInitialBottomAlignmentRetries()
    const delays: number[] = [0, 80, 180]
    const completionDelay = delays[delays.length - 1] + 180
    for (let i = 0; i < delays.length; i++) {
      const timerId = setTimeout(() => {
        if (!this.pendingInitialBottomAlignment || this.messages.length <= 0) {
          return
        }
        this.getScrollUiFlow().setIsAtBottom(true)
        this.getScrollUiFlow().setIsAtTop(false)
        this.getScrollUiFlow().alignToBottomAfterLayout()
      }, delays[i])
      this.initialBottomAlignmentRetryTimerIds.push(timerId)
    }
    this.initialBottomAlignmentCompletionTimerId = setTimeout(() => {
      if (!this.pendingInitialBottomAlignment) {
        return
      }
      this.pendingInitialBottomAlignment = false
      this.clearInitialBottomAlignmentRetries()
    }, completionDelay)
  }

  private refreshToolAvailabilityOnShown(): void {
    this.syncToolAvailabilityFromPreferences().then(() => {
      this.refreshMcpToolAvailabilityInBackground(false)
    }).catch((error: Object) => {
      console.warn('ChatPage', `[refreshToolAvailabilityOnShown] Failed: ${JSON.stringify(error)}`)
    })
  }

  private requestInitialBottomAlignment(): void {
    if (this.messages.length <= 0) {
      this.cancelPendingInitialBottomAlignment()
      return
    }
    this.pendingInitialBottomAlignment = true
    this.scheduleInitialBottomAlignmentRetries(true)
  }

  private handleListAppear(): void {
    if (!this.pendingInitialBottomAlignment || this.messages.length <= 0) {
      return
    }
    this.scheduleInitialBottomAlignmentRetries()
  }

  private handleMessageListContentAreaChange(): void {
    if (!this.pendingInitialBottomAlignment || this.messages.length <= 0) {
      return
    }
    this.scheduleInitialBottomAlignmentRetries()
  }

  private getBottomAnchorListIndex(): number {
    const draftItemCount = !this.isEditingMessage && this.hasDraftContent() ? 1 : 0
    return this.messages.length + 1 + draftItemCount
  }

  private getTotalListItemCount(): number {
    // 1 (top padding) + messages + draft preview (0 or 1) + 1 (bottom padding)
    const draftItemCount = !this.isEditingMessage && this.hasDraftContent() ? 1 : 0
    return 1 + this.messages.length + draftItemCount + 1
  }

  private getCurrentModelInfo(): ModelInfo | null {
    if (this.currentProvider === null || this.currentModelId === '') {
      return null
    }
    for (let i = 0; i < this.currentProvider.models.length; i++) {
      const model = this.currentProvider.models[i]
      if (model.id === this.currentModelId) {
        return model
      }
    }
    return null
  }

  private supportsReasoningForCurrentModel(): boolean {
    return this.getReasoningControlModeForCurrentModel() !== ReasoningControlMode.NONE
  }

  private supportsReasoningXhighForCurrentModel(): boolean {
    const model = this.getCurrentModelInfo()
    if (this.currentProvider === null || model === null) {
      return false
    }
    return supportsReasoningXhighControl(
      {
        providerId: this.currentProvider.id,
        baseUrl: this.currentProvider.baseUrl,
        apiStyle: this.currentProvider.apiStyle
      },
      model.id,
      model.capabilities.supportsReasoning,
      this.getCurrentReasoningStrategyOverride(model)
    )
  }

  private getReasoningControlModeForCurrentModel(): ReasoningControlMode {
    const model = this.getCurrentModelInfo()
    if (this.currentProvider === null || model === null) {
      return ReasoningControlMode.NONE
    }
    return this.getReasoningControlModeForModel(this.currentProvider, model)
  }

  private getReasoningControlModeForModel(provider: ModelProvider, model: ModelInfo): ReasoningControlMode {
    return resolveReasoningControlMode(
      {
        providerId: provider.id,
        baseUrl: provider.baseUrl,
        apiStyle: provider.apiStyle
      },
      model.id,
      model.capabilities.supportsReasoning,
      this.getCurrentReasoningStrategyOverride(model)
    )
  }

  private getCurrentReasoningStrategyOverride(model: ModelInfo): string {
    if (!model.capabilities.supportsReasoning) {
      return ''
    }
    return model.reasoningStrategyOverride
  }

  private syncReasoningAvailabilityWithCurrentModel(): void {
    const controlMode = this.getReasoningControlModeForCurrentModel()
    if (controlMode === ReasoningControlMode.NONE) {
      this.reasoningLevel = ReasoningLevel.OFF
      return
    }
    this.reasoningLevel = this.normalizeReasoningLevelForCurrentModel(this.reasoningLevel)
  }

  private resetReasoningForSelectedModel(provider: ModelProvider, model: ModelInfo): void {
    const controlMode = this.getReasoningControlModeForModel(provider, model)
    const resetLevel = resolveModelSwitchReasoningLevel(controlMode)
    if (resetLevel === ReasoningLevel.OFF) {
      this.reasoningLevel = ReasoningLevel.OFF
    } else {
      this.reasoningLevel = this.normalizeReasoningLevelForControlMode(
        ReasoningLevel.AUTO,
        controlMode,
        provider,
        model
      )
    }
    if (this.isEditingMessage) {
      this.editingReasoningLevel = this.reasoningLevel
    }
    this.persistReasoningPreference(this.reasoningLevel)
  }

  private normalizeReasoningLevelForCurrentModel(value: ReasoningLevel): ReasoningLevel {
    const model = this.getCurrentModelInfo()
    if (this.currentProvider === null || model === null) {
      return ReasoningLevel.OFF
    }
    return this.normalizeReasoningLevelForControlMode(
      value,
      this.getReasoningControlModeForModel(this.currentProvider, model),
      this.currentProvider,
      model
    )
  }

  private normalizeReasoningLevelForControlMode(
    value: ReasoningLevel,
    controlMode: ReasoningControlMode,
    provider: ModelProvider,
    model: ModelInfo
  ): ReasoningLevel {
    const normalized = normalizeReasoningLevelForControl(value, controlMode)
    if (normalized === ReasoningLevel.XHIGH && !supportsReasoningXhighControl(
      {
        providerId: provider.id,
        baseUrl: provider.baseUrl,
        apiStyle: provider.apiStyle
      },
      model.id,
      model.capabilities.supportsReasoning,
      this.getCurrentReasoningStrategyOverride(model)
    )) {
      return ReasoningLevel.HIGH
    }
    return normalized
  }

  private applySelectedToolIdsInMemory(toolIds: string[], enabledMcpServerIds?: Set<string>): void {
    this.selectedToolIds = [...this.normalizeSelectedToolIdsForPicker(toolIds, enabledMcpServerIds)]
  }

  private async setSelectedToolIds(toolIds: string[]): Promise<void> {
    const normalizedToolIds = this.normalizeSelectedToolIdsForPicker(toolIds)
    const savedToolIds = await this.mcpService.saveSelectedToolIds(normalizedToolIds)
    const enabledMcpServerIds = await this.loadEnabledMcpServerIds()
    this.applySelectedToolIdsInMemory(savedToolIds, enabledMcpServerIds)
  }

  private async setWebSearchConversationEnabled(enabled: boolean): Promise<void> {
    const normalized = this.webSearchAvailable && enabled
    await this.preferencesService.setBoolean(PreferenceKeys.SEARCH_CONVERSATION_ENABLED, normalized)
    this.webSearchConversationEnabled = normalized
  }

  private rebuildAvailableChatTools(): void {
    const configs = this.toolRegistry.getAllToolConfigs()
    const tools: ToolConfig[] = []
    for (let i = 0; i < configs.length; i++) {
      if (configs[i].enabled && configs[i].id !== 'web_search') {
        tools.push(configs[i])
      }
    }
    this.availableChatTools = tools
  }

  private async loadEnabledMcpServerIds(): Promise<Set<string>> {
    const configs = await this.mcpService.loadServerConfigs()
    const enabledServerIds: Set<string> = new Set<string>()
    for (let i = 0; i < configs.length; i++) {
      if (configs[i].enabled) {
        enabledServerIds.add(configs[i].id)
      }
    }
    return enabledServerIds
  }

  private normalizeStoredSelectedToolIdsLocally(toolIds: string[]): string[] {
    const normalizedToolIds: string[] = []
    for (let i = 0; i < toolIds.length; i++) {
      const toolId = toolIds[i].trim()
      if (toolId === '' || toolId === 'web_search') {
        continue
      }
      if (!normalizedToolIds.includes(toolId)) {
        normalizedToolIds.push(toolId)
      }
    }
    return normalizedToolIds
  }

  private extractMcpSourceIdFromToolId(toolId: string): string {
    if (!toolId.startsWith('mcp:')) {
      return ''
    }
    const raw = toolId.substring(4)
    const separatorIndex = raw.indexOf(':')
    if (separatorIndex <= 0) {
      return ''
    }
    return raw.substring(0, separatorIndex)
  }

  private async syncToolAvailabilityFromPreferences(): Promise<void> {
    const webSearchAvailable = await this.preferencesService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    this.webSearchAvailable = webSearchAvailable
    this.webSearchConversationEnabled = webSearchAvailable && await this.preferencesService.getBoolean(
      PreferenceKeys.SEARCH_CONVERSATION_ENABLED,
      webSearchAvailable
    )
    const webSearchTool = this.toolRegistry.getTool('web_search')
    if (webSearchTool !== undefined) {
      webSearchTool.config.enabled = webSearchAvailable
    }
    this.rebuildAvailableChatTools()
    const enabledMcpServerIds = await this.loadEnabledMcpServerIds()
    const selectedToolIds = await this.mcpService.loadSelectedToolIds()
    this.applySelectedToolIdsInMemory(selectedToolIds, enabledMcpServerIds)
  }

  private async refreshMcpToolAvailability(showError: boolean): Promise<void> {
    let refreshError: Object | null = null
    try {
      await this.mcpService.refreshAllServers()
    } catch (error) {
      refreshError = error
      console.warn('ChatPage', `[refreshMcpToolAvailability] MCP refresh failed: ${JSON.stringify(error)}`)
    }
    this.rebuildAvailableChatTools()
    const enabledMcpServerIds = await this.loadEnabledMcpServerIds()
    const selectedToolIds = await this.mcpService.loadSelectedToolIds()
    this.applySelectedToolIdsInMemory(selectedToolIds, enabledMcpServerIds)
    if (showError && refreshError !== null) {
      this.showError(pickLocalizedText('刷新工具失败', 'Failed to refresh tools'))
    }
  }

  private runMcpToolAvailabilityRefresh(showError: boolean): Promise<void> {
    if (this.mcpToolAvailabilityRefreshTask !== null) {
      return this.mcpToolAvailabilityRefreshTask
    }
    this.isRefreshingMcpToolAvailability = true
    const task = this.refreshMcpToolAvailability(showError).catch((error: Object) => {
      console.error('ChatPage', `[runMcpToolAvailabilityRefresh] Failed: ${JSON.stringify(error)}`)
      if (showError) {
        this.showError(pickLocalizedText('刷新工具失败', 'Failed to refresh tools'))
      }
    }).finally(() => {
      this.isRefreshingMcpToolAvailability = false
      if (this.mcpToolAvailabilityRefreshTask === task) {
        this.mcpToolAvailabilityRefreshTask = null
      }
    })
    this.mcpToolAvailabilityRefreshTask = task
    return task
  }

  private refreshMcpToolAvailabilityInBackground(showError: boolean): void {
    this.runMcpToolAvailabilityRefresh(showError)
  }

  private collectPendingEnabledMcpToolIds(toolIds: string[], enabledMcpServerIds: Set<string>): string[] {
    const pendingToolIds: string[] = []
    const normalizedToolIds = this.normalizeStoredSelectedToolIdsLocally(toolIds)
    for (let i = 0; i < normalizedToolIds.length; i++) {
      const toolId = normalizedToolIds[i]
      const sourceId = this.extractMcpSourceIdFromToolId(toolId)
      if (sourceId === '' || !enabledMcpServerIds.has(sourceId)) {
        continue
      }
      if (!this.toolRegistry.isToolRegistered(toolId)) {
        pendingToolIds.push(toolId)
      }
    }
    return pendingToolIds
  }

  private isMcpChatTool(tool: ToolConfig): boolean {
    return tool.sourceType === ToolSourceType.MCP && tool.sourceId.trim() !== ''
  }

  private normalizeSelectedToolIdsForPicker(toolIds: string[], enabledMcpServerIds?: Set<string>): string[] {
    const normalizedToolIds = this.normalizeStoredSelectedToolIdsLocally(toolIds)
    const selectedBuiltinToolIds: Set<string> = new Set<string>()
    const selectedMcpSourceIds: Set<string> = new Set<string>()
    const availableMcpSourceIds: Set<string> = new Set<string>()
    for (let i = 0; i < this.availableChatTools.length; i++) {
      const tool = this.availableChatTools[i]
      if (this.isMcpChatTool(tool)) {
        availableMcpSourceIds.add(tool.sourceId)
      }
    }
    for (let i = 0; i < normalizedToolIds.length; i++) {
      const toolId = normalizedToolIds[i]
      const registeredTool = this.toolRegistry.getTool(toolId)
      if (registeredTool !== undefined && registeredTool.config.enabled) {
        if (this.isMcpChatTool(registeredTool.config)) {
          selectedMcpSourceIds.add(registeredTool.config.sourceId)
          continue
        }
        selectedBuiltinToolIds.add(toolId)
        continue
      }
      const sourceId = this.extractMcpSourceIdFromToolId(toolId)
      if (sourceId !== '' && (enabledMcpServerIds === undefined || enabledMcpServerIds.has(sourceId))) {
        selectedMcpSourceIds.add(sourceId)
      }
    }
    for (let i = 0; i < this.availableChatTools.length; i++) {
      const tool = this.availableChatTools[i]
      if (this.isMcpChatTool(tool)) {
        if (selectedMcpSourceIds.has(tool.sourceId)) {
          selectedBuiltinToolIds.add(tool.id)
        }
        continue
      }
      if (!selectedBuiltinToolIds.has(tool.id)) {
        continue
      }
    }

    const pickerToolIds: string[] = []
    for (let i = 0; i < this.availableChatTools.length; i++) {
      const tool = this.availableChatTools[i]
      if (this.isMcpChatTool(tool)) {
        if (selectedMcpSourceIds.has(tool.sourceId)) {
          pickerToolIds.push(tool.id)
        }
        continue
      }
      if (selectedBuiltinToolIds.has(tool.id)) {
        pickerToolIds.push(tool.id)
      }
    }
    for (let i = 0; i < normalizedToolIds.length; i++) {
      const toolId = normalizedToolIds[i]
      const sourceId = this.extractMcpSourceIdFromToolId(toolId)
      if (sourceId === '' || !selectedMcpSourceIds.has(sourceId) || availableMcpSourceIds.has(sourceId)) {
        continue
      }
      if (!pickerToolIds.includes(toolId)) {
        pickerToolIds.push(toolId)
      }
    }
    return pickerToolIds
  }

  private isWebSearchFunctionName(functionName: string): boolean {
    const normalizedName = functionName.trim().toLowerCase().replace(/[\s\-]+/g, '_')
    return normalizedName === 'web_search' ||
      normalizedName === 'exa_search' ||
      normalizedName === 'websearch' ||
      normalizedName === 'search_web' ||
      normalizedName === 'internet_search' ||
      normalizedName === 'web_search_exa'
  }

  private isWebSearchToolCall(toolCall: ToolCall): boolean {
    if (toolCall.toolId.trim() === 'web_search') {
      return true
    }
    return this.isWebSearchFunctionName(toolCall.functionName)
  }

  private resolveEditedMessageToolContext(messageIndex: number): EditedMessageToolContext {
    const selectedToolIds: string[] = []
    let webSearchEnabled = false
    for (let i = messageIndex + 1; i < this.messages.length; i++) {
      const followupMessage = this.messages[i]
      if (followupMessage.role === MessageRole.USER) {
        break
      }
      if (followupMessage.searchQuery.trim() !== '') {
        webSearchEnabled = true
      }
      for (let j = 0; j < followupMessage.toolCalls.length; j++) {
        const toolCall = followupMessage.toolCalls[j]
        if (this.isWebSearchToolCall(toolCall)) {
          webSearchEnabled = true
          continue
        }
        const resolvedToolId = toolCall.toolId.trim() !== '' ?
          toolCall.toolId.trim() :
          (this.toolRegistry.getToolIdByFunctionName(toolCall.functionName.trim()) || '')
        if (resolvedToolId !== '' && !selectedToolIds.includes(resolvedToolId)) {
          selectedToolIds.push(resolvedToolId)
        }
      }
    }
    const context = new EditedMessageToolContext()
    context.webSearchEnabled = this.webSearchAvailable && webSearchEnabled
    context.selectedToolIds = this.normalizeSelectedToolIdsForPicker(selectedToolIds)
    return context
  }

  private getActiveComposerWebSearchEnabled(): boolean {
    if (this.isEditingMessage) {
      return this.editingWebSearchEnabled
    }
    return this.webSearchConversationEnabled
  }

  private getActiveComposerSelectedToolIds(): string[] {
    if (this.isEditingMessage) {
      return this.editingSelectedToolIds
    }
    return this.selectedToolIds
  }

  private getActiveComposerReasoningLevel(): ReasoningLevel {
    return this.isEditingMessage ? this.editingReasoningLevel : this.reasoningLevel
  }

  private updateActiveComposerSelectedToolIds(toolIds: string[]): Promise<void> {
    const normalizedToolIds = this.normalizeSelectedToolIdsForPicker(toolIds)
    if (this.isEditingMessage) {
      this.editingSelectedToolIds = [...normalizedToolIds]
      return Promise.resolve()
    }
    return this.setSelectedToolIds(normalizedToolIds)
  }

  private updateActiveComposerReasoningLevel(value: ReasoningLevel): void {
    const normalizedLevel = this.normalizeReasoningLevelForCurrentModel(value)
    if (this.isEditingMessage) {
      this.editingReasoningLevel = normalizedLevel
      return
    }
    this.reasoningLevel = normalizedLevel
    this.persistReasoningPreference(normalizedLevel)
  }

  private persistReasoningPreference(level: ReasoningLevel): void {
    this.persistReasoningPreferenceAsync(level).catch((error: Object) => {
      console.error('ChatPage', `[persistReasoningPreference] Failed: ${JSON.stringify(error)}`)
    })
  }

  private async persistReasoningPreferenceAsync(level: ReasoningLevel): Promise<void> {
    await this.preferencesService.setString(PreferenceKeys.CHAT_REASONING_LEVEL, level)
  }

  private handleComposerWebSearchToggle(): void {
    const nextValue = !this.getActiveComposerWebSearchEnabled()
    if (this.isEditingMessage) {
      this.editingWebSearchEnabled = this.webSearchAvailable && nextValue
      return
    }
    this.setWebSearchConversationEnabled(nextValue).catch((error: Object) => {
      console.error('ChatPage', `Failed to update chat search setting: ${JSON.stringify(error)}`)
      this.showError(pickLocalizedText('联网查询开关保存失败', 'Failed to save web search toggle'))
    })
  }

  private handleMcpToolGroupSelectionToggle(toolIds: string[], enabled: boolean): void {
    const nextToolIds = [...this.getActiveComposerSelectedToolIds()]
    for (let i = 0; i < toolIds.length; i++) {
      const toolId = toolIds[i]
      const index = nextToolIds.indexOf(toolId)
      if (enabled && index < 0) {
        nextToolIds.push(toolId)
      }
      if (!enabled && index >= 0) {
        nextToolIds.splice(index, 1)
      }
    }
    this.updateActiveComposerSelectedToolIds(nextToolIds).catch((error: Object) => {
      console.error('ChatPage', `Failed to update selected MCP tool group: ${JSON.stringify(error)}`)
      this.showError(pickLocalizedText('工具选择保存失败', 'Failed to save tool selection'))
    })
  }

  private hasSelectedTools(): boolean {
    return this.getActiveComposerSelectedToolIds().length > 0
  }

  private getDefaultSessionTitle(): string {
    return pickLocalizedText('新对话', 'New Chat')
  }

  private getNoToolArgumentsText(): string {
    return pickLocalizedText('无参数', 'No arguments')
  }

  private syncSendingStateFromRuntime(): void {
    if (this.sessionId === '') {
      this.isSending = false
      this.currentTaskId = ''
      return
    }
    this.isSending = this.chatViewModel.hasActiveRequestForSession(this.sessionId)
    if (!this.isSending) {
      this.currentTaskId = ''
    }
  }

  private updateRuntimeStateWatchdog(): void {
    const hasActiveRequestForCurrentSession = this.sessionId !== '' &&
      this.chatViewModel.hasActiveRequestForSession(this.sessionId)
    if (!this.isPageVisible || !hasActiveRequestForCurrentSession) {
      this.clearRuntimeStateWatchdog()
      return
    }
    if (this.runtimeStateWatchdogTimerId !== -1) {
      return
    }
    this.runtimeStateWatchdogTimerId = setInterval(() => {
      if (!this.isPageVisible || this.sessionId === '') {
        this.clearRuntimeStateWatchdog()
        return
      }
      if (this.chatViewModel.hasActiveRequestForSession(this.sessionId)) {
        return
      }
      this.syncSendingStateFromRuntime()
      this.fixInconsistentState()
      this.clearRuntimeStateWatchdog()
    }, 220)
  }

  private clearRuntimeStateWatchdog(): void {
    if (this.runtimeStateWatchdogTimerId === -1) {
      return
    }
    clearInterval(this.runtimeStateWatchdogTimerId)
    this.runtimeStateWatchdogTimerId = -1
  }

  private parseToolIdsFromRoute(raw: string): string[] {
    return parseToolIdsFromRouteRaw(raw)
  }

  private getSendFlow(): ChatSendFlow {
    if (this.sendFlow !== null) {
      return this.sendFlow
    }
    const deps: ChatSendFlowDependencies = {
      chatViewModel: this.chatViewModel,
      messages: this.messages,
      chatTaskOrchestrator: this.chatTaskOrchestrator,
      toolRegistry: this.toolRegistry,
      getSessionId: (): string => this.sessionId,
      getSessionTitle: (): string => this.sessionTitle,
      getCurrentTaskId: (): string => this.currentTaskId,
      getCurrentModelId: (): string => this.currentModelId,
      getCurrentModelName: (): string => this.currentModel,
      getMessages: (): ChatMessage[] => this.messages,
      getReasoningLevel: (): ReasoningLevel => this.reasoningLevel,
      executeManualSearch: async (messageContent: string, attachmentsToSend: MessageAttachment[]): Promise<void> => {
        console.info('ChatPage', '[联网查询] 显式联网模式，使用手动搜索执行链路')
        await this.getManualSearchFlow().startManualSearchFallback(messageContent, attachmentsToSend)
      },
      onClearComposer: (): void => {
        this.clearDraftAutosaveTimer()
        this.inputText = ''
        this.pendingAttachments = []
      },
      onBeforeSend: (): void => {
        this.safeStopInputSession()
        this.getScrollUiFlow().scrollToBottomWithAnimation()
      },
      onSetSending: (value: boolean): void => {
        this.isSending = value
      },
      onSetCurrentTaskId: (taskId: string): void => {
        this.currentTaskId = taskId
      },
      onSyncMessages: (): void => {
        this.markMessageListChanged()
      },
      onScrollBottom: (): void => {
        this.getScrollUiFlow().alignToBottomIfPinned()
      },
      onSetNewEmptySession: (value: boolean): void => {
        this.isNewEmptySession = value
      },
      onDraftCommitted: (): void => {
        this.persistCurrentDraftState('', []).catch((error: Error): void => {
          console.error('ChatPage', `Failed to clear draft after send: ${JSON.stringify(error)}`)
        })
      },
      onMarkAutoTaskCompleted: (): void => {
        // no-op
      },
      onMarkAutoTaskFailed: (message: string): void => {
        // no-op
      },
      onShowError: (message: string | Resource): void => {
        this.showError(message)
      },
      onShowToast: (message: string | Resource): void => {
        this.showChatSnack(message)
      }
    }
    this.sendFlow = new ChatSendFlow(deps)
    return this.sendFlow
  }

  private getStopFlow(): ChatStopFlow {
    if (this.stopFlow !== null) {
      return this.stopFlow
    }
    const deps: ChatStopFlowDependencies = {
      chatViewModel: this.chatViewModel,
      chatTaskOrchestrator: this.chatTaskOrchestrator,
      messages: this.messages,
      getCurrentTaskId: (): string => this.currentTaskId,
      onSetCurrentTaskId: (taskId: string): void => {
        this.currentTaskId = taskId
      },
      onSetSearchCancelled: (value: boolean): void => {
        this.isSearchCancelled = value
      },
      onCancelManualSearchRequests: (): void => {
        if (this.manualSearchFlow !== null) {
          this.manualSearchFlow.cancelCurrentSearchRequest()
          return
        }
        this.webSearchService.cancelAllRequests()
      },
      onSyncMessages: (): void => {
        this.markMessageListChanged()
      },
      onSetSending: (value: boolean): void => {
        this.isSending = value
      },
      onSetLoading: (value: boolean): void => {
        this.isLoading = value
      },
      onClearForcedToolIds: (): void => {
        this.forcedToolIdsOnce = []
      },
      onMarkAutoTaskFailed: (message: string): void => {
        // no-op
      }
    }
    this.stopFlow = new ChatStopFlow(deps)
    return this.stopFlow
  }

  private getManualSearchFlow(): ChatManualSearchFlow {
    if (this.manualSearchFlow !== null) {
      return this.manualSearchFlow
    }
    const deps: ChatManualSearchFlowDependencies = {
      chatViewModel: this.chatViewModel,
      chatTaskOrchestrator: this.chatTaskOrchestrator,
      providerViewModel: this.providerViewModel,
      webSearchService: this.webSearchService,
      defaultModelService: this.defaultModelService,
      preferencesService: this.preferencesService,
      appStateManager: this.appStateManager,
      messages: this.messages,
      getSessionId: (): string => this.sessionId,
      getSessionTitle: (): string => this.sessionTitle,
      getCurrentTaskId: (): string => this.currentTaskId,
      onSetCurrentTaskId: (taskId: string): void => {
        this.currentTaskId = taskId
      },
      getCurrentProvider: (): ModelProvider | null => this.currentProvider,
      getCurrentModelId: (): string => this.currentModelId,
      getCurrentModelName: (): string => this.currentModel,
      getMessages: (): ChatMessage[] => this.messages,
      getReasoningLevel: (): ReasoningLevel => this.reasoningLevel,
      isSearchCancelled: (): boolean => this.isSearchCancelled,
      onSyncMessages: (): void => {
        this.markMessageListChanged()
      },
      onScrollBottom: (): void => {
        this.getScrollUiFlow().alignToBottomIfPinned()
      },
      onSetSending: (value: boolean): void => {
        this.isSending = value
      },
      onSetSearchCancelled: (value: boolean): void => {
        this.isSearchCancelled = value
      },
      onClearComposer: (): void => {
        this.clearDraftAutosaveTimer()
        this.inputText = ''
        this.pendingAttachments = []
      },
      onBeforeManualSearchStart: (): void => {
        this.safeStopInputSession()
        this.getScrollUiFlow().scrollToBottomWithAnimation()
      },
      onSetNewEmptySession: (value: boolean): void => {
        this.isNewEmptySession = value
      },
      onDraftCommitted: (): void => {
        this.persistCurrentDraftState('', []).catch((error: Error): void => {
          console.error('ChatPage', `Failed to clear draft after manual search: ${JSON.stringify(error)}`)
        })
      },
      onMarkAutoTaskFailed: (message: string): void => {
        // no-op
      },
      onMarkAutoTaskCompleted: (): void => {
        // no-op
      },
      onShowError: (message: string | Resource): void => {
        this.showError(message)
      },
      onShowToast: (message: string | Resource): void => {
        this.showChatSnack(message)
      }
    }
    this.manualSearchFlow = new ChatManualSearchFlow(deps)
    return this.manualSearchFlow
  }

  private getInlineEditFlow(): ChatInlineEditFlow {
    if (this.inlineEditFlow !== null) {
      return this.inlineEditFlow
    }
    const deps: ChatInlineEditFlowDependencies = {
      chatViewModel: this.chatViewModel,
      getMessages: (): ChatMessage[] => this.messages,
      onValidateBeforeCommit: (
        content: string,
        attachments: MessageAttachment[],
        _webSearchEnabled: boolean,
        _selectedToolIds: string[],
        _reasoningLevel: ReasoningLevel
      ): boolean => {
        const prepareResult = this.getSendFlow().prepareSendRequest(
          content,
          attachments.length,
          this.isSending,
          this.currentProvider,
          this.currentModelId,
          this.chatTaskOrchestrator.canStartNewTask()
        )
        return prepareResult.shouldSend
      },
      onSyncMessages: (): void => {
        this.markMessageListChanged()
      },
      onResetEditState: (): void => {
        this.isEditingMessage = false
        this.editingMessageId = ''
        this.editingOriginalContent = ''
        this.editingOriginalAttachments = []
        this.editingWebSearchEnabled = false
        this.editingSelectedToolIds = []
        this.editingReasoningLevel = ReasoningLevel.OFF
      },
      onApplySavedDraft: (
        content: string,
        attachments: MessageAttachment[],
        webSearchEnabled: boolean,
        selectedToolIds: string[],
        reasoningLevel: ReasoningLevel
      ): void => {
        this.inputText = content
        this.pendingAttachments = [...attachments]
        this.webSearchConversationEnabled = this.webSearchAvailable && webSearchEnabled
        this.applySelectedToolIdsInMemory(selectedToolIds)
        this.reasoningLevel = this.normalizeReasoningLevelForCurrentModel(reasoningLevel)
      },
      onTriggerSend: async (
        content: string,
        attachments: MessageAttachment[],
        webSearchEnabled: boolean,
        selectedToolIds: string[],
        reasoningLevel: ReasoningLevel
      ): Promise<void> => {
        this.inputText = content
        this.pendingAttachments = [...attachments]
        this.webSearchConversationEnabled = this.webSearchAvailable && webSearchEnabled
        this.applySelectedToolIdsInMemory(selectedToolIds)
        this.reasoningLevel = this.normalizeReasoningLevelForCurrentModel(reasoningLevel)
        await this.sendMessage()
      },
      onShowToast: (message: string | Resource): void => {
        this.showChatSnack(message)
      }
    }
    this.inlineEditFlow = new ChatInlineEditFlow(deps)
    return this.inlineEditFlow
  }

  private getSelectionFlow(): ChatSelectionFlow {
    if (this.selectionFlow !== null) {
      return this.selectionFlow
    }
    const deps: ChatSelectionFlowDependencies = {
      chatViewModel: this.chatViewModel,
      messages: this.messages,
      onSyncMessages: (): void => {
        this.markMessageListChanged()
      },
      onSetMultiSelectMode: (value: boolean): void => {
        this.isMultiSelectMode = value
      },
      onSetSelectedMessageIds: (ids: string[]): void => {
        this.selectedMessageIds = ids
      },
      onSetInputBarVisible: (value: boolean): void => {
        this.getScrollUiFlow().setInputBarVisible(value)
      },
      onSetShareMessages: (messages: ChatMessage[]): void => {
        this.shareMessages = messages
      },
      onSetShowSharePreview: (value: boolean): void => {
        this.showSharePreview = value
      },
      onShowToast: (message: string | Resource): void => {
        this.showChatSnack(message)
      }
    }
    this.selectionFlow = new ChatSelectionFlow(deps)
    return this.selectionFlow
  }

  private getLoadFlow(): ChatPageLoadFlow {
    if (this.loadFlow !== null) {
      return this.loadFlow
    }
    const deps: ChatPageLoadFlowDependencies = {
      appStateManager: this.appStateManager,
      preferencesService: this.preferencesService,
      assistantService: ServiceRegistry.assistant(),
      providerViewModel: this.providerViewModel,
      chatViewModel: this.chatViewModel,
      parseToolIdsFromRoute: (raw: string): string[] => {
        return this.parseToolIdsFromRoute(raw)
      }
    }
    this.loadFlow = new ChatPageLoadFlow(deps)
    return this.loadFlow
  }

  private getTaskAlertFlow(): ChatTaskAlertFlow {
    if (this.taskAlertFlow !== null) {
      return this.taskAlertFlow
    }
    const deps: ChatTaskAlertFlowDependencies = {
      getCurrentSessionId: (): string => this.sessionId,
      getLastHandledAlertTimestamp: (): number => this.lastHandledAlertTimestamp,
      onSetLastHandledAlertTimestamp: (value: number): void => {
        this.lastHandledAlertTimestamp = value
      },
      onNavigateToSession: (sessionId: string): void => {
        this.navPathStack.replacePath({ name: 'ChatPage', param: { sessionId: sessionId } as ChatPageRouteParams })
      },
      onClearOpenSessionPayloadStorage: (): void => {
        setAppUiStateValue(AppStorageKeys.OPEN_SESSION_PAYLOAD, '')
      },
      onClearInAppTaskAlertPayloadStorage: (): void => {
        setAppUiStateValue(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, '')
      },
      getUIContext: (): UIContext => {
        return this.getUIContext()
      }
    }
    this.taskAlertFlow = new ChatTaskAlertFlow(deps)
    return this.taskAlertFlow
  }

  private getScrollUiFlow(): ChatScrollUiFlow {
    if (this.scrollUiFlow !== null) {
      return this.scrollUiFlow
    }
    const deps: ChatScrollUiFlowDependencies = {
      scroller: this.scroller,
      messages: this.messages,
        getBottomAnchorIndex: (): number => this.getBottomAnchorListIndex(),
        getCurrentScrollOffset: (): number => this.currentScrollOffsetVp,
        syncCurrentScrollOffset: (): number => this.syncCurrentScrollOffsetFromScroller(),
        syncIsAtBottomBoundary: (): boolean => this.syncIsAtBottomBoundaryFromScroller(),
        getLastScrollOffset: (): number => this.lastScrollOffset,
        setLastScrollOffset: (value: number): void => {
          this.lastScrollOffset = value
        },
      getMaxScrollOffset: (): number => this.maxScrollOffset,
      setMaxScrollOffset: (value: number): void => {
        this.maxScrollOffset = value
      },
      getFirstVisibleIndex: (): number => this.firstVisibleListIndex,
      getLastVisibleIndex: (): number => this.lastVisibleListIndex,
      getTotalListItemCount: (): number => this.getTotalListItemCount(),
      getInputBarShowThreshold: (): number => this.inputBarShowThreshold,
      getInputBarHideThreshold: (): number => this.inputBarHideThreshold,
      getIsAtTop: (): boolean => this.isAtTop,
      getIsAtBottom: (): boolean => this.isAtBottom,
      getIsInputBarVisible: (): boolean => this.isInputBarVisible,
      getIsSending: (): boolean => this.isSending,
      getIsEditingMessage: (): boolean => this.isEditingMessage,
      getEditingMessageId: (): string => this.editingMessageId,
      hasDraftContent: (): boolean => this.inputText.trim() !== '' || this.pendingAttachments.length > 0,
      onSetIsAtTopState: (value: boolean): void => {
        this.isAtTop = value
      },
      onSetIsAtBottomState: (value: boolean): void => {
        this.isAtBottom = value
      },
      onSetInputBarVisibleState: (_value: boolean): void => {
        // 输入框始终显示，不再响应滚动隐藏/显示
      },
      onSetCurrentScrollOffsetState: (value: number): void => {
        if (this.shouldSyncScrollOffsetToUi(value)) {
          this.currentScrollOffsetVp = value
        }
      },
      onSetScrollProgressState: (value: number): void => {
        this.scrollProgress = value
      },
      onAnimate: (duration: number, curve: Curve, updater: () => void): void => {
        this.getUIContext().animateTo({
          duration: duration,
          curve: curve
        }, updater)
      }
    }
    this.scrollUiFlow = new ChatScrollUiFlow(deps)
    return this.scrollUiFlow
  }

  private async autoSendInitialPrompt(): Promise<void> {
    if (this.initialPromptAutoSent || this.pendingInitialPrompt === '') {
      return
    }
    if (this.isSending) {
      return
    }

    this.initialPromptAutoSent = true
    this.inputText = this.pendingInitialPrompt
    this.pendingInitialPrompt = ''
    this.forcedToolIdsOnce = [...this.pendingInitialToolIds]

    await this.sendMessage()
  }

  private findProviderModelSelection(
    providerId: string,
    modelId: string
  ): ProviderModelSelection | null {
    if (providerId === '' || modelId === '') {
      return null
    }
    for (let i = 0; i < this.providers.length; i++) {
      const provider = this.providers[i]
      if (provider.id !== providerId) {
        continue
      }
      for (let j = 0; j < provider.models.length; j++) {
        const model = provider.models[j]
        if (model.id === modelId) {
          return new ProviderModelSelection(provider, model)
        }
      }
      break
    }
    return null
  }

  private findEnabledProviderModelSelection(
    providerId: string,
    modelId: string
  ): ProviderModelSelection | null {
    const selection = this.findProviderModelSelection(providerId, modelId)
    if (selection === null || !selection.model.isEnabled) {
      return null
    }
    return selection
  }

  private async applyModelSelection(
    provider: ModelProvider,
    model: ModelInfo,
    preferredName: string = '',
    syncGlobalModel: boolean = true,
    resetReasoning: boolean = false
  ): Promise<void> {
    const modelName = model.name !== '' ? model.name : (preferredName !== '' ? preferredName : model.id)
    this.currentProvider = provider
    this.currentModelId = model.id
    this.currentModel = modelName
    if (resetReasoning) {
      this.resetReasoningForSelectedModel(provider, model)
    } else {
      this.syncReasoningAvailabilityWithCurrentModel()
    }
    if (syncGlobalModel) {
      await this.appStateManager.setCurrentModel(model.id, modelName, provider.id)
    }
    await this.chatViewModel.updateCurrentSessionModelSelection(model.id, provider.id)
  }

  // 验证当前模型是否有效，如果无效则自动选择第一个可用模型
  private async validateAndSetCurrentModel(): Promise<void> {
    const currentSession = this.chatViewModel.getCurrentSession()
    if (currentSession !== null && currentSession.id === this.sessionId) {
      const sessionSelection = this.findEnabledProviderModelSelection(currentSession.providerId, currentSession.modelId)
      if (sessionSelection !== null) {
        await this.applyModelSelection(sessionSelection.provider, sessionSelection.model, '', !this.isNewEmptySession)
        return
      }
    }

    const savedSelection = this.findEnabledProviderModelSelection(
      this.appStateManager.getCurrentProviderId(),
      this.appStateManager.getCurrentModelId()
    )
    if (savedSelection !== null) {
      await this.applyModelSelection(savedSelection.provider, savedSelection.model)
      return
    }

    await this.selectFirstAvailableModel()
  }

  // 选择第一个可用的模型（优先使用默认聊天模型）
  private async selectFirstAvailableModel(): Promise<void> {
    // 先尝试使用默认聊天模型配置
    await this.defaultModelService.initialize()
    const defaultChatModel = this.defaultModelService.getModel(ModelRole.CHAT)

    if (defaultChatModel.isConfigured()) {
      // 检查默认模型是否仍然可用
      for (let i = 0; i < this.providers.length; i++) {
        const provider = this.providers[i]
        if (provider.id === defaultChatModel.providerId) {
          for (let j = 0; j < provider.models.length; j++) {
            const model = provider.models[j]
            if (model.id === defaultChatModel.modelId && model.isEnabled) {
              // 默认模型可用，使用它
              await this.applyModelSelection(provider, model)
              console.info('ChatPage', `Using default chat model: ${model.name} from ${provider.name}`)
              return
            }
          }
          break
        }
      }
      console.warn('ChatPage',
        `Default chat model configured but not available: ${defaultChatModel.modelName} from ${defaultChatModel.providerName}`)
    }

    // 默认模型未配置或不可用，回退到第一个可用模型
    for (let i = 0; i < this.providers.length; i++) {
      const provider = this.providers[i]
      for (let j = 0; j < provider.models.length; j++) {
        const model = provider.models[j]
        if (model.isEnabled) {
          await this.applyModelSelection(provider, model)
          console.info('ChatPage', `Auto-selected fallback model: ${model.name} from ${provider.name}`)
          return
        }
      }
    }

    // 没有可用模型
    this.currentProvider = null
    this.currentModelId = ''
    this.currentModel = ''
    this.syncReasoningAvailabilityWithCurrentModel()
  }

  private async refreshProviders(): Promise<void> {
    await this.appStateManager.loadState()

    const providers = await this.providerViewModel.loadProviders()
    console.info('ChatPage', `[refreshProviders] Loaded ${providers.length} providers`)

    if (providers.length > 0) {
      this.providers = providers
    }

    if (this.providers.length === 0) {
      this.currentModel = ''
      this.currentModelId = ''
      this.currentProvider = null
      this.syncReasoningAvailabilityWithCurrentModel()
    } else {
      // 验证并设置当前模型
      await this.validateAndSetCurrentModel()
    }
  }

  private getChatContentMaxWidth(): number {
    if (this.layoutSizeClass !== LayoutSizeClass.EXPANDED) {
      return 0
    }
    return getChatContentMaxWidth(this.windowWidthVp)
  }

  private getPageTopAvoidHeight(): number {
    if (this.layoutSizeClass === LayoutSizeClass.EXPANDED) {
      return 0
    }
    return this.px2vp(this.topAvoidHeight)
  }

  private getMessageListTopSpacerHeight(): number {
    return HDS_NAV_DESTINATION_MINI_TITLE_BAR_HEIGHT + this.getPageTopAvoidHeight()
  }

  private getTitleRightActionLaneWidth(): number {
    return this.shouldShowTitleBarNewChatAction() ?
      HDS_NAV_TITLE_RIGHT_ACTION_LANE_WIDTH_DOUBLE :
      HDS_NAV_TITLE_RIGHT_ACTION_LANE_WIDTH_SINGLE
  }

  private getStatusBarContentColor(): string {
    if (this.showImagePreview) {
      return '#F5F7FA'
    }
    return this.isDarkMode ? '#F5F7FA' : '#1F2329'
  }

  private isExistingSessionSeeded(): boolean {
    const seededSessionId = this.routeParams?.sessionId ?? this.routeParamsSeed?.sessionId ?? ''
    return seededSessionId.trim() !== ''
  }

  private shouldShowTitleBarNewChatAction(): boolean {
    if (!this.hasInitializedRoute) {
      return this.isExistingSessionSeeded()
    }
    if (this.messages.length > 0) {
      return true
    }
    return !this.isNewChatTransition && this.sessionId.trim() !== ''
  }

  private getTitleBarOptions(): HdsNavigationTitleBarOptions {
    const options = new HdsTopNavigationBlurOptions()
    options.startPaddingVp = 16
    options.endPaddingVp = 16
    options.materialType = this.materialType
    options.materialLevel = this.materialLevel
    options.windowWidthVp = this.windowWidthVp
    options.windowHeightVp = this.windowHeightVp
    options.maskExtraHeightVp = 24
    options.blurEffectiveEndOffsetVp = this.windowWidthVp > this.windowHeightVp ? 20 : 28
    options.stackBuilder = (): void => this.ChatTitleStackBuilder()
    return buildHdsTopNavigationTitleBarOptions(options)
  }

  @Builder
  private ChatTitleStackBuilder() {
    ChatNavigationTitleContent({
      sessionTitle: this.sessionTitle !== '' ? this.sessionTitle : this.getDefaultSessionTitle(),
      currentModelId: this.currentModelId,
      currentProviderId: this.currentProvider?.id ?? '',
      currentModelName: this.currentModel,
      currentProviderName: this.currentProvider?.name ?? '',
      currentProviderIconType: this.currentProvider?.iconType ?? 'svg',
      currentProviderIconPath: this.currentProvider?.iconPath ?? '',
      currentProviderTextIcon: this.currentProvider?.textIcon ?? '',
      currentProviderTextIconBgColor: this.currentProvider?.textIconBgColor ?? '',
      currentProviderCustomImagePath: this.currentProvider?.customImagePath ?? '',
      currentProviderBrandColor: this.currentProvider?.brandColor ?? '',
      isTitleGenerating: this.isTitleGenerating,
      isSending: this.isSending,
      titleGenerateFailed: this.titleGenerateFailed,
      showNewChatAction: this.shouldShowTitleBarNewChatAction(),
      leftActionLaneWidth: HDS_NAV_TITLE_LEFT_ACTION_LANE_WIDTH,
      rightActionLaneWidth: this.getTitleRightActionLaneWidth(),
      onBack: (): void => {
        this.handleBack()
      },
      onModelSelect: (): void => {
        this.safeStopInputSession()
        this.isModelSelectorVisible = true
        this.modelSheetActivePanel = 'selector'
      },
      onNewChat: (): void => {
        void this.handleNewChat()
      },
      onDeleteChat: (): void => {
        this.handleDeleteChat()
      },
      onRegenerateTitle: (): void => {
        void this.handleRegenerateTitle()
      },
      onWillEditTitle: (): void => {
        this.safeStopInputSession()
      },
      onTitleChanged: (newTitle: string): void => {
        this.handleSaveTitle(newTitle).catch((error: Object) => {
          console.error('ChatPage', `Failed to save inline title: ${JSON.stringify(error)}`)
          this.showError($r('app.string.action_failed_retry'))
        })
      }
    })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 消息列表 - 占满全屏
        ChatMessageListSection({
          isLoading: this.isLoading,
          loadingColor: this.themePrimary,
          scroller: this.scroller,
          messages: this.messages,
          syncVersion: this.messageListSyncVersion,
          isEditingMessage: this.isEditingMessage,
          editingMessageId: this.editingMessageId,
          selectedMessageIds: this.selectedMessageIds,
          isMultiSelectMode: this.isMultiSelectMode,
          selectableTextMessageId: this.selectableTextMessageId,
          inputText: this.inputText,
          pendingAttachments: this.pendingAttachments,
          showDraftPreview: this.hasDraftContent(),
          draftPreviewTimeText: this.getPreviewTimeText(),
          bottomPadding: this.getListBottomPadding(),
          topInsetHeight: this.getMessageListTopSpacerHeight(),
          currentModelId: this.currentModelId,
          assistantAvatarSymbol: this.currentAssistantAvatarSymbol,
          assistantAvatarColor: this.currentAssistantColor,
          assistantAvatarCacheKey: this.assistantAvatarRenderTick,
          chatFontSize: this.chatFontSize,
          themeRenderKey: this.messageThemeRenderKey,
          contentMaxWidth: this.getChatContentMaxWidth(),
          onRegenerate: (message: ChatMessage): void => {
            this.handleRegenerate(message)
          },
          onDelete: (message: ChatMessage): void => {
            this.handleDeleteMessage(message)
          },
          onEdit: (message: ChatMessage): void => {
            this.handleEditMessage(message)
          },
          onCancelEdit: (): void => {
            this.handleCancelEdit()
          },
          onShareMessage: (message: ChatMessage): void => {
            this.handleShareSingleMessage(message)
          },
          onTranslate: (content: string, targetLang: string,
            callback: (result: string, errorMessage: string) => void): void => {
            this.handleTranslate(content, targetLang, callback)
          },
          onImageClick: (images: Array<string>, imageIndex: number): void => {
            this.handleImagePreview(images, imageIndex)
          },
          onOpenLink: (title: string, url: string): void => {
            this.handleMessageLinkOpen(title, url)
          },
          onTTS: (messageId: string, content: string): void => {
            this.handleTTS(messageId, content)
          },
          onTTSStop: (): void => {
            this.handleTTSStop()
          },
          onSelect: (messageId: string): void => {
            this.handleToggleMessageSelection(messageId)
          },
          onEnterMultiSelect: (messageId: string): void => {
            this.handleEnterMultiSelectMode(messageId)
          },
          onSetSelectableTextMessageId: (messageId: string): void => {
            this.selectableTextMessageId = messageId
          },
          onListAppear: (): void => {
            this.handleListAppear()
          },
          onReachStart: (): void => {
            this.handleMessageListReachStart()
          },
          onReachEnd: (): void => {
            this.handleMessageListReachEnd()
          },
          onContentAreaChange: (): void => {
            this.handleMessageListContentAreaChange()
          },
          onDidScroll: (scrollOffset: number, scrollState: ScrollState): void => {
            this.handleMessageListDidScroll(scrollOffset, scrollState)
          },
          onScrollIndex: (firstIndex: number, lastIndex: number): void => {
            this.firstVisibleListIndex = firstIndex
            this.lastVisibleListIndex = lastIndex
          }
        })
          .width('100%')
          .height('100%')
          .backgroundColor(this.themeBackground)

        // 编辑模式点击层 - 点击空白处取消编辑
        if (this.isEditingMessage) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.handleCancelEdit()
            })
        }

        // 快速到顶部按钮
        ScrollToBottomButton({
          isVisible: this.shouldShowScrollToTopButton(),
          bottomAvoidHeight: this.getFloatingOverlayBottomAvoidHeightVp(),
          fixedBottomOffset: this.floatingScrollButtonBottomOffsetVp,
          buttonDirection: 1,
          progress: this.scrollProgress,
          extraOffsetY: this.shouldShowStandardScrollToBottomButton() ? -48 : 0,
          onScrollToTop: () => {
            this.handleScrollToTopRequest()
          }
        })

        // 回到底部按钮（非 AI 生成状态时显示）
        ScrollToBottomButton({
          isVisible: this.shouldShowStandardScrollToBottomButton(),
          bottomAvoidHeight: this.getFloatingOverlayBottomAvoidHeightVp(),
          fixedBottomOffset: this.floatingScrollButtonBottomOffsetVp,
          buttonDirection: 0,
          onScrollToBottom: () => {
            this.scrollToBottomWithAnimation()
          }
        })

        // AI 生成中的底部中间 loading 回到底部按钮
        ScrollToBottomLoadingButton({
          isVisible: this.shouldShowScrollToBottomLoadingButton(),
          isInputBarVisible: true,
          bottomAvoidHeight: this.getFloatingOverlayBottomAvoidHeightVp(),
          onScrollToBottom: () => {
            this.scrollToBottomWithAnimation()
          }
        })

        // 底部输入栏容器（非多选模式时显示）
        if (!this.isMultiSelectMode) {
          Column() {
            ChatInputAreaSection({
              inputText: this.inputText,
              onInputTextChange: (value: string): void => {
                this.inputText = value
              },
              attachments: this.pendingAttachments,
              onAttachmentsChange: (value: MessageAttachment[]): void => {
                this.pendingAttachments = [...value]
              },
              isSending: this.isSending,
              isAwaitingResponse: this.calcIsAwaitingAiOutput(),
              currentModelId: this.currentModelId,
              currentProviderId: this.currentProvider?.id ?? '',
              currentModelName: this.currentModel,
              currentProviderIconType: this.currentProvider?.iconType ?? 'svg',
              currentProviderIconPath: this.currentProvider?.iconPath ?? '',
              currentProviderTextIcon: this.currentProvider?.textIcon ?? '',
              currentProviderTextIconBgColor: this.currentProvider?.textIconBgColor ?? '',
              currentProviderCustomImagePath: this.currentProvider?.customImagePath ?? '',
              currentProviderBrandColor: this.currentProvider?.brandColor ?? '',
              autoFocus: this.autoFocusInput,
              isEditing: this.isEditingMessage,
              isAttachmentPanelOpen: this.showAttachmentPicker,
              webSearchAvailable: this.webSearchAvailable,
              webSearchEnabled: this.getActiveComposerWebSearchEnabled(),
              onToggleWebSearch: (): void => {
                this.handleComposerWebSearchToggle()
              },
              toolSelectionAvailable: shouldShowToolSelectionChipForChat(
                this.availableChatTools.length,
                this.getActiveComposerSelectedToolIds().length
              ),
              hasSelectedTools: this.hasSelectedTools(),
              reasoningAvailable: this.supportsReasoningForCurrentModel(),
              reasoningControlMode: this.getReasoningControlModeForCurrentModel(),
              reasoningXhighAvailable: this.supportsReasoningXhighForCurrentModel(),
              onOpenTools: (): void => {
                this.showToolPickerSheet = true
              },
              reasoningLevel: this.getActiveComposerReasoningLevel(),
              onReasoningLevelChange: (value: ReasoningLevel): void => {
                this.updateActiveComposerReasoningLevel(value)
              },
              hasRecentScreenshot: this.hasRecentScreenshot,
              bottomAvoidHeight: this.getComposerBottomAvoidHeightVp(),
              contentMaxWidth: this.getChatContentMaxWidth(),
              onCancelEdit: (): void => {
                this.handleCancelEdit()
              },
              onSend: (): void => {
                if (this.isEditingMessage) {
                  this.handleSaveAndSendInline()
                } else {
                  this.handleSend()
                }
              },
              onStop: (): void => {
                this.handleStop()
              },
              onModelIconClick: (): void => {
                this.isModelSelectorVisible = true
                this.modelSheetActivePanel = 'selector'
              },
              onAttachmentClick: (): void => {
                this.toggleAttachmentPanel()
              },
              onInputFocus: (): void => {
                if (!this.isEditingMessage) {
                  if (this.showAttachmentPicker) {
                    this.closeAttachmentPanel()
                  }
                  this.isInputFocused = true
                  setTimeout(() => {
                    this.getScrollUiFlow().alignToBottomAfterLayout()
                  }, 200)
                }
              },
              onInputBlur: (): void => {
                this.isInputFocused = false
              },
              onComposerContentChanged: (): void => {
                this.handleComposerContentChanged()
              },
              onRecentPhotoDetected: (detected: boolean): void => {
                this.hasRecentScreenshot = detected
              }
            })
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                this.handleInputAreaHeightChange(newArea)
              })
              .animation({
                duration: 220,
                curve: Curve.EaseOut
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: this.attachmentPanelHeightVp })
          .animation({
            duration: 260,
            curve: Curve.FastOutSlowIn
          })
          .position({ x: 0, y: '100%' })
          .translate({ y: '-100%', x: 0 })

          // 附件面板（与输入区分离定位，避免动态子布局只抬高输入区却不绘制面板内容）
          Column() {
            this.AttachmentPanelContentBuilder()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .height(this.attachmentPanelHeightVp)
          .opacity(this.showAttachmentPicker ? 1 : 0)
          .backgroundColor(this.themeSurface)
          .clip(true)
          .enabled(this.showAttachmentPicker)
          .animation({
            duration: 260,
            curve: Curve.FastOutSlowIn
          })
          .position({ x: 0, y: '100%' })
          .translate({ y: '-100%', x: 0 })
        }

        // 分享预览 Sheet 宿主（bindContentCover 和 bindSheet 不能在同一组件上，否则会冲突）
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.isModelSelectorVisible, this.ModelSelectorSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          blurStyle: BlurStyle.Thick,
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.isModelSelectorVisible = false
            this.modelSheetActivePanel = 'selector'
            this.editingModel = null
            this.editingModelProvider = null
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showMessageWebSheet, this.MessageWebSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          dragBar: true,
          showClose: true,
          title: { title: this.messageWebSheetTitle !== '' ? this.messageWebSheetTitle : $r('app.string.common_web_page') },
          onDisappear: () => {
            this.messageWebSheetUrl = ''
            this.messageWebSheetTitle = ''
            this.showMessageWebSheet = false
          }
        })
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
          .bindSheet($$this.showToolPickerSheet, this.ToolPickerBuilder(), {
            height: SheetSize.FIT_CONTENT,
            dragBar: true,
            showClose: false,
            backgroundColor: this.themeBackground,
            blurStyle: BlurStyle.Thick,
            preferType: SheetType.BOTTOM,
            onDisappear: () => {
              this.showToolPickerSheet = false
            }
          })

        Column()
          .width(0)
          .height(0)
          .bindSheet($$this.showToolExecutionApprovalSheet, this.ToolExecutionApprovalSheetBuilder(), {
            height: SheetSize.FIT_CONTENT,
            dragBar: true,
            showClose: false,
            backgroundColor: this.themeBackground,
            blurStyle: BlurStyle.Thick,
            preferType: SheetType.BOTTOM,
            maskColor: '#66000000',
            onDisappear: () => {
              this.handleToolExecutionApprovalSheetDisappear()
            }
          })

        // 多选工具栏（多选模式时显示）
        if (this.isMultiSelectMode) {
          Column() {
            ChatMultiSelectToolbar({
              selectedCount: this.selectedMessageIds.length,
              totalCount: this.messages.length,
              onSelectAll: () => {
                this.handleSelectAllMessages()
              },
              onDelete: () => {
                this.handleDeleteSelectedMessages()
              },
              onShare: () => {
                this.handleShareSelectedMessages()
              },
              onCancel: () => {
                this.handleExitMultiSelectMode()
              }
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 12, right: 12, bottom: this.getMultiSelectToolbarBottomInsetVp() })
          .position({ x: 0, y: '100%' })
          .translate({ y: '-100%', x: 0 })
          .hitTestBehavior(HitTestMode.Default)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.handleMultiSelectToolbarHeightChange(newArea)
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }

        // 图片预览（全屏覆盖层，不使用 bindContentCover 以避免模态层拦截手势）
        if (this.showImagePreview) {
          ImagePreview({
            images: this.previewImages,
            currentIndex: this.previewImageIndex,
            topSafeAreaVp: this.px2vp(this.topAvoidHeight),
            bottomSafeAreaVp: this.px2vp(this.bottomAvoidHeight),
            onClose: () => {
              this.showImagePreview = false
              this.updateStatusBar()
            }
          })
            .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .backgroundColor(this.themeBackground)
    }
    .titleBar(this.getTitleBarOptions())
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideTitleBar(this.showImagePreview, true)
    .systemBarStyle(
      { statusBarContentColor: this.getStatusBarContentColor() },
      { statusBarContentColor: this.getStatusBarContentColor() }
    )
    .hideBackButton(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .backgroundColor(this.themeBackground)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
      const param = context.pathInfo.param as ChatPageRouteParams
      if (param !== null && param !== undefined) {
        this.routeParams = param
      }
      // 如果 aboutToAppear 时 routeParams 还没设置，这里触发初始化
      if (!this.hasInitializedRoute) {
        this.tryInitWithParams(this.routeParams)
      }
    })
    .onShown(() => {
      this.handlePageShown()
    })
    .onHidden(() => {
      this.isPageVisible = false
      this.selectableTextMessageId = ''
      if (this.isMultiSelectMode) {
        this.handleExitMultiSelectMode()
      }
      this.syncActiveSessionBinding()
    })
    .onBackPressed((): boolean => {
      if (this.showImagePreview) {
        this.showImagePreview = false
        this.updateStatusBar()
        return true
      }
      if (this.showAttachmentPicker) {
        this.closeAttachmentPanel()
        return true
      }
      if (dismissActiveSnackBarOnBack()) {
        return true
      }
      this.handleBack()
      return true
    })
  }

  pageTransition() {
    PageTransitionEnter({
      type: RouteType.Push,
      duration: 350,
      curve: Curve.EaseOut
    })
      .slide(SlideEffect.Right)

    PageTransitionExit({
      type: RouteType.Pop,
      duration: 300,
      curve: Curve.EaseIn
    })
      .slide(SlideEffect.Right)

    // 被新页面覆盖时的退出动画
    PageTransitionExit({
      type: RouteType.Push,
      duration: 350,
      curve: Curve.EaseOut
    })
      .opacity(0.8)
      .translate({ x: '-20%' })

    // 返回时的进入动画
    PageTransitionEnter({
      type: RouteType.Pop,
      duration: 300,
      curve: Curve.EaseOut
    })
      .opacity(1)
      .translate({ x: 0 })
  }

  // 处理图片预览
  private handleImagePreview(images: Array<string>, index: number): void {
    hilog.info(DOMAIN, TAG, '🖼️ ChatPage.handleImagePreview (images: %{public}d, index: %{public}d)', images.length,
      index)
    this.previewImages = images
    this.previewImageIndex = index
    this.showImagePreview = true
    this.updateStatusBar()
  }

  @Builder
  ModelSelectorSheetBuilder() {
    ChatModelSelectorSheetContent({
      providers: this.providers,
      currentModelId: this.currentModelId,
      currentProviderId: this.currentProvider?.id ?? '',
      activePanel: this.modelSheetActivePanel,
      editingModel: this.editingModel!!,
      onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
        this.handleModelSelect(providerId, modelId, modelName)
        this.isModelSelectorVisible = false
      },
      onStartEdit: (model: ModelInfo, provider: ModelProvider): void => {
        this.editingModel = model
        this.editingModelProvider = provider
        this.modelSheetActivePanel = 'edit'
      },
      onSaveEdit: async (draft: ModelInfoExtendedJson): Promise<void> => {
        await this.saveModelEdit(draft)
      },
      onCancelEdit: (): void => {
        this.modelSheetActivePanel = 'selector'
        this.editingModel = null
        this.editingModelProvider = null
      }
    })
  }

  private async saveModelEdit(draft: ModelInfoExtendedJson): Promise<void> {
    const modelToSave = this.editingModel
    const providerToSave = this.editingModelProvider
    if (modelToSave === null || providerToSave === null) {
      return
    }

    applyModelDraft(modelToSave, draft)
    await this.providerViewModel.saveProvider(providerToSave)
    const refreshedProviders = await this.providerViewModel.loadProviders()
    this.providers = refreshedProviders

    for (let i = 0; i < refreshedProviders.length; i++) {
      const provider = refreshedProviders[i]
      if (this.currentProvider !== null && provider.id === this.currentProvider.id) {
        for (let j = 0; j < provider.models.length; j++) {
          const model = provider.models[j]
          if (model.id === this.currentModelId) {
            await this.applyModelSelection(provider, model)
            break
          }
        }
        break
      }
    }

    this.modelSheetActivePanel = 'selector'
    this.editingModel = null
    this.editingModelProvider = null
  }

  @Builder
  SharePreviewBuilder() {
    SharePreviewSheet({
      messages: this.shareMessages,
      currentModelId: this.currentModelId,
      onClose: () => {
        this.showSharePreview = false
      }
    })
  }

  private handleToolSelectionToggle(toolId: string, enabled: boolean): void {
    const nextToolIds = [...this.getActiveComposerSelectedToolIds()]
    const index = nextToolIds.indexOf(toolId)
    if (enabled && index < 0) {
      nextToolIds.push(toolId)
    }
    if (!enabled && index >= 0) {
      nextToolIds.splice(index, 1)
    }
    this.updateActiveComposerSelectedToolIds(nextToolIds).catch((error: Object) => {
      console.error('ChatPage', `Failed to update selected tools: ${JSON.stringify(error)}`)
      this.showError(pickLocalizedText('工具选择保存失败', 'Failed to save tool selection'))
    })
  }

  @Builder
  ToolPickerBuilder() {
    ChatToolPickerSheetContent({
      availableChatTools: this.availableChatTools,
      selectedToolIds: this.getActiveComposerSelectedToolIds(),
      isRefreshingMcpToolAvailability: this.isRefreshingMcpToolAvailability,
      themePrimary: this.themePrimary,
      themePrimaryLight: this.themePrimaryLight,
      isDarkMode: this.isDarkMode,
      onClose: (): void => {
        this.showToolPickerSheet = false
      },
      onRefresh: (): void => {
        this.refreshMcpToolAvailabilityInBackground(true)
      },
      onToggleTool: (toolId: string, enabled: boolean): void => {
        this.handleToolSelectionToggle(toolId, enabled)
      },
      onToggleMcpGroup: (toolIds: string[], enabled: boolean): void => {
        this.handleMcpToolGroupSelectionToggle(toolIds, enabled)
      }
    })
  }

  @Builder
  ToolExecutionApprovalSheetBuilder() {
    ChatToolExecutionApprovalSheetContent({
      sourceLabel: this.toolExecutionApprovalSourceLabel,
      toolName: this.toolExecutionApprovalName,
      argumentSummary: this.toolExecutionApprovalArgumentSummary,
      argumentEntries: this.toolExecutionApprovalArgumentEntries,
      argumentsPreview: this.toolExecutionApprovalArgumentsPreview,
      argumentsTruncated: this.toolExecutionApprovalArgumentsTruncated,
      showRawArguments: this.showRawToolExecutionApprovalArguments,
      themePrimary: this.themePrimary,
      isDarkMode: this.isDarkMode,
      onToggleShowRaw: (): void => {
        this.showRawToolExecutionApprovalArguments = !this.showRawToolExecutionApprovalArguments
      },
      onCancel: (): void => {
        this.resolveToolExecutionApproval(false)
      },
      onApprove: (): void => {
        this.resolveToolExecutionApproval(true)
      }
    })
  }

  // 处理附件选择
  private handleAttachmentsSelected(attachments: MessageAttachment[]): void {
    // 普通输入模式：添加到输入框的附件列表
    for (let i = 0; i < attachments.length; i++) {
      this.pendingAttachments.push(attachments[i])
    }
    // 触发数组更新，便于子组件监听并驱动发送按钮动效
    this.pendingAttachments = [...this.pendingAttachments]
    this.closeAttachmentPanel()
  }

  // 切换附件面板
  private toggleAttachmentPanel(): void {
    if (this.showAttachmentPicker) {
      this.closeAttachmentPanel()
    } else {
      this.openAttachmentPanel()
    }
  }

  private openAttachmentPanel(): void {
    this.safeStopInputSession()
    this.getUIContext().animateTo({
      duration: 260,
      curve: Curve.FastOutSlowIn
    }, () => {
      this.showAttachmentPicker = true
      this.attachmentPanelHeightVp = this.ATTACHMENT_PANEL_EXPANDED_HEIGHT
    })
  }

  private closeAttachmentPanel(): void {
    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.FastOutSlowIn
    }, () => {
      this.attachmentPanelHeightVp = 0
      this.showAttachmentPicker = false
    })
  }

  onAppInBackgroundChanged(): void {
    // 后台切换由任务调度器与后台守护服务处理，这里只保留日志
    console.info('ChatPage', `[onAppInBackgroundChanged] appInBackground=${this.appInBackground}`)
  }

  private calcIsAwaitingAiOutput(): boolean {
    if (!this.isSending) {
      return false
    }

    const total = this.messages.length
    if (total <= 0) {
      return true
    }

    // 从尾部向前找最近一条 AI 消息；若 AI 还没开始输出（内容为空），则认为处于等待态
    for (let i = total - 1; i >= 0; i--) {
      const msg = this.messages[i]
      if (msg.role === MessageRole.ASSISTANT) {
        return msg.isGenerating && msg.content.length === 0 && msg.reasoningContent.length === 0
      }
      if (msg.role === MessageRole.USER) {
        break
      }
    }

    return true
  }

  // 处理返回按钮点击
  private handleBack(): void {
    if (this.selectableTextMessageId !== '') {
      this.selectableTextMessageId = ''
      return
    }
    if (this.isMultiSelectMode) {
      this.handleExitMultiSelectMode()
      return
    }
    this.handleBackAsync().catch((error: Error): void => {
      console.error('ChatPage', `Failed to prepare chat before back: ${JSON.stringify(error)}`)
      this.navPathStack.pop()
    })
  }

  private async handleBackAsync(): Promise<void> {
    this.isPageVisible = false
    this.syncActiveSessionBinding()
    await this.prepareCurrentSessionForTransition()
    this.navPathStack.pop()
  }

  private safePushUrl(url: string, params?: Object): void {
    try {
      if (params !== undefined) {
        this.getUIContext().getRouter().pushUrl({ url: url, params: params })
      } else {
        this.getUIContext().getRouter().pushUrl({ url: url })
      }
    } catch (error) {
      console.error('ChatPage', `Router pushUrl failed: ${JSON.stringify(error)}`)
    }
  }

  private safeStopInputSession(): void {
    this.isInputFocused = false
    try {
      this.getUIContext().getFocusController().clearFocus()
    } catch (error) {
      console.error('ChatPage', `Clear focus failed: ${JSON.stringify(error)}`)
    }
    try {
      const inputMethodController = inputMethod.getController()
      inputMethodController.stopInputSession()
    } catch (error) {
      console.error('ChatPage', `Stop input session failed: ${JSON.stringify(error)}`)
    }
  }

  // px 转 vp
  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) *
      160
  }

  private getComposerBottomAvoidHeightVp(): number {
    if (this.showAttachmentPicker) {
      return 0
    }
    return this.px2vp(this.bottomAvoidHeight)
  }

  private getFloatingOverlayBottomAvoidHeightVp(): number {
    return this.px2vp(this.bottomAvoidHeight) + this.attachmentPanelHeightVp
  }

  private getMultiSelectToolbarBottomInsetVp(): number {
    return Math.max(this.px2vp(this.bottomAvoidHeight) + 10, 20)
  }

  @Builder
  private AttachmentPanelContentBuilder() {
    if (this.layoutSizeClass === LayoutSizeClass.EXPANDED) {
      Column() {
        AttachmentPicker({
          showDragBar: false,
          onSelectAttachments: (attachments: MessageAttachment[]): void => {
            this.handleAttachmentsSelected(attachments)
          },
          onClose: (): void => {
            this.closeAttachmentPanel()
          }
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: this.getChatContentMaxWidth() })
    } else {
      AttachmentPicker({
        showDragBar: false,
        onSelectAttachments: (attachments: MessageAttachment[]): void => {
          this.handleAttachmentsSelected(attachments)
        },
        onClose: (): void => {
          this.closeAttachmentPanel()
        }
      })
    }
  }

  private shouldShowScrollToTopButton(): boolean {
    if (this.hasDraftContent() || this.showImagePreview) {
      return false
    }
    return shouldShowScrollToTopButtonForChat(
      this.isMultiSelectMode,
      this.messages.length,
      this.isAtTop,
      this.currentScrollOffsetVp,
      this.windowHeightVp
    )
  }

  private shouldShowScrollToBottomLoadingButton(): boolean {
    return !this.hasDraftContent() && !this.showImagePreview && !this.isAtBottom && !this.isMultiSelectMode && this.isSending
  }

  private shouldShowStandardScrollToBottomButton(): boolean {
    return !this.hasDraftContent() && !this.showImagePreview && this.messages.length > 0 && !this.isAtBottom &&
      !this.isMultiSelectMode && !this.isSending
  }

  private handleMessageListDidScroll(scrollOffset: number, scrollState: ScrollState): void {
    if (this.showAttachmentPicker && (scrollState === ScrollState.Scroll || scrollState === ScrollState.Fling)) {
      this.closeAttachmentPanel()
    }
    const userScrolledAwayFromBottom = this.getScrollUiFlow().handleMessageListDidScroll(scrollOffset, scrollState)
    if (this.pendingInitialBottomAlignment && userScrolledAwayFromBottom) {
      this.cancelPendingInitialBottomAlignment()
    }
  }

  private handleMessageListReachStart(): void {
    this.getScrollUiFlow().handleReachStart()
  }

  private handleMessageListReachEnd(): void {
    this.getScrollUiFlow().handleReachEnd()
  }

  private hasDraftContent(): boolean {
    return this.inputText.trim() !== '' || this.pendingAttachments.length > 0
  }

  private readMeasuredAreaHeight(area: Area): number {
    const height = area.height
    if (typeof height !== 'number' || Number.isNaN(height)) {
      return 0
    }
    return height
  }

  private readCurrentScrollOffset(): number {
    try {
      const offset = this.scroller.currentOffset()
      if (typeof offset.yOffset !== 'number' || Number.isNaN(offset.yOffset) || offset.yOffset <= 0) {
        return 0
      }
      return offset.yOffset
    } catch (_error) {
      return 0
    }
  }

  private syncCurrentScrollOffsetFromScroller(): number {
    const offset = this.readCurrentScrollOffset()
    this.currentScrollOffsetVp = offset
    return offset
  }

  private syncIsAtBottomBoundaryFromScroller(): boolean {
    try {
      return this.scroller.isAtEnd()
    } catch (_error) {
      return false
    }
  }

  private alignListToBottomAfterLayout(): void {
    this.getScrollUiFlow().alignToBottomAfterLayout()
  }

  private syncBottomAlignmentAfterOverlayHeightChange(previousHeight: number, nextHeight: number, isActive: boolean): void {
    if (!isActive || !this.isAtBottom || Math.abs(previousHeight - nextHeight) < 0.5) {
      return
    }
    this.alignListToBottomAfterLayout()
  }

  private handleInputAreaHeightChange(area: Area): void {
    const nextHeight = this.readMeasuredAreaHeight(area)
    const previousHeight = this.inputAreaHeightVp
    this.inputAreaHeightVp = nextHeight
    this.syncBottomAlignmentAfterOverlayHeightChange(previousHeight, nextHeight,
      !this.isMultiSelectMode)
  }

  private handleMultiSelectToolbarHeightChange(area: Area): void {
    const nextHeight = this.readMeasuredAreaHeight(area)
    const previousHeight = this.multiSelectToolbarHeightVp
    this.multiSelectToolbarHeightVp = nextHeight
    this.syncBottomAlignmentAfterOverlayHeightChange(previousHeight, nextHeight, this.isMultiSelectMode)
  }

  private getActiveBottomOverlayHeight(): number {
    if (this.isMultiSelectMode) {
      return this.multiSelectToolbarHeightVp
    }
    return this.inputAreaHeightVp + this.attachmentPanelHeightVp
  }

  // 计算列表底部留白高度：优先跟随底部遮挡层的实测高度，避免和输入区布局漂移
  private getListBottomPadding(): number {
    const measuredHeight = this.getActiveBottomOverlayHeight()
    if (measuredHeight > 0) {
      return measuredHeight
    }
    return getListBottomPaddingForChat(this.pendingAttachments.length, this.isEditingMessage,
      this.px2vp(this.bottomAvoidHeight))
  }

  // 获取预览气泡的时间文本
  private getPreviewTimeText(): string {
    return getPreviewTimeTextForChat(new Date())
  }

  // 输入内容变化时，自动滚动到底部显示预览气泡
  @Monitor('inputText')
  onDraftContentChanged(): void {
    this.getScrollUiFlow().onDraftContentChanged()
  }

  private handleComposerContentChanged(): void {
    this.scheduleDraftAutosave()
  }

  private clearDraftAutosaveTimer(): void {
    if (this.draftAutosaveTimerId < 0) {
      return
    }
    clearTimeout(this.draftAutosaveTimerId)
    this.draftAutosaveTimerId = -1
  }

  private scheduleDraftAutosave(): void {
    if (this.isLoading || this.isEditingMessage) {
      return
    }
    this.clearDraftAutosaveTimer()
    this.draftAutosaveTimerId = setTimeout(() => {
      this.draftAutosaveTimerId = -1
      this.persistCurrentDraftState(this.inputText, this.pendingAttachments).catch((error: Error): void => {
        console.error('ChatPage', `Failed to autosave draft: ${JSON.stringify(error)}`)
      })
    }, this.draftAutosaveDelayMs)
  }

  private async flushDraftAutosave(immediate: boolean): Promise<void> {
    this.clearDraftAutosaveTimer()
    if (!immediate || this.isLoading || this.isEditingMessage) {
      return
    }
    await this.persistCurrentDraftState(this.inputText, this.pendingAttachments)
  }

  private async persistCurrentDraftState(content: string, attachments: MessageAttachment[]): Promise<void> {
    if (this.isLoading || this.isEditingMessage) {
      return
    }
    const session = await this.chatViewModel.saveSessionDraft(content, attachments)
    if (session === null) {
      return
    }
    this.sessionId = session.id
    this.sessionTitle = session.title
    this.syncActiveSessionBinding()
  }

  private async prepareCurrentSessionForTransition(): Promise<void> {
    try {
      await this.flushDraftAutosave(true)
    } catch (error) {
      console.error('ChatPage', `Failed to flush draft before session transition: ${JSON.stringify(error)}`)
    }
    if (!this.shouldDeleteEmptySessionOnDisappear()) {
      return
    }
    const deletingSessionId = this.sessionId
    await this.chatViewModel.deleteSession(deletingSessionId)
    console.info('ChatPage', '删除空会话: ' + deletingSessionId)
    if (this.sessionId === deletingSessionId) {
      this.sessionId = ''
      this.sessionTitle = ''
      this.isNewEmptySession = false
      this.syncActiveSessionBinding()
    }
  }

  private shouldDeleteEmptySessionOnDisappear(): boolean {
    return this.isNewEmptySession &&
      !this.isSending &&
      this.currentTaskId === '' &&
      this.messages.length === 0 &&
      !this.hasDraftContent() &&
      this.sessionId !== ''
  }

  // 滚动到底部（带动画过渡）
  private scrollToBottomWithAnimation(): void {
    this.getScrollUiFlow().scrollToBottomWithAnimation()
  }

  // 滚动到顶部
  private scrollToTopWithAnimation(): void {
    this.getScrollUiFlow().scrollToTopWithAnimation()
  }

  private async handleScrollToTopRequest(): Promise<void> {
    this.scrollToTopWithAnimation()
  }

  // 同步包装方法，用于 onSend 回调
  handleSend(): void {
    if (this.showAttachmentPicker) {
      this.closeAttachmentPanel()
    }
    this.sendMessage()
  }

  // 处理停止生成
  handleStop(): void {
    this.getStopFlow().stopCurrentTask()
  }

  // 处理模型选择
  handleModelSelect(providerId: string, modelId: string, modelName: string): void {
    const selection = this.findProviderModelSelection(providerId, modelId)
    if (selection === null) {
      console.warn('ChatPage', `[handleModelSelect] Model not found: ${providerId}/${modelId}`)
      return
    }
    this.applyModelSelection(selection.provider, selection.model, modelName, true, true).catch((error: Object) => {
      console.error('ChatPage', `[handleModelSelect] Failed to persist model selection: ${JSON.stringify(error)}`)
    })

    // 关闭模型选择器
    this.isModelSelectorVisible = false

    this.showChatSnack($r('app.string.model_switched'), 2000, SnackBarTone.SUCCESS)
  }

  async sendMessage(): Promise<void> {
    if (this.isSendDispatching || this.isSending) {
      return
    }
    this.isSendDispatching = true
    try {
      const prepareResult = this.getSendFlow().prepareSendRequest(
        this.inputText,
        this.pendingAttachments.length,
        this.isSending,
        this.currentProvider,
        this.currentModelId,
        this.chatTaskOrchestrator.canStartNewTask()
      )
      if (!prepareResult.shouldSend || prepareResult.currentProvider === null) {
        return
      }
      const messageContent = prepareResult.messageContent
      const currentProvider = prepareResult.currentProvider
      const effectiveApiKey = prepareResult.effectiveApiKey

      await this.syncToolAvailabilityFromPreferences()
      const requestedToolIds = [
        ...this.selectedToolIds,
        ...this.forcedToolIdsOnce
      ]
      const enabledMcpServerIds = await this.loadEnabledMcpServerIds()
      if (this.collectPendingEnabledMcpToolIds(requestedToolIds, enabledMcpServerIds).length > 0) {
        this.refreshMcpToolAvailabilityInBackground(false)
      }

      const attachmentsToSend = [...this.pendingAttachments]
      const searchEnabled = this.webSearchAvailable && this.webSearchConversationEnabled
      const selectedToolIds = [...this.selectedToolIds]
      const forcedToolIds = [...this.forcedToolIdsOnce]
      await this.getSendFlow().executeSend(
        messageContent,
        currentProvider,
        effectiveApiKey,
        attachmentsToSend,
        searchEnabled,
        selectedToolIds,
        forcedToolIds,
        this.currentModelId
      )
      this.forcedToolIdsOnce = []
    } catch (error) {
      console.error('ChatPage', `sendMessage failed: ${JSON.stringify(error)}`)
      this.forcedToolIdsOnce = []
      this.showError($r('app.string.action_failed_retry'))
    } finally {
      this.isSendDispatching = false
    }
  }

  // 处理重新生成（支持非最后一条消息，支持用户消息和 AI 消息）
  async handleRegenerate(message: ChatMessage): Promise<void> {
    if (this.isSending) {
      return
    }
    const userMsgIndex = resolveUserMessageIndexForRegenerate(this.messages, message)
    if (userMsgIndex < 0) {
      return
    }
    const userMsg = this.messages[userMsgIndex]
    const savedContent = userMsg.content
    const savedAttachments = userMsg.attachments.slice()
    const isFirstRound = userMsgIndex === 0
    const messageIdsToDelete = collectTailMessageIds(this.messages, userMsgIndex)
    await this.chatViewModel.deleteMessagesFromIndex(messageIdsToDelete)
    this.messages.splice(userMsgIndex)
    this.markMessageListChanged()
    if (isFirstRound) {
      this.titleGenerateFailed = false
    }
    this.inputText = savedContent
    this.pendingAttachments = savedAttachments
    this.handleSend()
  }

  showError(message: string | Resource): void {
    this.showChatSnack(message, 3000, SnackBarTone.ERROR)
  }

  private resetToolExecutionApprovalState(): void {
    this.toolExecutionApprovalSourceLabel = ''
    this.toolExecutionApprovalName = ''
    this.toolExecutionApprovalArgumentSummary = this.getNoToolArgumentsText()
    this.toolExecutionApprovalArgumentEntries = []
    this.toolExecutionApprovalArgumentsPreview = '{}'
    this.toolExecutionApprovalArgumentsTruncated = false
    this.showRawToolExecutionApprovalArguments = false
  }

  private resolveToolExecutionApproval(approved: boolean): void {
    const resolver = this.pendingToolExecutionApprovalResolver
    this.pendingToolExecutionApprovalResolver = null
    this.showToolExecutionApprovalSheet = false
    this.resetToolExecutionApprovalState()
    if (resolver !== null) {
      resolver(approved)
    }
  }

  private handleToolExecutionApprovalSheetDisappear(): void {
    this.showToolExecutionApprovalSheet = false
    const resolver = this.pendingToolExecutionApprovalResolver
    this.pendingToolExecutionApprovalResolver = null
    this.resetToolExecutionApprovalState()
    if (resolver !== null) {
      resolver(false)
    }
  }

  private async requestToolExecutionApproval(
    toolName: string,
    sourceLabel: string,
    argumentsJson: string
  ): Promise<boolean> {
    const preview = buildToolArgumentsPreview(argumentsJson, 4, 800)
    return await new Promise<boolean>((resolve) => {
      if (this.pendingToolExecutionApprovalResolver !== null) {
        const previousResolver = this.pendingToolExecutionApprovalResolver
        this.pendingToolExecutionApprovalResolver = null
        previousResolver(false)
      }
      this.toolExecutionApprovalSourceLabel = sourceLabel.trim()
      this.toolExecutionApprovalName = toolName.trim() !== ''
        ? toolName.trim()
        : pickLocalizedText('未知工具', 'Unknown tool')
      this.toolExecutionApprovalArgumentSummary = preview.summary
      this.toolExecutionApprovalArgumentEntries = [...preview.entries]
      this.toolExecutionApprovalArgumentsPreview = preview.rawPreview
      this.toolExecutionApprovalArgumentsTruncated = preview.rawTruncated
      this.showRawToolExecutionApprovalArguments = false
      this.pendingToolExecutionApprovalResolver = resolve
      this.showToolExecutionApprovalSheet = true
    })
  }

  // 处理删除消息
  async handleDeleteMessage(message: ChatMessage): Promise<void> {
    const index = findMessageIndexById(this.messages, message.id)
    if (index < 0) {
      return
    }
    this.messages.splice(index, 1)
    this.markMessageListChanged()
    await this.chatViewModel.deleteMessage(message.id)
    this.showChatSnack($r('app.string.message_deleted'), 2000, SnackBarTone.SUCCESS)
  }

  // 处理翻译请求
  handleTranslate(content: string, targetLang: string, callback: (result: string, errorMessage: string) => void): void {
    this.aiTaskService.translateText(content, targetLang).then((result) => {
      if (result.success) {
        callback(result.content, '')
      } else {
        callback('', result.errorMessage)
      }
    }).catch((error: Error) => {
      callback('', `${pickLocalizedText('翻译失败：', 'Translation failed: ')}${error.message}`)
    })
  }

  // 处理TTS朗读
  private handleTTS(messageId: string, content: string): void {
    // 如果正在朗读其他消息，先停止
    if (this.speakingMessageId !== '') {
      this.ttsService.stop()
    }

    this.setSpeakingMessageId(messageId)

    this.ttsService.speak(content, {
      onStart: () => {
        // 朗读开始
      },
      onComplete: () => {
        // 朗读完成
        this.setSpeakingMessageId('')
      },
      onError: (error: string) => {
        this.setSpeakingMessageId('')
        this.showChatSnack(error, 3000, SnackBarTone.ERROR)
      }
    })
  }

  // 处理停止TTS朗读
  private handleTTSStop(): void {
    this.ttsService.stop()
    this.setSpeakingMessageId('')
  }

  private setSpeakingMessageId(messageId: string): void {
    setAppUiStateValue(AppStorageKeys.SPEAKING_MESSAGE_ID, messageId)
  }

  // 处理新建对话
  private async handleNewChat(): Promise<void> {
    await this.prepareCurrentSessionForTransition()
    this.clearDraftAutosaveTimer()
    // 创建新会话
    const assistant = await ServiceRegistry.assistant().getCurrentAssistantForNewChat()
    const session = await this.chatViewModel.createNewSession(
      '',
      assistant.id,
      assistant.defaultModelId,
      assistant.defaultProviderId
    )
    this.isNewChatTransition = true
    this.routeParams = {} as ChatPageRouteParams
    this.inputText = ''
    this.pendingAttachments = []
    // 清空当前消息
    this.clearMessages()
    // 更新会话ID和标题
    this.sessionId = session.id
    this.sessionTitle = session.title
    this.applyAssistantSnapshot(assistant.id, assistant.avatarSymbol, assistant.color)
    // 重置标题状态
    this.isTitleGenerating = false
    this.titleGenerateFailed = false
    // 标记为新建的空会话（返回时需要删除）
    this.isNewEmptySession = true
    this.syncActiveSessionBinding()
    await this.validateAndSetCurrentModel()

    this.showChatSnack($r('app.string.chat_created'), 2000, SnackBarTone.SUCCESS)
  }

  // 处理重新生成标题
  private async handleRegenerateTitle(): Promise<void> {
    if (this.messages.length === 0) {
      this.showChatSnack($r('app.string.chat_empty'), 2000, SnackBarTone.ERROR)
      return
    }
    this.titleGenerateFailed = false
    this.showChatSnack($r('app.string.generating_title'), 2000)
    this.chatViewModel.regenerateTitle()
  }

  // 处理删除对话
  private handleDeleteChat(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.delete_chat'),
      message: $r('app.string.delete_session_confirm'),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
          // 取消
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: $r('app.color.status_error'),
        action: async () => {
          await this.chatViewModel.deleteSession(this.sessionId)
          this.navPathStack.pop()
        }
      }
    })
  }

  // 处理保存编辑的标题
  private async handleSaveTitle(newTitle: string): Promise<void> {
    if (newTitle.trim() === '') {
      return
    }
    await this.chatViewModel.updateSessionTitle(newTitle.trim())
    this.sessionTitle = newTitle.trim()
    this.showChatSnack($r('app.string.title_updated'), 2000, SnackBarTone.SUCCESS)
  }

  // ========== 多选模式相关方法 ==========

  // 点击防抖标志
  private isProcessingMessageClick: boolean = false

  // 编辑消息：进入内联编辑模式
  private async handleEditMessage(message: ChatMessage): Promise<void> {
    this.editingOriginalContent = message.content
    this.editingOriginalAttachments = [...message.attachments]
    this.editingMessageId = message.id
    this.editingMessageIsUser = message.role === MessageRole.USER
    this.inputText = message.content
    this.pendingAttachments = [...message.attachments]
    const messageIndex = findMessageIndexById(this.messages, message.id)
    const toolContext = messageIndex >= 0 ?
      this.resolveEditedMessageToolContext(messageIndex) :
      new EditedMessageToolContext()
    this.editingWebSearchEnabled = toolContext.webSearchEnabled
    this.editingSelectedToolIds = [...toolContext.selectedToolIds]
    this.editingReasoningLevel = this.reasoningLevel
    this.isEditingMessage = true
    this.getScrollUiFlow().setInputBarVisible(true)
    this.autoFocusInput = true
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve()
      }, 100)
    })
    if (messageIndex >= 0) {
      this.scroller.scrollToIndex(
        toListScrollIndexForMessage(messageIndex),
        true,
        ScrollAlign.CENTER
      )
    }
  }

  // ========== 内联编辑模式相关方法 ==========

  // 取消编辑
  private handleCancelEdit(): void {
    // 恢复原始内容
    this.inputText = ''
    this.pendingAttachments = []

    // 退出编辑模式
    this.isEditingMessage = false
    this.editingMessageId = ''
    this.editingOriginalContent = ''
    this.editingOriginalAttachments = []
    this.editingWebSearchEnabled = false
    this.editingSelectedToolIds = []
    this.editingReasoningLevel = ReasoningLevel.OFF
  }

  // 内联编辑模式：保存并发送
  private async handleSaveAndSendInline(): Promise<void> {
    await this.getInlineEditFlow().saveAndSendInline(
      this.editingMessageId,
      this.inputText,
      this.pendingAttachments,
      this.editingWebSearchEnabled,
      this.editingSelectedToolIds,
      this.editingReasoningLevel
    )
  }

  // 分享单条消息：进入多选模式并触发分享
  private handleShareSingleMessage(message: ChatMessage): void {
    this.selectableTextMessageId = ''
    this.getSelectionFlow().enterModeWithMessage(message.id)
    this.handleShareSelectedMessages()
  }

  // 进入多选模式
  private handleEnterMultiSelectMode(messageId: string): void {
    this.selectableTextMessageId = ''
    this.getSelectionFlow().enterModeWithMessage(messageId)
  }

  // 退出多选模式
  private handleExitMultiSelectMode(): void {
    this.getSelectionFlow().exitMode()
  }

  // 切换消息选中状态（带防抖）
  private handleToggleMessageSelection(messageId: string): void {
    // 防止重复点击
    if (this.isProcessingMessageClick) {
      return
    }
    this.isProcessingMessageClick = true

    this.selectedMessageIds = this.getSelectionFlow().toggleSelection(this.selectedMessageIds, messageId)

    // 100ms 后重置标志
    setTimeout(() => {
      this.isProcessingMessageClick = false
    }, 100)
  }

  // 全选/取消全选
  private handleSelectAllMessages(): void {
    this.selectedMessageIds = this.getSelectionFlow().toggleSelectAll(this.selectedMessageIds)
  }

  // 删除选中的消息
  private async handleDeleteSelectedMessages(): Promise<void> {
    if (this.selectedMessageIds.length === 0) {
      return
    }

    this.getUIContext().showAlertDialog({
      title: $r('app.string.delete_messages'),
      message: $r('app.string.delete_selected_messages_confirm'),
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
          await this.getSelectionFlow().deleteSelectedMessages(this.selectedMessageIds)
        }
      }
    })
  }

  // 分享选中的消息
  private handleShareSelectedMessages(): void {
    this.getSelectionFlow().openSharePreview(this.selectedMessageIds)
  }
}

@Builder
export function ChatPageBuilder(name: string, param: Object) {
  ChatPage({
    routeParamsSeed: param as ChatPageRouteParams
  })
}
