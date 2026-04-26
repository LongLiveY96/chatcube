import { ChatMessage, ChatSession, ToolCall, ToolResult } from '../models/ChatModels'
import { DatabaseService, ToolEventData } from '../services/DatabaseService'
import { AppStateManager } from './AppStateManager'

// 会话存储与状态聚合：集中处理会话的创建、加载、删除和偏好状态更新
export class ChatSessionStore {
  private databaseService: DatabaseService
  private appStateManager: AppStateManager
  private createId: () => string
  private onSessionListChanged: () => void
  private defaultTitle: string

  private currentSession: ChatSession | null = null
  private pendingSession: ChatSession | null = null

  constructor(
    databaseService: DatabaseService,
    appStateManager: AppStateManager,
    createId: () => string,
    onSessionListChanged: () => void,
    defaultTitle: string = '新对话'
  ) {
    this.databaseService = databaseService
    this.appStateManager = appStateManager
    this.createId = createId
    this.onSessionListChanged = onSessionListChanged
    this.defaultTitle = defaultTitle
  }

  async createNewSession(
    title: string = '',
    assistantId: string = 'default',
    modelIdSeed: string = '',
    providerIdSeed: string = ''
  ): Promise<ChatSession> {
    // Switching to a real session invalidates any in-memory placeholder session.
    this.pendingSession = null
    const sessionId = this.createId()
    const modelId = modelIdSeed !== '' ? modelIdSeed : this.appStateManager.getCurrentModelId()
    const providerId = providerIdSeed !== '' ? providerIdSeed : this.appStateManager.getCurrentProviderId()
    const sessionTitle = title !== '' ? title : this.defaultTitle

    const session = new ChatSession(sessionId, sessionTitle, modelId, providerId, assistantId)
    await this.databaseService.createSession(session)
    this.currentSession = session
    this.onSessionListChanged()
    return session
  }

  createPendingSession(
    title: string = '',
    assistantId: string = 'default',
    modelIdSeed: string = '',
    providerIdSeed: string = ''
  ): ChatSession {
    const sessionId = this.createId()
    const modelId = modelIdSeed !== '' ? modelIdSeed : this.appStateManager.getCurrentModelId()
    const providerId = providerIdSeed !== '' ? providerIdSeed : this.appStateManager.getCurrentProviderId()
    const sessionTitle = title !== '' ? title : this.defaultTitle

    const session = new ChatSession(sessionId, sessionTitle, modelId, providerId, assistantId)
    this.pendingSession = session
    this.currentSession = session
    return session
  }

  async persistPendingSession(): Promise<void> {
    if (this.pendingSession === null) {
      return
    }

    await this.databaseService.createSession(this.pendingSession)
    console.info('ChatSessionStore', 'Pending session persisted: ' + this.pendingSession.id)
    this.currentSession = this.pendingSession
    this.pendingSession = null
    this.onSessionListChanged()
  }

  async loadSession(sessionId: string): Promise<ChatSession | null> {
    return await this.loadSessionWithMessages(
      sessionId,
      async (): Promise<ChatMessage[]> => await this.databaseService.getMessages(sessionId)
    )
  }

  private async loadSessionWithMessages(
    sessionId: string,
    loadMessages: () => Promise<ChatMessage[]>
  ): Promise<ChatSession | null> {
    const session = await this.databaseService.getSession(sessionId)
    if (session === null) {
      return null
    }

    const messages = await loadMessages()
    const toolEvents = await this.databaseService.getToolEventsBySession(sessionId)
    this.rehydrateToolEvents(messages, toolEvents)
    session.messages = messages
    this.pendingSession = null
    this.currentSession = session
    return session
  }

  private buildToolEventMap(toolEvents: ToolEventData[]): Map<string, ToolEventData[]> {
    const eventMap = new Map<string, ToolEventData[]>()
    for (let i = 0; i < toolEvents.length; i++) {
      const event = toolEvents[i]
      const existing = eventMap.get(event.messageId)
      if (existing !== undefined) {
        existing.push(event)
        continue
      }
      eventMap.set(event.messageId, [event])
    }
    return eventMap
  }

  private rehydrateToolEvents(messages: ChatMessage[], toolEvents: ToolEventData[]): void {
    const eventMap = this.buildToolEventMap(toolEvents)
    for (let i = 0; i < messages.length; i++) {
      const message = messages[i]
      const messageToolEvents = eventMap.get(message.id)
      if (messageToolEvents === undefined || messageToolEvents.length === 0) {
        continue
      }
      message.toolCalls = []
      message.toolResults = []
      for (let j = 0; j < messageToolEvents.length; j++) {
        const event = messageToolEvents[j]
        const toolCall = new ToolCall(
          event.toolCallId,
          event.toolName,
          event.toolArguments,
          event.toolName,
          event.toolDisplayName !== '' ? event.toolDisplayName : event.toolName,
          event.sourceType,
          event.sourceLabel,
          event.permissionLevel
        )
        message.toolCalls.push(toolCall)
        if (event.toolResult !== '') {
          message.toolResults.push(new ToolResult(
            event.toolCallId,
            event.toolResult,
            event.status === 'failed',
            event.toolDisplayName,
            event.sourceLabel
          ))
        }
      }
    }
  }

  async getAllSessions(): Promise<ChatSession[]> {
    return await this.databaseService.getAllSessions()
  }

  async deleteSession(sessionId: string): Promise<void> {
    await this.databaseService.deleteSession(sessionId)
    if (this.currentSession !== null && this.currentSession.id === sessionId) {
      this.currentSession = null
    }
    if (this.pendingSession !== null && this.pendingSession.id === sessionId) {
      this.pendingSession = null
    }
    this.onSessionListChanged()
  }

  async toggleSessionFavorite(sessionId: string): Promise<boolean> {
    const isFavorite = await this.databaseService.toggleSessionFavorite(sessionId)
    if (this.currentSession !== null && this.currentSession.id === sessionId) {
      this.currentSession.isFavorite = isFavorite
    }
    this.onSessionListChanged()
    return isFavorite
  }

  async updateCurrentSessionTitle(title: string): Promise<boolean> {
    if (this.currentSession === null) {
      return false
    }

    this.currentSession.title = title
    await this.databaseService.updateSessionTitle(this.currentSession.id, title)
    this.onSessionListChanged()
    return true
  }

  async updateCurrentSessionModelSelection(modelId: string, providerId: string): Promise<boolean> {
    if (this.currentSession === null) {
      return false
    }

    if (this.currentSession.modelId === modelId && this.currentSession.providerId === providerId) {
      return true
    }

    this.currentSession.modelId = modelId
    this.currentSession.providerId = providerId
    if (this.pendingSession !== null && this.pendingSession.id === this.currentSession.id) {
      return true
    }

    await this.databaseService.updateSessionModelSelection(this.currentSession.id, modelId, providerId)
    return true
  }

  getCurrentSession(): ChatSession | null {
    return this.currentSession
  }

  setCurrentSession(session: ChatSession | null): void {
    this.currentSession = session
    if (session === null) {
      this.pendingSession = null
      return
    }
    if (this.pendingSession !== null && this.pendingSession.id !== session.id) {
      this.pendingSession = null
    }
  }

  getCurrentSessionTitle(): string {
    if (this.currentSession !== null) {
      return this.currentSession.title
    }
    return this.defaultTitle
  }

  hasPendingSession(): boolean {
    return this.pendingSession !== null
  }

  isCurrentSessionPending(): boolean {
    return this.currentSession !== null &&
      this.pendingSession !== null &&
      this.currentSession.id === this.pendingSession.id
  }
}
