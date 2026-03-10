import { KeyboardAvoidMode } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  ChatMessage,
  MessageRole,
  ModelProvider,
  ModelInfo,
  MessageAttachment,
  ReasoningLevel,
  ModelRole
} from '../models/ChatModels'
import { AttachmentPicker } from '../components/AttachmentPicker'
import { ImagePreview } from '../components/ImagePreview'
import { ChatNavigationBar } from '../components/ChatNavigationBar'
import { ScrollToBottomButton } from '../components/ScrollToBottomButton'
import { ScrollToBottomLoadingButton } from '../components/ScrollToBottomLoadingButton'
import { MultiSelectToolbar } from '../components/MultiSelectToolbar'
import { SharePreviewSheet } from '../components/SharePreviewSheet'
import { ChatViewModel, TitleGenerationCallbacks } from '../viewmodels/ChatViewModel'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { AppStateManager } from '../viewmodels/AppStateManager'
import { AITaskService } from '../services/AITaskService'
import { WebSearchService } from '../services/WebSearchService'
import { DefaultModelService } from '../services/DefaultModelService'
import { PreferenceKeys, PreferencesService } from '../services/PreferencesService'
import { TTSService } from '../services/TTSService'
import { ToolRegistry } from '../services/ToolRegistry'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { registerBuiltinTools } from '../config/BuiltinTools'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { inputMethod } from '@kit.IMEKit'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { createMessageDataSource, MessageDataSource } from '../datasource/MessageDataSource'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { ChatModelSelectorSheetContent } from '../components/chat/ChatModelSelectorSheetContent'
import { ChatInputAreaSection } from '../components/chat/ChatInputAreaSection'
import { ChatMessageListSection } from '../components/chat/ChatMessageListSection'
import {
  getListBottomPaddingForChat,
  getPreviewTimeTextForChat,
  shouldShowScrollToTopButtonForChat
} from './chat/ChatPageUiHelper'
import { parseToolIdsFromRouteRaw } from './chat/ChatToolIdHelper'
import { ChatManualSearchFlow, ChatManualSearchFlowDependencies } from './chat/ChatManualSearchFlow'
import { ChatSendFlow, ChatSendFlowDependencies, ChatSendDispatchResult } from './chat/ChatSendFlow'
import { ChatStopFlow, ChatStopFlowDependencies } from './chat/ChatStopFlow'
import { ChatInlineEditFlow, ChatInlineEditFlowDependencies } from './chat/ChatInlineEditFlow'
import { ChatSelectionFlow, ChatSelectionFlowDependencies } from './chat/ChatSelectionFlow'
import { ChatPageLoadFlow, ChatPageLoadFlowDependencies, ChatPageLoadResult } from './chat/ChatPageLoadFlow'
import { ChatTaskAlertFlow, ChatTaskAlertFlowDependencies } from './chat/ChatTaskAlertFlow'
import { ChatScrollUiFlow, ChatScrollUiFlowDependencies } from './chat/ChatScrollUiFlow'
import {
  collectTailMessageIds,
  findMessageIndexById,
  resolveUserMessageIndexForRegenerate,
  toListScrollIndexForMessage
} from './chat/ChatMessageActionHelper'
import { ChatPageRouteParams } from './chat/ChatPageRouteTypes'
import { getChatContentMaxWidth, LayoutSizeClass } from '../config/LayoutProfile'

const DOMAIN = 0x0003
const TAG = 'ChatPage'

@Component
export struct ChatPage {
  navPathStack: NavPathStack = new NavPathStack()
  routeParams: ChatPageRouteParams | null = null
  // 消息数据源（替代 @State messages）
  private messageDataSource: MessageDataSource = createMessageDataSource()
  // 保留消息数组引用用于兼容性（例如计算消息数量）
  @State messages: ChatMessage[] = []
  @State @Watch('onDraftContentChanged') inputText: string = ''
  @State currentModel: string = ''
  @State currentModelId: string = ''
  @State isModelSelectorVisible: boolean = false
  @State modelSheetActivePanel: string = 'selector'
  @State editingModel: ModelInfo | null = null
  @State editingModelProvider: ModelProvider | null = null
  @State isLoading: boolean = false
  @State isSending: boolean = false
  // 应用是否退到后台（用于处理生成中返回桌面/关闭应用）
  @StorageProp('appInBackground') @Watch('onAppInBackgroundChanged') appInBackground: boolean = false
  @StorageProp('task_unread_by_session') @Watch('onTaskUnreadBySessionChanged') taskUnreadBySessionJson: string = '{}'
  @StorageProp('in_app_task_alert_payload') @Watch('onInAppTaskAlertPayloadChanged') inAppTaskAlertPayload: string = ''
  @StorageProp('openSessionPayload') @Watch('onOpenSessionPayloadChanged') openSessionPayload: string = ''
  @State providers: ModelProvider[] = []
  // 附件相关状态
  @State pendingAttachments: MessageAttachment[] = []
  @State showAttachmentPicker: boolean = false
  // 是否在列表底部
  @State isAtBottom: boolean = false
  // 是否在列表顶部
  @State isAtTop: boolean = false
  // 输入框显示状态（true=显示，false=隐藏）
  @State isInputBarVisible: boolean = true
  // 输入框是否处于焦点状态（用于控制预览气泡显示）
  @State isInputFocused: boolean = false
  // 计算滚动偏移
  private lastScrollOffset: number = 0
  private readonly inputBarShowThreshold: number = 6
  private readonly inputBarHideThreshold: number = 18
  // 会话标题相关状态
  @State sessionTitle: string = '新对话'
  @State isTitleGenerating: boolean = false
  @State titleGenerateFailed: boolean = false
  // 更多菜单显示状态
  @State showMoreMenu: boolean = false
  // 标题内联编辑状态（已迁移到 ChatNavigationBar，保留用于回调）
  // 图片预览状态
  @State showImagePreview: boolean = false
  @State previewImages: Array<string> = []
  @State previewImageIndex: number = 0
  // 当前正在朗读的消息ID
  @StorageLink('speakingMessageId') speakingMessageId: string = ''
  // 是否为通过"新建对话"创建的空会话（返回时需要删除）
  private isNewEmptySession: boolean = false
  // 搜索取消标志（用于取消正在进行的联网查询）
  private isSearchCancelled: boolean = false
  // 联网查询全局可用状态（工具中心控制）
  @State webSearchAvailable: boolean = false
  // 联网查询本会话开关状态（聊天页控制）
  @State webSearchEnabled: boolean = false
  // 天气查询状态
  @State weatherQueryEnabled: boolean = false
  // 推理级别状态
  @State reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  // 最近截图检测状态（由 ChatInputBar 回调设置，ScreenshotBanner 独立渲染）
  @State hasRecentScreenshot: boolean = false
  // 是否为新建对话（用于加载和自动发送策略）
  @State isNewChatTransition: boolean = false
  // 是否自动聚焦输入框
  @State autoFocusInput: boolean = false
  // 避让区域高度
  @StorageProp('topAvoidHeight') topAvoidHeight: number = 0
  @StorageProp('bottomAvoidHeight') bottomAvoidHeight: number = 0
  @StorageProp('layout_size_class') layoutSizeClass: string = LayoutSizeClass.COMPACT
  @StorageProp('window_width_vp') windowWidthVp: number = 0
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_user_bubble') themeUserBubble: string = '#0A59F7'
  @StorageProp('theme_user_bubble_text') themeUserBubbleText: string = '#FFFFFF'
  // 多选模式状态
  @State isMultiSelectMode: boolean = false
  @State selectedMessageIds: Array<string> = []
  // 分享预览弹窗状态
  @State showSharePreview: boolean = false
  @State shareMessages: ChatMessage[] = []
  // 编辑消息相关状态（内联编辑模式）
  @State isEditingMessage: boolean = false // 是否处于消息编辑模式
  @State editingMessageId: string = '' // 正在编辑的消息ID
  @State editingOriginalContent: string = '' // 原始内容（用于取消编辑）
  @State editingOriginalAttachments: MessageAttachment[] = [] // 原始附件
  @State editingMessageIsUser: boolean = true // 是否为用户消息（决定是否显示"保存并发送"）
  @State editingWebSearchEnabled: boolean = false
  @State editingReasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  @State otherSessionUnreadCount: number = 0
  private scroller: Scroller = new Scroller()
  private chatViewModel: ChatViewModel = ServiceRegistry.chat()
  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()
  private appStateManager: AppStateManager = ServiceRegistry.appState()
  private webSearchService: WebSearchService = ServiceRegistry.webSearch()
  private defaultModelService: DefaultModelService = ServiceRegistry.defaultModel()
  private preferencesService: PreferencesService = ServiceRegistry.preferences()
  private aiTaskService: AITaskService = ServiceRegistry.aiTask()
  private toolRegistry: ToolRegistry = ServiceRegistry.toolRegistry()
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
  private lastHandledAlertTimestamp: number = 0
  private isPageVisible: boolean = false
  private streamSyncTimerId: number = -1
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

  private showChatSnack(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  aboutToAppear(): void {
    // 设置键盘避让模式
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)

    // 注册内置工具
    registerBuiltinTools()

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
      this.initWithParams(this.routeParams)
    }
  }

  // 从路由参数初始化页面（aboutToAppear 或 onReady 触发）
  private initWithParams(params: ChatPageRouteParams | null): void {
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

  // 修复页面恢复时可能的不一致状态
  private fixInconsistentState(): void {
    // 如果 isSending 为 true 但没有活跃请求，重置状态
    if (this.isSending && !this.chatViewModel.hasActiveRequest()) {
      this.isSending = false
      console.info('ChatPage', '[fixInconsistentState] 重置 isSending 状态')
    }

    // 检查最后一条消息的 isGenerating 和 isSearching 状态
    if (this.messageDataSource.totalCount() > 0) {
      const lastMessage = this.messageDataSource.getData(this.messageDataSource.totalCount() - 1)
      if (lastMessage.role === MessageRole.ASSISTANT) {
        let needUpdate = false
        // 如果没有活跃请求，重置生成状态
        if (lastMessage.isGenerating && !this.chatViewModel.hasActiveRequest()) {
          lastMessage.isGenerating = false
          needUpdate = true
          console.info('ChatPage', '[fixInconsistentState] 重置最后一条消息的 isGenerating 状态')
        }
        // 如果没有活跃请求，重置搜索状态
        if (lastMessage.isSearching && !this.chatViewModel.hasActiveRequest()) {
          lastMessage.isSearching = false
          needUpdate = true
          console.info('ChatPage', '[fixInconsistentState] 重置最后一条消息的 isSearching 状态')
        }
        if (needUpdate) {
          this.messageDataSource.notifyLastMessageChanged()
        }
      }
    }
  }

  aboutToDisappear(): void {
    this.isPageVisible = false
    // 释放TTS资源
    this.ttsService.destroy()
    this.clearStreamSyncTimer()
    this.flushDraftAutosave(true).catch((error: Error): void => {
      console.error('ChatPage', `Failed to flush draft on disappear: ${JSON.stringify(error)}`)
    })
    AppStorage.setOrCreate(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, '')

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

    // 新建对话时不显示加载动画，让用户无感
    // 只有打开现有对话时才显示加载动画
    if (!this.isNewChatTransition) {
      this.isLoading = true
    }

    const loadResult = await this.getLoadFlow().loadPageData(this.routeParams, this.sessionTitle)

    this.webSearchAvailable = loadResult.webSearchEnabled
    this.webSearchEnabled = this.webSearchAvailable && loadResult.webSearchConversationEnabled
    this.weatherQueryEnabled = loadResult.weatherQueryEnabled
    console.info(
      'ChatPage',
      `[loadData] 联网可用=${this.webSearchAvailable}, 联网会话开关=${this.webSearchEnabled}, 天气查询=${this.weatherQueryEnabled}`
    )

    this.applyLoadedProviders(loadResult.providers)
    this.applyLoadedSessionData(loadResult)

    this.isLoading = false

    const elapsed = Date.now() - startTime
    hilog.info(DOMAIN, TAG, '✅ 聊天页面数据加载完成 (耗时: %{public}dms)', elapsed)

    this.triggerPostLoadActions()
    this.activateCurrentSessionRuntimeState()
  }

  private applyLoadedProviders(providers: ModelProvider[]): void {
    this.providers = providers
    console.info('ChatPage', `[loadData] Loaded ${this.providers.length} providers`)

    if (this.providers.length === 0) {
      this.currentModel = ''
      this.currentModelId = ''
      this.currentProvider = null
      return
    }
    this.validateAndSetCurrentModel()
  }

  private applyLoadedSessionData(loadResult: ChatPageLoadResult): void {
    this.pendingInitialPrompt = loadResult.pendingInitialPrompt
    this.pendingInitialToolIds = loadResult.pendingInitialToolIds
    this.initialPromptAutoSent = loadResult.initialPromptAutoSent
    this.sessionId = loadResult.sessionId
    this.sessionTitle = loadResult.sessionTitle
    this.inputText = loadResult.draftText
    this.pendingAttachments = [...loadResult.draftAttachments]
    this.isNewChatTransition = loadResult.isNewChatTransition
    this.isNewEmptySession = loadResult.isNewEmptySession

    if (!this.isNewChatTransition) {
      this.messageDataSource.setAllMessages(loadResult.messages)
      this.messages = [...loadResult.messages]
      hilog.info(DOMAIN, TAG, '📨 加载会话消息: %{public}d 条', this.messages.length)
      return
    }

    this.messageDataSource.clear()
    this.messages = []
  }

  private triggerPostLoadActions(): void {
    if (this.isNewChatTransition) {
      setTimeout(() => {
        this.autoFocusInput = true
      }, 50)
    }

    if (this.isNewChatTransition && this.pendingInitialPrompt !== '' && !this.initialPromptAutoSent) {
      setTimeout(() => {
        this.autoSendInitialPrompt()
      }, 120)
    }
  }

  onTaskUnreadBySessionChanged(): void {
    this.getTaskAlertFlow().refreshOtherSessionUnreadCount()
  }

  onInAppTaskAlertPayloadChanged(): void {
    this.getTaskAlertFlow().handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
  }

  onOpenSessionPayloadChanged(): void {
    this.getTaskAlertFlow().handleOpenSessionPayload(this.openSessionPayload)
  }

  private handlePageShown(): void {
    this.isPageVisible = true
    if (this.isLoading || this.sessionId === '') {
      return
    }
    this.refreshToolAvailabilityOnShown()
    this.syncSendingStateFromRuntime()
    this.fixInconsistentState()
    this.refreshProviders()
    AppStorage.setOrCreate(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, this.sessionId)
    this.chatTaskOrchestrator.markSessionRead(this.sessionId)
    this.getTaskAlertFlow().refreshOtherSessionUnreadCount()
    this.updateStreamSyncTimer()
  }

  private activateCurrentSessionRuntimeState(): void {
    AppStorage.setOrCreate(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, this.sessionId)
    this.chatTaskOrchestrator.markSessionRead(this.sessionId)
    this.getTaskAlertFlow().refreshOtherSessionUnreadCount()
    this.syncSendingStateFromRuntime()
    this.getTaskAlertFlow().handleOpenSessionPayload(this.openSessionPayload)
    this.getTaskAlertFlow().handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
    this.updateStreamSyncTimer()
  }

  private refreshToolAvailabilityOnShown(): void {
    this.refreshToolAvailabilityFromPreferences(true).catch((error: Object) => {
      console.warn('ChatPage', `[refreshToolAvailabilityOnShown] Failed: ${JSON.stringify(error)}`)
    })
  }

  private async refreshToolAvailabilityFromPreferences(syncConversationSwitch: boolean): Promise<void> {
    const webSearchAvailable = await this.preferencesService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    const weatherQueryEnabled = await this.preferencesService.getBoolean(
      PreferenceKeys.WEATHER_QUERY_ENABLED,
      webSearchAvailable
    )
    let webSearchConversationEnabled = this.webSearchEnabled
    if (syncConversationSwitch) {
      webSearchConversationEnabled = await this.preferencesService.getBoolean(
        PreferenceKeys.SEARCH_CONVERSATION_ENABLED,
        webSearchAvailable
      )
    }
    this.webSearchAvailable = webSearchAvailable
    if (!this.webSearchAvailable) {
      this.webSearchEnabled = false
    } else {
      this.webSearchEnabled = webSearchConversationEnabled
    }
    this.weatherQueryEnabled = weatherQueryEnabled
  }

  private syncSendingStateFromRuntime(): void {
    if (this.sessionId === '') {
      this.isSending = false
      return
    }
    this.isSending = this.chatViewModel.hasActiveRequestForSession(this.sessionId)
  }

  private hasStreamingAssistantMessage(): boolean {
    const total = this.messageDataSource.totalCount()
    if (total <= 0) {
      return false
    }
    const lastMessage = this.messageDataSource.getData(total - 1)
    if (lastMessage.role !== MessageRole.ASSISTANT) {
      return false
    }
    return lastMessage.isGenerating || lastMessage.isSearching
  }

  private notifyStreamingMessageChanged(forceNotify: boolean): void {
    const total = this.messageDataSource.totalCount()
    if (total <= 0) {
      return
    }
    const lastMessage = this.messageDataSource.getData(total - 1)
    if (lastMessage.role !== MessageRole.ASSISTANT) {
      return
    }
    if (forceNotify || lastMessage.isGenerating || lastMessage.isSearching) {
      this.messageDataSource.notifyLastMessageChanged()
      this.syncMessagesFromDataSource()
    }
  }

  private updateStreamSyncTimer(): void {
    if (!this.chatViewModel.hasActiveRequest() || !this.hasStreamingAssistantMessage()) {
      this.clearStreamSyncTimer()
      return
    }
    if (this.streamSyncTimerId !== -1) {
      return
    }
    this.streamSyncTimerId = setInterval(() => {
      if (!this.chatViewModel.hasActiveRequest()) {
        this.notifyStreamingMessageChanged(true)
        this.clearStreamSyncTimer()
        return
      }
      this.notifyStreamingMessageChanged(false)
    }, 180)
  }

  private clearStreamSyncTimer(): void {
    if (this.streamSyncTimerId !== -1) {
      clearInterval(this.streamSyncTimerId)
      this.streamSyncTimerId = -1
    }
  }

  private parseToolIdsFromRoute(raw: string): string[] {
    return parseToolIdsFromRouteRaw(raw)
  }

  private getSendFlow(): ChatSendFlow {
    if (this.sendFlow !== null) {
      return this.sendFlow
    }
    const deps = new ChatSendFlowDependencies(
      this.chatViewModel,
      this.messageDataSource,
      this.chatTaskOrchestrator,
      this.toolRegistry,
      (): string => this.sessionId,
      (): string => this.sessionTitle,
      (): string => this.currentTaskId,
      (): string => this.currentModelId,
      (): string => this.currentModel,
      (): ChatMessage[] => this.messages,
      (): ReasoningLevel => this.reasoningLevel,
      (): void => {
        this.clearDraftAutosaveTimer()
        this.inputText = ''
        this.pendingAttachments = []
      },
      (): void => {
        this.safeStopInputSession()
        this.getScrollUiFlow().scrollToBottomWithAnimation()
      },
      (value: boolean): void => {
        this.isSending = value
      },
      (taskId: string): void => {
        this.currentTaskId = taskId
      },
      (): void => {
        this.syncMessagesFromDataSource()
      },
      (): void => {
        if (this.isAtBottom) {
          this.scroller.scrollEdge(Edge.Bottom)
        }
      },
      (value: boolean): void => {
        this.isNewEmptySession = value
      },
      (): void => {
        this.persistCurrentDraftState('', []).catch((error: Error): void => {
          console.error('ChatPage', `Failed to clear draft after send: ${JSON.stringify(error)}`)
        })
      },
      (): void => {
        // no-op
      },
      (message: string): void => {
        // no-op
      },
      (message: string | Resource): void => {
        this.showError(message)
      },
      (message: string | Resource): void => {
        this.showChatSnack(message)
      }
    )
    this.sendFlow = new ChatSendFlow(deps)
    return this.sendFlow
  }

  private getStopFlow(): ChatStopFlow {
    if (this.stopFlow !== null) {
      return this.stopFlow
    }
    const deps = new ChatStopFlowDependencies(
      this.chatViewModel,
      this.chatTaskOrchestrator,
      this.messageDataSource,
      (): string => this.currentTaskId,
      (taskId: string): void => {
        this.currentTaskId = taskId
      },
      (value: boolean): void => {
        this.isSearchCancelled = value
      },
      (): void => {
        if (this.manualSearchFlow !== null) {
          this.manualSearchFlow.cancelCurrentSearchRequest()
          return
        }
        this.webSearchService.cancelAllRequests()
      },
      (): void => {
        this.syncMessagesFromDataSource()
      },
      (value: boolean): void => {
        this.isSending = value
      },
      (value: boolean): void => {
        this.isLoading = value
      },
      (): void => {
        this.forcedToolIdsOnce = []
      },
      (message: string): void => {
        // no-op
      }
    )
    this.stopFlow = new ChatStopFlow(deps)
    return this.stopFlow
  }

  private getManualSearchFlow(): ChatManualSearchFlow {
    if (this.manualSearchFlow !== null) {
      return this.manualSearchFlow
    }
    const deps = new ChatManualSearchFlowDependencies(
      this.chatViewModel,
      this.providerViewModel,
      this.webSearchService,
      this.defaultModelService,
      this.preferencesService,
      this.appStateManager,
      this.messageDataSource,
      (): ModelProvider | null => this.currentProvider,
      (): string => this.currentModelId,
      (): string => this.currentModel,
      (): ChatMessage[] => this.messages,
      (): ReasoningLevel => this.reasoningLevel,
      (): boolean => this.isSearchCancelled,
      (): void => this.syncMessagesFromDataSource(),
      (): void => {
        if (this.isAtBottom) {
          this.scroller.scrollEdge(Edge.Bottom)
        }
      },
      (value: boolean): void => {
        this.isSending = value
      },
      (value: boolean): void => {
        this.isSearchCancelled = value
      },
      (): void => {
        this.clearDraftAutosaveTimer()
        this.inputText = ''
        this.pendingAttachments = []
      },
      (): void => {
        this.safeStopInputSession()
        this.getScrollUiFlow().scrollToBottomWithAnimation()
      },
      (value: boolean): void => {
        this.isNewEmptySession = value
      },
      (): void => {
        this.persistCurrentDraftState('', []).catch((error: Error): void => {
          console.error('ChatPage', `Failed to clear draft after manual search: ${JSON.stringify(error)}`)
        })
      },
      (message: string): void => {
        // no-op
      },
      (): void => {
        // no-op
      },
      (message: string | Resource): void => {
        this.showError(message)
      },
      (message: string | Resource): void => {
        this.showChatSnack(message)
      }
    )
    this.manualSearchFlow = new ChatManualSearchFlow(deps)
    return this.manualSearchFlow
  }

  private getInlineEditFlow(): ChatInlineEditFlow {
    if (this.inlineEditFlow !== null) {
      return this.inlineEditFlow
    }
    const deps = new ChatInlineEditFlowDependencies(
      this.chatViewModel,
      this.messageDataSource,
      (): ChatMessage[] => this.messages,
      (): void => {
        this.syncMessagesFromDataSource()
      },
      (): void => {
        this.isEditingMessage = false
        this.editingMessageId = ''
        this.editingOriginalContent = ''
        this.editingOriginalAttachments = []
        this.editingWebSearchEnabled = false
        this.editingReasoningLevel = ReasoningLevel.OFF
      },
      (
        content: string,
        attachments: MessageAttachment[],
        webSearchEnabled: boolean,
        reasoningLevel: ReasoningLevel
      ): void => {
        this.inputText = content
        this.pendingAttachments = attachments
        this.webSearchEnabled = webSearchEnabled
        this.reasoningLevel = reasoningLevel
      },
      (value: boolean): void => {
        this.isSending = value
      },
      (): void => {
        this.handleSend()
      },
      (message: string | Resource): void => {
        this.showChatSnack(message)
      }
    )
    this.inlineEditFlow = new ChatInlineEditFlow(deps)
    return this.inlineEditFlow
  }

  private getSelectionFlow(): ChatSelectionFlow {
    if (this.selectionFlow !== null) {
      return this.selectionFlow
    }
    const deps = new ChatSelectionFlowDependencies(
      this.chatViewModel,
      this.messageDataSource,
      (): ChatMessage[] => this.messages,
      (messages: ChatMessage[]): void => {
        this.messages = messages
      },
      (): void => {
        this.syncMessagesFromDataSource()
      },
      (value: boolean): void => {
        this.isMultiSelectMode = value
      },
      (ids: string[]): void => {
        this.selectedMessageIds = ids
      },
      (value: boolean): void => {
        this.getScrollUiFlow().setInputBarVisible(value)
      },
      (messages: ChatMessage[]): void => {
        this.shareMessages = messages
      },
      (value: boolean): void => {
        this.showSharePreview = value
      },
      (message: string | Resource): void => {
        this.showChatSnack(message)
      }
    )
    this.selectionFlow = new ChatSelectionFlow(deps)
    return this.selectionFlow
  }

  private getLoadFlow(): ChatPageLoadFlow {
    if (this.loadFlow !== null) {
      return this.loadFlow
    }
    const deps = new ChatPageLoadFlowDependencies(
      this.appStateManager,
      this.preferencesService,
      this.providerViewModel,
      this.chatViewModel,
      (raw: string): string[] => {
        return this.parseToolIdsFromRoute(raw)
      }
    )
    this.loadFlow = new ChatPageLoadFlow(deps)
    return this.loadFlow
  }

  private getTaskAlertFlow(): ChatTaskAlertFlow {
    if (this.taskAlertFlow !== null) {
      return this.taskAlertFlow
    }
    const deps = new ChatTaskAlertFlowDependencies(
      this.chatTaskOrchestrator,
      (): string => this.taskUnreadBySessionJson,
      (): string => this.sessionId,
      (): boolean => this.isPageVisible,
      (): number => this.lastHandledAlertTimestamp,
      (count: number): void => {
        this.otherSessionUnreadCount = count
      },
      (value: number): void => {
        this.lastHandledAlertTimestamp = value
      },
      (sessionId: string): void => {
        this.navPathStack.replacePath({ name: 'ChatPage', param: { sessionId: sessionId } as ChatPageRouteParams })
      },
      (): void => {
        AppStorage.setOrCreate(AppStorageKeys.OPEN_SESSION_PAYLOAD, '')
      },
      (): void => {
        AppStorage.setOrCreate(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, '')
      },
      (): UIContext => {
        return this.getUIContext()
      }
    )
    this.taskAlertFlow = new ChatTaskAlertFlow(deps)
    return this.taskAlertFlow
  }

  private getScrollUiFlow(): ChatScrollUiFlow {
    if (this.scrollUiFlow !== null) {
      return this.scrollUiFlow
    }
    const deps = new ChatScrollUiFlowDependencies(
      this.scroller,
      this.messageDataSource,
      (): number => this.lastScrollOffset,
      (value: number): void => {
        this.lastScrollOffset = value
      },
      (): number => this.inputBarShowThreshold,
      (): number => this.inputBarHideThreshold,
      (): boolean => this.isAtTop,
      (): boolean => this.isAtBottom,
      (): boolean => this.isInputBarVisible,
      (): boolean => this.isSending,
      (): boolean => this.isInputFocused,
      (): boolean => this.isEditingMessage,
      (): string => this.editingMessageId,
      (): boolean => this.inputText.trim() !== '' || this.pendingAttachments.length > 0,
      (value: boolean): void => {
        this.isAtTop = value
      },
      (value: boolean): void => {
        this.isAtBottom = value
      },
      (value: boolean): void => {
        this.isInputBarVisible = value
      },
      (duration: number, curve: Curve, updater: () => void): void => {
        this.getUIContext().animateTo({
          duration: duration,
          curve: curve
        }, updater)
      }
    )
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
    if (this.pendingInitialToolIds.includes('web_search') && this.webSearchAvailable) {
      this.webSearchEnabled = true
    }

    await this.sendMessage()
  }

  // 验证当前模型是否有效，如果无效则自动选择第一个可用模型
  private validateAndSetCurrentModel(): void {
    const savedModelId = this.appStateManager.getCurrentModelId()
    const savedProviderId = this.appStateManager.getCurrentProviderId()

    // 检查保存的供应商和模型是否仍然有效
    let isValid = false
    for (let i = 0; i < this.providers.length; i++) {
      const provider = this.providers[i]
      if (provider.id === savedProviderId) {
        // 供应商存在，检查模型是否启用
        for (let j = 0; j < provider.models.length; j++) {
          const model = provider.models[j]
          if (model.id === savedModelId && model.isEnabled) {
            // 模型有效
            isValid = true
            this.currentProvider = provider
            this.currentModelId = savedModelId
            this.currentModel = this.appStateManager.getCurrentModelName()
            break
          }
        }
        break
      }
    }

    // 如果保存的模型无效，自动选择第一个可用模型
    if (!isValid) {
      this.selectFirstAvailableModel()
    }
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
              this.currentProvider = provider
              this.currentModelId = model.id
              this.currentModel = model.name
              await this.appStateManager.setCurrentModel(model.id, model.name, provider.id)
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
          this.currentProvider = provider
          this.currentModelId = model.id
          this.currentModel = model.name
          await this.appStateManager.setCurrentModel(model.id, model.name, provider.id)
          console.info('ChatPage', `Auto-selected fallback model: ${model.name} from ${provider.name}`)
          return
        }
      }
    }

    // 没有可用模型
    this.currentProvider = null
    this.currentModelId = ''
    this.currentModel = ''
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
    } else {
      // 验证并设置当前模型
      this.validateAndSetCurrentModel()
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

  build() {
    NavDestination() {
        Stack() {
        // 消息列表 - 占满全屏
        ChatMessageListSection({
          isLoading: this.isLoading,
          loadingColor: this.themePrimary,
          scroller: this.scroller,
          messageDataSource: this.messageDataSource,
          isEditingMessage: this.isEditingMessage,
          editingMessageId: this.editingMessageId,
          selectedMessageIds: this.selectedMessageIds,
          isMultiSelectMode: this.isMultiSelectMode,
          inputText: this.inputText,
          pendingAttachments: this.pendingAttachments,
          showDraftPreview: this.hasDraftContent(),
          draftPreviewTimeText: this.getPreviewTimeText(),
          bottomPadding: this.getListBottomPadding(),
          topInsetHeight: this.getPageTopAvoidHeight(),
          currentModelId: this.currentModelId,
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
          onListAppear: (): void => {
            hilog.info(DOMAIN, TAG, '👁️ 消息列表已显示 (消息数: %{public}d)', this.messages.length)
          },
          onReachStart: (): void => {
            this.getScrollUiFlow().setIsAtTop(true)
          },
          onReachEnd: (): void => {
            this.getScrollUiFlow().setIsAtBottom(true)
            this.getScrollUiFlow().setInputBarVisible(true)
          },
          onDidScroll: (scrollOffset: number, scrollState: ScrollState): void => {
            this.handleMessageListDidScroll(scrollOffset, scrollState)
          }
        })
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))

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

        // 顶部导航栏 - 使用独立组件
        ChatNavigationBar({
          sessionTitle: this.sessionTitle,
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
          hasMessages: this.messages.length > 0,
          isTitleGenerating: this.isTitleGenerating,
          titleGenerateFailed: this.titleGenerateFailed,
          contentMaxWidth: this.getChatContentMaxWidth(),
          isSending: this.isSending,
          otherSessionUnreadCount: this.otherSessionUnreadCount,
          topInsetHeight: this.getPageTopAvoidHeight(),
          onBack: () => {
            this.handleBack()
          },
          onModelSelect: () => {
            this.isModelSelectorVisible = true
            this.modelSheetActivePanel = 'selector'
          },
          onNewChat: () => {
            this.handleNewChat()
          },
          onRegenerateTitle: () => {
            this.handleRegenerateTitle()
          },
          onTitleChanged: (newTitle: string) => {
            this.handleSaveTitle(newTitle)
          },
          onNavigateToModelManage: () => {
            this.safePushUrl('pages/ModelManagePage')
          },
          onDeleteChat: () => {
            this.handleDeleteChat()
          }
        })
          .position({ x: 0, y: 0 })
          .bindSheet($$this.isModelSelectorVisible, this.ModelSelectorSheetBuilder(), {
              height: this.modelSheetActivePanel === 'selector' ? SheetSize.MEDIUM : SheetSize.LARGE,
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

        // 快速到顶部按钮
        ScrollToBottomButton({
          isVisible: this.shouldShowScrollToTopButton(),
          isInputBarVisible: this.isInputBarVisible,
          bottomAvoidHeight: this.px2vp(this.bottomAvoidHeight),
          buttonDirection: 1,
          extraOffsetY: -48,
          onScrollToTop: () => {
            this.scrollToTopWithAnimation()
          }
        })

        // 回到底部按钮（非 AI 生成状态时显示）
        ScrollToBottomButton({
          isVisible: !this.isAtBottom && !this.isMultiSelectMode && !this.isSending,
          isInputBarVisible: this.isInputBarVisible,
          bottomAvoidHeight: this.px2vp(this.bottomAvoidHeight),
          buttonDirection: 0,
          onScrollToBottom: () => {
            this.scrollToBottomWithAnimation()
          }
        })

        // AI 生成中的底部居中 loading 回到底部按钮
        ScrollToBottomLoadingButton({
          isVisible: !this.isAtBottom && !this.isMultiSelectMode && this.isSending,
          isInputBarVisible: this.isInputBarVisible,
          bottomAvoidHeight: this.px2vp(this.bottomAvoidHeight),
          onScrollToBottom: () => {
            this.scrollToBottomWithAnimation()
          }
        })

        // 底部输入栏容器（非多选模式时显示）
        if (!this.isMultiSelectMode) {
          ChatInputAreaSection({
            inputText: $inputText,
            attachments: $pendingAttachments,
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
            webSearchAvailable: this.webSearchAvailable,
            webSearchEnabled: $webSearchEnabled,
            reasoningLevel: $reasoningLevel,
            hasRecentScreenshot: this.hasRecentScreenshot,
            bottomAvoidHeight: this.px2vp(this.bottomAvoidHeight),
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
              this.showAttachmentPicker = true
            },
            onInputFocus: (): void => {
              if (!this.isEditingMessage) {
                this.isInputFocused = true
                setTimeout(() => {
                  this.scroller.scrollEdge(Edge.Bottom)
                }, 200)
              }
            },
            onInputBlur: (): void => {
              if (!this.hasDraftContent()) {
                this.isInputFocused = false
              }
            },
            onComposerContentChanged: (): void => {
              this.handleComposerContentChanged()
            },
            onRecentPhotoDetected: (detected: boolean): void => {
              this.hasRecentScreenshot = detected
            }
          })
          .position({ x: 0, y: '100%' })
          .translate({
            y: this.isInputBarVisible ? '-100%' : '0%',
            x: 0
          })
          .opacity(this.isInputBarVisible ? 1 : 0)
          .animation({
            duration: 220,
            curve: Curve.EaseOut
          })
          .bindSheet($$this.showAttachmentPicker, this.AttachmentPickerBuilder(), {
            height: 160,
            dragBar: false,
            showClose: false,
            backgroundColor: $r('app.color.surface'),
            blurStyle: BlurStyle.Thick,
            preferType: SheetType.BOTTOM
          })
        }

        // 分享预览 Sheet 宿主（bindContentCover 和 bindSheet 不能在同一组件上，否则会冲突）
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

        // 多选工具栏（多选模式时显示）
        if (this.isMultiSelectMode) {
          Column() {
            MultiSelectToolbar({
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

            // 底部安全区域占位
            Column()
              .width('100%')
              .height(this.px2vp(this.bottomAvoidHeight))
          }
          .width('100%')
          .position({ x: 0, y: '100%' })
          .translate({ y: '-100%', x: 0 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }

        // 图片预览（全屏覆盖层，不使用 bindContentCover 以避免模态层拦截手势）
        if (this.showImagePreview) {
          ImagePreview({
            images: this.previewImages,
            currentIndex: this.previewImageIndex,
            onClose: () => {
              this.showImagePreview = false
            }
          })
            .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }
      }
      .width('100%')
      .height('100%')
      .clip(true)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
      const param = context.pathInfo.param as ChatPageRouteParams
      if (param !== null && param !== undefined) {
        this.routeParams = param
      }
      // 如果 aboutToAppear 时 routeParams 还没设置，这里触发初始化
      if (this.sessionId === '') {
        this.initWithParams(this.routeParams)
      }
    })
    .onShown(() => {
      this.handlePageShown()
    })
    .onBackPressed((): boolean => {
      if (this.showImagePreview) {
        this.showImagePreview = false
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
  }

  @Builder
  ModelSelectorSheetBuilder() {
    ChatModelSelectorSheetContent({
      providers: this.providers,
      currentModelId: this.currentModelId,
      activePanel: this.modelSheetActivePanel,
      editingModel: $editingModel,
      onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
        this.handleModelSelect(providerId, modelId, modelName)
        this.isModelSelectorVisible = false
      },
      onStartEdit: (model: ModelInfo, provider: ModelProvider): void => {
        this.editingModel = model
        this.editingModelProvider = provider
        this.modelSheetActivePanel = 'edit'
      },
      onSaveEdit: async (): Promise<void> => {
        await this.saveModelEdit()
      },
      onCancelEdit: (): void => {
        this.modelSheetActivePanel = 'selector'
        this.editingModel = null
        this.editingModelProvider = null
      }
    })
  }

  private async saveModelEdit(): Promise<void> {
    const providerToSave = this.editingModelProvider
    if (providerToSave !== null) {
      await this.providerViewModel.saveProvider(providerToSave)
      const refreshedProviders = await this.providerViewModel.loadProviders()
      this.providers = refreshedProviders

      for (let i = 0; i < refreshedProviders.length; i++) {
        const provider = refreshedProviders[i]
        if (this.currentProvider !== null && provider.id === this.currentProvider.id) {
          this.currentProvider = provider
          for (let j = 0; j < provider.models.length; j++) {
            const model = provider.models[j]
            if (model.id === this.currentModelId) {
              const modelName = model.name !== '' ? model.name : model.id
              this.currentModel = modelName
              await this.appStateManager.setCurrentModel(model.id, modelName, provider.id)
              break
            }
          }
          break
        }
      }
    }
  }

  @Builder
  AttachmentPickerBuilder() {
    AttachmentPicker({
      onSelectAttachments: (attachments: MessageAttachment[]): void => {
        this.handleAttachmentsSelected(attachments)
      },
      onClose: (): void => {
        this.showAttachmentPicker = false
      }
    })
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

  // 处理附件选择
  private handleAttachmentsSelected(attachments: MessageAttachment[]): void {
    // 普通输入模式：添加到输入框的附件列表
    for (let i = 0; i < attachments.length; i++) {
      this.pendingAttachments.push(attachments[i])
    }
    // 触发数组更新，便于子组件监听并驱动发送按钮动效
    this.pendingAttachments = [...this.pendingAttachments]
    this.showAttachmentPicker = false

  }

  private onAppInBackgroundChanged(): void {
    // 后台切换由任务调度器与后台守护服务处理，这里只保留日志
    console.info('ChatPage', `[onAppInBackgroundChanged] appInBackground=${this.appInBackground}`)
  }

  private calcIsAwaitingAiOutput(): boolean {
    if (!this.isSending) {
      return false
    }

    const total = this.messageDataSource.totalCount()
    if (total <= 0) {
      return true
    }

    // 从尾部向前找最近一条 AI 消息；若 AI 还没开始输出（内容为空），则认为处于等待态
    for (let i = total - 1; i >= 0; i--) {
      const msg = this.messageDataSource.getData(i)
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
    this.handleBackAsync().catch((error: Error): void => {
      console.error('ChatPage', `Failed to prepare chat before back: ${JSON.stringify(error)}`)
      this.navPathStack.pop()
    })
  }

  private async handleBackAsync(): Promise<void> {
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

  private shouldShowScrollToTopButton(): boolean {
    return shouldShowScrollToTopButtonForChat(this.isMultiSelectMode, this.messageDataSource.totalCount(), this.isAtTop)
  }

  private handleMessageListDidScroll(scrollOffset: number, scrollState: ScrollState): void {
    this.getScrollUiFlow().handleMessageListDidScroll(scrollOffset, scrollState)
  }

  private hasDraftContent(): boolean {
    return this.inputText.trim() !== '' || this.pendingAttachments.length > 0
  }

  // 计算列表底部留白高度（需要根据输入栏实际高度动态调整）
  private getListBottomPadding(): number {
    return getListBottomPaddingForChat(this.pendingAttachments.length, this.isEditingMessage,
      this.px2vp(this.bottomAvoidHeight))
  }

  // 获取预览气泡的时间文本
  private getPreviewTimeText(): string {
    return getPreviewTimeTextForChat(new Date())
  }

  // 输入内容变化时，自动滚动到底部显示预览气泡
  private onDraftContentChanged(): void {
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
    if (this.isLoading || this.isEditingMessage || this.sessionId === '') {
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
    if (!immediate || this.isLoading || this.isEditingMessage || this.sessionId === '') {
      return
    }
    await this.persistCurrentDraftState(this.inputText, this.pendingAttachments)
  }

  private async persistCurrentDraftState(content: string, attachments: MessageAttachment[]): Promise<void> {
    if (this.isLoading || this.isEditingMessage || this.sessionId === '') {
      return
    }
    const session = await this.chatViewModel.saveSessionDraft(content, attachments)
    if (session === null) {
      return
    }
    this.sessionId = session.id
    this.sessionTitle = session.title
    AppStorage.setOrCreate(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, session.id)
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
      AppStorage.setOrCreate(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, '')
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

  // 同步包装方法，用于 onSend 回调
  handleSend(): void {
    this.sendMessage()
  }

  // 处理停止生成
  handleStop(): void {
    this.getStopFlow().stopCurrentTask()
  }

  // 处理模型选择
  handleModelSelect(providerId: string, modelId: string, modelName: string): void {
    // 更新当前模型
    this.currentModel = modelName
    this.currentModelId = modelId
    this.appStateManager.setCurrentModel(modelId, modelName, providerId)

    // 更新当前服务商
    for (let i = 0; i < this.providers.length; i++) {
      if (this.providers[i].id === providerId) {
        this.currentProvider = this.providers[i]
        break
      }
    }

    // 关闭模型选择器
    this.isModelSelectorVisible = false

    this.showChatSnack($r('app.string.model_switched'), 2000, SnackBarTone.SUCCESS)
  }

  async sendMessage(): Promise<void> {
    const prepareResult = this.getSendFlow().prepareSendRequest(
      this.inputText,
      this.pendingAttachments.length,
      this.isSending,
      this.currentProvider,
      this.chatTaskOrchestrator.canStartNewTask()
    )
    if (!prepareResult.shouldSend || prepareResult.currentProvider === null) {
      return
    }
    const messageContent = prepareResult.messageContent
    const currentProvider = prepareResult.currentProvider
    const effectiveApiKey = prepareResult.effectiveApiKey

    await this.refreshToolAvailabilityFromPreferences(false)

    const attachmentsToSend = [...this.pendingAttachments]
    const forcedToolIds = [...this.forcedToolIdsOnce]
    const dispatchResult = await this.getSendFlow().trySendWithFunctionCalling(
      messageContent,
      currentProvider,
      effectiveApiKey,
      attachmentsToSend,
      forcedToolIds,
      this.webSearchAvailable && this.webSearchEnabled,
      this.weatherQueryEnabled,
      this.currentModelId,
      (content: string, attachments: MessageAttachment[]): void => {
        console.info('ChatPage', '[联网查询] 当前模型未启用/不支持 tools，使用手动搜索链路')
        this.getManualSearchFlow().startManualSearchFallback(content, attachments)
      },
      (): void => {
        this.showError($r('app.string.function_calling_not_supported'))
      }
    )
    if (dispatchResult !== ChatSendDispatchResult.NOT_HANDLED) {
      this.forcedToolIdsOnce = []
      return
    }

    this.forcedToolIdsOnce = []
    await this.getSendFlow().sendPlainMessage(
      messageContent,
      currentProvider,
      effectiveApiKey,
      attachmentsToSend
    )
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
    this.messageDataSource.setAllMessages(this.messages)
    this.syncMessagesFromDataSource()
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

  // 从 messageDataSource 同步数据到 messages 数组（创建副本，避免共享引用）
  private syncMessagesFromDataSource(): void {
    const allMessages = this.messageDataSource.getAllMessages()
    this.messages = []
    for (let i = 0; i < allMessages.length; i++) {
      this.messages.push(allMessages[i])
    }
  }

  // 处理删除消息
  async handleDeleteMessage(message: ChatMessage): Promise<void> {
    const index = findMessageIndexById(this.messages, message.id)
    if (index < 0) {
      return
    }
    this.messages.splice(index, 1)
    this.messageDataSource.setAllMessages(this.messages)
    this.syncMessagesFromDataSource()
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
      callback('', '翻译失败：' + error.message)
    })
  }

  // 处理TTS朗读
  private handleTTS(messageId: string, content: string): void {
    // 如果正在朗读其他消息，先停止
    if (this.speakingMessageId !== '') {
      this.ttsService.stop()
    }

    this.speakingMessageId = messageId

    this.ttsService.speak(content, {
      onStart: () => {
        // 朗读开始
      },
      onComplete: () => {
        // 朗读完成
        this.speakingMessageId = ''
      },
      onError: (error: string) => {
        this.speakingMessageId = ''
        this.showChatSnack(error, 3000, SnackBarTone.ERROR)
      }
    })
  }

  // 处理停止TTS朗读
  private handleTTSStop(): void {
    this.ttsService.stop()
    this.speakingMessageId = ''
  }

  // 处理新建对话
  private async handleNewChat(): Promise<void> {
    await this.prepareCurrentSessionForTransition()
    this.clearDraftAutosaveTimer()
    // 创建新会话
    const session = await this.chatViewModel.createNewSession()
    this.inputText = ''
    this.pendingAttachments = []
    // 清空当前消息
    this.messages = []
    this.messageDataSource.clear()
    // 更新会话ID和标题
    this.sessionId = session.id
    this.sessionTitle = session.title
    // 重置标题状态
    this.isTitleGenerating = false
    this.titleGenerateFailed = false
    // 标记为新建的空会话（返回时需要删除）
    this.isNewEmptySession = true
    AppStorage.setOrCreate(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, this.sessionId)

    this.showChatSnack($r('app.string.chat_created'), 2000, SnackBarTone.SUCCESS)
  }

  // 处理重新生成标题
  private handleRegenerateTitle(): void {
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
    if (message.role === MessageRole.USER) {
      this.editingWebSearchEnabled = message.searchQuery !== undefined && message.searchQuery !== ''
    }
    this.isEditingMessage = true
    this.getScrollUiFlow().setInputBarVisible(true)
    this.autoFocusInput = true
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve()
      }, 100)
    })
    const messageIndex = findMessageIndexById(this.messages, message.id)
    if (messageIndex >= 0) {
      this.scroller.scrollToIndex(toListScrollIndexForMessage(messageIndex), true, ScrollAlign.CENTER)
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
    this.editingReasoningLevel = ReasoningLevel.OFF
  }

  // 内联编辑模式：保存并发送
  private async handleSaveAndSendInline(): Promise<void> {
    await this.getInlineEditFlow().saveAndSendInline(
      this.editingMessageId,
      this.inputText,
      this.pendingAttachments,
      this.editingWebSearchEnabled,
      this.editingReasoningLevel
    )
  }

  // 分享单条消息：进入多选模式并触发分享
  private handleShareSingleMessage(message: ChatMessage): void {
    this.getSelectionFlow().enterModeWithMessage(message.id)
    this.handleShareSelectedMessages()
  }

  // 进入多选模式
  private handleEnterMultiSelectMode(messageId: string): void {
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
  ChatPage({ routeParams: param as ChatPageRouteParams })
}
