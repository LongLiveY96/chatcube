import {
  ApiStyle,
  ChatMessage,
  MessageAttachment,
  ModelProvider,
  ReasoningLevel,
  ToolCall,
  ToolResult
} from '../../models/ChatModels'
import { ChatViewModel, ToolCallCallbacks } from '../../viewmodels/ChatViewModel'
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

export enum ChatExecutionMode {
  PLAIN = 'plain',
  WEB_SEARCH = 'web_search'
}

enum ChatExecutionPlanKind {
  PLAIN_DIRECT = 'plain_direct',
  TOOLS = 'tools',
  MANUAL_SEARCH = 'manual_search'
}

class ChatExecutionPlan {
  kind: ChatExecutionPlanKind
  enabledToolIds: string[]

  constructor(kind: ChatExecutionPlanKind, enabledToolIds: string[] = []) {
    this.kind = kind
    this.enabledToolIds = enabledToolIds
  }
}

export interface ChatSendFlowDependencies {
  chatViewModel: ChatViewModel
  messages: ChatMessage[]
  chatTaskOrchestrator: ChatTaskOrchestratorService
  toolRegistry: ToolRegistry
  getSessionId: () => string
  getSessionTitle: () => string
  getCurrentTaskId: () => string
  getCurrentModelId: () => string
  getCurrentModelName: () => string
  getMessages: () => ChatMessage[]
  getReasoningLevel: () => ReasoningLevel
  executeManualSearch: (messageContent: string, attachmentsToSend: MessageAttachment[]) => Promise<void>
  onClearComposer: () => void
  onBeforeSend: () => void
  onSetSending: (value: boolean) => void
  onSetCurrentTaskId: (taskId: string) => void
  onSyncMessages: () => void
  onScrollBottom: () => void
  onSetNewEmptySession: (value: boolean) => void
  onDraftCommitted: () => void
  onMarkAutoTaskCompleted: () => void
  onMarkAutoTaskFailed: (message: string) => void
  onShowError: (message: string | Resource) => void
  onShowToast: (message: string | Resource) => void
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
    currentModelId: string,
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
      } else if (currentProvider.requiresApiKey && providerValidation.effectiveApiKey === '') {
        this.deps.onShowError($r('app.string.api_key_required'))
        this.deps.onMarkAutoTaskFailed('缺少 API Key')
      } else {
        this.deps.onShowError(providerValidation.errorMessage)
        this.deps.onMarkAutoTaskFailed(providerValidation.errorMessage)
      }
      return result
    }

    if (!this.isCurrentModelAvailable(currentProvider, currentModelId)) {
      this.deps.onShowError('当前模型不可用，请重新选择模型')
      this.deps.onMarkAutoTaskFailed('当前模型不可用')
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

  private isCurrentModelAvailable(currentProvider: ModelProvider, currentModelId: string): boolean {
    if (currentModelId === '') {
      return false
    }
    for (let i = 0; i < currentProvider.models.length; i++) {
      const model = currentProvider.models[i]
      if (model.id === currentModelId && model.isEnabled) {
        return true
      }
    }
    return false
  }

  async executeSend(
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[],
    forcedToolIds: string[],
    executionMode: ChatExecutionMode,
    currentModelId: string
  ): Promise<void> {
    const plan = this.buildExecutionPlan(
      messageContent,
      currentProvider,
      forcedToolIds,
      executionMode,
      currentModelId
    )
    console.info(
      'ChatSendFlow',
      `[executeSend] mode=${executionMode}, plan=${plan.kind}, tools=${plan.enabledToolIds.join(',')}`
    )

    if (plan.kind === ChatExecutionPlanKind.MANUAL_SEARCH) {
      await this.deps.executeManualSearch(messageContent, attachmentsToSend)
      return
    }

    if (plan.kind === ChatExecutionPlanKind.TOOLS) {
      await this.sendMessageWithTools(
        messageContent,
        currentProvider,
        effectiveApiKey,
        attachmentsToSend,
        plan.enabledToolIds
      )
      return
    }

    await this.sendPlainMessage(
      messageContent,
      currentProvider,
      effectiveApiKey,
      attachmentsToSend
    )
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

  buildEnabledToolIds(extraToolIds: string[] = []): string[] {
    const ids: string[] = []

    for (let i = 0; i < extraToolIds.length; i++) {
      const toolId = extraToolIds[i]
      if (this.deps.toolRegistry.isToolRegistered(toolId)) {
        appendUniqueToolId(ids, toolId)
      }
    }

    return ids
  }

  private buildExecutionPlan(
    messageContent: string,
    currentProvider: ModelProvider,
    forcedToolIds: string[],
    executionMode: ChatExecutionMode,
    currentModelId: string
  ): ChatExecutionPlan {
    const enabledToolIds = this.buildEnabledToolIds(forcedToolIds)
    if (enabledToolIds.length > 0) {
      if (this.isCurrentModelSupportsTools(currentProvider, currentModelId)) {
        return new ChatExecutionPlan(ChatExecutionPlanKind.TOOLS, enabledToolIds)
      }
      if (this.hasWebSearchTool(enabledToolIds)) {
        return new ChatExecutionPlan(ChatExecutionPlanKind.MANUAL_SEARCH)
      }
      return new ChatExecutionPlan(ChatExecutionPlanKind.PLAIN_DIRECT)
    }

    if (executionMode === ChatExecutionMode.WEB_SEARCH) {
      const webSearchToolIds = this.getRegisteredWebSearchToolIds()
      if (webSearchToolIds.length > 0 && this.isCurrentModelSupportsTools(currentProvider, currentModelId)) {
        return new ChatExecutionPlan(ChatExecutionPlanKind.TOOLS, webSearchToolIds)
      }

      return new ChatExecutionPlan(ChatExecutionPlanKind.MANUAL_SEARCH)
    }

    return new ChatExecutionPlan(ChatExecutionPlanKind.PLAIN_DIRECT)
  }

  private getRegisteredWebSearchToolIds(): string[] {
    const ids: string[] = []
    if (this.deps.toolRegistry.isToolRegistered('web_search')) {
      ids.push('web_search')
    }
    return ids
  }

  private hasWebSearchTool(toolIds: string[]): boolean {
    for (let i = 0; i < toolIds.length; i++) {
      if (toolIds[i] === 'web_search') {
        return true
      }
    }
    return false
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
    this.deps.onSetSending(true)
    this.deps.onBeforeSend()
  }

  private handleUserMessageAdded(userMessage: ChatMessage): void {
    this.deps.onClearComposer()
    this.deps.messages.push(userMessage)
    this.deps.onSyncMessages()
    this.deps.onSetNewEmptySession(false)
    this.deps.onDraftCommitted()
    this.deps.onScrollBottom()
  }

  private handleAIMessageAdded(aiMessage: ChatMessage): void {
    this.deps.messages.push(aiMessage)
    this.deps.onSyncMessages()
    this.deps.onScrollBottom()
  }

  private handleAIMessageUpdated(aiMessage: ChatMessage): void {
    const index = this.deps.messages.findIndex((message: ChatMessage) => message.id === aiMessage.id)
    if (index < 0) {
      console.warn('ChatSendFlow', `[handleAIMessageUpdated] message not found: ${aiMessage.id}`)
      return
    }
    this.deps.messages[index] = aiMessage
    this.deps.onSyncMessages()
    this.deps.onScrollBottom()
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
    enabledToolIds: string[] = []
  ): Promise<void> {
    const taskId = this.startTaskOrFail(messageContent)
    if (taskId === '') {
      return
    }

    this.prepareSendState(taskId)
    const modelId = this.deps.getCurrentModelId()
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
