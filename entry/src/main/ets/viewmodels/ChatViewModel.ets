import { getDatabaseService, DatabaseService } from '../services/DatabaseService'
import { getAIApiService, AIApiService, AIApiConfig, RequestMessage, AIApiResult } from '../services/AIApiService'
import { getAppStateManager, AppStateManager } from './AppStateManager'
import { getAITaskService, AITaskService } from '../services/AITaskService'
import { getAttachmentStorageService, AttachmentStorageService } from '../services/AttachmentStorageService'
import { getToolExecutionService, ToolExecutionService } from '../services/ToolExecutionService'
import { getProviderViewModel, ProviderViewModel } from './ProviderViewModel'
import { ChatMessage, ChatSession, MessageRole, ProviderType, ApiStyle, MessageAttachment, AttachmentType, ReasoningLevel, ToolDefinition, ToolCall, ToolResult, SearchReference, ModelParameters } from '../models/ChatModels'
import { WebSearchResult, SearchResult } from '../services/WebSearchService'
import { http } from '@kit.NetworkKit'
import { getEffectiveApiKey } from '../config/PresetProviders'
import { getPreferencesService } from '../services/PreferencesService'
import { PreferenceKeys } from '../services/PreferencesService'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { ChatSessionStore } from './ChatSessionStore'
import { createThrottle, ThrottleUtil } from '../utils/ThrottleUtil'
import {
  buildCurrentTimeContext,
  renderSystemPromptTemplate,
  SystemPromptTemplateDefaults
} from '../utils/SystemPromptTemplateUtils'
import {
  cleanSearchQuery as cleanSearchQueryShared,
  normalizeRelativeTimeForSearchQuery as normalizeRelativeTimeForSearchQueryShared
} from '../utils/SearchQueryUtils'

// 标题生成状态
export interface TitleGenerationCallbacks {
  onTitleUpdated?: (title: string) => void
  onTitleGenerating?: (isGenerating: boolean) => void
  onTitleFailed?: () => void
}

// 工具调用回调
export interface ToolCallCallbacks {
  onToolCallStarted?: (toolCalls: ToolCall[]) => void
  onToolCallCompleted?: (results: ToolResult[]) => void
  onSearching?: (query: string) => void
}

// web_search 工具参数接口
interface WebSearchArgs {
  query: string
}

// 搜索结果数据接口
interface SearchResultItem {
  title: string
  url: string
  snippet: string
}

interface SearchResultData {
  query: string
  searchEngine: string
  results: SearchResultItem[]
  summary: string
}

// 待持久化 AI 消息信息（每请求独立）
interface PendingAIMessageInfo {
  message: ChatMessage
  sessionId: string
  persisted: boolean
}

// 活跃请求信息（每请求独立，用于 stopGeneration 时取消）
interface ActiveRequestInfo {
  httpRequest: http.HttpRequest
  cancelCallback: () => void  // 调用后将闭包内的 cancelled 标志设为 true
}

// 聊天状态管理
export class ChatViewModel {
  private databaseService: DatabaseService
  private aiApiService: AIApiService
  private appStateManager: AppStateManager
  private aiTaskService: AITaskService
  private attachmentStorageService: AttachmentStorageService
  private toolExecutionService: ToolExecutionService
  private providerViewModel: ProviderViewModel
  private sessionStore: ChatSessionStore

  // 当前会话
  private currentSession: ChatSession | null = null
  // 活跃请求 Map（key = requestId，支持多个并发请求）
  private activeRequests: Map<string, ActiveRequestInfo> = new Map()
  // 待持久化 AI 消息 Map（key = messageId，支持多个并发请求）
  private pendingAIMessages: Map<string, PendingAIMessageInfo> = new Map()
  // 标题生成回调
  private titleCallbacks: TitleGenerationCallbacks | null = null
  // 最大重试次数
  private readonly MAX_TITLE_RETRY = 3
  // 最大工具调用轮次
  private readonly MAX_TOOL_ITERATIONS = 6
  // 取消令牌：用于停止”尚未开始发送的请求”（例如退出页面时）
  private cancelToken: number = 0
  // 历史附件懒加载配置
  private readonly MAX_HISTORY_ATTACHMENTS = 5
  private readonly MAX_HISTORY_ATTACHMENT_SIZE = 5 * 1024 * 1024 // 5MB

  constructor() {
    this.databaseService = getDatabaseService()
    this.aiApiService = getAIApiService()
    this.appStateManager = getAppStateManager()
    this.aiTaskService = getAITaskService()
    this.attachmentStorageService = getAttachmentStorageService()
    this.toolExecutionService = getToolExecutionService()
    this.providerViewModel = getProviderViewModel()
    this.sessionStore = new ChatSessionStore(
      this.databaseService,
      this.appStateManager,
      () => this.generateId(),
      () => this.notifySessionListChanged()
    )
  }

  private async getRenderedSystemPrompt(): Promise<string> {
    const prefsService = getPreferencesService()
    const template = await prefsService.getString(
      PreferenceKeys.CUSTOM_SYSTEM_PROMPT,
      SystemPromptTemplateDefaults.DEFAULT_TEMPLATE
    )
    return renderSystemPromptTemplate(template)
  }

  private notifySessionListChanged(): void {
    AppStorage.setOrCreate<number>(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())
  }

  private isFirstRoundSession(session: ChatSession | null): boolean {
    return session !== null && session.messages.length === 0
  }

  private appendMessageToSessionIfMissing(session: ChatSession | null, message: ChatMessage): void {
    if (session === null) {
      return
    }
    for (let i = 0; i < session.messages.length; i++) {
      if (session.messages[i].id === message.id) {
        return
      }
    }
    session.messages.push(message)
  }

  private isCancelled(snapshot: number): boolean {
    return snapshot !== this.cancelToken
  }

  private addPendingAIMessage(message: ChatMessage, sessionId: string): void {
    this.pendingAIMessages.set(message.id, {
      message: message,
      sessionId: sessionId,
      persisted: false
    } as PendingAIMessageInfo)
  }

  private clearPendingAIMessageIfMatches(messageId: string): void {
    this.pendingAIMessages.delete(messageId)
  }

  private markPendingAIMessagePersisted(messageId: string): void {
    const info = this.pendingAIMessages.get(messageId)
    if (info !== undefined) {
      info.persisted = true
    }
  }

  // 判断待持久化消息是否包含有效内容（空占位消息不应跨会话残留）
  private hasMeaningfulPendingMessageContent(message: ChatMessage): boolean {
    if (message.content.trim() !== '') {
      return true
    }
    if (message.reasoningContent.trim() !== '') {
      return true
    }
    if (message.attachments.length > 0) {
      return true
    }
    if (message.searchReferences.length > 0) {
      return true
    }
    if (message.toolCalls.length > 0) {
      return true
    }
    if (message.toolResults.length > 0) {
      return true
    }
    return false
  }

  // 丢弃指定待持久化 AI 消息（用于 stop 后清理空占位）
  discardPendingAIMessage(messageId: string): void {
    this.clearPendingAIMessageIfMatches(messageId)
  }

  private persistPendingAIMessageIfNeeded(): void {
    const entries: PendingAIMessageInfo[] = []
    const discardMessageIds: string[] = []
    this.pendingAIMessages.forEach((info: PendingAIMessageInfo) => {
      if (info.persisted || info.sessionId === '') {
        return
      }
      if (!this.hasMeaningfulPendingMessageContent(info.message)) {
        discardMessageIds.push(info.message.id)
        return
      }
      // stop 后持久化的消息应结束生成/搜索状态
      info.message.isGenerating = false
      info.message.isSearching = false
      entries.push(info)
    })

    for (let i = 0; i < discardMessageIds.length; i++) {
      this.clearPendingAIMessageIfMatches(discardMessageIds[i])
      console.info('ChatViewModel', `Discard empty pending AI message on stop: ${discardMessageIds[i]}`)
    }

    for (let i = 0; i < entries.length; i++) {
      const info = entries[i]
      // 避免重复插入
      info.persisted = true

      const msgToSave = info.message
      const sessionId = info.sessionId
      const messageId = msgToSave.id
      ;(async () => {
        try {
          await this.databaseService.addMessage(sessionId, msgToSave)
          this.clearPendingAIMessageIfMatches(messageId)
          console.info('ChatViewModel', `Pending AI message persisted on stop: ${messageId}`)
        } catch (e) {
          console.error('ChatViewModel', `Failed to persist pending AI message: ${JSON.stringify(e)}`)
          // 失败时允许后续再尝试
          const failedInfo = this.pendingAIMessages.get(messageId)
          if (failedInfo !== undefined) {
            failedInfo.persisted = false
          }
        }
      })()
    }
  }

  private registerActiveRequest(requestId: string, httpRequest: http.HttpRequest, cancelCallback: () => void): void {
    this.activeRequests.set(requestId, {
      httpRequest: httpRequest,
      cancelCallback: cancelCallback
    } as ActiveRequestInfo)
  }

  private unregisterActiveRequest(requestId: string): void {
    this.activeRequests.delete(requestId)
  }

  // 创建新会话
  async createNewSession(title: string = ''): Promise<ChatSession> {
    const session = await this.sessionStore.createNewSession(title)
    this.currentSession = this.sessionStore.getCurrentSession()
    return session
  }

  // 创建待持久化的会话（仅内存中，不保存到数据库）
  createPendingSession(title: string = ''): ChatSession {
    const session = this.sessionStore.createPendingSession(title)
    this.currentSession = this.sessionStore.getCurrentSession()
    return session
  }

  // 持久化待处理的会话
  private async persistPendingSession(): Promise<void> {
    await this.sessionStore.persistPendingSession()
    this.currentSession = this.sessionStore.getCurrentSession()
  }

  // 加载会话
  async loadSession(sessionId: string): Promise<ChatSession | null> {
    const session = await this.sessionStore.loadSession(sessionId)
    if (session !== null) {
      const messages = session.messages

      // 如果有尚未落库的 AI 占位消息（例如用户在模型响应前退出页面），合并到会话消息中，避免”返回再进来没有模型信息”
      this.pendingAIMessages.forEach((info: PendingAIMessageInfo) => {
        if (info.sessionId === sessionId) {
          let exists = false
          for (let i = 0; i < messages.length; i++) {
            if (messages[i].id === info.message.id) {
              exists = true
              break
            }
          }
          if (!exists) {
            messages.push(info.message)
          }
        }
      })

      session.messages = messages
      this.currentSession = session
      this.sessionStore.setCurrentSession(session)
    }
    return session
  }

  // 获取所有会话
  async getAllSessions(): Promise<ChatSession[]> {
    return await this.sessionStore.getAllSessions()
  }

  // 删除会话
  async deleteSession(sessionId: string): Promise<void> {
    await this.sessionStore.deleteSession(sessionId)
    this.currentSession = this.sessionStore.getCurrentSession()
  }

  // 获取当前会话
  getCurrentSession(): ChatSession | null {
    this.currentSession = this.sessionStore.getCurrentSession()
    return this.currentSession
  }

  async toggleSessionFavorite(sessionId: string): Promise<boolean> {
    const isFavorite = await this.sessionStore.toggleSessionFavorite(sessionId)
    this.currentSession = this.sessionStore.getCurrentSession()
    return isFavorite
  }

  // 发送消息并获取 AI 回复
  async sendMessage(
    content: string,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    attachments: MessageAttachment[] = [],
    contextStartIndex: number = 0,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    apiPath?: string  // 可选的自定义 API 路径
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    // 首次发送消息时，先持久化待处理的会话
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 如果仍然没有当前会话，创建新的
    if (this.currentSession === null) {
      await this.createNewSession()
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession，避免并发请求时会话被覆盖
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)

    // 创建用户消息
    const userMessage = new ChatMessage(
      this.generateId(),
      MessageRole.USER,
      content,
      ''
    )
    // 添加附件到用户消息
    if (attachments.length > 0) {
      for (let i = 0; i < attachments.length; i++) {
        userMessage.attachments.push(attachments[i])
      }
    }

    // 通知 UI 添加用户消息（优先渲染，避免”返回再进来只剩用户消息/无模型信息”）
    onUserMessageAdded(userMessage)

    // 提前创建 AI 消息占位符：如果用户在模型响应前退出页面，stopGeneration 仍能持久化该消息
    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.isGenerating = true
    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    // 保存用户消息到数据库
    if (snapshotSession !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
      if (shouldAutoGenerateTitle) {
        const title = content.length > 20 ? content.substring(0, 20) + '...' : content
        snapshotSession.title = title
        await this.databaseService.updateSessionTitle(snapshotSessionId, title)
        this.notifySessionListChanged()
      }
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建请求消息列表（从上下文起始位置开始，过滤掉上下文清空标记）
    const requestMessages: RequestMessage[] = []
    const renderedSystemPrompt = await this.getRenderedSystemPrompt()
    requestMessages.push(new RequestMessage('system', renderedSystemPrompt))
    for (let i = contextStartIndex; i < messages.length; i++) {
      const msg = messages[i]
      if (msg.role === MessageRole.SYSTEM) {
        continue
      }
      requestMessages.push(new RequestMessage(msg.role, msg.content, msg.attachments))
    }
    requestMessages.push(new RequestMessage('user', content, attachments))

    // 懒加载历史附件
    await this.prepareHistoryAttachments(requestMessages)
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建 API 配置
    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: getEffectiveApiKey(providerId, apiKey),
      baseUrl: baseUrl,
      apiPath: apiPath
    }

    const modelParams = this.getCurrentModelParameters(providerId, modelId)
    if (modelParams !== null) {
      apiConfig.topP = modelParams.topP
      apiConfig.presencePenalty = modelParams.presencePenalty
      apiConfig.frequencyPenalty = modelParams.frequencyPenalty
    }

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let hasReceivedFirstChunk = false
    const localFirstChunkThrottle = createThrottle(50)
    const localContentThrottle = createThrottle(150)
    const localReasoningThrottle = createThrottle(150)
    const requestId = this.generateId()

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 发送流式请求
    const httpRequest = this.aiApiService.streamChatRequest(
      apiConfig,
      requestMessages,
      modelId,
      (contentChunk: string) => {
        if (cancelled) {
          return
        }
        if (!hasReceivedFirstChunk) {
          localFirstChunkThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
            hasReceivedFirstChunk = true
          })
        } else {
          localContentThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          })
        }
      },
      async () => {
        if (cancelled) {
          return
        }
        // 刷新节流器
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })

        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        if (snapshotSession !== null) {
          await this.databaseService.addMessage(snapshotSessionId, aiMessage)
          this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
          this.markPendingAIMessagePersisted(aiMessage.id)
          this.clearPendingAIMessageIfMatches(aiMessage.id)

          if (shouldAutoGenerateTitle) {
            this.generateSmartTitle(snapshotSession)
          }
        }
        this.unregisterActiveRequest(requestId)
        onComplete()
      },
      (error: string) => {
        if (cancelled) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        if (userCancelled) {
          console.info('ChatViewModel', 'Request cancelled by user')
          onComplete()
        } else {
          onError(error)
        }
        this.clearPendingAIMessageIfMatches(aiMessage.id)
        this.unregisterActiveRequest(requestId)
      },
      this.appStateManager.getDefaultTemperature(),
      this.appStateManager.getDefaultMaxTokens(),
      (reasoningContent: string) => {
        if (cancelled) {
          return
        }
        localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
          if (cancelled) {
            return
          }
          aiMessage.reasoningContent += throttledContent
          onAIMessageUpdated(aiMessage)
        })
      },
      async (base64Data: string, mimeType: string) => {
        if (cancelled) {
          return
        }
        console.info('ChatViewModel', `Received AI generated image: ${mimeType}, size: ${base64Data.length}`)
        try {
          const attachmentId = `ai_img_${Date.now()}`
          const ext = this.getExtensionFromMimeType(mimeType)
          const fileName = `generated_${Date.now()}${ext}`

          const attachment = new MessageAttachment(
            attachmentId,
            AttachmentType.IMAGE,
            fileName,
            '',
            mimeType,
            Math.floor(base64Data.length * 0.75)
          )
          attachment.base64Data = base64Data

          if (this.attachmentStorageService.isReady()) {
            const filePath = await this.attachmentStorageService.saveAttachment(attachment)
            attachment.filePath = filePath
            console.info('ChatViewModel', `AI generated image saved to: ${filePath}`)
          } else {
            console.warn('ChatViewModel', 'AttachmentStorageService not ready, image not persisted to file')
          }

          aiMessage.addAttachment(attachment)
          onAIMessageUpdated(aiMessage)
        } catch (error) {
          console.error('ChatViewModel', `Failed to save AI generated image: ${JSON.stringify(error)}`)
        }
      },
      reasoningLevel
    )

    // 注册到活跃请求 Map
    this.registerActiveRequest(requestId, httpRequest, () => {
      cancelled = true
      userCancelled = true
      localFirstChunkThrottle.reset()
      localContentThrottle.reset()
      localReasoningThrottle.reset()
    })
  }

  // 带网页上下文发送消息
  async sendMessageWithWebContext(
    content: string,
    webContext: WebSearchResult,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    attachments: MessageAttachment[],
    contextStartIndex: number,
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    apiPath?: string  // 可选的自定义 API 路径
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    if (this.currentSession === null) {
      await this.createNewSession()
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)

    // 构建系统提示（包含网页内容）
    const systemPrompt = `用户提供了以下网页内容供参考：

标题：${webContext.title}
来源：${webContext.url}
正文：
${webContext.content}

请基于以上网页内容回答用户的问题。如果网页内容不完整或无法回答，请告知用户。`

    // 创建用户消息
    const userMessage = new ChatMessage(
      this.generateId(),
      MessageRole.USER,
      content,
      ''
    )
    for (let i = 0; i < attachments.length; i++) {
      userMessage.attachments.push(attachments[i])
    }

    onUserMessageAdded(userMessage)

    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.isGenerating = true
    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    if (snapshotSession !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建请求消息列表
    const requestMessages: RequestMessage[] = []
    const renderedSystemPromptWeb = await this.getRenderedSystemPrompt()
    const finalSystemPromptWeb = `${renderedSystemPromptWeb}\n\n${systemPrompt}`
    requestMessages.push(new RequestMessage('system', finalSystemPromptWeb))

    for (let i = contextStartIndex; i < messages.length; i++) {
      const msg = messages[i]
      if (msg.role === MessageRole.SYSTEM) {
        continue
      }
      requestMessages.push(new RequestMessage(msg.role, msg.content, msg.attachments))
    }
    requestMessages.push(new RequestMessage('user', content, attachments))

    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: apiKey,
      baseUrl: baseUrl
    }

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let hasReceivedFirstChunk = false
    const localFirstChunkThrottle = createThrottle(50)
    const localContentThrottle = createThrottle(150)
    const localReasoningThrottle = createThrottle(150)
    const requestId = this.generateId()

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    const httpRequest = this.aiApiService.streamChatRequest(
      apiConfig,
      requestMessages,
      modelId,
      (contentChunk: string) => {
        if (cancelled) {
          return
        }
        if (!hasReceivedFirstChunk) {
          localFirstChunkThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
            hasReceivedFirstChunk = true
          })
        } else {
          localContentThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          })
        }
      },
      async () => {
        if (cancelled) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)
        if (snapshotSession !== null) {
          await this.databaseService.addMessage(snapshotSessionId, aiMessage)
          this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
          this.markPendingAIMessagePersisted(aiMessage.id)
          this.clearPendingAIMessageIfMatches(aiMessage.id)
          if (shouldAutoGenerateTitle) {
            this.generateSmartTitle(snapshotSession)
          }
        }
        this.unregisterActiveRequest(requestId)
        onComplete()
      },
      (error: string) => {
        if (cancelled) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        if (userCancelled) {
          console.info('ChatViewModel', 'Request cancelled by user')
          onComplete()
        } else {
          onError(error)
        }
        this.clearPendingAIMessageIfMatches(aiMessage.id)
        this.unregisterActiveRequest(requestId)
      },
      this.appStateManager.getDefaultTemperature(),
      this.appStateManager.getDefaultMaxTokens(),
      (reasoningContent: string) => {
        if (cancelled) {
          return
        }
        localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
          if (cancelled) {
            return
          }
          aiMessage.reasoningContent += throttledContent
          onAIMessageUpdated(aiMessage)
        })
      },
      async (base64Data: string, mimeType: string) => {
        if (cancelled) {
          return
        }
        console.info('ChatViewModel', `Received AI generated image: ${mimeType}`)
      }
    )

    // 注册到活跃请求 Map
    this.registerActiveRequest(requestId, httpRequest, () => {
      cancelled = true
      userCancelled = true
      localFirstChunkThrottle.reset()
      localContentThrottle.reset()
      localReasoningThrottle.reset()
    })
  }

  // 带搜索结果上下文发送消息（新版）
  async sendMessageWithSearchResult(
    content: string,
    searchResult: SearchResult,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    attachments: MessageAttachment[],
    contextStartIndex: number,
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    apiPath?: string  // 可选的自定义 API 路径
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    if (this.currentSession === null) {
      await this.createNewSession()
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)

    // 构建系统提示（包含搜索内容和当前时间）
    const currentTime = this.getCurrentTimeContext()
    const limitedSearchContext = this.limitSearchContextForPrompt(searchResult.contentForAI, 5000)
    const systemPrompt = `当前时间: ${currentTime}

用户进行了联网搜索,以下是搜索结果供参考:

${limitedSearchContext}

回答规则(非常重要):
1. 如果搜索结果/抓取正文中已经包含回答所需的信息(例如天气的温度/风力/AQI等具体数值),请直接整理并回答,不要再让用户去别的网站查询。
2. 只有当搜索结果中确实缺少关键数据时,才说明"未找到"并建议进一步查询。
3. 如果用户询问"今天"、"现在"等相对时间,请使用上述当前时间作为参考。
4. 若回答中需要写出"今天是X年X月X日",必须与"当前时间"保持一致,不得改成其他日期。`

    console.info('ChatViewModel', `[搜索上下文] 当前时间: ${currentTime}`)
    console.info('ChatViewModel', `[搜索上下文] 搜索查询: ${searchResult.query}`)
    console.info('ChatViewModel', `[搜索上下文] 系统提示长度: ${systemPrompt.length} 字符`)
    console.info('ChatViewModel', `[搜索上下文] 预览: ${systemPrompt.substring(0, 240)}...`)

    // 创建用户消息
    const userMessage = new ChatMessage(
      this.generateId(),
      MessageRole.USER,
      content,
      ''
    )
    for (let i = 0; i < attachments.length; i++) {
      userMessage.attachments.push(attachments[i])
    }

    // 添加搜索引用数据和查询内容
    userMessage.searchQuery = searchResult.query
    userMessage.searchEngine = searchResult.searchEngine || 'Web'
    userMessage.searchSource = 'manual'
    userMessage.isSearching = false  // 搜索已完成
    for (let i = 0; i < searchResult.references.length; i++) {
      userMessage.searchReferences.push(searchResult.references[i])
    }

    onUserMessageAdded(userMessage)

    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.isGenerating = true

    // 将搜索引用数据复制到 AI 消息，确保 SearchReferenceCard 可以正确显示
    aiMessage.searchQuery = searchResult.query
    aiMessage.searchEngine = searchResult.searchEngine || 'Web'
    aiMessage.searchSource = 'manual'
    for (let i = 0; i < searchResult.references.length; i++) {
      aiMessage.searchReferences.push(searchResult.references[i])
    }

    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    if (snapshotSession !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建请求消息列表
    const requestMessages: RequestMessage[] = []
    const renderedSystemPromptSearch = await this.getRenderedSystemPrompt()
    const finalSystemPromptSearch = `${renderedSystemPromptSearch}\n\n${systemPrompt}`
    requestMessages.push(new RequestMessage('system', finalSystemPromptSearch))

    for (let i = contextStartIndex; i < messages.length; i++) {
      const msg = messages[i]
      if (msg.role === MessageRole.SYSTEM) {
        continue
      }
      requestMessages.push(new RequestMessage(msg.role, msg.content, msg.attachments))
    }
    requestMessages.push(new RequestMessage('user', content, attachments))

    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: apiKey,
      baseUrl: baseUrl
    }

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let hasReceivedFirstChunk = false
    const localFirstChunkThrottle = createThrottle(50)
    const localContentThrottle = createThrottle(150)
    const localReasoningThrottle = createThrottle(150)
    const requestId = this.generateId()

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    const httpRequest = this.aiApiService.streamChatRequest(
      apiConfig,
      requestMessages,
      modelId,
      (contentChunk: string) => {
        if (cancelled) {
          return
        }
        if (!hasReceivedFirstChunk) {
          localFirstChunkThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
            hasReceivedFirstChunk = true
          })
        } else {
          localContentThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          })
        }
      },
      async () => {
        if (cancelled) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)
        if (snapshotSession !== null) {
          await this.databaseService.addMessage(snapshotSessionId, aiMessage)
          this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
          this.markPendingAIMessagePersisted(aiMessage.id)
          this.clearPendingAIMessageIfMatches(aiMessage.id)
          if (shouldAutoGenerateTitle) {
            this.generateSmartTitle(snapshotSession)
          }
        }
        this.unregisterActiveRequest(requestId)
        onComplete()
      },
      (error: string) => {
        if (cancelled) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        if (userCancelled) {
          console.info('ChatViewModel', 'Request cancelled by user')
          onComplete()
        } else {
          onError(error)
        }
        this.clearPendingAIMessageIfMatches(aiMessage.id)
        this.unregisterActiveRequest(requestId)
      },
      this.appStateManager.getDefaultTemperature(),
      this.appStateManager.getDefaultMaxTokens(),
      (reasoningContent: string) => {
        if (cancelled) {
          return
        }
        localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
          if (cancelled) {
            return
          }
          aiMessage.reasoningContent += throttledContent
          onAIMessageUpdated(aiMessage)
        })
      },
      async (base64Data: string, mimeType: string) => {
        if (cancelled) {
          return
        }
        console.info('ChatViewModel', `Received AI generated image: ${mimeType}`)
        try {
          const attachmentId = `ai_img_${Date.now()}`
          const ext = this.getExtensionFromMimeType(mimeType)
          const fileName = `generated_${Date.now()}${ext}`

          const attachment = new MessageAttachment(
            attachmentId,
            AttachmentType.IMAGE,
            fileName,
            '',
            mimeType,
            Math.floor(base64Data.length * 0.75)
          )
          attachment.base64Data = base64Data

          if (this.attachmentStorageService.isReady()) {
            const filePath = await this.attachmentStorageService.saveAttachment(attachment)
            attachment.filePath = filePath
            console.info('ChatViewModel', `AI generated image saved to: ${filePath}`)
          } else {
            console.warn('ChatViewModel', 'AttachmentStorageService not ready, image not persisted to file')
          }

          aiMessage.addAttachment(attachment)
          onAIMessageUpdated(aiMessage)
        } catch (error) {
          console.error('ChatViewModel', `Failed to save AI generated image: ${JSON.stringify(error)}`)
        }
      },
      reasoningLevel
    )

    // 注册到活跃请求 Map
    this.registerActiveRequest(requestId, httpRequest, () => {
      cancelled = true
      userCancelled = true
      localFirstChunkThrottle.reset()
      localContentThrottle.reset()
      localReasoningThrottle.reset()
    })
  }

  // 发送消息并使用 Function Calling 工具
  async sendMessageWithTools(
    content: string,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    attachments: MessageAttachment[] = [],
    contextStartIndex: number = 0,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    tools: ToolDefinition[] = [],
    toolCallbacks?: ToolCallCallbacks,
    apiPath?: string  // 可选的自定义 API 路径
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    // 首次发送消息时，先持久化待处理的会话
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 如果仍然没有当前会话，创建新的
    if (this.currentSession === null) {
      await this.createNewSession()
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)

    // 创建用户消息
    const userMessage = new ChatMessage(
      this.generateId(),
      MessageRole.USER,
      content,
      ''
    )
    // 添加附件到用户消息
    if (attachments.length > 0) {
      for (let i = 0; i < attachments.length; i++) {
        userMessage.attachments.push(attachments[i])
      }
    }

    // 通知 UI 添加用户消息（优先渲染）
    onUserMessageAdded(userMessage)

    // 提前创建 AI 消息占位符，确保中途退出页面也能恢复模型信息/重新生成
    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.isGenerating = true

    // 检测启用了哪些工具（用于构建 system prompt）
    let hasWebSearchTool = false
    let hasWeatherQueryTool = false
    for (let i = 0; i < tools.length; i++) {
      if (tools[i].function.name === 'web_search') {
        hasWebSearchTool = true
      }
      if (tools[i].function.name === 'weather_query') {
        hasWeatherQueryTool = true
      }
      if (hasWebSearchTool && hasWeatherQueryTool) {
        break
      }
    }

    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    // 保存用户消息到数据库
    if (snapshotSession !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
      if (shouldAutoGenerateTitle) {
        const title = content.length > 20 ? content.substring(0, 20) + '...' : content
        snapshotSession.title = title
        await this.databaseService.updateSessionTitle(snapshotSessionId, title)
        this.notifySessionListChanged()
      }
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建请求消息列表
    const requestMessages: RequestMessage[] = []
    const currentTime = this.getCurrentTimeContext()
    let toolUsageSystemPrompt = `当前时间: ${currentTime}

你是一个智能助手，具备联网查询能力。你的首要任务是直接回答用户问题，只在确实需要实时信息时才调用工具。

工具使用规则(非常重要):
- 绝大多数问题不需要调用工具，请优先用自身知识直接回答。
- 仅当用户问题明确需要实时数据（如今日天气、最新新闻、实时股价等）时才调用工具。
- 编程、写作、翻译、数学、创意等任务绝对不要调用任何工具，直接回答即可。`
    if (hasWeatherQueryTool) {
      toolUsageSystemPrompt += `
- 当用户询问天气/气温/降雨/风力/AQI 等信息时，优先调用 weather_query。
- 调用 weather_query 时: location 只填地点名称，days 取 1-7，unit 仅用 celsius/fahrenheit。`
    }
    if (hasWebSearchTool) {
      toolUsageSystemPrompt += `
- 针对同一个用户问题，最多调用 web_search 1 次;如需多个关键词，请合并为一次查询。
- 生成 web_search.query 时优先保留用户原始关键词，不要擅自改写实体、地点和时间。`
    }
    toolUsageSystemPrompt += `
- 若用户提到“今天/昨天/明天/现在/最新”等相对时间，请以当前时间为基准理解，不要编造不一致的绝对日期。
- 工具返回后必须给出最终回答，不要在没有必要的情况下重复调用工具。
- 回答时请优先提取并明确给出具体数值（如温度、降水概率、湿度、风速、AQI）。`
    const renderedSystemPromptTools = await this.getRenderedSystemPrompt()
    const finalToolUsageSystemPrompt = `${renderedSystemPromptTools}\n\n${toolUsageSystemPrompt}`
    requestMessages.push(new RequestMessage('system', finalToolUsageSystemPrompt))
    for (let i = contextStartIndex; i < messages.length; i++) {
      const msg = messages[i]
      if (msg.role === MessageRole.SYSTEM) {
        continue
      }
      requestMessages.push(new RequestMessage(msg.role, msg.content, msg.attachments))
    }
    requestMessages.push(new RequestMessage('user', content, attachments))

    // 懒加载历史附件
    await this.prepareHistoryAttachments(requestMessages)
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建 API 配置
    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: getEffectiveApiKey(providerId, apiKey),
      baseUrl: baseUrl,
      apiPath: apiPath
    }

    const modelParams = this.getCurrentModelParameters(providerId, modelId)
    if (modelParams !== null) {
      apiConfig.topP = modelParams.topP
      apiConfig.presencePenalty = modelParams.presencePenalty
      apiConfig.frequencyPenalty = modelParams.frequencyPenalty
    }

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let toolExecutionCancelled = false
    let hasReceivedFirstChunk = false
    const localFirstChunkThrottle = createThrottle(50)
    const localContentThrottle = createThrottle(150)
    const localReasoningThrottle = createThrottle(150)
    const requestId = this.generateId()

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 先注册到活跃请求 Map（使用占位 httpRequest，executeToolCallLoop 内部会更新实际引用）
    // 必须在 await 之前注册，否则 stopGeneration 无法取消正在执行的请求
    const placeholderHttp = http.createHttp()
    this.registerActiveRequest(requestId, placeholderHttp, () => {
      cancelled = true
      userCancelled = true
      toolExecutionCancelled = true
      localFirstChunkThrottle.reset()
      localContentThrottle.reset()
      localReasoningThrottle.reset()
    })

    // 开始工具调用循环
    await this.executeToolCallLoop(
      apiConfig,
      requestMessages,
      modelId,
      aiMessage,
      onAIMessageUpdated,
      onComplete,
      onError,
      tools,
      toolCallbacks,
      reasoningLevel,
      0,  // 初始迭代次数
      snapshotSessionId,
      snapshotSession,
      shouldAutoGenerateTitle,
      requestId,
      () => cancelled,
      () => userCancelled,
      () => toolExecutionCancelled,
      (v: boolean) => { userCancelled = v },
      () => hasReceivedFirstChunk,
      (v: boolean) => { hasReceivedFirstChunk = v },
      localFirstChunkThrottle,
      localContentThrottle,
      localReasoningThrottle
    )
  }

  private fillFallbackFromSearchSummaryIfNeeded(aiMessage: ChatMessage): void {
    if (aiMessage.content.trim() !== '' || aiMessage.toolResults.length === 0) {
      return
    }

    for (let i = aiMessage.toolResults.length - 1; i >= 0; i--) {
      try {
        const data = JSON.parse(aiMessage.toolResults[i].content) as SearchResultData
        if (data !== undefined && data.summary !== undefined && data.summary.trim() !== '') {
          let preview = data.summary.trim()
          const maxLen = 1200
          if (preview.length > maxLen) {
            preview = preview.substring(0, maxLen) + '...'
          }
          aiMessage.content = `已完成联网搜索，但模型未返回最终回答。以下为搜索结果摘要（可用于人工查看/再次提问）：\n\n${preview}`
          return
        }
      } catch (e) {
        // ignore
      }
    }
  }

  // 工具调用循环
  private async executeToolCallLoop(
    apiConfig: AIApiConfig,
    requestMessages: RequestMessage[],
    modelId: string,
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    tools: ToolDefinition[],
    toolCallbacks: ToolCallCallbacks | undefined,
    reasoningLevel: ReasoningLevel,
    iteration: number,
    snapshotSessionId: string,
    snapshotSession: ChatSession | null,
    shouldAutoGenerateTitle: boolean,
    requestId: string,
    isCancelledFn: () => boolean,
    isUserCancelledFn: () => boolean,
    isToolCancelledFn: () => boolean,
    setUserCancelled: (v: boolean) => void,
    getHasReceivedFirstChunk: () => boolean,
    setHasReceivedFirstChunk: (v: boolean) => void,
    localFirstChunkThrottle: ThrottleUtil,
    localContentThrottle: ThrottleUtil,
    localReasoningThrottle: ThrottleUtil
  ): Promise<void> {
    if (isCancelledFn()) {
      return
    }

    const toolsEnabledInThisRound = iteration < this.MAX_TOOL_ITERATIONS
    if (!toolsEnabledInThisRound) {
      console.warn('ChatViewModel', `Max tool iterations (${this.MAX_TOOL_ITERATIONS}) reached, forcing final answer without tools`)
    }

    console.info('ChatViewModel', `Tool call loop iteration ${iteration + 1}`)

    // 检查是否已取消
    if (isToolCancelledFn()) {
      console.info('ChatViewModel', 'Tool execution cancelled by user')
      aiMessage.isGenerating = false
      onAIMessageUpdated(aiMessage)
      onComplete()
      return
    }

    // 设置取消检查回调
    this.toolExecutionService.setCancelCheckCallback(isToolCancelledFn)

    // 发送流式请求（带工具）
    const httpRequest = this.aiApiService.streamChatRequestWithTools(
      apiConfig,
      requestMessages,
      modelId,
      (contentChunk: string) => {
        if (isCancelledFn()) {
          return
        }
        if (!getHasReceivedFirstChunk()) {
          localFirstChunkThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (isCancelledFn()) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
            setHasReceivedFirstChunk(true)
          })
        } else {
          localContentThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (isCancelledFn()) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          })
        }
      },
      async (toolCalls: ToolCall[]) => {
        if (isCancelledFn()) {
          return
        }
        // 刷新节流器
        localContentThrottle.flush((throttledContent: string) => {
          if (isCancelledFn()) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (isCancelledFn()) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (isCancelledFn()) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        setHasReceivedFirstChunk(false)

        // 检查是否有工具调用
        if (toolCalls.length > 0 && toolsEnabledInThisRound) {
          console.info('ChatViewModel', `[Function Calling] Received ${toolCalls.length} tool calls`)
          const latestUserQuery = this.getLatestUserQueryFromRequestMessages(requestMessages)

          // 保存工具调用到 AI 消息
          for (let i = 0; i < toolCalls.length; i++) {
            if (this.isWebSearchFunction(toolCalls[i].functionName)) {
              const normalizedSearchQuery = this.normalizeWebSearchToolCallQuery(toolCalls[i], latestUserQuery)
              if (normalizedSearchQuery !== '') {
                console.info('ChatViewModel', `[Function Calling] normalized web_search query="${normalizedSearchQuery}"`)
              }
            }
            aiMessage.toolCalls.push(toolCalls[i])
          }
          onAIMessageUpdated(aiMessage)

          // 通知工具调用开始
          if (toolCallbacks !== undefined && toolCallbacks.onToolCallStarted !== undefined) {
            toolCallbacks.onToolCallStarted(toolCalls)
          }

          // 检查是否是搜索工具，更新搜索状态
          for (let i = 0; i < toolCalls.length; i++) {
            if (this.isWebSearchFunction(toolCalls[i].functionName)) {
              aiMessage.searchSource = 'tool'
              aiMessage.isSearching = true
              try {
                const args = JSON.parse(toolCalls[i].arguments) as WebSearchArgs
                aiMessage.searchQuery = args.query
                console.info('ChatViewModel', `[Function Calling] web_search(query="${args.query}")`)
                if (toolCallbacks !== undefined && toolCallbacks.onSearching !== undefined) {
                  toolCallbacks.onSearching(args.query)
                }
              } catch (e) {
                console.warn('ChatViewModel', `Failed to parse web_search args: ${JSON.stringify(e)}`)
              }
              onAIMessageUpdated(aiMessage)
              break
            }
          }

          // 执行工具调用
          const toolResults = await this.toolExecutionService.executeToolCalls(toolCalls)
          if (isCancelledFn()) {
            return
          }

          // 检查工具执行是否被取消
          if (toolResults.length > 0 && toolResults[0].content.includes('"cancelled":true')) {
            console.info('ChatViewModel', 'Tool execution was cancelled')
            aiMessage.isGenerating = false
            onAIMessageUpdated(aiMessage)
            onComplete()
            this.toolExecutionService.clearCancelCheckCallback()
            return
          }

          // 保存工具结果到 AI 消息
          for (let i = 0; i < toolResults.length; i++) {
            aiMessage.toolResults.push(toolResults[i])
          }

          // 持久化工具事件到数据库（使用快照 sessionId）
          if (snapshotSession !== null) {
            for (let i = 0; i < toolCalls.length; i++) {
              if (isCancelledFn()) {
                return
              }
              const result = i < toolResults.length ? toolResults[i] : null
              const status = result !== null && result.content !== '' ? 'completed' : 'pending'
              await this.databaseService.saveToolEvent(
                snapshotSessionId,
                aiMessage.id,
                toolCalls[i].id,
                toolCalls[i].functionName,
                toolCalls[i].arguments,
                result !== null ? result.content : '',
                status
              )
            }
          }

          // 处理搜索结果，提取引用
          for (let i = 0; i < toolCalls.length; i++) {
            if (this.isWebSearchFunction(toolCalls[i].functionName)) {
              const result = toolResults[i]
              try {
                const searchData = JSON.parse(result.content) as SearchResultData
                if (searchData.results !== undefined) {
                  if (searchData.query !== undefined && searchData.query !== '') {
                    aiMessage.searchQuery = searchData.query
                  }
                  aiMessage.searchEngine = searchData.searchEngine || 'Web'
                  aiMessage.searchSource = 'tool'
                  if (searchData.query !== undefined && searchData.query !== '') {
                    console.info('ChatViewModel', `[Function Calling] web_search result query="${searchData.query}"`)
                  }
                  for (let j = 0; j < searchData.results.length; j++) {
                    const item = searchData.results[j]
                    const ref = new SearchReference(
                      `ref_${Date.now()}_${j}`,
                      item.title,
                      item.url,
                      item.snippet
                    )
                    aiMessage.searchReferences.push(ref)
                  }
                }
              } catch (e) {
                console.warn('ChatViewModel', `Failed to parse search result: ${JSON.stringify(e)}`)
              }
              aiMessage.isSearching = false
              break
            }
          }
          onAIMessageUpdated(aiMessage)

          // 通知工具调用完成
          if (toolCallbacks !== undefined && toolCallbacks.onToolCallCompleted !== undefined) {
            toolCallbacks.onToolCallCompleted(toolResults)
          }

          // 构建下一轮请求消息
          const assistantMsg = RequestMessage.createAssistantWithToolCalls(aiMessage.content, toolCalls)
          requestMessages.push(assistantMsg)

          for (let i = 0; i < toolResults.length; i++) {
            const toolResultMsg = RequestMessage.createToolResultMessage(
              toolResults[i].toolCallId,
              toolResults[i].content
            )
            requestMessages.push(toolResultMsg)
          }

          // 清空 AI 消息内容，准备接收新的回复
          aiMessage.content = ''
          onAIMessageUpdated(aiMessage)

          // 继续下一轮
          await this.executeToolCallLoop(
            apiConfig,
            requestMessages,
            modelId,
            aiMessage,
            onAIMessageUpdated,
            onComplete,
            onError,
            tools,
            toolCallbacks,
            reasoningLevel,
            iteration + 1,
            snapshotSessionId,
            snapshotSession,
            shouldAutoGenerateTitle,
            requestId,
            isCancelledFn,
            isUserCancelledFn,
            isToolCancelledFn,
            setUserCancelled,
            getHasReceivedFirstChunk,
            setHasReceivedFirstChunk,
            localFirstChunkThrottle,
            localContentThrottle,
            localReasoningThrottle
          )
        } else {
          if (toolCalls.length > 0) {
            console.warn('ChatViewModel', `Ignored ${toolCalls.length} tool calls because tool round limit is reached`)
          }
          // 没有工具调用，完成
          this.fillFallbackFromSearchSummaryIfNeeded(aiMessage)
          aiMessage.isGenerating = false
          aiMessage.isSearching = false
          onAIMessageUpdated(aiMessage)

          if (snapshotSession !== null) {
            await this.databaseService.addMessage(snapshotSessionId, aiMessage)
            this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
            this.markPendingAIMessagePersisted(aiMessage.id)
            this.clearPendingAIMessageIfMatches(aiMessage.id)
            if (shouldAutoGenerateTitle) {
              this.generateSmartTitle(snapshotSession)
            }
          }
          this.unregisterActiveRequest(requestId)
          onComplete()
        }
      },
      (error: string) => {
        if (isCancelledFn()) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (isCancelledFn()) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (isCancelledFn()) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (isCancelledFn()) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        aiMessage.isGenerating = false
        aiMessage.isSearching = false
        onAIMessageUpdated(aiMessage)

        if (isUserCancelledFn()) {
          setUserCancelled(false)
          console.info('ChatViewModel', 'Request cancelled by user')
          onComplete()
        } else {
          onError(error)
        }
        this.clearPendingAIMessageIfMatches(aiMessage.id)
        this.unregisterActiveRequest(requestId)
      },
      this.appStateManager.getDefaultTemperature(),
      this.appStateManager.getDefaultMaxTokens(),
      (reasoningContent: string) => {
        if (isCancelledFn()) {
          return
        }
        localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
          if (isCancelledFn()) {
            return
          }
          aiMessage.reasoningContent += throttledContent
          onAIMessageUpdated(aiMessage)
        })
      },
      async (base64Data: string, mimeType: string) => {
        if (isCancelledFn()) {
          return
        }
        console.info('ChatViewModel', `Received AI generated image: ${mimeType}`)
        try {
          const attachmentId = `ai_img_${Date.now()}`
          const ext = this.getExtensionFromMimeType(mimeType)
          const fileName = `generated_${Date.now()}${ext}`

          const attachment = new MessageAttachment(
            attachmentId,
            AttachmentType.IMAGE,
            fileName,
            '',
            mimeType,
            Math.floor(base64Data.length * 0.75)
          )
          attachment.base64Data = base64Data

          if (this.attachmentStorageService.isReady()) {
            const filePath = await this.attachmentStorageService.saveAttachment(attachment)
            attachment.filePath = filePath
            console.info('ChatViewModel', `AI generated image saved to: ${filePath}`)
          } else {
            console.warn('ChatViewModel', 'AttachmentStorageService not ready, image not persisted to file')
          }

          aiMessage.addAttachment(attachment)
          onAIMessageUpdated(aiMessage)
        } catch (error) {
          console.error('ChatViewModel', `Failed to save AI generated image: ${JSON.stringify(error)}`)
        }
      },
      reasoningLevel,
      toolsEnabledInThisRound ? tools : undefined,
      toolsEnabledInThisRound ? 'auto' : undefined
    )

    // 更新活跃请求中的 httpRequest 引用（每轮循环可能创建新的 httpRequest）
    const existingInfo = this.activeRequests.get(requestId)
    if (existingInfo !== undefined) {
      existingInfo.httpRequest = httpRequest
    } else {
      this.registerActiveRequest(requestId, httpRequest, () => {
        // cancel 回调由 sendMessageWithTools 中注册的回调处理
      })
    }
  }

  // 根据 MIME 类型获取文件扩展名
  private getExtensionFromMimeType(mimeType: string): string {
    const mimeToExt: Record<string, string> = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'image/bmp': '.bmp'
    }
    return mimeToExt[mimeType] || '.png'
  }

  // 删除消息
  async deleteMessage(messageId: string): Promise<void> {
    await this.databaseService.deleteMessage(messageId)
    if (this.currentSession !== null) {
      const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageId)
      if (index >= 0) {
        this.currentSession.messages.splice(index, 1)
      }
    }
  }

  // 批量删除消息（用于重新生成功能）
  async deleteMessagesFromIndex(messageIds: string[]): Promise<void> {
    await this.databaseService.deleteMessagesByIds(messageIds)
    if (this.currentSession !== null) {
      // 从 currentSession.messages 中移除这些消息
      for (let i = 0; i < messageIds.length; i++) {
        const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageIds[i])
        if (index >= 0) {
          this.currentSession.messages.splice(index, 1)
        }
      }
    }
  }

  // 更新消息内容
  async updateMessageContent(messageId: string, content: string): Promise<void> {
    await this.databaseService.updateMessageContent(messageId, content)
    if (this.currentSession !== null) {
      const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageId)
      if (index >= 0) {
        this.currentSession.messages[index].content = content
      }
    }
  }

  // 更新消息内容和附件
  async updateMessageContentAndAttachments(
    messageId: string,
    content: string,
    attachments: MessageAttachment[]
  ): Promise<void> {
    // 更新数据库
    await this.databaseService.updateMessageContent(messageId, content)
    await this.databaseService.updateMessageAttachments(messageId, attachments)

    // 更新内存中的会话
    if (this.currentSession !== null) {
      const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageId)
      if (index >= 0) {
        this.currentSession.messages[index].content = content
        this.currentSession.messages[index].attachments = attachments.slice()
      }
    }
  }

  // 添加消息到数据库
  async addMessage(message: ChatMessage): Promise<void> {
    if (this.currentSession === null) {
      console.error('ChatViewModel', 'Cannot add message: no current session')
      return
    }
    await this.databaseService.addMessage(this.currentSession.id, message)
  }

  // 停止生成
  stopGeneration(): void {
    // 取消令牌前移：确保”仍在准备阶段的发送流程”也能被终止
    this.cancelToken = this.cancelToken + 1

    // 停止前持久化所有待处理的 AI 消息
    this.persistPendingAIMessageIfNeeded()

    // 遍历所有活跃请求，调用取消回调并销毁 HTTP 请求
    this.activeRequests.forEach((info: ActiveRequestInfo) => {
      info.cancelCallback()
      try {
        info.httpRequest.destroy()
      } catch (e) {
        // ignore destroy errors
      }
    })
    this.activeRequests.clear()

    // 重置 AIApiService 的解析状态（MiniMax 缓冲区等）
    this.aiApiService.resetThinkingState()

    console.info('ChatViewModel', 'Generation stopped and all buffers reset')
  }

  // 检查是否有活跃的请求
  hasActiveRequest(): boolean {
    return this.activeRequests.size > 0
  }

  // 检查指定会话是否存在活跃请求（用于页面恢复后还原发送/停止按钮状态）
  hasActiveRequestForSession(sessionId: string): boolean {
    if (sessionId === '') {
      return false
    }
    if (this.activeRequests.size === 0) {
      return false
    }
    let found = false
    this.pendingAIMessages.forEach((info: PendingAIMessageInfo) => {
      if (info.sessionId === sessionId) {
        found = true
      }
    })
    return found
  }

  // 生成唯一ID
  private generateId(): string {
    return Date.now().toString() + Math.random().toString(36).substring(2, 9)
  }

  // 获取格式化的当前时间信息
  private getCurrentTimeContext(): string {
    return buildCurrentTimeContext()
  }

  private limitSearchContextForPrompt(content: string, maxChars: number): string {
    const trimmed = content.trim()
    if (trimmed.length <= maxChars) {
      return trimmed
    }
    return trimmed.substring(0, maxChars) + '\n\n[搜索上下文已截断]'
  }

  private isWebSearchFunction(functionName: string): boolean {
    const raw = functionName as string | null | undefined
    if (raw === undefined || raw === null) {
      return false
    }
    const normalized = raw.trim().toLowerCase().replace(/[\s\-]+/g, '_')
    return normalized === 'web_search' || normalized === 'exa_search' || normalized === 'websearch'
      || normalized === 'search_web' || normalized === 'internet_search' || normalized === 'web_search_exa'
  }

  private getLatestUserQueryFromRequestMessages(requestMessages: RequestMessage[]): string {
    for (let i = requestMessages.length - 1; i >= 0; i--) {
      const msg = requestMessages[i]
      if (msg.role === 'user' && msg.content.trim() !== '') {
        return msg.content
      }
    }
    return ''
  }

  private normalizeWebSearchToolCallQuery(toolCall: ToolCall, latestUserQuery: string): string {
    let parsedQuery = ''
    try {
      const args = JSON.parse(toolCall.arguments) as WebSearchArgs
      if (args.query !== undefined) {
        parsedQuery = this.cleanSearchQuery(args.query)
      }
    } catch (error) {
      parsedQuery = ''
      console.warn('ChatViewModel', `Failed to parse search tool args before normalize: ${JSON.stringify(error)}`)
    }

    let finalQuery = parsedQuery
    if (latestUserQuery !== '') {
      finalQuery = this.normalizeRelativeTimeForSearchQuery(latestUserQuery, parsedQuery)
    }
    if (finalQuery === '' && latestUserQuery !== '') {
      finalQuery = this.cleanSearchQuery(latestUserQuery)
    }

    toolCall.functionName = 'web_search'
    toolCall.arguments = JSON.stringify({ query: finalQuery })
    return finalQuery
  }

  // 简单清洗搜索查询（去除口语化前缀、多余空格）
  cleanSearchQuery(query: string): string {
    return cleanSearchQueryShared(query)
  }

  normalizeRelativeTimeForSearchQuery(userQuery: string, candidateQuery: string): string {
    return normalizeRelativeTimeForSearchQueryShared(userQuery, candidateQuery)
  }

  private isWeatherIntent(text: string): boolean {
    const t = text.replace(/\s+/g, '')
    const keywords: string[] = [
      '天气', '天气预报', '气温', '温度', '降雨', '降水', '湿度', '风速', '风力', '空气质量', 'AQI', 'PM2.5'
    ]
    for (let i = 0; i < keywords.length; i++) {
      if (t.includes(keywords[i])) {
        return true
      }
    }
    return false
  }

  private isTravelIntent(text: string): boolean {
    const t = text.replace(/\s+/g, '')
    const keywords: string[] = [
      '旅游', '攻略', '自由行', '景点', '美食', '酒店', '住宿', '行程', '路线', 'CityWalk', 'City Walk'
    ]
    for (let i = 0; i < keywords.length; i++) {
      if (t.includes(keywords[i])) {
        return true
      }
    }
    return false
  }

  // 清洗模型输出：取第一行、去掉前缀/引号，保证可直接用于搜索
  private cleanOptimizedSearchQuery(text: string): string {
    let cleaned = text.trim()
    const lines = cleaned.split(/\r?\n/)
    cleaned = ''
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line !== '') {
        cleaned = line
        break
      }
    }
    if (cleaned === '') {
      return ''
    }

    cleaned = cleaned.replace(/^(优化后的(?:搜索)?关键词|搜索关键词|关键词|search query)\s*[:：]\s*/i, '')
    cleaned = cleaned.replace(/^[\"“'‘]+/, '').replace(/[\"”'’]+$/, '')
    return cleaned.trim()
  }

  private isOptimizedQueryAcceptable(userQuery: string, optimizedQuery: string): boolean {
    // 防止模型输出过长或跑题；必要时直接回退到用户原始输入
    if (optimizedQuery.trim() === '') {
      return false
    }
    if (optimizedQuery.length > 80) {
      return false
    }
    // 若用户明确问“天气/气温”等，优化结果也必须保持同一意图
    if (this.isWeatherIntent(userQuery) && !this.isWeatherIntent(optimizedQuery)) {
      return false
    }
    // 避免把“天气”等明确意图误改写为“旅游攻略”等
    if (this.isWeatherIntent(userQuery) && !this.isTravelIntent(userQuery) && this.isTravelIntent(optimizedQuery)) {
      return false
    }
    return true
  }

  // 优化搜索查询关键词：在调用搜索服务之前，将口语化输入改写为更适合检索的关键词
  async optimizeSearchQuery(
    userQuery: string,
    recentMessages: ChatMessage[],
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string
  ): Promise<string> {
    try {
      const cleanedUserQuery = this.cleanSearchQuery(userQuery)

      // 构建上下文（最近3条消息）
      let context = ''
      const contextMessages = recentMessages.slice(-3)
      for (let i = 0; i < contextMessages.length; i++) {
        const msg = contextMessages[i]
        context += `${msg.role === MessageRole.USER ? '用户' : 'AI'}: ${msg.content}\n`
      }

      const currentTime = this.getCurrentTimeContext()

      // 构建优化提示
      const systemPrompt = `你是一个“搜索关键词优化助手”。你的任务是将用户的口语化查询转换为适合搜索引擎的关键词。

规则（非常重要）:
1. 只做轻量优化：去口语化/补全指代/补全时间，不要改变用户意图，不要引入无关主题
2. 必须保留用户查询中的关键实体/地点/产品名/主题词（例如：天气/价格/汇率/新闻/教程等）
3. 如用户查询本身已是关键词（例如“西安天气”），直接原样输出
4. 解析指代词（如“那里”“这个”），结合对话历史替换为具体内容
5. 将相对时间（如“今天”“现在”）转换为具体日期
6. 输出要求：只输出“一行”关键词；不要解释、不要加引号、不要加序号或前缀

当前时间: ${currentTime}

对话历史:
${context !== '' ? context : '(无历史对话)'}

用户查询: ${cleanedUserQuery}

请直接输出优化后的搜索关键词:`

      console.info('ChatViewModel', `[关键词优化] 原始查询: ${userQuery}`)

      const apiConfig: AIApiConfig = {
        providerId: providerId,
        providerType: providerType,
        apiStyle: apiStyle,
        apiKey: apiKey,
        baseUrl: baseUrl
      }

      const messages: RequestMessage[] = [
        new RequestMessage('system', systemPrompt),
        new RequestMessage('user', cleanedUserQuery)
      ]

      // 使用非流式请求获取优化后的关键词
      const result = await this.aiApiService.sendChatRequest(apiConfig, messages, modelId, 0.3, 200)

      if (result.success && result.content.trim() !== '') {
        const optimized = this.cleanOptimizedSearchQuery(result.content)
        if (!this.isOptimizedQueryAcceptable(cleanedUserQuery, optimized)) {
          console.warn('ChatViewModel', `[关键词优化] 结果不可靠,回退原始查询. 原始: ${cleanedUserQuery}, 优化: ${optimized}`)
          return cleanedUserQuery
        }
        const finalQuery = this.cleanSearchQuery(optimized)
        console.info('ChatViewModel', `[关键词优化] 优化后查询: ${finalQuery}`)
        return finalQuery !== '' ? finalQuery : cleanedUserQuery
      }

      console.warn('ChatViewModel', `[关键词优化] 优化失败,使用原始查询: ${result.errorMessage}`)
      return cleanedUserQuery
    } catch (error) {
      console.error('ChatViewModel', `[关键词优化] 异常: ${JSON.stringify(error)}`)
      return this.cleanSearchQuery(userQuery)
    }
  }

  // 设置标题生成回调
  setTitleCallbacks(callbacks: TitleGenerationCallbacks | null): void {
    this.titleCallbacks = callbacks
  }

  // 生成智能标题（带重试机制）
  private async generateSmartTitle(session: ChatSession, retryCount: number = 0): Promise<void> {
    // 通知开始生成
    if (this.titleCallbacks !== null && this.titleCallbacks.onTitleGenerating !== undefined) {
      this.titleCallbacks.onTitleGenerating(true)
    }

    try {
      // 构建对话内容
      let content = ''
      for (let i = 0; i < session.messages.length; i++) {
        const msg = session.messages[i]
        content += `${msg.role}: ${msg.content}\n`
      }

      // 调用 AI 任务服务生成标题（自动检测语言）
      const title = await this.aiTaskService.generateTitle(content)
      if (title !== '' && this.currentSession !== null && this.currentSession.id === session.id) {
        this.currentSession.title = title
        await this.databaseService.updateSessionTitle(this.currentSession.id, title)
        this.notifySessionListChanged()
        console.info('ChatViewModel', 'Smart title generated: ' + title)

        // 通知标题更新成功
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleUpdated !== undefined) {
          this.titleCallbacks.onTitleUpdated(title)
        }
      } else if (title === '') {
        // 生成失败（配置问题或 API 返回空），通知失败
        console.warn('ChatViewModel', 'Title generation returned empty string')
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleFailed !== undefined) {
          this.titleCallbacks.onTitleFailed()
        }
      }

      // 通知生成结束
      if (this.titleCallbacks !== null && this.titleCallbacks.onTitleGenerating !== undefined) {
        this.titleCallbacks.onTitleGenerating(false)
      }
    } catch (error) {
      console.error('ChatViewModel', 'Failed to generate smart title: ' + JSON.stringify(error))

      // 检查是否可以重试（网络错误等可重试，配置错误不重试）
      const errorStr = JSON.stringify(error)
      const isConfigError = errorStr.includes('API Key') || errorStr.includes('未配置') || errorStr.includes('not configured')

      if (!isConfigError && retryCount < this.MAX_TITLE_RETRY) {
        // 指数退避重试：2秒、4秒、8秒
        const delayMs = Math.pow(2, retryCount + 1) * 1000
        console.info('ChatViewModel', `Retrying title generation in ${delayMs}ms (attempt ${retryCount + 1}/${this.MAX_TITLE_RETRY})`)

        setTimeout(() => {
          this.generateSmartTitle(session, retryCount + 1)
        }, delayMs)
      } else {
        // 重试次数用尽或配置错误，通知失败
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleGenerating !== undefined) {
          this.titleCallbacks.onTitleGenerating(false)
        }
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleFailed !== undefined) {
          this.titleCallbacks.onTitleFailed()
        }
      }
    }
  }

  // 手动重新生成标题
  async regenerateTitle(): Promise<void> {
    if (this.currentSession === null) {
      return
    }
    if (this.currentSession.messages.length === 0) {
      console.warn('ChatViewModel', 'Cannot generate title: no messages in session')
      return
    }
    await this.generateSmartTitle(this.currentSession, 0)
  }

  // 手动更新会话标题
  async updateSessionTitle(title: string): Promise<void> {
    const updated = await this.sessionStore.updateCurrentSessionTitle(title)
    this.currentSession = this.sessionStore.getCurrentSession()
    if (!updated) {
      return
    }

    // 通知标题更新
    if (this.titleCallbacks !== null && this.titleCallbacks.onTitleUpdated !== undefined) {
      this.titleCallbacks.onTitleUpdated(title)
    }
  }

  // 获取当前会话标题
  getCurrentSessionTitle(): string {
    return this.sessionStore.getCurrentSessionTitle()
  }

  // 获取当前模型的参数配置
  private getCurrentModelParameters(providerId: string, modelId: string): ModelParameters | null {
    const provider = this.providerViewModel.getProviderById(providerId)
    if (provider === null) {
      return null
    }

    for (let i = 0; i < provider.models.length; i++) {
      if (provider.models[i].id === modelId) {
        return provider.models[i].parameters
      }
    }

    return null
  }

  // 懒加载历史附件（从后向前扫描，只加载最后 N 条用户消息的图片附件）
  private async prepareHistoryAttachments(messages: RequestMessage[]): Promise<void> {
    let loadedCount = 0
    let totalSize = 0

    // 从后向前扫描，只加载最后 N 条用户消息的附件
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i]
      if (msg.role === 'user' && msg.attachments.length > 0) {
        if (loadedCount >= this.MAX_HISTORY_ATTACHMENTS) {
          break
        }

        for (let j = 0; j < msg.attachments.length; j++) {
          const att = msg.attachments[j]
          if (att.type === AttachmentType.IMAGE) {
            // 跳过已有数据的附件
            if (att.base64Data !== '') {
              continue
            }

            // 估算文件大小
            const estimatedSize = att.size > 0 ? att.size : (1024 * 1024) // 默认 1MB

            // 检查大小限制
            if (totalSize + estimatedSize > this.MAX_HISTORY_ATTACHMENT_SIZE) {
              console.warn('ChatViewModel', `Attachment size limit reached, skipping ${att.id}`)
              continue
            }

            // 从文件加载 base64 数据
            try {
              att.base64Data = await this.attachmentStorageService.readAsBase64(att.filePath)
              totalSize += estimatedSize
              console.info('ChatViewModel', `Loaded history attachment: ${att.id}`)
            } catch (error) {
              console.error('ChatViewModel', `Failed to load attachment ${att.id}: ${JSON.stringify(error)}`)
            }
          }
        }
        loadedCount++
      }
    }

    console.info('ChatViewModel', `Prepared history attachments: ${loadedCount} messages, ${totalSize} bytes`)
  }
}

let chatViewModelInstance: ChatViewModel | null = null

// 导出创建实例方法
export function createChatViewModel(): ChatViewModel {
  if (chatViewModelInstance === null) {
    chatViewModelInstance = new ChatViewModel()
  }
  return chatViewModelInstance
}
