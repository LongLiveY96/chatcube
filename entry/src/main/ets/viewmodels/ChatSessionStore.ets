import { ChatSession } from '../models/ChatModels'
import { DatabaseService } from '../services/DatabaseService'
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

  async createNewSession(title: string = ''): Promise<ChatSession> {
    const sessionId = this.createId()
    const modelId = this.appStateManager.getCurrentModelId()
    const providerId = this.appStateManager.getCurrentProviderId()
    const sessionTitle = title !== '' ? title : this.defaultTitle

    const session = new ChatSession(sessionId, sessionTitle, modelId, providerId)
    await this.databaseService.createSession(session)
    this.currentSession = session
    this.onSessionListChanged()
    return session
  }

  createPendingSession(title: string = ''): ChatSession {
    const sessionId = this.createId()
    const modelId = this.appStateManager.getCurrentModelId()
    const providerId = this.appStateManager.getCurrentProviderId()
    const sessionTitle = title !== '' ? title : this.defaultTitle

    const session = new ChatSession(sessionId, sessionTitle, modelId, providerId)
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
    const session = await this.databaseService.getSession(sessionId)
    if (session === null) {
      return null
    }

    const messages = await this.databaseService.getMessages(sessionId)
    session.messages = messages
    this.currentSession = session
    return session
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

  getCurrentSession(): ChatSession | null {
    return this.currentSession
  }

  setCurrentSession(session: ChatSession | null): void {
    this.currentSession = session
  }

  getCurrentSessionTitle(): string {
    if (this.currentSession !== null) {
      return this.currentSession.title
    }
    return this.defaultTitle
  }
}
