import { ChatMessage, ModelProvider } from '../../models/ChatModels'
import { AppStateManager } from '../../viewmodels/AppStateManager'
import { ProviderViewModel } from '../../viewmodels/ProviderViewModel'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'
import { PreferenceKeys, PreferencesService } from '../../services/PreferencesService'
import { ChatPageRouteParams } from './ChatPageRouteTypes'

export class ChatPageLoadResult {
  webSearchEnabled: boolean = false
  webSearchConversationEnabled: boolean = false
  weatherQueryEnabled: boolean = false
  providers: ModelProvider[] = []
  pendingInitialPrompt: string = ''
  pendingInitialToolIds: string[] = []
  initialPromptAutoSent: boolean = false
  sessionId: string = ''
  sessionTitle: string = '新对话'
  messages: ChatMessage[] = []
  isNewChatTransition: boolean = true
  isNewEmptySession: boolean = false
}

export class ChatPageLoadFlowDependencies {
  appStateManager: AppStateManager
  preferencesService: PreferencesService
  providerViewModel: ProviderViewModel
  chatViewModel: ChatViewModel
  parseToolIdsFromRoute: (raw: string) => string[]

  constructor(
    appStateManager: AppStateManager,
    preferencesService: PreferencesService,
    providerViewModel: ProviderViewModel,
    chatViewModel: ChatViewModel,
    parseToolIdsFromRoute: (raw: string) => string[]
  ) {
    this.appStateManager = appStateManager
    this.preferencesService = preferencesService
    this.providerViewModel = providerViewModel
    this.chatViewModel = chatViewModel
    this.parseToolIdsFromRoute = parseToolIdsFromRoute
  }
}

export class ChatPageLoadFlow {
  private deps: ChatPageLoadFlowDependencies

  constructor(deps: ChatPageLoadFlowDependencies) {
    this.deps = deps
  }

  async loadPageData(routeParams: ChatPageRouteParams | null, fallbackTitle: string): Promise<ChatPageLoadResult> {
    const result = new ChatPageLoadResult()
    result.sessionTitle = fallbackTitle

    await this.deps.appStateManager.loadState()
    result.webSearchEnabled = await this.deps.preferencesService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    result.webSearchConversationEnabled = await this.deps.preferencesService.getBoolean(
      PreferenceKeys.SEARCH_CONVERSATION_ENABLED,
      result.webSearchEnabled
    )
    result.weatherQueryEnabled = await this.deps.preferencesService.getBoolean(
      PreferenceKeys.WEATHER_QUERY_ENABLED,
      result.webSearchEnabled
    )
    result.providers = await this.deps.providerViewModel.loadProviders()

    result.pendingInitialPrompt =
      routeParams !== null && routeParams !== undefined && routeParams.initialPrompt !== undefined ?
        routeParams.initialPrompt.trim() : ''
    result.pendingInitialToolIds =
      this.deps.parseToolIdsFromRoute(routeParams !== null && routeParams !== undefined &&
        routeParams.initialToolIds !== undefined ? routeParams.initialToolIds : '')
    result.initialPromptAutoSent = false

    if (routeParams !== null && routeParams !== undefined &&
      routeParams.sessionId !== undefined && routeParams.sessionId !== '') {
      result.sessionId = routeParams.sessionId
      result.isNewChatTransition = false
      const session = await this.deps.chatViewModel.loadSession(routeParams.sessionId)
      if (session !== null) {
        result.sessionTitle = session.title
        result.messages = [...session.messages]
      }
      result.isNewEmptySession = false
      return result
    }

    const pendingSession = this.deps.chatViewModel.createPendingSession()
    result.sessionId = pendingSession.id
    result.sessionTitle = pendingSession.title
    result.messages = []
    result.isNewChatTransition = true
    result.isNewEmptySession = false
    return result
  }
}
