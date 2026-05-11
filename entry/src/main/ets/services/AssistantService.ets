import {
  Assistant,
  DEFAULT_ASSISTANT_ID,
  ASSISTANT_CONTEXT_MESSAGE_SIZE_MAX,
  ASSISTANT_MAX_TOKENS_LIMIT
} from '../models/AssistantModels'
import { ModelRole, ReasoningLevel } from '../models/ChatModels'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { DEFAULT_PRIMARY_COLOR } from '../config/ThemeDefaults'
import { getAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { getAppSettingsStore, AppSettingsStore } from '../state/AppSettingsStore'
import { getDatabaseService, DatabaseService } from './DatabaseService'

export class AssistantRuntimeConfig {
  assistantId: string = DEFAULT_ASSISTANT_ID
  systemPrompt: string = ''
  temperatureEnabled: boolean = false
  temperature: number = 0.7
  topPEnabled: boolean = false
  topP: number = 1.0
  presencePenaltyEnabled: boolean = false
  presencePenalty: number = 0
  frequencyPenaltyEnabled: boolean = false
  frequencyPenalty: number = 0
}

export class ResolvedAssistantModel {
  providerId: string = ''
  modelId: string = ''
  modelName: string = ''
  providerName: string = ''

  constructor(providerId: string = '', modelId: string = '', modelName: string = '', providerName: string = '') {
    this.providerId = providerId
    this.modelId = modelId
    this.modelName = modelName
    this.providerName = providerName
  }

  isConfigured(): boolean {
    return this.providerId !== '' && this.modelId !== ''
  }
}

class AssistantPresetMessageData {
  role: string
  content: string

  constructor(role: string, content: string) {
    this.role = role
    this.content = content
  }
}

/**
 * Assistant 视图模型：对外公开 API 保持不变，作为 AppSettingsStore 的 facade。
 *
 * 拆分原则与 ProviderViewModel 一致：
 * - 持久化 / 内存态 / currentAssistantId 同步 → AppSettingsStore 统一管理
 * - 数据规整（normalizeAssistant）、头像变更推断、session list 刷新脉冲 → 留在本服务
 *
 * 保留的脉冲字段（订阅端暂不改造）：
 * - SESSION_LIST_REFRESH_AT：任何 assistant 写操作后打一次时间戳，让首页会话列表刷新
 * - ASSISTANT_AVATAR_REFRESH_AT：avatarSymbol 或 color 变更时触发，让 avatar cache 失效
 */
export class AssistantService {
  private static instance: AssistantService | null = null
  private store: AppSettingsStore
  private db: DatabaseService

  private constructor() {
    this.store = getAppSettingsStore()
    this.db = getDatabaseService()
  }

  static getInstance(): AssistantService {
    if (AssistantService.instance === null) {
      AssistantService.instance = new AssistantService()
    }
    return AssistantService.instance
  }

  /**
   * 应用启动时调用，保证 assistants 列表和 currentAssistantId 都被加载到内存，
   * 并把当前 id 校正到一个在 DB 里实际存在的 assistant（若当前引用已失效则回落默认）
   */
  async initialize(): Promise<void> {
    await this.store.ensureAssistantsInitialized()
    await this.ensureValidCurrentAssistant()
  }

  // ============================================================================
  // 数据规整 & UI 脉冲 helpers
  // ============================================================================

  private normalizeAssistant(assistant: Assistant): Assistant {
    assistant.name = assistant.name.trim() !== '' ? assistant.name.trim() : '未命名助手'
    assistant.avatarSymbol = assistant.avatarSymbol.trim() !== '' ? assistant.avatarSymbol.trim() : 'AI'
    assistant.color = assistant.color.trim() !== '' ? assistant.color.trim() : DEFAULT_PRIMARY_COLOR
    if (assistant.id === DEFAULT_ASSISTANT_ID) {
      assistant.isDefault = true
    }
    if (assistant.temperature < 0) {
      assistant.temperature = 0
    } else if (assistant.temperature > 2) {
      assistant.temperature = 2
    }
    assistant.contextMessageSize = this.clampInteger(
      assistant.contextMessageSize,
      0,
      ASSISTANT_CONTEXT_MESSAGE_SIZE_MAX
    )
    assistant.maxTokens = this.clampInteger(assistant.maxTokens, 0, ASSISTANT_MAX_TOKENS_LIMIT)
    assistant.reasoningLevel = this.normalizeReasoningLevel(assistant.reasoningLevel)
    assistant.customHeadersJson = this.normalizeJsonObjectText(assistant.customHeadersJson)
    assistant.customBodiesJson = this.normalizeJsonObjectText(assistant.customBodiesJson)
    assistant.mcpServerIdsJson = this.normalizeStringArrayJsonText(assistant.mcpServerIdsJson)
    assistant.quickMessageIdsJson = this.normalizeStringArrayJsonText(assistant.quickMessageIdsJson)
    assistant.tagsJson = this.normalizeStringArrayJsonText(assistant.tagsJson)
    assistant.presetMessagesJson = this.normalizePresetMessagesJsonText(assistant.presetMessagesJson)
    return assistant
  }

  private clampInteger(value: number, min: number, max: number): number {
    if (Number.isNaN(value) || value === Infinity || value === -Infinity) {
      return min
    }
    const normalized = Math.floor(value)
    if (normalized < min) {
      return min
    }
    if (normalized > max) {
      return max
    }
    return normalized
  }

  private normalizeReasoningLevel(value: string): string {
    const normalized = value.trim()
    switch (normalized) {
      case '':
      case ReasoningLevel.OFF:
      case ReasoningLevel.AUTO:
      case ReasoningLevel.LOW:
      case ReasoningLevel.MEDIUM:
      case ReasoningLevel.HIGH:
      case ReasoningLevel.XHIGH:
        return normalized
      default:
        return ''
    }
  }

  private normalizeJsonObjectText(raw: string): string {
    const trimmed = raw.trim()
    if (trimmed === '') {
      return ''
    }
    try {
      const parsed = JSON.parse(trimmed) as Object
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed as Array<Object>)) {
        return ''
      }
      return JSON.stringify(parsed)
    } catch (_error) {
      return ''
    }
  }

  private normalizeStringArrayJsonText(raw: string): string {
    const trimmed = raw.trim()
    if (trimmed === '') {
      return ''
    }
    try {
      const parsed = JSON.parse(trimmed) as Object[]
      const values: string[] = []
      for (let i = 0; i < parsed.length; i++) {
        if (typeof parsed[i] !== 'string') {
          continue
        }
        const value = (parsed[i] as string).trim()
        if (value !== '' && !values.includes(value)) {
          values.push(value)
        }
      }
      return values.length > 0 ? JSON.stringify(values) : ''
    } catch (_error) {
      return ''
    }
  }

  private normalizePresetMessagesJsonText(raw: string): string {
    const trimmed = raw.trim()
    if (trimmed === '') {
      return ''
    }
    try {
      const parsed = JSON.parse(trimmed) as Array<Record<string, Object>>
      const messages: AssistantPresetMessageData[] = []
      for (let i = 0; i < parsed.length; i++) {
        const role = parsed[i]['role']
        const content = parsed[i]['content']
        if (typeof role !== 'string' || typeof content !== 'string') {
          continue
        }
        const normalizedRole = role.trim()
        const normalizedContent = content.trim()
        if ((normalizedRole === 'system' || normalizedRole === 'user' || normalizedRole === 'assistant') &&
          normalizedContent !== '') {
          messages.push(new AssistantPresetMessageData(normalizedRole, normalizedContent))
        }
      }
      return messages.length > 0 ? JSON.stringify(messages) : ''
    } catch (_error) {
      return ''
    }
  }

  private notifyAssistantAvatarChanged(): void {
    const current = getAppUiState().assistantAvatarRefreshAt
    const now = Date.now()
    setAppUiStateValue(AppStorageKeys.ASSISTANT_AVATAR_REFRESH_AT, now > current ? now : current + 1)
  }

  private hasAvatarPresentationChanged(previous: Assistant | null, next: Assistant): boolean {
    if (previous === null) {
      return true
    }
    return previous.avatarSymbol !== next.avatarSymbol || previous.color !== next.color
  }

  private pulseSessionList(): void {
    setAppUiStateValue(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())
  }

  // ============================================================================
  // 查询（内存优先，必要时 ensure）
  // ============================================================================

  async getAllAssistants(): Promise<Assistant[]> {
    await this.store.ensureAssistantsInitialized()
    return this.store.getAssistants()
  }

  async getAssistant(assistantId: string): Promise<Assistant | null> {
    await this.store.ensureAssistantsInitialized()
    const id = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    const cached = this.store.getAssistantById(id)
    if (cached !== null) {
      return cached
    }
    // 降级：如果内存里没有（可能是外部直写 DB），走一次回源
    return await this.store.getAssistantByIdAsync(id)
  }

  async getCurrentAssistantId(): Promise<string> {
    await this.store.ensureAssistantsInitialized()
    const id = this.store.getCurrentAssistantIdInMemory()
    return id.trim() !== '' ? id.trim() : DEFAULT_ASSISTANT_ID
  }

  async getCurrentAssistant(): Promise<Assistant> {
    await this.store.ensureAssistantsInitialized()
    const assistantId = await this.getCurrentAssistantId()
    const assistant = this.store.getAssistantById(assistantId)
    if (assistant !== null) {
      return assistant
    }
    // 当前 id 失效：回落默认，并把 Preferences 修正
    await this.store.setCurrentAssistantIdPersisted(DEFAULT_ASSISTANT_ID)
    const fallback = this.store.getAssistantById(DEFAULT_ASSISTANT_ID)
    if (fallback !== null) {
      return fallback
    }
    const all = this.store.getAssistants()
    return all.length > 0 ? all[0] : new Assistant(DEFAULT_ASSISTANT_ID, '默认助手')
  }

  /**
   * 专门给“发起新会话”用：跟 getCurrentAssistant 的主体一致，
   * 但额外会把兜底选择写回 Preferences，保证下次进入 new chat 时状态一致
   */
  async getCurrentAssistantForNewChat(): Promise<Assistant> {
    await this.store.ensureAssistantsInitialized()
    const assistantId = await this.getCurrentAssistantId()
    const assistant = this.store.getAssistantById(assistantId)
    if (assistant !== null) {
      return assistant
    }
    const fallback = this.store.getAssistantById(DEFAULT_ASSISTANT_ID)
    if (fallback !== null) {
      await this.store.setCurrentAssistantIdPersisted(fallback.id)
      return fallback
    }
    const all = this.store.getAssistants()
    if (all.length > 0) {
      await this.store.setCurrentAssistantIdPersisted(all[0].id)
      return all[0]
    }
    return new Assistant(DEFAULT_ASSISTANT_ID, '默认助手')
  }

  async ensureValidCurrentAssistant(): Promise<Assistant> {
    await this.store.ensureAssistantsInitialized()
    const currentId = this.store.getCurrentAssistantIdInMemory()
    const assistant = this.store.getAssistantById(currentId)
    if (assistant !== null) {
      return assistant
    }
    await this.store.setCurrentAssistantIdPersisted(DEFAULT_ASSISTANT_ID)
    const fallback = this.store.getAssistantById(DEFAULT_ASSISTANT_ID)
    if (fallback !== null) {
      return fallback
    }
    const all = this.store.getAssistants()
    return all.length > 0 ? all[0] : new Assistant(DEFAULT_ASSISTANT_ID, '默认助手')
  }

  /**
   * 把当前助手 id 切到目标 id。如果目标 id 在 DB/缓存里不存在则回落到 DEFAULT，
   * 再从回落后的状态读出 Assistant 返回（保证返回值可用）
   */
  async setCurrentAssistantId(assistantId: string): Promise<Assistant> {
    await this.store.ensureAssistantsInitialized()
    const id = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    const candidate = this.store.getAssistantById(id)
    const effectiveAssistant = candidate !== null ? candidate : await this.getCurrentAssistant()
    const effectiveId = candidate !== null ? id : DEFAULT_ASSISTANT_ID
    await this.store.setCurrentAssistantIdPersisted(effectiveId)
    this.pulseSessionList()
    return effectiveAssistant
  }

  // ============================================================================
  // 写操作
  // ============================================================================

  async createAssistant(assistant: Assistant): Promise<Assistant> {
    await this.store.ensureAssistantsInitialized()
    this.normalizeAssistant(assistant)
    if (assistant.id === '') {
      assistant.id = `assistant_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`
    }
    await this.store.upsertAssistant(assistant, true)
    this.pulseSessionList()
    this.notifyAssistantAvatarChanged()
    return assistant
  }

  async saveAssistant(assistant: Assistant): Promise<void> {
    await this.store.ensureAssistantsInitialized()
    this.normalizeAssistant(assistant)
    const previous = this.store.getAssistantById(assistant.id)
    const avatarChanged = this.hasAvatarPresentationChanged(previous, assistant)
    await this.store.upsertAssistant(assistant, false)
    this.pulseSessionList()
    if (avatarChanged) {
      this.notifyAssistantAvatarChanged()
    }
  }

  async reorderAssistants(assistants: Assistant[]): Promise<void> {
    if (assistants.length === 0) {
      return
    }
    await this.store.ensureAssistantsInitialized()
    await this.store.reorderAssistants(assistants)
    this.pulseSessionList()
  }

  async deleteAssistant(assistantId: string): Promise<boolean> {
    if (assistantId === DEFAULT_ASSISTANT_ID) {
      return false
    }
    await this.store.ensureAssistantsInitialized()
    const deleted = await this.store.removeAssistant(assistantId)
    if (deleted) {
      const currentId = this.store.getCurrentAssistantIdInMemory()
      if (currentId === assistantId) {
        await this.store.setCurrentAssistantIdPersisted(DEFAULT_ASSISTANT_ID)
      }
      this.pulseSessionList()
    }
    return deleted
  }

  /**
   * 某助手关联的会话数。跟 assistant 本身无缓存关系，直接透传 DB
   */
  async getAssistantSessionCount(assistantId: string): Promise<number> {
    return await this.db.getAssistantSessionCount(assistantId)
  }

  // ============================================================================
  // 派生配置
  // ============================================================================

  async getRuntimeConfig(assistantId: string): Promise<AssistantRuntimeConfig> {
    await this.store.ensureAssistantsInitialized()
    const config = new AssistantRuntimeConfig()
    const id = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    let assistant = this.store.getAssistantById(id)
    if (assistant === null) {
      assistant = this.store.getAssistantById(DEFAULT_ASSISTANT_ID)
    }
    if (assistant === null) {
      return config
    }
    config.assistantId = assistant.id
    config.systemPrompt = assistant.systemPrompt.trim()
    config.temperatureEnabled = assistant.temperatureEnabled
    config.temperature = assistant.temperature
    config.topPEnabled = assistant.topPEnabled
    config.topP = assistant.topP
    config.presencePenaltyEnabled = assistant.presencePenaltyEnabled
    config.presencePenalty = assistant.presencePenalty
    config.frequencyPenaltyEnabled = assistant.frequencyPenaltyEnabled
    config.frequencyPenalty = assistant.frequencyPenalty
    return config
  }

  async resolveChatModel(assistant: Assistant): Promise<ResolvedAssistantModel> {
    await this.store.ensureInitialized()
    await this.store.ensureDefaultModelsInitialized()

    const assistantModel = this.resolveEnabledModel(
      assistant.defaultProviderId,
      assistant.defaultModelId,
      assistant.defaultModelName,
      ''
    )
    if (assistantModel !== null) {
      return assistantModel
    }

    const defaultChatModel = this.store.getDefaultModel(ModelRole.CHAT)
    const fallbackModel = this.resolveEnabledModel(
      defaultChatModel.providerId,
      defaultChatModel.modelId,
      defaultChatModel.modelName,
      defaultChatModel.providerName
    )
    if (fallbackModel !== null) {
      return fallbackModel
    }

    return new ResolvedAssistantModel()
  }

  private resolveEnabledModel(
    providerId: string,
    modelId: string,
    modelNameFallback: string,
    providerNameFallback: string
  ): ResolvedAssistantModel | null {
    const normalizedProviderId = providerId.trim()
    const normalizedModelId = modelId.trim()
    if (normalizedProviderId === '' || normalizedModelId === '') {
      return null
    }

    const provider = this.store.getProviderById(normalizedProviderId)
    if (provider === null || !provider.isConnected) {
      return null
    }

    for (let i = 0; i < provider.models.length; i++) {
      const model = provider.models[i]
      if (model.id !== normalizedModelId || !model.isEnabled) {
        continue
      }
      const modelName = model.name.trim() !== '' ? model.name.trim() :
        (modelNameFallback.trim() !== '' ? modelNameFallback.trim() : model.id)
      const providerName = provider.name.trim() !== '' ? provider.name.trim() : providerNameFallback.trim()
      return new ResolvedAssistantModel(provider.id, model.id, modelName, providerName)
    }
    return null
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
