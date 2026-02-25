// 消息角色类型
export enum MessageRole {
  USER = 'user',
  ASSISTANT = 'assistant',
  SYSTEM = 'system',
  TOOL = 'tool'
}

// ============ Function Calling 工具相关类型 ============

// 工具参数属性（用于 JSON 序列化）
class ToolParameterPropertyJson {
  type: string = ''
  description: string = ''
  enum: string[] | undefined = undefined

  constructor(type: string, description: string, enumValues?: string[]) {
    this.type = type
    this.description = description
    if (enumValues !== undefined && enumValues.length > 0) {
      this.enum = enumValues
    }
  }
}

// 工具参数 JSON 对象（用于 API 请求）
class ToolParametersJson {
  type: string = 'object'
  properties: Record<string, ToolParameterPropertyJson> = {}
  required: string[] = []

  constructor(type: string, properties: Record<string, ToolParameterPropertyJson>, required: string[]) {
    this.type = type
    this.properties = properties
    this.required = required
  }
}

// 工具参数属性
export class ToolParameterProperty {
  type: string = ''
  description: string = ''
  enumValues: string[] = []

  constructor(type: string, description: string, enumValues: string[] = []) {
    this.type = type
    this.description = description
    this.enumValues = enumValues
  }
}

// 工具参数定义
export class ToolParameters {
  type: string = 'object'
  properties: Map<string, ToolParameterProperty> = new Map()
  required: string[] = []

  constructor() {
    this.type = 'object'
    this.properties = new Map()
    this.required = []
  }

  addProperty(name: string, property: ToolParameterProperty): void {
    this.properties.set(name, property)
  }

  addRequired(name: string): void {
    this.required.push(name)
  }

  // 转换为 JSON 对象（用于 API 请求）
  toJsonObject(): object {
    const props: Record<string, ToolParameterPropertyJson> = {}
    this.properties.forEach((value, key) => {
      if (value.enumValues.length > 0) {
        props[key] = new ToolParameterPropertyJson(value.type, value.description, value.enumValues)
      } else {
        props[key] = new ToolParameterPropertyJson(value.type, value.description)
      }
    })
    return new ToolParametersJson(this.type, props, this.required)
  }
}

// 工具函数定义
export class ToolFunction {
  name: string = ''
  description: string = ''
  parameters: ToolParameters

  constructor(name: string, description: string, parameters: ToolParameters) {
    this.name = name
    this.description = description
    this.parameters = parameters
  }
}

// 工具定义（用于 API 请求）
export class ToolDefinition {
  type: string = 'function'
  function: ToolFunction

  constructor(func: ToolFunction) {
    this.function = func
  }
}

// 工具调用（AI 返回）
@Observed
export class ToolCall {
  id: string = ''
  type: string = 'function'
  functionName: string = ''
  arguments: string = ''

  constructor(id: string = '', functionName: string = '', args: string = '') {
    this.id = id
    this.functionName = functionName
    this.arguments = args
  }
}

// 工具执行结果
export class ToolResult {
  toolCallId: string = ''
  content: string = ''

  constructor(toolCallId: string = '', content: string = '') {
    this.toolCallId = toolCallId
    this.content = content
  }
}

// 工具配置（用于 UI 开关管理）
@Observed
export class ToolConfig {
  id: string = ''           // 工具唯一标识，如 'web_search'
  name: string = ''         // 显示名称，如 '联网搜索'
  description: string = ''  // 工具描述
  icon: Resource | null = null  // 图标
  enabled: boolean = false  // 是否启用
  requiresSetup: boolean = false  // 是否需要额外配置

  constructor(
    id: string = '',
    name: string = '',
    description: string = '',
    icon: Resource | null = null,
    enabled: boolean = false,
    requiresSetup: boolean = false
  ) {
    this.id = id
    this.name = name
    this.description = description
    this.icon = icon
    this.enabled = enabled
    this.requiresSetup = requiresSetup
  }
}

// 供应商图标类型
export enum ProviderIconType {
  SVG = 'svg',        // SVG 图标（预设供应商）
  TEXT = 'text',      // 文字图标（自动生成或自定义）
  IMAGE = 'image'     // 自定义图片
}

// 模型角色枚举（用于默认模型配置）
export enum ModelRole {
  CHAT = 'chat',
  TITLE = 'title',
  TRANSLATE = 'translate',
  SEARCH_OPTIMIZATION = 'search_optimization'
}

// 华为官方智能体入口配置
@Observed
export class HuaweiAgentEntry {
  id: string = ''
  name: string = ''
  bundleName: string = ''
  abilityName: string = ''
  uri: string = ''
  enabled: boolean = true
  lastLaunchAt: number = 0

  constructor(id: string = '', name: string = '') {
    this.id = id
    this.name = name
  }
}

// 推理级别枚举
export enum ReasoningLevel {
  OFF = 'off',           // 关闭推理
  LOW = 'low',           // 轻度推理
  MEDIUM = 'medium',     // 中度推理
  HIGH = 'high'          // 重度推理
}

// 默认模型配置类
@Observed
export class DefaultModelConfig {
  modelId: string = ''
  providerId: string = ''
  modelName: string = ''
  providerName: string = ''

  constructor(modelId: string = '', providerId: string = '', modelName: string = '', providerName: string = '') {
    this.modelId = modelId
    this.providerId = providerId
    this.modelName = modelName
    this.providerName = providerName
  }

  isConfigured(): boolean {
    return this.modelId !== '' && this.providerId !== ''
  }

  getDisplayName(): string {
    if (this.modelName !== '') {
      return this.modelName
    }
    if (this.modelId !== '') {
      return this.modelId
    }
    return ''
  }
}

// ============ 模型能力相关枚举 ============

// 模型类型
export enum ModelType {
  CHAT = 'chat',           // 聊天模型
  EMBEDDING = 'embedding'  // 嵌入模型
}

// 输入模式
export enum InputMode {
  TEXT = 'text',     // 纯文本
  VISION = 'vision'  // 支持图片输入
}

// 输出模式
export enum OutputMode {
  TEXT = 'text',   // 文本输出
  IMAGE = 'image'  // 图片生成
}

// ============ 模型能力配置 ============
@Observed
export class ModelCapabilities {
  supportsTools: boolean      // 支持工具调用/Function Calling
  supportsReasoning: boolean  // 支持推理/思维链（如 o1, DeepSeek R1）
  supportsWebSearch: boolean  // 支持联网搜索
  supportsVision: boolean     // 支持图片输入
  supportsStreaming: boolean  // 支持流式输出

  constructor(
    supportsTools: boolean = false,
    supportsReasoning: boolean = false,
    supportsWebSearch: boolean = false,
    supportsVision: boolean = false,
    supportsStreaming: boolean = true
  ) {
    this.supportsTools = supportsTools
    this.supportsReasoning = supportsReasoning
    this.supportsWebSearch = supportsWebSearch
    this.supportsVision = supportsVision
    this.supportsStreaming = supportsStreaming
  }

  // 从 JSON 对象创建
  static fromJson(json: ModelCapabilitiesJson): ModelCapabilities {
    return new ModelCapabilities(
      json.supportsTools,
      json.supportsReasoning,
      json.supportsWebSearch,
      json.supportsVision,
      json.supportsStreaming
    )
  }

  // 转换为 JSON 对象
  toJson(): ModelCapabilitiesJson {
    const json: ModelCapabilitiesJson = {
      supportsTools: this.supportsTools,
      supportsReasoning: this.supportsReasoning,
      supportsWebSearch: this.supportsWebSearch,
      supportsVision: this.supportsVision,
      supportsStreaming: this.supportsStreaming
    }
    return json
  }
}

// 模型能力 JSON 接口
export interface ModelCapabilitiesJson {
  supportsTools: boolean
  supportsReasoning: boolean
  supportsWebSearch: boolean
  supportsVision: boolean
  supportsStreaming: boolean
}

// ============ 模型默认参数 ============
@Observed
export class ModelParameters {
  temperature: number         // 温度 0-2
  topP: number               // Top P 0-1
  maxTokens: number          // 最大输出 Token
  presencePenalty: number    // 存在惩罚 -2 到 2
  frequencyPenalty: number   // 频率惩罚 -2 到 2

  constructor(
    temperature: number = 0.7,
    topP: number = 1.0,
    maxTokens: number = 4096,
    presencePenalty: number = 0,
    frequencyPenalty: number = 0
  ) {
    this.temperature = temperature
    this.topP = topP
    this.maxTokens = maxTokens
    this.presencePenalty = presencePenalty
    this.frequencyPenalty = frequencyPenalty
  }

  // 从 JSON 对象创建
  static fromJson(json: ModelParametersJson): ModelParameters {
    return new ModelParameters(
      json.temperature,
      json.topP,
      json.maxTokens,
      json.presencePenalty,
      json.frequencyPenalty
    )
  }

  // 转换为 JSON 对象
  toJson(): ModelParametersJson {
    const json: ModelParametersJson = {
      temperature: this.temperature,
      topP: this.topP,
      maxTokens: this.maxTokens,
      presencePenalty: this.presencePenalty,
      frequencyPenalty: this.frequencyPenalty
    }
    return json
  }

  // 重置为默认值
  reset(): void {
    this.temperature = 0.7
    this.topP = 1.0
    this.maxTokens = 4096
    this.presencePenalty = 0
    this.frequencyPenalty = 0
  }
}

// 模型参数 JSON 接口
export interface ModelParametersJson {
  temperature: number
  topP: number
  maxTokens: number
  presencePenalty: number
  frequencyPenalty: number
}

// 搜索引擎类型枚举
export enum SearchEngine {
  BING = 'bing',
  EXA = 'exa',
  DUCKDUCKGO = 'duckduckgo',
  TAVILY = 'tavily',
  CUSTOM = 'custom'
}

// 搜索服务配置类
@Observed
export class SearchServiceConfig {
  enabled: boolean = true
  searchEngine: SearchEngine = SearchEngine.BING
  maxResults: number = 10
  timeout: number = 5000
  autoTestConnection: boolean = true

  constructor() {
    this.enabled = true
    this.searchEngine = SearchEngine.BING
    this.maxResults = 10
    this.timeout = 5000
    this.autoTestConnection = true
  }
}

// 搜索引用项
@Observed
export class SearchReference {
  id: string
  title: string
  url: string
  snippet: string
  timestamp: number

  constructor(id: string, title: string, url: string, snippet: string) {
    this.id = id
    this.title = title
    this.url = url
    this.snippet = snippet
    this.timestamp = Date.now()
  }
}

// 附件类型枚举
export enum AttachmentType {
  IMAGE = 'image',
  FILE = 'file'
}

// 附件信息
export class MessageAttachment {
  id: string
  type: AttachmentType
  name: string           // 文件名
  filePath: string       // 应用沙箱中的文件路径
  mimeType: string       // MIME 类型
  size: number           // 文件大小（字节）
  // 临时字段：用于发送 API 前加载
  base64Data: string = ''

  constructor(
    id: string,
    type: AttachmentType,
    name: string,
    filePath: string,
    mimeType: string,
    size: number = 0
  ) {
    this.id = id
    this.type = type
    this.name = name
    this.filePath = filePath
    this.mimeType = mimeType
    this.size = size
  }
}

// 聊天消息模型
@Observed
export class ChatMessage {
  id: string
  role: MessageRole
  content: string
  timestamp: number
  modelName: string
  // 模型 ID（用于图标匹配等）
  modelId: string
  // 推理内容（用于支持 o1, DeepSeek R1 等推理模型）
  reasoningContent: string
  // 附件列表（图片、文件等）
  attachments: MessageAttachment[]
  // 是否正在生成中（用于 UI 显示动态效果）
  isGenerating: boolean
  // 联网搜索引用数据
  searchReferences: SearchReference[]
  // 搜索查询内容
  searchQuery: string
  // 搜索引擎名称
  searchEngine: string
  // 搜索来源：manual(手动) / tool(工具调用)
  searchSource: string
  // 是否正在搜索
  isSearching: boolean
  // Function Calling 相关字段
  toolCalls: ToolCall[]      // AI 请求的工具调用
  toolResults: ToolResult[]  // 工具执行结果
  toolCallId: string         // 用于 tool 角色消息，关联到对应的 tool_call

  constructor(id: string, role: MessageRole, content: string, modelName: string = '', modelId: string = '') {
    this.id = id
    this.role = role
    this.content = content
    this.timestamp = Date.now()
    this.modelName = modelName
    this.modelId = modelId
    this.reasoningContent = ''
    this.attachments = []
    this.isGenerating = false
    this.searchReferences = []
    this.searchQuery = ''
    this.searchEngine = ''
    this.searchSource = ''
    this.isSearching = false
    this.toolCalls = []
    this.toolResults = []
    this.toolCallId = ''
  }

  // 检查是否有推理内容
  hasReasoningContent(): boolean {
    return this.reasoningContent.length > 0
  }

  // 检查是否有附件
  hasAttachments(): boolean {
    return this.attachments.length > 0
  }

  // 获取图片附件
  getImageAttachments(): MessageAttachment[] {
    return this.attachments.filter(a => a.type === AttachmentType.IMAGE)
  }

  // 添加附件
  addAttachment(attachment: MessageAttachment): void {
    this.attachments.push(attachment)
  }

  // 检查是否有搜索引用
  hasSearchReferences(): boolean {
    return this.searchReferences.length > 0
  }

  // 检查是否有工具调用
  hasToolCalls(): boolean {
    return this.toolCalls.length > 0
  }
}

// 模型信息
@Observed
export class ModelInfo {
  id: string
  name: string
  contextLength: number
  isEnabled: boolean
  isRecommended: boolean

  // 新增字段：模型类型和模式
  modelType: ModelType
  inputMode: InputMode
  outputMode: OutputMode

  // 新增字段：能力配置
  capabilities: ModelCapabilities

  // 新增字段：默认参数
  parameters: ModelParameters

  constructor(
    id: string,
    name: string,
    contextLength: number = 4096,
    isEnabled: boolean = false,
    isRecommended: boolean = false
  ) {
    this.id = id
    this.name = name
    this.contextLength = contextLength
    this.isEnabled = isEnabled
    this.isRecommended = isRecommended

    // 初始化新字段（使用默认值，不再自动推断）
    this.modelType = ModelType.CHAT
    this.inputMode = InputMode.TEXT
    this.outputMode = OutputMode.TEXT
    this.capabilities = new ModelCapabilities()
    this.parameters = new ModelParameters()
  }

  // 从扩展 JSON 对象创建
  static fromExtendedJson(json: ModelInfoExtendedJson): ModelInfo {
    const model = new ModelInfo(
      json.id,
      json.name,
      json.contextLength,
      json.isEnabled,
      json.isRecommended
    )

    // 恢复类型和模式
    if (json.modelType !== undefined) {
      model.modelType = json.modelType === 'embedding' ? ModelType.EMBEDDING : ModelType.CHAT
    }
    if (json.inputMode !== undefined) {
      model.inputMode = json.inputMode === 'vision' ? InputMode.VISION : InputMode.TEXT
    }
    if (json.outputMode !== undefined) {
      model.outputMode = json.outputMode === 'image' ? OutputMode.IMAGE : OutputMode.TEXT
    }

    // 恢复能力配置
    if (json.capabilities !== undefined) {
      model.capabilities = ModelCapabilities.fromJson(json.capabilities)
    }

    // 恢复参数配置
    if (json.parameters !== undefined) {
      model.parameters = ModelParameters.fromJson(json.parameters)
    }

    return model
  }

  // 转换为扩展 JSON 对象
  toExtendedJson(): ModelInfoExtendedJson {
    const json: ModelInfoExtendedJson = {
      id: this.id,
      name: this.name,
      contextLength: this.contextLength,
      isEnabled: this.isEnabled,
      isRecommended: this.isRecommended,
      modelType: this.modelType,
      inputMode: this.inputMode,
      outputMode: this.outputMode,
      capabilities: this.capabilities.toJson(),
      parameters: this.parameters.toJson()
    }
    return json
  }
}

// 扩展的模型信息 JSON 接口
export interface ModelInfoExtendedJson {
  id: string
  name: string
  contextLength: number
  isEnabled: boolean
  isRecommended: boolean
  modelType?: string
  inputMode?: string
  outputMode?: string
  capabilities?: ModelCapabilitiesJson
  parameters?: ModelParametersJson
}

// 模型提供商类型
export enum ProviderType {
  OPENAI = 'openai',
  ANTHROPIC = 'anthropic',
  AZURE = 'azure',
  DEEPSEEK = 'deepseek',
  OLLAMA = 'ollama',
  LMSTUDIO = 'lmstudio',
  CUSTOM = 'custom'
}

// API 接口风格
export enum ApiStyle {
  OPENAI = 'openai',      // OpenAI 兼容格式
  ANTHROPIC = 'anthropic', // Claude/Anthropic 格式
  GOOGLE = 'google'        // Google Gemini 格式
}

// 模型提供商信息
@Observed
export class ModelProvider {
  id: string
  name: string
  type: ProviderType
  apiStyle: ApiStyle
  apiKey: string
  baseUrl: string
  isConnected: boolean
  isExpanded: boolean
  models: ModelInfo[]
  iconSymbol: string
  brandColor: Resource
  // 新增字段
  isPreset: boolean     // 是否为预设供应商（不可删除）
  iconPath: string      // SVG 图标路径（相对于 assets/icons/）
  apiPath: string       // API 路径（可选，如 /chat/completions）
  // 图标类型相关字段
  iconType: ProviderIconType = ProviderIconType.SVG
  textIcon: string = ''
  textIconBgColor: string = ''
  customImagePath: string = ''

  constructor(
    id: string,
    name: string,
    type: ProviderType,
    iconSymbol: string,
    brandColor: Resource,
    baseUrl: string = '',
    apiStyle: ApiStyle = ApiStyle.OPENAI
  ) {
    this.id = id
    this.name = name
    this.type = type
    this.apiStyle = apiStyle
    this.apiKey = ''
    this.baseUrl = baseUrl
    this.isConnected = false
    this.isExpanded = false
    this.models = []
    this.iconSymbol = iconSymbol
    this.brandColor = brandColor
    // 初始化新字段
    this.isPreset = false
    this.iconPath = ''
    this.apiPath = ''
    // 初始化图标类型字段
    this.iconType = ProviderIconType.SVG
    this.textIcon = ''
    this.textIconBgColor = ''
    this.customImagePath = ''
  }
}

// 对话会话
@Observed
export class ChatSession {
  id: string
  title: string
  messages: ChatMessage[]
  modelId: string
  providerId: string  // 供应商 ID，用于重启后恢复会话使用的供应商
  createdAt: number
  updatedAt: number
  isFavorite: boolean
  lastMessagePreview: string
  messageCount: number
  // 同步相关字段(为 WebDAV 同步预留)
  syncVersion: number = 0
  lastModified: number = Date.now()
  syncStatus: 'synced' | 'pending' | 'conflict' = 'synced'
  deviceId: string = ''

  constructor(id: string, title: string, modelId: string, providerId: string = '') {
    this.id = id
    this.title = title
    this.modelId = modelId
    this.providerId = providerId
    this.messages = []
    this.createdAt = Date.now()
    this.updatedAt = Date.now()
    this.isFavorite = false
    this.lastMessagePreview = ''
    this.messageCount = 0
    this.syncVersion = 0
    this.lastModified = Date.now()
    this.syncStatus = 'synced'
    this.deviceId = ''
  }
}
