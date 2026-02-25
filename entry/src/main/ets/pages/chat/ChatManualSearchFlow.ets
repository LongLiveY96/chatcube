import {
  ChatMessage,
  MessageAttachment,
  MessageRole,
  ModelProvider,
  ModelRole,
  ProviderType,
  ReasoningLevel,
  SearchReference
} from '../../models/ChatModels'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'
import { ProviderViewModel } from '../../viewmodels/ProviderViewModel'
import {
  WebSearchService,
  SearchResult,
  SearchRuntimeConfigSnapshot,
  WebSearchExecutionOptions
} from '../../services/WebSearchService'
import { DefaultModelService } from '../../services/DefaultModelService'
import { PreferenceKeys, PreferencesService } from '../../services/PreferencesService'
import { AppStateManager } from '../../viewmodels/AppStateManager'
import { MessageDataSource } from '../../datasource/MessageDataSource'
import { getEffectiveApiKey } from '../../config/PresetProviders'
import {
  cleanSearchQuery,
  normalizeRelativeTimeForSearchQuery,
  shouldApplyLlmOptimizationByQuery
} from '../../utils/SearchQueryUtils'
import {
  isSelfOptimizedSearchEngineForChat,
  shouldApplyLlmQueryOptimizationForChat
} from './ChatSearchDecisionHelper'

export class ChatManualSearchFlowDependencies {
  chatViewModel: ChatViewModel
  providerViewModel: ProviderViewModel
  webSearchService: WebSearchService
  defaultModelService: DefaultModelService
  preferencesService: PreferencesService
  appStateManager: AppStateManager
  messageDataSource: MessageDataSource
  getCurrentProvider: () => ModelProvider | null
  getCurrentModelId: () => string
  getCurrentModelName: () => string
  getMessages: () => ChatMessage[]
  getReasoningLevel: () => ReasoningLevel
  isSearchCancelled: () => boolean
  onSyncMessages: () => void
  onScrollBottom: () => void
  onSetSending: (value: boolean) => void
  onSetSearchCancelled: (value: boolean) => void
  onClearComposer: () => void
  onBeforeManualSearchStart: () => void
  onSetNewEmptySession: (value: boolean) => void
  onMarkAutoTaskFailed: (message: string) => void
  onMarkAutoTaskCompleted: () => void
  onShowError: (message: string | Resource) => void
  onShowToast: (message: string | Resource) => void

  constructor(
    chatViewModel: ChatViewModel,
    providerViewModel: ProviderViewModel,
    webSearchService: WebSearchService,
    defaultModelService: DefaultModelService,
    preferencesService: PreferencesService,
    appStateManager: AppStateManager,
    messageDataSource: MessageDataSource,
    getCurrentProvider: () => ModelProvider | null,
    getCurrentModelId: () => string,
    getCurrentModelName: () => string,
    getMessages: () => ChatMessage[],
    getReasoningLevel: () => ReasoningLevel,
    isSearchCancelled: () => boolean,
    onSyncMessages: () => void,
    onScrollBottom: () => void,
    onSetSending: (value: boolean) => void,
    onSetSearchCancelled: (value: boolean) => void,
    onClearComposer: () => void,
    onBeforeManualSearchStart: () => void,
    onSetNewEmptySession: (value: boolean) => void,
    onMarkAutoTaskFailed: (message: string) => void,
    onMarkAutoTaskCompleted: () => void,
    onShowError: (message: string | Resource) => void,
    onShowToast: (message: string | Resource) => void
  ) {
    this.chatViewModel = chatViewModel
    this.providerViewModel = providerViewModel
    this.webSearchService = webSearchService
    this.defaultModelService = defaultModelService
    this.preferencesService = preferencesService
    this.appStateManager = appStateManager
    this.messageDataSource = messageDataSource
    this.getCurrentProvider = getCurrentProvider
    this.getCurrentModelId = getCurrentModelId
    this.getCurrentModelName = getCurrentModelName
    this.getMessages = getMessages
    this.getReasoningLevel = getReasoningLevel
    this.isSearchCancelled = isSearchCancelled
    this.onSyncMessages = onSyncMessages
    this.onScrollBottom = onScrollBottom
    this.onSetSending = onSetSending
    this.onSetSearchCancelled = onSetSearchCancelled
    this.onClearComposer = onClearComposer
    this.onBeforeManualSearchStart = onBeforeManualSearchStart
    this.onSetNewEmptySession = onSetNewEmptySession
    this.onMarkAutoTaskFailed = onMarkAutoTaskFailed
    this.onMarkAutoTaskCompleted = onMarkAutoTaskCompleted
    this.onShowError = onShowError
    this.onShowToast = onShowToast
  }
}

export class ChatManualSearchFlow {
  private deps: ChatManualSearchFlowDependencies
  private currentSearchRequestId: string = ''

  constructor(deps: ChatManualSearchFlowDependencies) {
    this.deps = deps
  }

  cancelCurrentSearchRequest(): void {
    if (this.currentSearchRequestId === '') {
      return
    }
    this.deps.webSearchService.cancelRequest(this.currentSearchRequestId)
    this.currentSearchRequestId = ''
  }

  private createManualSearchRequestId(): string {
    return `manual_search_${this.generateId()}`
  }

  private buildSearchExecutionOptions(
    requestId: string,
    runtimeConfig: SearchRuntimeConfigSnapshot
  ): WebSearchExecutionOptions {
    return {
      requestId: requestId,
      runtimeConfig: runtimeConfig,
      cancelCheck: (): boolean => this.deps.isSearchCancelled()
    }
  }

  private finishSearchRequest(requestId: string): void {
    if (this.currentSearchRequestId === requestId) {
      this.currentSearchRequestId = ''
    }
  }

  startManualSearchFallback(messageContent: string, attachmentsToSend: MessageAttachment[] = []): void {
    this.cancelCurrentSearchRequest()
    const requestId = this.createManualSearchRequestId()
    this.currentSearchRequestId = requestId

    const extractedUrl = this.deps.webSearchService.extractUrl(messageContent)
    const isPureUrl = extractedUrl !== null && extractedUrl === messageContent.trim()

    this.deps.onClearComposer()
    this.deps.onSetSending(true)
    this.deps.onSetSearchCancelled(false)
    this.deps.onBeforeManualSearchStart()

    const userMessage = this.createPendingUserMessage(messageContent, attachmentsToSend)

    if (isPureUrl && extractedUrl !== null) {
      this.performUrlFetchAsync(extractedUrl, messageContent, userMessage, attachmentsToSend, requestId)
      return
    }
    this.performBingSearchAsync(messageContent, userMessage, attachmentsToSend, requestId)
  }

  private generateId(): string {
    return Date.now().toString() + Math.random().toString(36).substring(2, 9)
  }

  createPendingUserMessage(content: string, attachments: MessageAttachment[] = []): ChatMessage {
    const userMessage = new ChatMessage(
      this.generateId(),
      MessageRole.USER,
      content,
      ''
    )
    userMessage.isSearching = false
    for (let i = 0; i < attachments.length; i++) {
      userMessage.attachments.push(attachments[i])
    }
    this.deps.messageDataSource.addMessage(userMessage)
    this.deps.onSyncMessages()
    this.deps.onSetNewEmptySession(false)
    this.deps.onScrollBottom()
    return userMessage
  }

  private createSearchingAIMessage(): ChatMessage {
    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      this.deps.getCurrentModelName()
    )
    aiMessage.isSearching = true
    this.deps.messageDataSource.addMessage(aiMessage)
    this.deps.onSyncMessages()
    this.deps.onScrollBottom()
    return aiMessage
  }

  private removeSearchingAIMessage(aiMessage: ChatMessage): void {
    this.deps.messageDataSource.removeMessageById(aiMessage.id)
    this.deps.onSyncMessages()
  }

  async performBingSearchAsync(query: string, userMessage: ChatMessage,
    attachmentsToSend: MessageAttachment[] = [],
    requestId: string = ''): Promise<void> {
    const searchingAIMessage = this.createSearchingAIMessage()

    try {
      const runtimeConfig = await this.deps.webSearchService.getRuntimeConfigSnapshot()
      const preferredEngineName = await this.deps.webSearchService.getPreferredEngineName(runtimeConfig)
      searchingAIMessage.searchQuery = query
      searchingAIMessage.searchEngine = preferredEngineName
      const searchingIndex = this.deps.messageDataSource.findMessageIndex(searchingAIMessage.id)
      if (searchingIndex >= 0) {
        this.deps.messageDataSource.updateMessage(searchingIndex, searchingAIMessage)
        this.deps.onSyncMessages()
      }

      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      const cleanedQuery = cleanSearchQuery(query)

      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      let optimizedQuery = cleanedQuery
      let optimizationApplied = false
      const optimizationConfigured = await this.deps.preferencesService.getBoolean(
        PreferenceKeys.SEARCH_QUERY_OPTIMIZATION_ENABLED,
        false
      )
      const shouldOptimizeByQuery = shouldApplyLlmOptimizationByQuery(query, cleanedQuery)
      const shouldApplyOptimization = shouldApplyLlmQueryOptimizationForChat(
        preferredEngineName,
        optimizationConfigured
      ) && shouldOptimizeByQuery
      if (optimizationConfigured &&
        !shouldApplyOptimization &&
      isSelfOptimizedSearchEngineForChat(preferredEngineName)) {
        console.info('ChatPage', `[联网查询] 当前引擎为${preferredEngineName}，跳过额外搜索词优化，避免重复改写`)
      }
      if (optimizationConfigured && !shouldOptimizeByQuery) {
        console.info('ChatPage', '[联网查询] 查询已足够结构化，跳过关键词优化')
      }

      if (shouldApplyOptimization) {
        await this.deps.defaultModelService.initialize()
        const searchOptModel = this.deps.defaultModelService.getModel(ModelRole.SEARCH_OPTIMIZATION)
        if (searchOptModel.isConfigured()) {
          const provider = await this.deps.providerViewModel.getProviderByIdAsync(searchOptModel.providerId)
          if (provider !== null) {
            const effectiveApiKey = getEffectiveApiKey(provider.id, provider.apiKey)
            if (effectiveApiKey !== '' || provider.type === ProviderType.OLLAMA) {
              optimizedQuery = await this.deps.chatViewModel.optimizeSearchQuery(
                cleanedQuery,
                this.deps.getMessages(),
                provider.id,
                provider.type,
                provider.apiStyle,
                effectiveApiKey,
                provider.baseUrl,
                searchOptModel.modelId
              )
              optimizationApplied = true
            }
          }
        }
        const currentProvider = this.deps.getCurrentProvider()
        if (!optimizationApplied && currentProvider !== null) {
          const effectiveApiKey = getEffectiveApiKey(currentProvider.id, currentProvider.apiKey)
          if (effectiveApiKey !== '' || currentProvider.type === ProviderType.OLLAMA) {
            optimizedQuery = await this.deps.chatViewModel.optimizeSearchQuery(
              cleanedQuery,
              this.deps.getMessages(),
              currentProvider.id,
              currentProvider.type,
              currentProvider.apiStyle,
              effectiveApiKey,
              currentProvider.baseUrl,
              this.deps.getCurrentModelId()
            )
            optimizationApplied = true
          }
        }
      }

      optimizedQuery = cleanSearchQuery(optimizedQuery)
      const normalizedQuery = normalizeRelativeTimeForSearchQuery(cleanedQuery, optimizedQuery)
      if (normalizedQuery !== optimizedQuery) {
        optimizedQuery = normalizedQuery
      }
      console.info('ChatPage',
        `[联网查询] 最终搜索关键词: "${optimizedQuery}" (optimizationApplied=${optimizationApplied})`)

      if (optimizedQuery !== searchingAIMessage.searchQuery) {
        searchingAIMessage.searchQuery = optimizedQuery
        const optimizedIndex = this.deps.messageDataSource.findMessageIndex(searchingAIMessage.id)
        if (optimizedIndex >= 0) {
          this.deps.messageDataSource.updateMessage(optimizedIndex, searchingAIMessage)
          this.deps.onSyncMessages()
        }
      }

      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      const searchResult = await this.deps.webSearchService.search(
        optimizedQuery,
        this.buildSearchExecutionOptions(requestId, runtimeConfig)
      )

      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      this.removeSearchingAIMessage(searchingAIMessage)

      if (!searchResult.success) {
        this.deps.onShowToast($r('app.string.web_search_failed'))
        this.deps.onSetSending(false)
        this.deps.onMarkAutoTaskFailed(searchResult.errorMessage)
        return
      }

      userMessage.searchQuery = searchResult.query
      userMessage.searchEngine = searchResult.searchEngine || preferredEngineName
      for (let i = 0; i < searchResult.references.length; i++) {
        userMessage.searchReferences.push(searchResult.references[i])
      }
      this.deps.onSyncMessages()

      await this.sendSearchResultMessage(query, searchResult, attachmentsToSend)
    } catch (error) {
      this.removeSearchingAIMessage(searchingAIMessage)
      console.error('ChatPage', `[performBingSearchAsync] 搜索异常: ${JSON.stringify(error)}`)
      this.deps.onShowToast($r('app.string.web_search_failed'))
      this.deps.onSetSending(false)
      this.deps.onMarkAutoTaskFailed('联网搜索失败')
    } finally {
      this.finishSearchRequest(requestId)
    }
  }

  async performUrlFetchAsync(url: string, _originalInput: string, userMessage: ChatMessage,
    attachmentsToSend: MessageAttachment[] = [],
    requestId: string = ''): Promise<void> {
    const searchingAIMessage = this.createSearchingAIMessage()

    try {
      const runtimeConfig = await this.deps.webSearchService.getRuntimeConfigSnapshot()
      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      const webResult = await this.deps.webSearchService.fetchUrlContent(
        url,
        this.buildSearchExecutionOptions(requestId, runtimeConfig)
      )

      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      this.removeSearchingAIMessage(searchingAIMessage)

      if (!webResult.success) {
        console.error('ChatPage', `[performUrlFetchAsync] 网页获取失败: ${webResult.errorMessage}`)
        this.deps.onShowToast($r('app.string.url_fetch_failed'))
        this.deps.onSetSending(false)
        this.deps.onMarkAutoTaskFailed(webResult.errorMessage)
        return
      }

      const searchResult = new SearchResult(
        true,
        '请分析这个网页',
        'URL抓取',
        [new SearchReference(
          `ref_${Date.now()}`,
          webResult.title,
          webResult.url,
          webResult.content.substring(0, 200) + '...'
        )],
        `标题: ${webResult.title}\n来源: ${webResult.url}\n\n${webResult.content}`,
        ''
      )

      userMessage.searchQuery = searchResult.query
      userMessage.searchEngine = searchResult.searchEngine
      for (let i = 0; i < searchResult.references.length; i++) {
        userMessage.searchReferences.push(searchResult.references[i])
      }
      this.deps.onSyncMessages()

      await this.sendSearchResultMessage('请分析这个网页', searchResult, attachmentsToSend)
    } catch (error) {
      this.removeSearchingAIMessage(searchingAIMessage)
      console.error('ChatPage', `[performUrlFetchAsync] 网页获取异常: ${JSON.stringify(error)}`)
      this.deps.onShowToast($r('app.string.url_fetch_failed'))
      this.deps.onSetSending(false)
      this.deps.onMarkAutoTaskFailed('网页抓取失败')
    } finally {
      this.finishSearchRequest(requestId)
    }
  }

  private async sendSearchResultMessage(userQuery: string, searchResult: SearchResult,
    attachmentsToSend: MessageAttachment[] = []): Promise<void> {
    const currentProvider = this.deps.getCurrentProvider()
    if (currentProvider === null) {
      this.deps.onShowError($r('app.string.provider_required_before_chat'))
      this.deps.onSetSending(false)
      this.deps.onMarkAutoTaskFailed('未配置可用服务商')
      return
    }

    const effectiveApiKey = getEffectiveApiKey(currentProvider.id, currentProvider.apiKey)
    if (effectiveApiKey === '' && currentProvider.type !== ProviderType.OLLAMA) {
      this.deps.onShowError($r('app.string.api_key_required'))
      this.deps.onSetSending(false)
      this.deps.onMarkAutoTaskFailed('缺少 API Key')
      return
    }

    const modelId = this.deps.appStateManager.getCurrentModelId()
    await this.deps.chatViewModel.sendMessageWithSearchResult(
      userQuery,
      searchResult,
      currentProvider.id,
      currentProvider.type,
      currentProvider.apiStyle,
      effectiveApiKey,
      currentProvider.baseUrl,
      modelId,
      this.deps.getCurrentModelName(),
      this.deps.getMessages(),
      attachmentsToSend,
      0,
      (userMessage: ChatMessage): void => {
        const allMessages = this.deps.messageDataSource.getAllMessages()
        let found = false
        for (let i = allMessages.length - 1; i >= 0; i--) {
          if (allMessages[i].role === MessageRole.USER) {
            allMessages[i] = userMessage
            found = true
            break
          }
        }
        if (!found) {
          allMessages.push(userMessage)
        }
        this.deps.messageDataSource.setAllMessages(allMessages)
        this.deps.onSyncMessages()
      },
      (aiMessage: ChatMessage): void => {
        this.deps.messageDataSource.addMessage(aiMessage)
        this.deps.onSyncMessages()
        this.deps.onScrollBottom()
      },
      (aiMessage: ChatMessage): void => {
        if (this.deps.messageDataSource.totalCount() > 0) {
          this.deps.messageDataSource.updateLastMessage(aiMessage)
          this.deps.onSyncMessages()
          this.deps.onScrollBottom()
        }
      },
      (): void => {
        this.deps.onSetSending(false)
        this.deps.onMarkAutoTaskCompleted()
      },
      (error: string): void => {
        this.deps.onSetSending(false)
        this.deps.onMarkAutoTaskFailed(error)
        this.deps.onShowError(error)
      },
      this.deps.getReasoningLevel(),
      currentProvider.apiPath || undefined
    )
  }
}
