import { ChatMessage, MessageAttachment, ModelProvider } from '../../models/ChatModels'
import { AppStateManager } from '../../viewmodels/AppStateManager'
import { ProviderViewModel } from '../../viewmodels/ProviderViewModel'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'
import { PreferenceKeys, PreferencesService } from '../../services/PreferencesService'
import { AssistantService } from '../../services/AssistantService'
import { ChatPageRouteParams } from './ChatPageRouteTypes'
import { Assistant, DEFAULT_ASSISTANT_ID } from '../../models/AssistantModels'

export class ChatPageLoadResult {
  webSearchEnabled: boolean = false
  webSearchConversationEnabled: boolean = false
  providers: ModelProvider[] = []
  pendingInitialPrompt: string = ''
  pendingInitialToolIds: string[] = []
  initialPromptAutoSent: boolean = false
  sessionId: string = ''
  sessionTitle: string = '新对话'
  messages: ChatMessage[] = []
  draftText: string = ''
  draftAttachments: MessageAttachment[] = []
  isNewChatTransition: boolean = true
  isNewEmptySession: boolean = false
  assistantId: string = DEFAULT_ASSISTANT_ID
  assistantAvatarSymbol: string = 'AI'
  assistantColor: string = '#0A59F7'
}

export interface ChatPageLoadFlowDependencies {
  appStateManager: AppStateManager
  preferencesService: PreferencesService
  assistantService: AssistantService
  providerViewModel: ProviderViewModel
  chatViewModel: ChatViewModel
  parseToolIdsFromRoute: (raw: string) => string[]
}

export class ChatPageLoadFlow {
  private deps: ChatPageLoadFlowDependencies

  constructor(deps: ChatPageLoadFlowDependencies) {
    this.deps = deps
  }

  async loadPageData(
    routeParams: ChatPageRouteParams | null,
    fallbackTitle: string
  ): Promise<ChatPageLoadResult> {
    const result = new ChatPageLoadResult()
    result.sessionTitle = fallbackTitle

    await this.deps.appStateManager.loadState()
    result.webSearchEnabled = await this.deps.preferencesService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    result.webSearchConversationEnabled = await this.deps.preferencesService.getBoolean(
      PreferenceKeys.SEARCH_CONVERSATION_ENABLED,
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
        result.draftText = session.draftText
        result.draftAttachments = this.cloneDraftAttachments(session.draftAttachments)
        const assistant = await this.loadAssistantSnapshot(session.assistantId)
        this.applyAssistantSnapshot(result, assistant)
      }
      result.isNewEmptySession = false
      return result
    }

    const assistant = await this.deps.assistantService.getCurrentAssistantForNewChat()
    this.applyAssistantSnapshot(result, assistant)
    const pendingSession = this.deps.chatViewModel.createPendingSession(
      '',
      assistant.id,
      assistant.defaultModelId,
      assistant.defaultProviderId
    )
    result.sessionId = pendingSession.id
    result.sessionTitle = pendingSession.title
    result.messages = []
    result.isNewChatTransition = true
    result.isNewEmptySession = true
    return result
  }

  private async loadAssistantSnapshot(assistantId: string): Promise<Assistant> {
    const id = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    const assistant = await this.deps.assistantService.getAssistant(id)
    if (assistant !== null) {
      return assistant
    }
    const fallback = await this.deps.assistantService.getAssistant(DEFAULT_ASSISTANT_ID)
    if (fallback !== null) {
      return fallback
    }
    return new Assistant(DEFAULT_ASSISTANT_ID, '默认助手')
  }

  private applyAssistantSnapshot(result: ChatPageLoadResult, assistant: Assistant): void {
    result.assistantId = assistant.id !== '' ? assistant.id : DEFAULT_ASSISTANT_ID
    result.assistantAvatarSymbol = assistant.avatarSymbol !== '' ? assistant.avatarSymbol : 'AI'
    result.assistantColor = assistant.color !== '' ? assistant.color : '#0A59F7'
  }

  private cloneDraftAttachments(attachments: MessageAttachment[]): MessageAttachment[] {
    const cloned: MessageAttachment[] = []
    for (let i = 0; i < attachments.length; i++) {
      cloned.push(
        new MessageAttachment(
          attachments[i].id,
          attachments[i].type,
          attachments[i].name,
          attachments[i].filePath,
          attachments[i].mimeType,
          attachments[i].size
        )
      )
    }
    return cloned
  }
}
