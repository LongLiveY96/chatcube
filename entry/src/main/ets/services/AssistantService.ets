import { Assistant, DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'
import { getDatabaseService, DatabaseService } from './DatabaseService'
import { getPreferencesService, PreferencesService } from './PreferencesService'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { getAppUiState, setAppUiStateValue } from '../state/AppUiState'

export class AssistantRuntimeConfig {
  assistantId: string = DEFAULT_ASSISTANT_ID
  systemPrompt: string = ''
  temperatureEnabled: boolean = false
  temperature: number = 0.7
}

export class AssistantService {
  private static instance: AssistantService | null = null
  private databaseService: DatabaseService
  private preferencesService: PreferencesService

  private constructor() {
    this.databaseService = getDatabaseService()
    this.preferencesService = getPreferencesService()
  }

  static getInstance(): AssistantService {
    if (AssistantService.instance === null) {
      AssistantService.instance = new AssistantService()
    }
    return AssistantService.instance
  }

  async initialize(): Promise<void> {
    await this.ensureValidCurrentAssistant()
  }

  private normalizeAssistant(assistant: Assistant): Assistant {
    assistant.name = assistant.name.trim() !== '' ? assistant.name.trim() : '未命名助手'
    assistant.avatarSymbol = assistant.avatarSymbol.trim() !== '' ? assistant.avatarSymbol.trim() : 'AI'
    assistant.color = assistant.color.trim() !== '' ? assistant.color.trim() : '#0A59F7'
    if (assistant.id === DEFAULT_ASSISTANT_ID) {
      assistant.isDefault = true
    }
    if (assistant.temperature < 0) {
      assistant.temperature = 0
    } else if (assistant.temperature > 2) {
      assistant.temperature = 2
    }
    return assistant
  }

  private notifyAssistantAvatarChanged(): void {
    const current = getAppUiState().assistantAvatarRefreshAt
    const now = Date.now()
    setAppUiStateValue(AppStorageKeys.ASSISTANT_AVATAR_REFRESH_AT, now > current ? now : current + 1)
  }

  async getAllAssistants(): Promise<Assistant[]> {
    return await this.databaseService.getAllAssistants()
  }

  async getAssistant(assistantId: string): Promise<Assistant | null> {
    const id = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    return await this.databaseService.getAssistant(id)
  }

  async getCurrentAssistantId(): Promise<string> {
    const assistantId = await this.preferencesService.getCurrentAssistantId()
    return assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
  }

  async getCurrentAssistant(): Promise<Assistant> {
    const assistantId = await this.getCurrentAssistantId()
    const assistant = await this.databaseService.getAssistant(assistantId)
    if (assistant !== null) {
      return assistant
    }
    await this.preferencesService.setCurrentAssistantId(DEFAULT_ASSISTANT_ID)
    const fallback = await this.databaseService.getAssistant(DEFAULT_ASSISTANT_ID)
    if (fallback !== null) {
      return fallback
    }
    const assistants = await this.databaseService.getAllAssistants()
    return assistants.length > 0 ? assistants[0] : new Assistant(DEFAULT_ASSISTANT_ID, '默认助手')
  }

  async getCurrentAssistantForNewChat(): Promise<Assistant> {
    const assistantId = await this.getCurrentAssistantId()
    const assistant = await this.databaseService.getAssistant(assistantId)
    if (assistant !== null) {
      return assistant
    }
    const fallback = await this.databaseService.getAssistant(DEFAULT_ASSISTANT_ID)
    if (fallback !== null) {
      await this.preferencesService.setCurrentAssistantId(fallback.id)
      return fallback
    }
    const assistants = await this.databaseService.getAllAssistants()
    if (assistants.length > 0) {
      await this.preferencesService.setCurrentAssistantId(assistants[0].id)
      return assistants[0]
    }
    return new Assistant(DEFAULT_ASSISTANT_ID, '默认助手')
  }

  async setCurrentAssistantId(assistantId: string): Promise<Assistant> {
    const id = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    const assistant = await this.databaseService.getAssistant(id)
    const effectiveAssistant = assistant !== null ? assistant : await this.getCurrentAssistant()
    const effectiveId = assistant !== null ? id : DEFAULT_ASSISTANT_ID
    await this.preferencesService.setCurrentAssistantId(effectiveId)
    setAppUiStateValue(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())
    return effectiveAssistant
  }

  async ensureValidCurrentAssistant(): Promise<Assistant> {
    const currentId = await this.getCurrentAssistantId()
    const assistant = await this.databaseService.getAssistant(currentId)
    if (assistant !== null) {
      return assistant
    }
    await this.preferencesService.setCurrentAssistantId(DEFAULT_ASSISTANT_ID)
    const fallback = await this.databaseService.getAssistant(DEFAULT_ASSISTANT_ID)
    if (fallback !== null) {
      return fallback
    }
    const assistants = await this.databaseService.getAllAssistants()
    return assistants.length > 0 ? assistants[0] : new Assistant(DEFAULT_ASSISTANT_ID, '默认助手')
  }

  async createAssistant(assistant: Assistant): Promise<Assistant> {
    this.normalizeAssistant(assistant)
    if (assistant.id === '') {
      assistant.id = `assistant_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`
    }
    await this.databaseService.createAssistant(assistant)
    setAppUiStateValue(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())
    this.notifyAssistantAvatarChanged()
    return assistant
  }

  async saveAssistant(assistant: Assistant): Promise<void> {
    this.normalizeAssistant(assistant)
    await this.databaseService.saveAssistant(assistant)
    setAppUiStateValue(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())
    this.notifyAssistantAvatarChanged()
  }

  async reorderAssistants(assistants: Assistant[]): Promise<void> {
    if (assistants.length === 0) {
      return
    }
    for (let i = 0; i < assistants.length; i++) {
      assistants[i].sortOrder = i
    }
    await this.databaseService.saveAssistantSortOrders(assistants)
    setAppUiStateValue(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())
  }

  async deleteAssistant(assistantId: string): Promise<boolean> {
    if (assistantId === DEFAULT_ASSISTANT_ID) {
      return false
    }
    const deleted = await this.databaseService.deleteAssistant(assistantId)
    if (deleted) {
      const currentId = await this.getCurrentAssistantId()
      if (currentId === assistantId) {
        await this.preferencesService.setCurrentAssistantId(DEFAULT_ASSISTANT_ID)
      }
      setAppUiStateValue(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())
    }
    return deleted
  }

  async getAssistantSessionCount(assistantId: string): Promise<number> {
    return await this.databaseService.getAssistantSessionCount(assistantId)
  }

  async getRuntimeConfig(assistantId: string): Promise<AssistantRuntimeConfig> {
    const config = new AssistantRuntimeConfig()
    const id = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    let assistant = await this.databaseService.getAssistant(id)
    if (assistant === null) {
      assistant = await this.databaseService.getAssistant(DEFAULT_ASSISTANT_ID)
    }
    if (assistant === null) {
      return config
    }
    config.assistantId = assistant.id
    config.systemPrompt = assistant.systemPrompt.trim()
    config.temperatureEnabled = assistant.temperatureEnabled
    config.temperature = assistant.temperature
    return config
  }

  combineSystemPrompts(globalPrompt: string, assistantPrompt: string): string {
    const parts: string[] = []
    if (globalPrompt.trim() !== '') {
      parts.push(globalPrompt.trim())
    }
    if (assistantPrompt.trim() !== '') {
      parts.push(assistantPrompt.trim())
    }
    return parts.join('\n\n')
  }
}

export function getAssistantService(): AssistantService {
  return AssistantService.getInstance()
}
