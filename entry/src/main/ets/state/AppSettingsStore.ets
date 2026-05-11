import { getDatabaseService, DatabaseService, ProviderConfig } from '../services/DatabaseService'
import { getPreferencesService, PreferencesService, PreferenceKeys } from '../services/PreferencesService'
import {
  ModelProvider,
  ModelInfo,
  ProviderType,
  ApiStyle,
  OpenAITransport,
  ModelCapabilities,
  ModelType,
  InputMode,
  OutputMode,
  ModelCapabilitiesJson,
  ProviderIconType,
  DefaultModelConfig,
  ModelRole
} from '../models/ChatModels'
import { Assistant, DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'
import { DefaultPrompts } from '../config/DefaultPrompts'
import {
  getPresetProviderIconPath,
  isPresetProvider,
  getPresetProviderById,
  isPresetProviderApiKeyRequired,
  applyPresetIconDefaults,
  getPresetProviderLogoUrl
} from '../config/PresetProviders'
import { AppSettingsState, getAppSettingsState } from './AppSettingsState'

/**
 * 模型 JSON 中的扩展字段（跟 ProviderViewModel 里原先的 ModelData 同构）
 */
interface ModelJsonRow {
  id: string
  name: string
  contextLength: number
  isEnabled?: boolean
  isRecommended: boolean
  modelType?: string
  inputMode?: string
  outputMode?: string
  capabilities?: ModelCapabilitiesJson
  reasoningStrategyOverride?: string
}

/**
 * 预置服务商启动时补齐的 ID 顺序（硅基流动放最前）
 */
const ALL_PRESET_PROVIDER_IDS: string[] = [
  'siliconflow', 'openai', 'anthropic', 'deepseek', 'gemini',
  'openrouter', 'qwen', 'kimi', 'zhipu', 'doubao',
  'minimax', 'aihubmix', 'grok', 'mimo', 'ollama'
]

/**
 * 历史错误 baseUrl 迁移规则：providerId → 期望的 baseUrl
 * 之前 MiniMax 误用 api.minimax.chat，已切换到 api.minimaxi.com
 */
interface BaseUrlFix {
  providerId: string
  wrongBaseUrl: string
  correctBaseUrl: string
}

const HISTORICAL_BASE_URL_FIXES: BaseUrlFix[] = [
  { providerId: 'minimax', wrongBaseUrl: 'https://api.minimax.chat/v1', correctBaseUrl: 'https://api.minimaxi.com/v1' }
]

/**
 * 应用设置 Store（当前阶段只管 providers）
 *
 * 作为 SQLite + 预设补齐 + 运行时内存状态的唯一入口。
 * - 读：先走内存 state.providers；未初始化时回源 DB
 * - 写：先写 DB，再整数组替换 state.providers 并自增 providersVersion 触发 @Trace
 *
 * 设计原则：
 * 1. 所有 Provider 的持久化只经过这里，避免多个服务各自缓存导致不一致
 * 2. 内存写操作采用“新建数组 + 整体赋值”方式，保证即使只改一个子字段也会触发响应式刷新
 * 3. normalize pipeline（URL 修复、预设补齐、图标迁移）集中在本类内，便于后续扩展
 */
export class AppSettingsStore {
  private static instance: AppSettingsStore | null = null
  private db: DatabaseService
  private preferences: PreferencesService
  private initPromise: Promise<void> | null = null
  private assistantsInitPromise: Promise<void> | null = null
  private defaultModelsInitPromise: Promise<void> | null = null

  private constructor() {
    this.db = getDatabaseService()
    this.preferences = getPreferencesService()
  }

  static getInstance(): AppSettingsStore {
    if (AppSettingsStore.instance === null) {
      AppSettingsStore.instance = new AppSettingsStore()
    }
    return AppSettingsStore.instance
  }

  // ============================================================================
  // 查询（不碰 DB）
  // ============================================================================

  /** 返回当前内存中的所有 providers（含未启用），调用方只读 */
  getProviders(): ModelProvider[] {
    return getAppSettingsState().providers
  }

  /** 只返回启用状态的 providers，用于模型选择等面向用户的入口 */
  getEnabledProviders(): ModelProvider[] {
    const all = this.getProviders()
    const enabled: ModelProvider[] = []
    for (let i = 0; i < all.length; i++) {
      if (all[i].isConnected) {
        enabled.push(all[i])
      }
    }
    return enabled
  }

  /** 根据 ID 查找内存中的 provider；未命中返回 null（不触发回源） */
  getProviderById(providerId: string): ModelProvider | null {
    const list = this.getProviders()
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === providerId) {
        return list[i]
      }
    }
    return null
  }

  /** 异步查找：缓存未命中时做一次 loadAll 回源再取 */
  async getProviderByIdAsync(providerId: string): Promise<ModelProvider | null> {
    const cached = this.getProviderById(providerId)
    if (cached !== null) {
      return cached
    }
    await this.loadAll()
    return this.getProviderById(providerId)
  }

  // ============================================================================
  // 加载（DB → normalize → state）
  // ============================================================================

  /**
   * 从 DB 拉一遍 providers，更新内存 state；返回同样的数组以兼容原调用方
   */
  async loadAll(): Promise<ModelProvider[]> {
    const configs = await this.db.getAllProviders()
    const providers: ModelProvider[] = []
    for (let i = 0; i < configs.length; i++) {
      providers.push(this.configToProvider(configs[i]))
    }
    this.setProviders(providers)
    return providers
  }

  /**
   * 启动初始化：历史 URL 修复 + 预设补齐 + 加载到内存。
   * 多次调用合并为同一个 promise，不会重复执行
   */
  async ensureInitialized(): Promise<void> {
    if (getAppSettingsState().providersInitialized) {
      return
    }
    if (this.initPromise !== null) {
      await this.initPromise
      return
    }
    this.initPromise = this.doInitialize()
    try {
      await this.initPromise
    } finally {
      this.initPromise = null
    }
  }

  private async doInitialize(): Promise<void> {
    const existingConfigs = await this.db.getAllProviders()

    await this.applyHistoricalBaseUrlFixes(existingConfigs)

    const existingIds = new Set<string>()
    for (let i = 0; i < existingConfigs.length; i++) {
      existingIds.add(existingConfigs[i].id)
    }

    for (let i = 0; i < ALL_PRESET_PROVIDER_IDS.length; i++) {
      const presetId = ALL_PRESET_PROVIDER_IDS[i]
      if (!existingIds.has(presetId)) {
        const preset = getPresetProviderById(presetId)
        if (preset !== null) {
          const provider = new ModelProvider(
            preset.id,
            preset.name,
            preset.type,
            'message',
            this.brandColorFor(preset.type),
            preset.baseUrl,
            preset.apiStyle
          )
          provider.apiKey = ''
          provider.requiresApiKey = isPresetProviderApiKeyRequired(preset.id)
          provider.isConnected = preset.id === 'siliconflow'
          provider.isPreset = true
          provider.iconPath = ''
          provider.apiPath = ''
          provider.openaiTransport = preset.openaiTransport !== undefined
            ? preset.openaiTransport
            : OpenAITransport.CHAT_COMPLETIONS
          applyPresetIconDefaults(provider, preset.id)
          // 这里直接写 DB；loadAll 会把最终结果 sync 到 state
          await this.db.saveProvider(provider)
        }
      }
    }

    await this.loadAll()
    getAppSettingsState().providersInitialized = true
  }

  private async applyHistoricalBaseUrlFixes(configs: ProviderConfig[]): Promise<void> {
    for (let i = 0; i < configs.length; i++) {
      const cfg = configs[i]
      for (let j = 0; j < HISTORICAL_BASE_URL_FIXES.length; j++) {
        const fix = HISTORICAL_BASE_URL_FIXES[j]
        if (cfg.id === fix.providerId && cfg.baseUrl === fix.wrongBaseUrl) {
          await this.db.updateProviderBaseUrl(fix.providerId, fix.correctBaseUrl)
        }
      }
    }
  }

  // ============================================================================
  // 写入（DB + state）
  // ============================================================================

  /** 新增或更新 provider：写 DB + 同步内存数组 */
  async upsertProvider(provider: ModelProvider, insertAtFront: boolean = false): Promise<void> {
    await this.db.saveProvider(provider, insertAtFront)
    const current = this.getProviders()
    const next: ModelProvider[] = []
    let replaced = false
    for (let i = 0; i < current.length; i++) {
      if (current[i].id === provider.id) {
        next.push(provider)
        replaced = true
      } else {
        next.push(current[i])
      }
    }
    if (!replaced) {
      if (insertAtFront) {
        next.unshift(provider)
      } else {
        next.push(provider)
      }
    }
    this.setProviders(next)
  }

  /** 删除 provider：写 DB + 从内存数组过滤掉 */
  async removeProvider(providerId: string): Promise<void> {
    await this.db.deleteProvider(providerId)
    const current = this.getProviders()
    const next: ModelProvider[] = []
    for (let i = 0; i < current.length; i++) {
      if (current[i].id !== providerId) {
        next.push(current[i])
      }
    }
    this.setProviders(next)
  }

  /** 改启用状态：写 DB + 同步到内存数组 */
  async setProviderEnabled(providerId: string, isEnabled: boolean): Promise<void> {
    await this.db.updateProviderEnabled(providerId, isEnabled)
    const current = this.getProviders()
    const next: ModelProvider[] = []
    for (let i = 0; i < current.length; i++) {
      const p = current[i]
      if (p.id === providerId) {
        p.isConnected = isEnabled
      }
      next.push(p)
    }
    this.setProviders(next)
  }

  /** 按给定 id 顺序重排 */
  async reorderProviders(providerIds: string[]): Promise<void> {
    await this.db.updateProvidersOrder(providerIds)
    const current = this.getProviders()
    const sorted: ModelProvider[] = []
    for (let i = 0; i < providerIds.length; i++) {
      const id = providerIds[i]
      for (let j = 0; j < current.length; j++) {
        if (current[j].id === id) {
          sorted.push(current[j])
          break
        }
      }
    }
    // 兜底：不在 providerIds 里的也保留，避免误丢数据
    for (let j = 0; j < current.length; j++) {
      let found = false
      for (let i = 0; i < providerIds.length; i++) {
        if (providerIds[i] === current[j].id) {
          found = true
          break
        }
      }
      if (!found) {
        sorted.push(current[j])
      }
    }
    this.setProviders(sorted)
  }

  /**
   * 给 state.providers 换成新数组，并自增 providersVersion。
   * @Trace 只能追踪数组“整体”变化，所以必须用新引用替换
   */
  private setProviders(next: ModelProvider[]): void {
    const state: AppSettingsState = getAppSettingsState()
    state.providers = next
    state.providersVersion = state.providersVersion + 1
  }

  // ============================================================================
  // ProviderConfig ↔ ModelProvider 转换
  // ============================================================================

  /**
   * 从 DB 行（ProviderConfig）反序列化回运行时 ModelProvider。
   * 原先在 ProviderViewModel.configToProvider 里，搬到这里让 Store 自洽
   */
  configToProvider(config: ProviderConfig): ModelProvider {
    const providerType = this.stringToProviderType(config.type)
    const apiStyle = this.stringToApiStyle(config.apiStyle)
    const provider = new ModelProvider(
      config.id,
      config.name,
      providerType,
      config.iconSymbol,
      this.brandColorFor(providerType),
      config.baseUrl,
      apiStyle
    )
    provider.apiKey = config.apiKey
    provider.requiresApiKey = (providerType === ProviderType.OLLAMA || providerType === ProviderType.LMSTUDIO)
      ? false
      : config.requiresApiKey
    provider.isConnected = config.isEnabled

    provider.isPreset = config.isPreset || isPresetProvider(config.id)
    provider.iconPath = config.iconPath !== '' ? config.iconPath : getPresetProviderIconPath(config.id)
    provider.apiPath = config.apiPath !== undefined ? config.apiPath : ''
    provider.openaiTransport = config.openaiTransport === OpenAITransport.RESPONSES
      ? OpenAITransport.RESPONSES
      : OpenAITransport.CHAT_COMPLETIONS
    provider.customHeadersJson = config.customHeadersJson !== undefined ? config.customHeadersJson : ''

    provider.iconType = (config.iconType !== undefined && config.iconType !== '')
      ? config.iconType as ProviderIconType
      : ProviderIconType.SVG
    provider.textIcon = config.textIcon !== undefined ? config.textIcon : ''
    provider.textIconBgColor = config.textIconBgColor !== undefined ? config.textIconBgColor : ''
    provider.customImagePath = config.customImagePath !== undefined ? config.customImagePath : ''

    // 预设图标迁移：保留用户自定义；其它用预设默认覆盖
    if (provider.isPreset) {
      const preset = getPresetProviderById(config.id)
      if (preset !== null) {
        const presetLogoUrl = getPresetProviderLogoUrl(preset.id)
        const isUserCustomImage = provider.iconType === ProviderIconType.IMAGE
          && provider.customImagePath !== ''
          && provider.customImagePath !== presetLogoUrl
        const savedTextIcon: string = config.textIcon !== undefined ? config.textIcon : ''
        const isUserCustomText = provider.iconType === ProviderIconType.TEXT
          && savedTextIcon !== ''
          && savedTextIcon !== preset.textIcon

        if (!isUserCustomImage && !isUserCustomText) {
          applyPresetIconDefaults(provider, preset.id)
        } else {
          provider.iconPath = ''
        }
      }
    }

    if (config.modelsJson !== undefined && config.modelsJson !== null && config.modelsJson !== '') {
      try {
        const modelsArray: ModelJsonRow[] = JSON.parse(config.modelsJson) as ModelJsonRow[]
        for (let i = 0; i < modelsArray.length; i++) {
          const modelObj = modelsArray[i]
          const shouldEnable = modelObj.isEnabled !== undefined ? modelObj.isEnabled : true
          const modelInfo = new ModelInfo(
            modelObj.id,
            modelObj.name,
            modelObj.contextLength,
            shouldEnable,
            modelObj.isRecommended
          )
          if (modelObj.modelType !== undefined) {
            modelInfo.modelType = modelObj.modelType === 'embedding' ? ModelType.EMBEDDING : ModelType.CHAT
          }
          if (modelObj.inputMode !== undefined) {
            modelInfo.inputMode = modelObj.inputMode === 'vision' ? InputMode.VISION : InputMode.TEXT
          }
          if (modelObj.outputMode !== undefined) {
            modelInfo.outputMode = modelObj.outputMode === 'image' ? OutputMode.IMAGE : OutputMode.TEXT
          }
          if (modelObj.capabilities !== undefined) {
            modelInfo.capabilities = ModelCapabilities.fromJson(modelObj.capabilities)
          }
          if (modelObj.reasoningStrategyOverride !== undefined) {
            modelInfo.reasoningStrategyOverride = modelObj.reasoningStrategyOverride
          }
          provider.models.push(modelInfo)
        }
      } catch (error) {
        console.error('AppSettingsStore', `Failed to parse models JSON: ${JSON.stringify(error)}`)
      }
    } else {
      provider.models = []
    }

    return provider
  }

  private stringToProviderType(typeStr: string): ProviderType {
    if (typeStr === 'openai') {
      return ProviderType.OPENAI
    } else if (typeStr === 'anthropic') {
      return ProviderType.ANTHROPIC
    } else if (typeStr === 'azure') {
      return ProviderType.AZURE
    } else if (typeStr === 'deepseek') {
      return ProviderType.DEEPSEEK
    } else if (typeStr === 'ollama') {
      return ProviderType.OLLAMA
    } else if (typeStr === 'lmstudio') {
      return ProviderType.LMSTUDIO
    } else if (typeStr === 'custom') {
      return ProviderType.CUSTOM
    }
    return ProviderType.OPENAI
  }

  private stringToApiStyle(styleStr: string): ApiStyle {
    if (styleStr === 'openai') {
      return ApiStyle.OPENAI
    } else if (styleStr === 'anthropic') {
      return ApiStyle.ANTHROPIC
    } else if (styleStr === 'google') {
      return ApiStyle.GOOGLE
    }
    return ApiStyle.OPENAI
  }

  /**
   * ProviderType 对应的品牌色资源。迁自原 ProviderViewModel.getProviderBrandColor
   */
  brandColorFor(type: ProviderType): Resource {
    if (type === ProviderType.OPENAI) {
      return $r('app.color.brand_openai')
    } else if (type === ProviderType.ANTHROPIC) {
      return $r('app.color.brand_anthropic')
    } else if (type === ProviderType.AZURE) {
      return $r('app.color.brand_azure')
    } else if (type === ProviderType.DEEPSEEK) {
      return $r('app.color.brand_deepseek')
    }
    return $r('app.color.primary')
  }

  // ============================================================================
  // Assistant —— 查询（不碰 DB）
  // ============================================================================

  /** 返回当前内存中的所有 assistants，调用方只读 */
  getAssistants(): Assistant[] {
    return getAppSettingsState().assistants
  }

  /** 根据 ID 查找内存中的 assistant；未命中返回 null（不触发回源） */
  getAssistantById(assistantId: string): Assistant | null {
    const list = this.getAssistants()
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === assistantId) {
        return list[i]
      }
    }
    return null
  }

  /**
   * 内存未命中时回源 DB，但不会刷新整个 state（单个 assistant 场景不值得整表同步）
   */
  async getAssistantByIdAsync(assistantId: string): Promise<Assistant | null> {
    const cached = this.getAssistantById(assistantId)
    if (cached !== null) {
      return cached
    }
    return await this.db.getAssistant(assistantId)
  }

  /** 从 state 读当前助手 id（已是 Preferences 同步值） */
  getCurrentAssistantIdInMemory(): string {
    return getAppSettingsState().currentAssistantId
  }

  // ============================================================================
  // Assistant —— 加载
  // ============================================================================

  /** 从 DB 拉一遍 assistants，更新内存 state */
  async loadAllAssistants(): Promise<Assistant[]> {
    const list = await this.db.getAllAssistants()
    this.setAssistants(list)
    return list
  }

  /**
   * 启动初始化：加载所有 assistants + 同步 currentAssistantId 到 state。
   * 多次调用合并为同一个 promise，不会重复执行
   */
  async ensureAssistantsInitialized(): Promise<void> {
    if (getAppSettingsState().assistantsInitialized) {
      return
    }
    if (this.assistantsInitPromise !== null) {
      await this.assistantsInitPromise
      return
    }
    this.assistantsInitPromise = this.doInitializeAssistants()
    try {
      await this.assistantsInitPromise
    } finally {
      this.assistantsInitPromise = null
    }
  }

  private async doInitializeAssistants(): Promise<void> {
    await this.loadAllAssistants()
    const storedId = await this.preferences.getCurrentAssistantId()
    const trimmed = storedId.trim() !== '' ? storedId.trim() : DEFAULT_ASSISTANT_ID
    this.setCurrentAssistantIdInMemory(trimmed)
    getAppSettingsState().assistantsInitialized = true
  }

  // ============================================================================
  // Assistant —— 写入（DB + state）
  // ============================================================================

  /**
   * 新增或更新 assistant：写 DB + 同步内存数组。
   * insert=true 时调用 createAssistant（走自增 sort_order 路径），否则 saveAssistant（原地更新）
   */
  async upsertAssistant(assistant: Assistant, insert: boolean): Promise<void> {
    if (insert) {
      await this.db.createAssistant(assistant)
    } else {
      await this.db.saveAssistant(assistant)
    }
    const current = this.getAssistants()
    const next: Assistant[] = []
    let replaced = false
    for (let i = 0; i < current.length; i++) {
      if (current[i].id === assistant.id) {
        next.push(assistant)
        replaced = true
      } else {
        next.push(current[i])
      }
    }
    if (!replaced) {
      next.push(assistant)
    }
    this.setAssistants(next)
  }

  /** 删 assistant：返回 DB 是否真的删了，删掉后从内存过滤 */
  async removeAssistant(assistantId: string): Promise<boolean> {
    const deleted = await this.db.deleteAssistant(assistantId)
    if (!deleted) {
      return false
    }
    const current = this.getAssistants()
    const next: Assistant[] = []
    for (let i = 0; i < current.length; i++) {
      if (current[i].id !== assistantId) {
        next.push(current[i])
      }
    }
    this.setAssistants(next)
    return true
  }

  /**
   * 按给定顺序 + sortOrder 持久化，同步到内存
   * 入参数组的 sortOrder 会被覆写成 index，以保持与 DB 一致
   */
  async reorderAssistants(assistants: Assistant[]): Promise<void> {
    if (assistants.length === 0) {
      return
    }
    for (let i = 0; i < assistants.length; i++) {
      assistants[i].sortOrder = i
    }
    await this.db.saveAssistantSortOrders(assistants)
    // 以入参为新顺序；若原 state 里还有额外项（通常不会），兜底追加
    const seen = new Set<string>()
    const next: Assistant[] = []
    for (let i = 0; i < assistants.length; i++) {
      next.push(assistants[i])
      seen.add(assistants[i].id)
    }
    const current = this.getAssistants()
    for (let j = 0; j < current.length; j++) {
      if (!seen.has(current[j].id)) {
        next.push(current[j])
      }
    }
    this.setAssistants(next)
  }

  /**
   * 更新 currentAssistantId：写 Preferences + 同步到 state。
   * 空串会被规整为 DEFAULT_ASSISTANT_ID，语义与 PreferencesService 保持一致
   */
  async setCurrentAssistantIdPersisted(assistantId: string): Promise<void> {
    const normalized = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    await this.preferences.setCurrentAssistantId(normalized)
    this.setCurrentAssistantIdInMemory(normalized)
  }

  // ============================================================================
  // Assistant —— state 刷新 helpers
  // ============================================================================

  private setAssistants(next: Assistant[]): void {
    const state = getAppSettingsState()
    state.assistants = next
    state.assistantsVersion = state.assistantsVersion + 1
  }

  private setCurrentAssistantIdInMemory(id: string): void {
    getAppSettingsState().currentAssistantId = id
  }

  // ============================================================================
  // DefaultModel —— 加载 / 读 / 写（Preferences 层）
  // ============================================================================

  /** 读内存中对应 role 的 default model 配置 */
  getDefaultModel(role: ModelRole): DefaultModelConfig {
    const s = getAppSettingsState()
    if (role === ModelRole.CHAT) {
      return s.defaultChatModel
    } else if (role === ModelRole.TITLE) {
      return s.defaultTitleModel
    } else if (role === ModelRole.TRANSLATE) {
      return s.defaultTranslateModel
    } else if (role === ModelRole.SEARCH_OPTIMIZATION) {
      return s.defaultSearchOptimizationModel
    }
    return new DefaultModelConfig()
  }

  /** 启动时加载四个 role 的 default model（幂等，多次调用合并为一个 promise） */
  async ensureDefaultModelsInitialized(): Promise<void> {
    if (getAppSettingsState().defaultModelsInitialized) {
      return
    }
    if (this.defaultModelsInitPromise !== null) {
      await this.defaultModelsInitPromise
      return
    }
    this.defaultModelsInitPromise = this.doInitializeDefaultModels()
    try {
      await this.defaultModelsInitPromise
    } finally {
      this.defaultModelsInitPromise = null
    }
  }

  /** 强制刷新（DefaultModelPage.loadConfig 的语义） */
  async reloadDefaultModels(): Promise<void> {
    await this.doInitializeDefaultModels()
    getAppSettingsState().defaultModelsInitialized = true
  }

  private async doInitializeDefaultModels(): Promise<void> {
    const chat = await this.loadDefaultModelFromPreferences(
      PreferenceKeys.DEFAULT_CHAT_MODEL_ID,
      PreferenceKeys.DEFAULT_CHAT_PROVIDER_ID,
      PreferenceKeys.DEFAULT_CHAT_MODEL_NAME,
      PreferenceKeys.DEFAULT_CHAT_PROVIDER_NAME,
      '', '', '', ''
    )
    const title = await this.loadDefaultModelFromPreferences(
      PreferenceKeys.DEFAULT_TITLE_MODEL_ID,
      PreferenceKeys.DEFAULT_TITLE_PROVIDER_ID,
      PreferenceKeys.DEFAULT_TITLE_MODEL_NAME,
      PreferenceKeys.DEFAULT_TITLE_PROVIDER_NAME,
      DefaultPrompts.SILICONFLOW_TITLE_MODEL,
      DefaultPrompts.SILICONFLOW_PROVIDER_ID,
      DefaultPrompts.SILICONFLOW_TITLE_MODEL,
      '硅基流动'
    )
    const translate = await this.loadDefaultModelFromPreferences(
      PreferenceKeys.DEFAULT_TRANSLATE_MODEL_ID,
      PreferenceKeys.DEFAULT_TRANSLATE_PROVIDER_ID,
      PreferenceKeys.DEFAULT_TRANSLATE_MODEL_NAME,
      PreferenceKeys.DEFAULT_TRANSLATE_PROVIDER_NAME,
      DefaultPrompts.SILICONFLOW_TRANSLATE_MODEL,
      DefaultPrompts.SILICONFLOW_PROVIDER_ID,
      DefaultPrompts.SILICONFLOW_TRANSLATE_MODEL,
      '硅基流动'
    )
    const searchOpt = await this.loadDefaultModelFromPreferences(
      PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_MODEL_ID,
      PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_PROVIDER_ID,
      PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_MODEL_NAME,
      PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_PROVIDER_NAME,
      DefaultPrompts.SILICONFLOW_SEARCH_OPTIMIZATION_MODEL,
      DefaultPrompts.SILICONFLOW_PROVIDER_ID,
      DefaultPrompts.SILICONFLOW_SEARCH_OPTIMIZATION_MODEL,
      '硅基流动'
    )

    const s = getAppSettingsState()
    s.defaultChatModel = chat
    s.defaultTitleModel = title
    s.defaultTranslateModel = translate
    s.defaultSearchOptimizationModel = searchOpt
    s.defaultModelsVersion = s.defaultModelsVersion + 1
    s.defaultModelsInitialized = true
  }

  private async loadDefaultModelFromPreferences(
    modelIdKey: string, providerIdKey: string, modelNameKey: string, providerNameKey: string,
    modelIdFallback: string, providerIdFallback: string, modelNameFallback: string, providerNameFallback: string
  ): Promise<DefaultModelConfig> {
    const modelId = await this.preferences.getString(modelIdKey, modelIdFallback)
    const providerId = await this.preferences.getString(providerIdKey, providerIdFallback)
    const modelName = await this.preferences.getString(modelNameKey, modelNameFallback)
    const providerName = await this.preferences.getString(providerNameKey, providerNameFallback)
    return new DefaultModelConfig(modelId, providerId, modelName, providerName)
  }

  /** 写某个 role 的 default model：Preferences 持久化 + state 同步 */
  async setDefaultModel(role: ModelRole, config: DefaultModelConfig): Promise<void> {
    const keys = this.preferenceKeysFor(role)
    if (keys === null) {
      return
    }
    await this.preferences.setString(keys.modelIdKey, config.modelId)
    await this.preferences.setString(keys.providerIdKey, config.providerId)
    await this.preferences.setString(keys.modelNameKey, config.modelName)
    await this.preferences.setString(keys.providerNameKey, config.providerName)

    const s = getAppSettingsState()
    if (role === ModelRole.CHAT) {
      s.defaultChatModel = config
    } else if (role === ModelRole.TITLE) {
      s.defaultTitleModel = config
    } else if (role === ModelRole.TRANSLATE) {
      s.defaultTranslateModel = config
    } else if (role === ModelRole.SEARCH_OPTIMIZATION) {
      s.defaultSearchOptimizationModel = config
    }
    s.defaultModelsVersion = s.defaultModelsVersion + 1
  }

  private preferenceKeysFor(role: ModelRole): DefaultModelPreferenceKeys | null {
    if (role === ModelRole.CHAT) {
      return {
        modelIdKey: PreferenceKeys.DEFAULT_CHAT_MODEL_ID,
        providerIdKey: PreferenceKeys.DEFAULT_CHAT_PROVIDER_ID,
        modelNameKey: PreferenceKeys.DEFAULT_CHAT_MODEL_NAME,
        providerNameKey: PreferenceKeys.DEFAULT_CHAT_PROVIDER_NAME
      }
    } else if (role === ModelRole.TITLE) {
      return {
        modelIdKey: PreferenceKeys.DEFAULT_TITLE_MODEL_ID,
        providerIdKey: PreferenceKeys.DEFAULT_TITLE_PROVIDER_ID,
        modelNameKey: PreferenceKeys.DEFAULT_TITLE_MODEL_NAME,
        providerNameKey: PreferenceKeys.DEFAULT_TITLE_PROVIDER_NAME
      }
    } else if (role === ModelRole.TRANSLATE) {
      return {
        modelIdKey: PreferenceKeys.DEFAULT_TRANSLATE_MODEL_ID,
        providerIdKey: PreferenceKeys.DEFAULT_TRANSLATE_PROVIDER_ID,
        modelNameKey: PreferenceKeys.DEFAULT_TRANSLATE_MODEL_NAME,
        providerNameKey: PreferenceKeys.DEFAULT_TRANSLATE_PROVIDER_NAME
      }
    } else if (role === ModelRole.SEARCH_OPTIMIZATION) {
      return {
        modelIdKey: PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_MODEL_ID,
        providerIdKey: PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_PROVIDER_ID,
        modelNameKey: PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_MODEL_NAME,
        providerNameKey: PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_PROVIDER_NAME
      }
    }
    return null
  }
}

interface DefaultModelPreferenceKeys {
  modelIdKey: string
  providerIdKey: string
  modelNameKey: string
  providerNameKey: string
}

export function getAppSettingsStore(): AppSettingsStore {
  return AppSettingsStore.getInstance()
}
