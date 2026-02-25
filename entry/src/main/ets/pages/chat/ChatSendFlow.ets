import {
  ApiStyle,
  ChatMessage,
  MessageAttachment,
  ModelProvider,
  ProviderType,
  ReasoningLevel,
  ToolCall,
  ToolResult
} from '../../models/ChatModels'
import { ChatViewModel, ToolCallCallbacks } from '../../viewmodels/ChatViewModel'
import { MessageDataSource } from '../../datasource/MessageDataSource'
import { ChatTaskOrchestratorService } from '../../services/ChatTaskOrchestratorService'
import { ToolRegistry } from '../../services/ToolRegistry'
import { appendUniqueToolId } from './ChatToolIdHelper'
import { validateProviderConfig } from '../../utils/ProviderValidationUtils'

export class ChatSendPrepareResult {
  shouldSend: boolean = false
  messageContent: string = ''
  effectiveApiKey: string = ''
  currentProvider: ModelProvider | null = null
}

export class ChatSendDispatchResult {
  static readonly NOT_HANDLED: number = 0
  static readonly SENT_WITH_TOOLS: number = 1
  static readonly MANUAL_FALLBACK: number = 2
  static readonly UNSUPPORTED_TOOLS: number = 3
}

export class ChatSendFlowDependencies {
  chatViewModel: ChatViewModel
  messageDataSource: MessageDataSource
  chatTaskOrchestrator: ChatTaskOrchestratorService
  toolRegistry: ToolRegistry
  getSessionId: () => string
  getSessionTitle: () => string
  getCurrentTaskId: () => string
  getCurrentModelId: () => string
  getCurrentModelName: () => string
  getMessages: () => ChatMessage[]
  getReasoningLevel: () => ReasoningLevel
  onClearComposer: () => void
  onBeforeSend: () => void
  onSetSending: (value: boolean) => void
  onSetCurrentTaskId: (taskId: string) => void
  onSyncMessages: () => void
  onScrollBottom: () => void
  onSetNewEmptySession: (value: boolean) => void
  onMarkAutoTaskCompleted: () => void
  onMarkAutoTaskFailed: (message: string) => void
  onShowError: (message: string | Resource) => void
  onShowToast: (message: string | Resource) => void

  constructor(
    chatViewModel: ChatViewModel,
    messageDataSource: MessageDataSource,
    chatTaskOrchestrator: ChatTaskOrchestratorService,
    toolRegistry: ToolRegistry,
    getSessionId: () => string,
    getSessionTitle: () => string,
    getCurrentTaskId: () => string,
    getCurrentModelId: () => string,
    getCurrentModelName: () => string,
    getMessages: () => ChatMessage[],
    getReasoningLevel: () => ReasoningLevel,
    onClearComposer: () => void,
    onBeforeSend: () => void,
    onSetSending: (value: boolean) => void,
    onSetCurrentTaskId: (taskId: string) => void,
    onSyncMessages: () => void,
    onScrollBottom: () => void,
    onSetNewEmptySession: (value: boolean) => void,
    onMarkAutoTaskCompleted: () => void,
    onMarkAutoTaskFailed: (message: string) => void,
    onShowError: (message: string | Resource) => void,
    onShowToast: (message: string | Resource) => void
  ) {
    this.chatViewModel = chatViewModel
    this.messageDataSource = messageDataSource
    this.chatTaskOrchestrator = chatTaskOrchestrator
    this.toolRegistry = toolRegistry
    this.getSessionId = getSessionId
    this.getSessionTitle = getSessionTitle
    this.getCurrentTaskId = getCurrentTaskId
    this.getCurrentModelId = getCurrentModelId
    this.getCurrentModelName = getCurrentModelName
    this.getMessages = getMessages
    this.getReasoningLevel = getReasoningLevel
    this.onClearComposer = onClearComposer
    this.onBeforeSend = onBeforeSend
    this.onSetSending = onSetSending
    this.onSetCurrentTaskId = onSetCurrentTaskId
    this.onSyncMessages = onSyncMessages
    this.onScrollBottom = onScrollBottom
    this.onSetNewEmptySession = onSetNewEmptySession
    this.onMarkAutoTaskCompleted = onMarkAutoTaskCompleted
    this.onMarkAutoTaskFailed = onMarkAutoTaskFailed
    this.onShowError = onShowError
    this.onShowToast = onShowToast
  }
}

export class ChatSendFlow {
  private deps: ChatSendFlowDependencies

  constructor(deps: ChatSendFlowDependencies) {
    this.deps = deps
  }

  prepareSendRequest(
    inputText: string,
    pendingAttachmentCount: number,
    isSending: boolean,
    currentProvider: ModelProvider | null,
    canStartNewTask: boolean
  ): ChatSendPrepareResult {
    const result = new ChatSendPrepareResult()
    const messageContent = inputText.trim()
    if (messageContent === '' && pendingAttachmentCount === 0) {
      return result
    }
    if (isSending) {
      return result
    }

    const providerValidation = validateProviderConfig(currentProvider)
    if (!providerValidation.isValid || currentProvider === null) {
      if (currentProvider === null) {
        this.deps.onShowError($r('app.string.provider_required_before_chat'))
        this.deps.onMarkAutoTaskFailed('未配置可用服务商')
      } else if (providerValidation.effectiveApiKey === '' && currentProvider.type !== ProviderType.OLLAMA) {
        this.deps.onShowError($r('app.string.api_key_required'))
        this.deps.onMarkAutoTaskFailed('缺少 API Key')
      } else {
        this.deps.onShowError(providerValidation.errorMessage)
        this.deps.onMarkAutoTaskFailed(providerValidation.errorMessage)
      }
      return result
    }

    if (!canStartNewTask) {
      this.deps.onShowToast($r('app.string.task_parallel_limit_reached'))
      this.deps.onMarkAutoTaskFailed('并行任务已达上限')
      return result
    }

    result.shouldSend = true
    result.messageContent = messageContent
    result.effectiveApiKey = providerValidation.effectiveApiKey
    result.currentProvider = currentProvider
    return result
  }

  async trySendWithFunctionCalling(
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[],
    forcedToolIds: string[],
    webSearchEnabled: boolean,
    weatherQueryEnabled: boolean,
    currentModelId: string,
    onManualFallbackStart: (content: string, attachments: MessageAttachment[]) => void,
    onUnsupportedTools: () => void
  ): Promise<number> {
    const enabledToolIds = this.buildEnabledToolIds(webSearchEnabled, weatherQueryEnabled, forcedToolIds)
    if (enabledToolIds.length <= 0) {
      return ChatSendDispatchResult.NOT_HANDLED
    }

    const currentModelSupportsTools = this.isCurrentModelSupportsTools(currentProvider, currentModelId)
    if (currentModelSupportsTools) {
      await this.sendMessageWithTools(
        messageContent,
        currentProvider,
        effectiveApiKey,
        attachmentsToSend,
        forcedToolIds,
        webSearchEnabled,
        weatherQueryEnabled
      )
      return ChatSendDispatchResult.SENT_WITH_TOOLS
    }

    if (enabledToolIds.includes('web_search')) {
      onManualFallbackStart(messageContent, attachmentsToSend)
      return ChatSendDispatchResult.MANUAL_FALLBACK
    }

    onUnsupportedTools()
    return ChatSendDispatchResult.UNSUPPORTED_TOOLS
  }

  isCurrentModelSupportsTools(currentProvider: ModelProvider | null, currentModelId: string): boolean {
    if (currentProvider === null) {
      return false
    }
    if (currentProvider.apiStyle !== ApiStyle.OPENAI) {
      console.info('ChatSendFlow', `[Function Calling] 当前 API 风格不支持 tools: ${currentProvider.apiStyle}`)
      return false
    }
    for (let i = 0; i < currentProvider.models.length; i++) {
      const model = currentProvider.models[i]
      if (model.id === currentModelId) {
        console.info('ChatSendFlow',
          `[Function Calling] 当前模型 supportsTools=${model.capabilities.supportsTools}, modelId=${model.id}`)
        return model.capabilities.supportsTools
      }
    }
    console.info('ChatSendFlow',
      `[Function Calling] 未在 provider.models 中找到当前模型: currentModelId=${currentModelId}, provider=${currentProvider.id}`)
    return false
  }

  buildEnabledToolIds(
    webSearchEnabled: boolean,
    weatherQueryEnabled: boolean,
    extraToolIds: string[] = []
  ): string[] {
    const ids: string[] = []

    if (webSearchEnabled && this.deps.toolRegistry.isToolRegistered('web_search')) {
      appendUniqueToolId(ids, 'web_search')
    }

    if (weatherQueryEnabled && this.deps.toolRegistry.isToolRegistered('weather_query')) {
      appendUniqueToolId(ids, 'weather_query')
    }

    for (let i = 0; i < extraToolIds.length; i++) {
      const toolId = extraToolIds[i]
      if (toolId === 'web_search' && !webSearchEnabled) {
        continue
      }
      if (toolId === 'weather_query' && !weatherQueryEnabled) {
        continue
      }
      if (this.deps.toolRegistry.isToolRegistered(toolId)) {
        appendUniqueToolId(ids, toolId)
      }
    }

    return ids
  }

  private startTaskOrFail(messageContent: string): string {
    const taskId = this.deps.chatTaskOrchestrator.startTask(
      this.deps.getSessionId(),
      this.deps.getSessionTitle(),
      messageContent,
      this.deps.chatViewModel
    )
    if (taskId === '') {
      this.deps.onShowToast($r('app.string.task_parallel_limit_reached'))
      this.deps.onMarkAutoTaskFailed('并行任务已达上限')
      return ''
    }
    return taskId
  }

  private prepareSendState(taskId: string): void {
    this.deps.onSetCurrentTaskId(taskId)
    this.deps.onClearComposer()
    this.deps.onSetSending(true)
    this.deps.onBeforeSend()
  }

  private handleUserMessageAdded(userMessage: ChatMessage): void {
    this.deps.messageDataSource.addMessage(userMessage)
    this.deps.onSyncMessages()
    this.deps.onSetNewEmptySession(false)
    this.deps.onScrollBottom()
  }

  private handleAIMessageAdded(aiMessage: ChatMessage): void {
    this.deps.messageDataSource.addMessage(aiMessage)
    this.deps.onSyncMessages()
    this.deps.onScrollBottom()
  }

  private handleAIMessageUpdated(aiMessage: ChatMessage): void {
    if (this.deps.messageDataSource.totalCount() > 0) {
      this.deps.messageDataSource.updateLastMessage(aiMessage)
      this.deps.onSyncMessages()
      this.deps.onScrollBottom()
    }
  }

  private handleTaskCompleted(taskId: string): void {
    this.deps.chatTaskOrchestrator.completeTask(taskId)
    if (this.deps.getCurrentTaskId() === taskId) {
      this.deps.onSetCurrentTaskId('')
    }
    this.deps.onSetSending(false)
    this.deps.onMarkAutoTaskCompleted()
  }

  private handleTaskFailed(taskId: string, error: string, showError: boolean): void {
    this.deps.chatTaskOrchestrator.failTask(taskId, error)
    if (this.deps.getCurrentTaskId() === taskId) {
      this.deps.onSetCurrentTaskId('')
    }
    this.deps.onSetSending(false)
    this.deps.onMarkAutoTaskFailed(error)
    if (showError) {
      this.deps.onShowError(error)
    }
  }

  async sendPlainMessage(
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[] = []
  ): Promise<void> {
    const taskId = this.startTaskOrFail(messageContent)
    if (taskId === '') {
      return
    }

    this.prepareSendState(taskId)
    const modelId = this.deps.getCurrentModelId()

    try {
      await this.deps.chatViewModel.sendMessage(
        messageContent,
        currentProvider.id,
        currentProvider.type,
        currentProvider.apiStyle,
        effectiveApiKey,
        currentProvider.baseUrl,
        modelId,
        this.deps.getCurrentModelName(),
        this.deps.getMessages(),
        (userMessage: ChatMessage): void => {
          this.handleUserMessageAdded(userMessage)
        },
        (aiMessage: ChatMessage): void => {
          this.handleAIMessageAdded(aiMessage)
        },
        (aiMessage: ChatMessage): void => {
          this.handleAIMessageUpdated(aiMessage)
        },
        (): void => {
          this.handleTaskCompleted(taskId)
        },
        (error: string): void => {
          this.handleTaskFailed(taskId, error, true)
        },
        attachmentsToSend,
        0,
        this.deps.getReasoningLevel(),
        currentProvider.apiPath || undefined
      )
    } catch (error) {
      const message = `发送失败: ${JSON.stringify(error)}`
      this.handleTaskFailed(taskId, message, true)
    }
  }

  async sendMessageWithTools(
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[] = [],
    extraToolIds: string[] = [],
    webSearchEnabled: boolean = false,
    weatherQueryEnabled: boolean = false
  ): Promise<void> {
    const taskId = this.startTaskOrFail(messageContent)
    if (taskId === '') {
      return
    }

    this.prepareSendState(taskId)
    const modelId = this.deps.getCurrentModelId()
    const enabledToolIds = this.buildEnabledToolIds(webSearchEnabled, weatherQueryEnabled, extraToolIds)
    const tools = this.deps.toolRegistry.getEnabledToolDefinitions(enabledToolIds)

    console.info('ChatSendFlow', `[Function Calling] 启用工具: ${enabledToolIds.join(', ')}`)

    const toolCallbacks: ToolCallCallbacks = {
      onToolCallStarted: (toolCalls: ToolCall[]): void => {
        console.info('ChatSendFlow', `[Function Calling] 工具调用开始: ${toolCalls.length} 个`)
        for (let i = 0; i < toolCalls.length; i++) {
          console.info('ChatSendFlow', `  - ${toolCalls[i].functionName}: ${toolCalls[i].arguments}`)
        }
      },
      onToolCallCompleted: (results: ToolResult[]): void => {
        console.info('ChatSendFlow', `[Function Calling] 工具调用完成: ${results.length} 个结果`)
      },
      onSearching: (query: string): void => {
        console.info('ChatSendFlow', `[Function Calling] 正在搜索: ${query}`)
      }
    }

    try {
      await this.deps.chatViewModel.sendMessageWithTools(
        messageContent,
        currentProvider.id,
        currentProvider.type,
        currentProvider.apiStyle,
        effectiveApiKey,
        currentProvider.baseUrl,
        modelId,
        this.deps.getCurrentModelName(),
        this.deps.getMessages(),
        (userMessage: ChatMessage): void => {
          this.handleUserMessageAdded(userMessage)
        },
        (aiMessage: ChatMessage): void => {
          this.handleAIMessageAdded(aiMessage)
        },
        (aiMessage: ChatMessage): void => {
          this.handleAIMessageUpdated(aiMessage)
        },
        (): void => {
          this.handleTaskCompleted(taskId)
        },
        (error: string): void => {
          this.handleTaskFailed(taskId, error, true)
        },
        attachmentsToSend,
        0,
        this.deps.getReasoningLevel(),
        tools,
        toolCallbacks,
        currentProvider.apiPath || undefined
      )
    } catch (error) {
      const message = `发送失败: ${JSON.stringify(error)}`
      this.handleTaskFailed(taskId, message, true)
    }
  }
}
