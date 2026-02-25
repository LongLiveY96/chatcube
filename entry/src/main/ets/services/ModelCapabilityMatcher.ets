import { http } from '@kit.NetworkKit'
import { ModelInfo, InputMode } from '../models/ChatModels'
import { PreferenceKeys, getPreferencesService } from './PreferencesService'

// models.dev 单个模型的数据结构
interface ModelsDevModalities {
  input: string[]
  output: string[]
}

interface ModelsDevLimit {
  context: number
  output: number
}

interface ModelsDevEntry {
  id: string
  name: string
  family: string
  reasoning: boolean
  tool_call: boolean
  modalities: ModelsDevModalities
  limit: ModelsDevLimit
}

// models.dev 供应商结构
interface ModelsDevProvider {
  id: string
  models: Record<string, ModelsDevEntry>
}

// models.dev 顶层结构：供应商 ID → 供应商对象
type ModelsDevData = Record<string, ModelsDevProvider>

// 持久化的模型图标索引项
interface PersistedLogoIndexEntry {
  modelId: string
  logoUrl: string
}

// 模型能力匹配服务（单例）
export class ModelCapabilityMatcher {
  private static instance: ModelCapabilityMatcher | null = null
  // 扁平化缓存：模型 ID → 模型条目
  private cache: Map<string, ModelsDevEntry> = new Map()
  // 小写索引：模型 ID 小写 → 原始模型 ID（用于大小写不敏感回退匹配）
  private lowerCaseIndex: Map<string, string> = new Map()
  // family → 原厂供应商 key（用于获取正确的 logo）
  private familyLogoMap: Map<string, string> = new Map()
  // 所有供应商 key 集合（用于从模型 ID 前缀推断原厂）
  private allProviderKeys: Set<string> = new Set()
  private cacheTimestamp: number = 0
  private readonly CACHE_TTL: number = 24 * 60 * 60 * 1000 // 24h
  private fetchPromise: Promise<boolean> | null = null
  private baseUrl: string = 'https://models.dev'
  // 模型 ID（含别名） -> logo URL
  private persistedLogoIndex: Map<string, string> = new Map()
  private isPersistedLogoIndexLoaded: boolean = false
  private saveLogoIndexTimerId: number = -1
  private readonly LOGO_INDEX_SAVE_DEBOUNCE_MS: number = 1200

  private constructor() {
  }

  static getInstance(): ModelCapabilityMatcher {
    if (ModelCapabilityMatcher.instance === null) {
      ModelCapabilityMatcher.instance = new ModelCapabilityMatcher()
    }
    return ModelCapabilityMatcher.instance
  }

  // 批量匹配并填充模型能力，返回成功匹配数量
  async applyCapabilitiesBatch(models: ModelInfo[]): Promise<number> {
    const prefs = getPreferencesService()
    const enabled = await prefs.getBoolean(PreferenceKeys.MODELS_DEV_ENABLED, true)
    if (!enabled) {
      return 0
    }

    const loaded = await this.ensureCache()
    if (!loaded) {
      return 0
    }

    let matched = 0
    for (let i = 0; i < models.length; i++) {
      const model = models[i]
      const entry = this.findEntry(model.id)
      if (entry !== null) {
        this.applyEntry(model, entry)
        matched++
      }
      const logoUrl = this.getLogoUrlFromCache(model.id)
      if (logoUrl !== '') {
        this.recordModelLogo(model.id, logoUrl)
      }
    }
    return matched
  }

  // 启动时加载持久化的模型图标索引
  async loadPersistedLogoIndex(): Promise<void> {
    if (this.isPersistedLogoIndexLoaded) {
      return
    }

    const prefs = getPreferencesService()
    const raw = await prefs.getString(PreferenceKeys.MODEL_LOGO_INDEX_JSON, '')
    this.persistedLogoIndex.clear()

    if (raw !== '') {
      try {
        const parsed: Object = JSON.parse(raw) as Object
        if (Array.isArray(parsed)) {
          const entries = parsed as PersistedLogoIndexEntry[]
          for (let i = 0; i < entries.length; i++) {
            const entry = entries[i]
            if (entry.modelId !== undefined && entry.logoUrl !== undefined &&
              entry.modelId !== '' && entry.logoUrl !== '') {
              this.persistedLogoIndex.set(entry.modelId, entry.logoUrl)
            }
          }
        }
      } catch (error) {
        console.warn('ModelCapabilityMatcher', `Failed to parse persisted logo index: ${JSON.stringify(error)}`)
      }
    }

    this.isPersistedLogoIndexLoaded = true
  }

  // 保存模型图标索引到偏好设置
  async savePersistedLogoIndex(): Promise<void> {
    const entries: PersistedLogoIndexEntry[] = []
    this.persistedLogoIndex.forEach((logoUrl: string, modelId: string) => {
      if (modelId !== '' && logoUrl !== '') {
        entries.push({
          modelId: modelId,
          logoUrl: logoUrl
        })
      }
    })
    const prefs = getPreferencesService()
    await prefs.setString(PreferenceKeys.MODEL_LOGO_INDEX_JSON, JSON.stringify(entries))
  }

  // 记录模型图标映射并节流持久化
  recordModelLogo(modelId: string, logoUrl: string): void {
    if (modelId === '' || logoUrl === '') {
      return
    }
    const aliases = this.buildModelIdAliases(modelId)
    let changed = false
    for (let i = 0; i < aliases.length; i++) {
      const alias = aliases[i]
      const existing = this.persistedLogoIndex.get(alias)
      if (existing !== logoUrl) {
        this.persistedLogoIndex.set(alias, logoUrl)
        changed = true
      }
    }
    if (changed) {
      this.schedulePersistedLogoIndexSave()
    }
  }

  private schedulePersistedLogoIndexSave(): void {
    if (this.saveLogoIndexTimerId !== -1) {
      clearTimeout(this.saveLogoIndexTimerId)
    }
    this.saveLogoIndexTimerId = setTimeout(() => {
      this.saveLogoIndexTimerId = -1
      this.savePersistedLogoIndex()
        .catch((error: Object) => {
          console.warn('ModelCapabilityMatcher', `Failed to persist logo index: ${JSON.stringify(error)}`)
        })
    }, this.LOGO_INDEX_SAVE_DEBOUNCE_MS)
  }

  // 确保缓存已加载
  private async ensureCache(): Promise<boolean> {
    if (this.cache.size > 0 && (Date.now() - this.cacheTimestamp) < this.CACHE_TTL) {
      return true
    }
    // 避免并发重复请求
    if (this.fetchPromise !== null) {
      return await this.fetchPromise
    }
    this.fetchPromise = this.fetchAndBuildCache()
    const result = await this.fetchPromise
    this.fetchPromise = null
    return result
  }

  // 从 models.dev 拉取数据并构建扁平化缓存
  private async fetchAndBuildCache(): Promise<boolean> {
    try {
      const prefs = getPreferencesService()
      const baseUrl = await prefs.getString(PreferenceKeys.MODELS_DEV_BASE_URL, 'https://models.dev')
      const url = `${baseUrl}/api.json`

      const httpRequest = http.createHttp()
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 30000
      })
      httpRequest.destroy()

      if (response.responseCode !== 200) {
        console.warn('ModelCapabilityMatcher', `HTTP ${response.responseCode}`)
        return false
      }

      const raw = response.result as string
      const data: ModelsDevData = JSON.parse(raw) as ModelsDevData
      this.cache.clear()
      this.lowerCaseIndex.clear()
      this.familyLogoMap.clear()
      this.allProviderKeys.clear()
      this.baseUrl = baseUrl

      // 第一遍：收集所有供应商 key，以及每个供应商拥有的 family 集合
      const providerFamilies: Map<string, Set<string>> = new Map()
      const providerKeys = Object.keys(data)
      for (let i = 0; i < providerKeys.length; i++) {
        const providerKey = providerKeys[i]
        this.allProviderKeys.add(providerKey)
        const provider = data[providerKey]
        if (provider.models === undefined || provider.models === null) {
          continue
        }
        const families = new Set<string>()
        const modelKeys = Object.keys(provider.models)
        for (let j = 0; j < modelKeys.length; j++) {
          const entry = provider.models[modelKeys[j]]
          // 构建模型缓存：优先保留有 family 信息的条目
          const existing = this.cache.get(entry.id)
          if (existing === undefined ||
            (existing.family === undefined || existing.family === '') &&
            (entry.family !== undefined && entry.family !== '')) {
            this.cache.set(entry.id, entry)
            this.lowerCaseIndex.set(entry.id.toLowerCase(), entry.id)
          } else if (this.lowerCaseIndex.get(entry.id.toLowerCase()) === undefined) {
            this.lowerCaseIndex.set(entry.id.toLowerCase(), entry.id)
          }
          // 收集 family
          if (entry.family !== undefined && entry.family !== '') {
            families.add(entry.family)
          }
        }
        providerFamilies.set(providerKey, families)
      }

      // 第二遍：为每个 family 找到最佳原厂供应商
      // 策略：在所有拥有该 family 的供应商中，选择 unique family 数量最少且供应商 key
      //       与 family 名有关联的（优先精确匹配、包含关系）
      const familyProviders: Map<string, string[]> = new Map()
      providerFamilies.forEach((families: Set<string>, providerKey: string) => {
        families.forEach((family: string) => {
          let list = familyProviders.get(family)
          if (list === undefined) {
            list = []
            familyProviders.set(family, list)
          }
          list.push(providerKey)
        })
      })

      familyProviders.forEach((providers: string[], family: string) => {
        const best = this.selectBestLogoProvider(family, providers, providerFamilies)
        this.familyLogoMap.set(family, best)
      })

      this.cacheTimestamp = Date.now()
      console.info('ModelCapabilityMatcher', `Cache built: ${this.cache.size} models, ${this.familyLogoMap.size} family logos`)
      return true
    } catch (error) {
      console.warn('ModelCapabilityMatcher', `Fetch failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  // 为 family 选择最佳的 logo 供应商
  // 优先级：供应商 key 与 family 精确匹配 > 包含关系 > 专注度最高的原厂 > fallback
  private selectBestLogoProvider(
    family: string,
    providers: string[],
    providerFamilies: Map<string, Set<string>>
  ): string {
    const familyLower = family.toLowerCase()

    // 1. 精确匹配：供应商 key == family（如 family=deepseek, provider=deepseek）
    for (let i = 0; i < providers.length; i++) {
      if (providers[i].toLowerCase() === familyLower) {
        return providers[i]
      }
    }

    // 2. family 以供应商 key 开头，或反过来（如 family=kimi, provider=kimi-for-coding）
    for (let i = 0; i < providers.length; i++) {
      const pkLower = providers[i].toLowerCase()
      if (familyLower.startsWith(pkLower) || pkLower.startsWith(familyLower)) {
        return providers[i]
      }
    }

    // 3. 选"专注度"最高的供应商 —— 该供应商的所有 family 都共享相同的品牌根词
    // 例如 openai 的 family: gpt, gpt-mini, gpt-nano, gpt-codex... → 品牌一致性高
    // 而 aihubmix 的 family: gpt, claude, deepseek... → 品牌一致性低（聚合平台）
    // 综合得分 = 相关数量 × 占比，兼顾品牌覆盖度和专注度
    let bestProvider = providers[0]
    let bestScore = -1.0
    let bestNameLen = 999
    for (let i = 0; i < providers.length; i++) {
      const families = providerFamilies.get(providers[i])
      if (families === undefined) {
        continue
      }
      const brandRoot = this.extractBrandRoot(family)
      let relatedCount = 0
      let totalCount = 0
      families.forEach((f: string) => {
        totalCount++
        const fRoot = this.extractBrandRoot(f)
        if (fRoot === brandRoot) {
          relatedCount++
        }
      })
      const ratio = totalCount > 0 ? relatedCount / totalCount : 0
      // 综合得分 = 相关数量 × 占比
      // anthropic: 3 × 1.0 = 3.0 vs amazon-bedrock: 4 × 0.14 = 0.56
      // openai: 4 × 0.36 = 1.44 vs sap-ai-core: 3 × 0.38 = 1.14
      const score = relatedCount * ratio
      const nameLen = providers[i].length
      if (score > bestScore || (score === bestScore && nameLen < bestNameLen)) {
        bestScore = score
        bestProvider = providers[i]
        bestNameLen = nameLen
      }
    }
    return bestProvider
  }

  // 提取 family 的品牌根词（去掉变体后缀）
  // 例如：claude-sonnet → claude, gpt-mini → gpt, deepseek-thinking → deepseek
  //       kimi-thinking → kimi, glm-air → glm, minimax → minimax
  private extractBrandRoot(family: string): string {
    const lower = family.toLowerCase()
    // 常见变体后缀
    const suffixes = [
      '-thinking', '-sonnet', '-opus', '-haiku', '-mini', '-nano',
      '-pro', '-flash', '-lite', '-air', '-small', '-medium', '-large',
      '-instruct', '-chat', '-coder', '-reasoning', '-embed'
    ]
    for (let i = 0; i < suffixes.length; i++) {
      if (lower.endsWith(suffixes[i])) {
        return lower.substring(0, lower.length - suffixes[i].length)
      }
    }
    // 去掉 -数字后缀（如 glm-4.6 → glm）
    const numSuffix = lower.match(/-[\d.]+$/)
    if (numSuffix !== null) {
      return lower.substring(0, numSuffix.index!)
    }
    return lower
  }

  // 通过小写索引查找缓存条目（大小写不敏感回退）
  private getCaseInsensitive(key: string): ModelsDevEntry | null {
    const originalId = this.lowerCaseIndex.get(key.toLowerCase())
    if (originalId !== undefined) {
      const entry = this.cache.get(originalId)
      if (entry !== undefined) {
        return entry
      }
    }
    return null
  }

  // 按优先级查找匹配的模型条目
  private findEntry(modelId: string): ModelsDevEntry | null {
    // 1. 精确匹配
    const exact = this.cache.get(modelId)
    if (exact !== undefined) {
      return exact
    }

    // 2. 去供应商前缀：取最后一个 / 后的内容，兼容聚合商多层路径
    //    如 deepseek-ai/deepseek-v3.2 → deepseek-v3.2
    const slashIndex = modelId.lastIndexOf('/')
    if (slashIndex >= 0) {
      const stripped = modelId.substring(slashIndex + 1)
      const found = this.cache.get(stripped)
      if (found !== undefined) {
        return found
      }
    }

    // 3. 去日期后缀：gpt-4o-2024-08-06 → gpt-4o
    const baseId = slashIndex >= 0 ? modelId.substring(slashIndex + 1) : modelId
    const datePattern = new RegExp('-\\d{4}[-]?\\d{0,2}[-]?\\d{0,2}$')
    const dateMatch = baseId.match(datePattern)
    if (dateMatch !== null) {
      const withoutDate = baseId.substring(0, dateMatch.index!)
      if (withoutDate.length > 0) {
        const found = this.cache.get(withoutDate)
        if (found !== undefined) {
          return found
        }
      }
    }

    // 4. 大小写不敏感回退：minimax-m2.1 → MiniMax-M2.1
    const ci1 = this.getCaseInsensitive(modelId)
    if (ci1 !== null) {
      return ci1
    }
    if (slashIndex >= 0) {
      const stripped = modelId.substring(slashIndex + 1)
      const ci2 = this.getCaseInsensitive(stripped)
      if (ci2 !== null) {
        return ci2
      }
    }
    if (dateMatch !== null) {
      const withoutDate = baseId.substring(0, dateMatch.index!)
      if (withoutDate.length > 0) {
        const ci3 = this.getCaseInsensitive(withoutDate)
        if (ci3 !== null) {
          return ci3
        }
      }
    }

    return null
  }

  // 将 models.dev 条目的能力映射到 ModelInfo
  private applyEntry(model: ModelInfo, entry: ModelsDevEntry): void {
    // tool_call → supportsTools
    if (entry.tool_call) {
      model.capabilities.supportsTools = true
    }
    // reasoning → supportsReasoning
    if (entry.reasoning) {
      model.capabilities.supportsReasoning = true
    }
    // modalities.input 含 "image" → supportsVision + inputMode
    if (entry.modalities !== undefined && entry.modalities !== null &&
      entry.modalities.input !== undefined && entry.modalities.input !== null) {
      for (let i = 0; i < entry.modalities.input.length; i++) {
        if (entry.modalities.input[i] === 'image') {
          model.capabilities.supportsVision = true
          model.inputMode = InputMode.VISION
          break
        }
      }
    }
    // limit.context → contextLength
    if (entry.limit !== undefined && entry.limit !== null &&
      entry.limit.context > 0) {
      model.contextLength = entry.limit.context
    }
    // name → 仅当 name === id 时覆盖（说明用户没有自定义名称）
    if (model.name === model.id && entry.name !== undefined && entry.name !== '') {
      model.name = entry.name
    }
  }

  // 从模型 ID 推断原厂供应商 key，用于获取正确的 logo
  private findLogoProvider(modelId: string): string {
    // 1. 通过模型条目的 family 字段查找
    const entry = this.findEntry(modelId)
    if (entry !== null && entry.family !== undefined && entry.family !== '') {
      const provider = this.familyLogoMap.get(entry.family)
      if (provider !== undefined) {
        return provider
      }
    }

    // 2. 如果模型 ID 有 org 前缀（如 deepseek-ai/deepseek-v3.2），
    //    检查前缀是否对应 models.dev 中的供应商
    const slashIndex = modelId.indexOf('/')
    if (slashIndex >= 0) {
      const orgPrefix = modelId.substring(0, slashIndex).toLowerCase()
      // 直接匹配供应商 key
      if (this.allProviderKeys.has(orgPrefix)) {
        return orgPrefix
      }
      // 去除常见后缀（如 deepseek-ai → deepseek, mistralai → mistral）
      const suffixesToStrip = ['-ai', 'ai', '-org', 'org']
      for (let i = 0; i < suffixesToStrip.length; i++) {
        const suffix = suffixesToStrip[i]
        if (orgPrefix.endsWith(suffix) && orgPrefix.length > suffix.length) {
          const stripped = orgPrefix.substring(0, orgPrefix.length - suffix.length)
          if (this.allProviderKeys.has(stripped)) {
            return stripped
          }
        }
      }
      // 模糊匹配：供应商 key 包含在 orgPrefix 中
      const providerKeysArray = Array.from(this.allProviderKeys)
      for (let i = 0; i < providerKeysArray.length; i++) {
        if (orgPrefix.includes(providerKeysArray[i])) {
          return providerKeysArray[i]
        }
      }
    }

    return ''
  }

  // 主动加载缓存（供外部调用）
  async loadCache(): Promise<boolean> {
    return await this.ensureCache()
  }

  // 判断缓存是否已加载
  isCacheLoaded(): boolean {
    return this.cache.size > 0 && (Date.now() - this.cacheTimestamp) < this.CACHE_TTL
  }

  // 获取模型的 models.dev logo URL，优先实时缓存，失败回退本地持久化索引
  getLogoUrl(modelId: string): string {
    const onlineLogoUrl = this.getLogoUrlFromCache(modelId)
    if (onlineLogoUrl !== '') {
      this.recordModelLogo(modelId, onlineLogoUrl)
      return onlineLogoUrl
    }
    return this.getPersistedLogoUrl(modelId)
  }

  private getLogoUrlFromCache(modelId: string): string {
    if (this.cache.size === 0) {
      return ''
    }
    const providerId = this.findLogoProvider(modelId)
    if (providerId === '') {
      return ''
    }
    return `${this.baseUrl}/logos/${providerId}.svg`
  }

  private getPersistedLogoUrl(modelId: string): string {
    const aliases = this.buildModelIdAliases(modelId)
    for (let i = 0; i < aliases.length; i++) {
      const logoUrl = this.persistedLogoIndex.get(aliases[i])
      if (logoUrl !== undefined && logoUrl !== '') {
        return logoUrl
      }
    }
    return ''
  }

  private buildModelIdAliases(modelId: string): string[] {
    const aliases: string[] = []
    this.appendAlias(aliases, modelId)

    // 取最后一个 / 后的内容，兼容聚合商多层路径
    const slashIndex = modelId.lastIndexOf('/')
    let baseId = modelId
    if (slashIndex >= 0) {
      const stripped = modelId.substring(slashIndex + 1)
      this.appendAlias(aliases, stripped)
      baseId = stripped
    }

    const datePattern = new RegExp('-\\d{4}[-]?\\d{0,2}[-]?\\d{0,2}$')
    const dateMatch = baseId.match(datePattern)
    if (dateMatch !== null && dateMatch.index !== undefined) {
      const withoutDate = baseId.substring(0, dateMatch.index)
      this.appendAlias(aliases, withoutDate)
    }

    // 增加小写别名，兼容模型 ID 大小写差异
    const originalLength = aliases.length
    for (let i = 0; i < originalLength; i++) {
      const lower = aliases[i].toLowerCase()
      this.appendAlias(aliases, lower)
    }

    return aliases
  }

  private appendAlias(aliases: string[], alias: string): void {
    if (alias === '') {
      return
    }
    for (let i = 0; i < aliases.length; i++) {
      if (aliases[i] === alias) {
        return
      }
    }
    aliases.push(alias)
  }
}
