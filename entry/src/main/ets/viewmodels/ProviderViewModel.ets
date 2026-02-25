import { getDatabaseService, DatabaseService, ProviderConfig } from '../services/DatabaseService'
import { getAIApiService, AIApiService, AIApiConfig, ModelsListResult, AIApiResult } from '../services/AIApiService'
import {
  ModelProvider,
  ModelInfo,
  ProviderType,
  ApiStyle,
  ModelCapabilities,
  ModelParameters,
  ModelType,
  InputMode,
  OutputMode,
  ModelCapabilitiesJson,
  ModelParametersJson,
  ProviderIconType
} from '../models/ChatModels'
import { getPresetProviderIconPath, isPresetProvider, getEffectiveApiKey, getPresetProviderById } from '../config/PresetProviders'

// 服务商状态管理 - 单例模式
export class ProviderViewModel {
  private static instance: ProviderViewModel | null = null
  private databaseService: DatabaseService
  private aiApiService: AIApiService
  // 缓存供应商列表
  private cachedProviders: ModelProvider[] = []

  private constructor() {
    this.databaseService = getDatabaseService()
    this.aiApiService = getAIApiService()
  }

  static getInstance(): ProviderViewModel {
    if (ProviderViewModel.instance === null) {
      ProviderViewModel.instance = new ProviderViewModel()
    }
    return ProviderViewModel.instance
  }

  // 获取所有已保存的服务商配置（只返回启用的供应商，用于模型选择器）
  async loadProviders(): Promise<ModelProvider[]> {
    const configs = await this.databaseService.getAllProviders()
    const providers: ModelProvider[] = []

    for (let i = 0; i < configs.length; i++) {
      const config = configs[i]
      // 只加载启用的供应商
      if (!config.isEnabled) {
        continue
      }
      const provider = this.configToProvider(config)
      providers.push(provider)
    }

    this.cachedProviders = providers
    return providers
  }

  // 获取所有已保存的服务商配置（包括禁用的，用于模型管理页面）
  async loadAllProviders(): Promise<ModelProvider[]> {
    const configs = await this.databaseService.getAllProviders()
    const providers: ModelProvider[] = []

    for (let i = 0; i < configs.length; i++) {
      const config = configs[i]
      const provider = this.configToProvider(config)
      providers.push(provider)
    }

    this.cachedProviders = providers
    return providers
  }

  // 根据 ID 获取供应商（从缓存中获取）
  getProviderById(providerId: string): ModelProvider | null {
    for (let i = 0; i < this.cachedProviders.length; i++) {
      if (this.cachedProviders[i].id === providerId) {
        return this.cachedProviders[i]
      }
    }
    return null
  }

  // 异步根据 ID 获取供应商（从数据库加载后获取）
  async getProviderByIdAsync(providerId: string): Promise<ModelProvider | null> {
    // 先尝试从缓存获取
    const cached = this.getProviderById(providerId)
    if (cached !== null) {
      return cached
    }
    // 如果缓存为空，重新加载
    await this.loadAllProviders()
    return this.getProviderById(providerId)
  }

  // 保存服务商配置
  async saveProvider(provider: ModelProvider): Promise<void> {
    await this.databaseService.saveProvider(provider)
  }

  // 删除服务商配置
  async deleteProvider(providerId: string): Promise<void> {
    await this.databaseService.deleteProvider(providerId)
  }

  // 更新服务商启用状态
  async updateProviderEnabled(providerId: string, isEnabled: boolean): Promise<void> {
    await this.databaseService.updateProviderEnabled(providerId, isEnabled)
  }

  // 保存供应商排序顺序
  async saveProvidersOrder(providerIds: string[]): Promise<void> {
    await this.databaseService.updateProvidersOrder(providerIds)
  }

  // 测试服务商连接
  async testConnection(provider: ModelProvider): Promise<AIApiResult> {
    const config = this.providerToApiConfig(provider)
    const testModelId = this.getPreferredModelId(provider)
    return await this.aiApiService.testConnection(config, testModelId)
  }

  // 获取服务商的模型列表
  async refreshModels(provider: ModelProvider): Promise<ModelsListResult> {
    const config = this.providerToApiConfig(provider)
    return await this.aiApiService.getModels(config)
  }

  // 将 ProviderConfig 转换为 ModelProvider
  private configToProvider(config: ProviderConfig): ModelProvider {
    const providerType = this.stringToProviderType(config.type)
    const apiStyle = this.stringToApiStyle(config.apiStyle)
    const provider = new ModelProvider(
      config.id,
      config.name,
      providerType,
      config.iconSymbol,
      this.getProviderBrandColor(providerType),
      config.baseUrl,
      apiStyle
    )
    provider.apiKey = config.apiKey
    provider.isConnected = config.isEnabled

    // 设置新字段
    provider.isPreset = config.isPreset || isPresetProvider(config.id)
    provider.iconPath = config.iconPath !== '' ? config.iconPath : getPresetProviderIconPath(config.id)
    provider.apiPath = config.apiPath !== undefined ? config.apiPath : ''

    // 设置图标类型相关字段
    provider.iconType = (config.iconType !== undefined && config.iconType !== '') ? config.iconType as ProviderIconType : ProviderIconType.SVG
    provider.textIcon = config.textIcon !== undefined ? config.textIcon : ''
    provider.textIconBgColor = config.textIconBgColor !== undefined ? config.textIconBgColor : ''
    provider.customImagePath = config.customImagePath !== undefined ? config.customImagePath : ''

    // 自动迁移：预设供应商如果仍为 SVG 类型，改为 TEXT 类型
    if (provider.isPreset && provider.iconType === ProviderIconType.SVG) {
      const preset = getPresetProviderById(config.id)
      if (preset !== null) {
        provider.iconType = ProviderIconType.TEXT
        provider.iconPath = ''
        provider.textIcon = preset.textIcon
        provider.textIconBgColor = preset.textIconBgColor
      }
    }

    // 解析模型列表
    if (config.modelsJson !== undefined && config.modelsJson !== null && config.modelsJson !== '') {
      console.info('ProviderViewModel', `Parsing models for ${config.name}: ${config.modelsJson}`)
      try {
        const modelsArray: ModelData[] = JSON.parse(config.modelsJson) as ModelData[]
        let hasEnabledModel = false

        // 先检查是否有任何启用的模型
        for (let i = 0; i < modelsArray.length; i++) {
          if (modelsArray[i].isEnabled) {
            hasEnabledModel = true
            break
          }
        }

        for (let i = 0; i < modelsArray.length; i++) {
          const modelObj = modelsArray[i]
          // 如果没有任何启用的模型，则默认全部启用
          const shouldEnable = hasEnabledModel ? modelObj.isEnabled : true
          const modelInfo = new ModelInfo(
            modelObj.id,
            modelObj.name,
            modelObj.contextLength,
            shouldEnable,
            modelObj.isRecommended
          )

          // 恢复扩展字段
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
          if (modelObj.parameters !== undefined) {
            modelInfo.parameters = ModelParameters.fromJson(modelObj.parameters)
          }

          provider.models.push(modelInfo)
        }
      } catch (error) {
        console.error('ProviderViewModel', `Failed to parse models JSON: ${JSON.stringify(error)}`)
      }
    } else {
      // 确保 models 属性被初始化为空数组
      provider.models = []
    }

    return provider
  }

  // 将 ModelProvider 转换为 AIApiConfig
  private providerToApiConfig(provider: ModelProvider): AIApiConfig {
    return {
      providerId: provider.id,
      providerType: provider.type,
      apiStyle: provider.apiStyle,
      apiKey: getEffectiveApiKey(provider.id, provider.apiKey),
      baseUrl: provider.baseUrl,
      apiPath: provider.apiPath || undefined  // 传递自定义 API 路径
    }
  }

  // 字符串转换为 ProviderType
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

  // 字符串转换为 ApiStyle
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

  // 获取服务商品牌颜色
  private getProviderBrandColor(type: ProviderType): Resource {
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

  // 获取测试连接的优先模型
  private getPreferredModelId(provider: ModelProvider): string {
    for (let i = 0; i < provider.models.length; i++) {
      const model = provider.models[i]
      if (model.isEnabled) {
        return model.id
      }
    }
    if (provider.models.length > 0) {
      return provider.models[0].id
    }
    return ''
  }

  // 获取默认的服务商列表（用于首次启动）
  getDefaultProviders(): ModelProvider[] {
    // 返回默认的硅基流动服务商
    const providers: ModelProvider[] = []

    // 添加硅基流动（内置 API Key，开箱即用）
    const siliconflow = new ModelProvider(
      'siliconflow',
      '硅基流动',
      ProviderType.CUSTOM,
      'message',
      $r('app.color.brand_custom'),
      'https://api.siliconflow.cn/v1',
      ApiStyle.OPENAI
    )
    siliconflow.apiKey = ''  // 使用预设 API Key
    siliconflow.isConnected = true
    siliconflow.isPreset = true
    siliconflow.iconPath = ''
    siliconflow.apiPath = ''
    siliconflow.iconType = ProviderIconType.TEXT
    siliconflow.textIcon = 'SF'
    siliconflow.textIconBgColor = '#7C3AED'
    siliconflow.customImagePath = ''
    providers.push(siliconflow)

    return providers
  }

  // 初始化所有预置服务商（确保预置服务商总是存在）
  async initializeAllPresetProviders(): Promise<void> {
    const existingProviders = await this.databaseService.getAllProviders()

    // 获取已存在的服务商 ID 集合
    const existingIds = new Set<string>()
    for (let i = 0; i < existingProviders.length; i++) {
      existingIds.add(existingProviders[i].id)
    }

    // 所有预置服务商 ID（硅基流动放在最前面）
    const allPresetIds = ['siliconflow', 'openai', 'anthropic', 'deepseek', 'gemini', 'openrouter', 'qwen', 'zhipu', 'doubao', 'minimax', 'aihubmix', 'grok', 'ollama']

    for (let i = 0; i < allPresetIds.length; i++) {
      const presetId = allPresetIds[i]
      // 如果服务商不存在，则添加
      if (!existingIds.has(presetId)) {
        const preset = getPresetProviderById(presetId)
        if (preset !== null) {
          const provider = new ModelProvider(
            preset.id,
            preset.name,
            preset.type,
            'message',
            $r('app.color.brand_custom'),
            preset.baseUrl,
            preset.apiStyle
          )
          provider.apiKey = ''
          provider.isConnected = preset.id === 'siliconflow'  // 仅硅基流动默认启用
          provider.isPreset = true
          provider.iconPath = ''
          provider.apiPath = ''
          provider.iconType = ProviderIconType.TEXT
          provider.textIcon = preset.textIcon
          provider.textIconBgColor = preset.textIconBgColor
          provider.customImagePath = ''
          await this.saveProvider(provider)
        }
      }
    }
  }
}

// 模型数据接口（支持扩展字段）
interface ModelData {
  id: string
  name: string
  contextLength: number
  isEnabled: boolean
  isRecommended: boolean
  // 扩展字段
  modelType?: string
  inputMode?: string
  outputMode?: string
  capabilities?: ModelCapabilitiesJson
  parameters?: ModelParametersJson
}

// 导出获取实例方法
export function createProviderViewModel(): ProviderViewModel {
  return ProviderViewModel.getInstance()
}

// 导出单例获取方法
export function getProviderViewModel(): ProviderViewModel {
  return ProviderViewModel.getInstance()
}
