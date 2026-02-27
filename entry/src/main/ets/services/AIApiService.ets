import { getHttpService, HttpService } from './HttpService'
import { util } from '@kit.ArkTS'
import { http } from '@kit.NetworkKit'
import {
  ProviderType,
  ApiStyle,
  MessageAttachment,
  AttachmentType,
  ReasoningLevel,
  ToolDefinition,
  ToolCall,
  ToolResult
} from '../models/ChatModels'

// URL 解析工具类
class ApiUrlResolver {
  /**
   * 构建 API URL，处理 baseUrl 和 path 的拼接
   * @param baseUrl 基础 URL（如 https://api.example.com 或 https://api.example.com/v1）
   * @param path API 路径（如 /chat/completions 或 v1/chat/completions）
   * @returns 完整的 API URL
   */
  static buildUrl(baseUrl: string, path: string): string {
    let url = baseUrl
    let apiPath = path

    // 移除 baseUrl 末尾的斜杠
    if (url.endsWith('/')) {
      url = url.slice(0, -1)
    }

    // 确保 path 以斜杠开头
    if (!apiPath.startsWith('/')) {
      apiPath = '/' + apiPath
    }

    // 检查 baseUrl 是否已经包含版本路径（如 /v1, /v2, /v3, /beta 等）
    if (/\/v\d+/.test(url) || url.includes('/beta')) {
      // baseUrl 已包含版本路径，直接拼接
      // 但要避免重复的 /v1
      const baseUrlEnd = url.substring(url.lastIndexOf('/'))
      if (apiPath.includes(baseUrlEnd) && apiPath.startsWith(baseUrlEnd)) {
        // path 包含相同的版本前缀，去掉 path 中的版本部分
        const versionIndex = apiPath.indexOf('/', 1) // 跳过开头的 /
        if (versionIndex !== -1) {
          apiPath = apiPath.substring(versionIndex)
        } else {
          apiPath = ''
        }
      }
    }

    return url + apiPath
  }
}

// 请求消息格式
export class RequestMessage {
  role: string = ''
  content: string = ''
  // 图片附件（用于多模态请求）
  attachments: MessageAttachment[] = []
  // Function Calling 相关字段
  toolCallId: string = ''      // 用于 tool 角色消息
  toolCalls: ToolCall[] = []   // 用于 assistant 消息中的工具调用

  constructor(role: string, content: string, attachments: MessageAttachment[] = []) {
    this.role = role
    this.content = content
    this.attachments = attachments
  }

  // 检查是否包含图片
  hasImages(): boolean {
    return this.attachments.some(a => a.type === AttachmentType.IMAGE)
  }

  // 检查是否包含任何附件（图片或文件）
  hasAttachments(): boolean {
    return this.attachments.length > 0 && this.attachments.some(a => a.base64Data !== '')
  }

  // 检查是否包含文件（非图片）
  hasFiles(): boolean {
    return this.attachments.some(a => a.type === AttachmentType.FILE && a.base64Data !== '')
  }

  // 检查是否是工具结果消息
  isToolResultMessage(): boolean {
    return this.role === 'tool' && this.toolCallId !== ''
  }

  // 检查是否包含工具调用
  hasToolCalls(): boolean {
    return this.toolCalls.length > 0
  }

  // 创建工具结果消息
  static createToolResultMessage(toolCallId: string, content: string): RequestMessage {
    const msg = new RequestMessage('tool', content)
    msg.toolCallId = toolCallId
    return msg
  }

  // 创建带工具调用的 assistant 消息
  static createAssistantWithToolCalls(content: string, toolCalls: ToolCall[]): RequestMessage {
    const msg = new RequestMessage('assistant', content)
    msg.toolCalls = toolCalls
    return msg
  }
}

// 多模态消息内容部分（OpenAI Vision 格式）
interface MultimodalContentPart {
  type: string
  text?: string
  image_url?: ImageUrl
}

interface ImageUrl {
  url: string
  detail?: string
}

// 多模态消息内容接口
interface MultimodalMessageContent {
  role: string
  content: string | MultimodalContentPart[]
}

// 消息内容接口
interface MessageContent {
  role: string
  content: string
}

// 测试请求接口
interface TestRequestBody {
  model: string
  messages: RequestMessage[]
  max_tokens: number
}

// OpenAI 工具定义接口（用于 API 请求）
interface OpenAIToolFunction {
  name: string
  description: string
  parameters: object
}

interface OpenAITool {
  type: string
  function: OpenAIToolFunction
}

// OpenAI 工具调用接口（用于 API 响应）
interface OpenAIToolCallFunction {
  name: string
  arguments: string
}

interface OpenAIToolCall {
  id: string
  type: string
  function: OpenAIToolCallFunction
}

// 工具结果消息接口
interface ToolResultMessageContent {
  role: string
  tool_call_id: string
  content: string
}

// 带工具调用的 assistant 消息接口
interface AssistantMessageWithToolCalls {
  role: string
  content: string | null
  tool_calls: OpenAIToolCall[]
}

// 通用思考配置接口（小米 MiMo / 智谱 GLM 等模型）
interface ThinkingConfig {
  type: string           // "enabled" | "disabled"
  clear_thinking?: boolean  // GLM 特有：是否清除历史推理内容（默认 false 保留）
}

// OpenAI 请求体接口
interface OpenAIRequestBody {
  model: string
  messages: (MessageContent | MultimodalMessageContent | ToolResultMessageContent | AssistantMessageWithToolCalls)[]
  temperature: number
  max_tokens: number
  stream?: boolean
  reasoning_effort?: string  // OpenAI o1/o3 系列推理级别: low, medium, high
  reasoning_split?: boolean  // MiniMax 推理内容分离（reasoning_details 字段）
  thinking?: ThinkingConfig  // 小米 MiMo / 智谱 GLM 思考模式配置
  tools?: OpenAITool[]       // Function Calling 工具定义
  tool_choice?: string       // 工具选择策略: "auto" | "none" | "required"
  top_p?: number             // Top P 采样参数
  presence_penalty?: number  // 存在惩罚
  frequency_penalty?: number // 频率惩罚
}

// Anthropic 思考配置接口
interface AnthropicThinking {
  type: string
  budget_tokens: number
}

// Anthropic 请求体接口
interface AnthropicRequestBody {
  model: string
  messages: (MessageContent | AnthropicMultimodalMessage)[]
  max_tokens: number
  temperature: number
  system?: string
  stream?: boolean
  thinking?: AnthropicThinking  // Claude 扩展思考配置
}

// Anthropic 多模态消息内容部分
interface AnthropicContentPart {
  type: string
  text?: string
  source?: AnthropicDocumentSource
}

interface AnthropicDocumentSource {
  type: string
  media_type: string
  data: string
}

// Anthropic 多模态消息
interface AnthropicMultimodalMessage {
  role: string
  content: AnthropicContentPart[]
}

// 选择项
export interface ChoiceMessage {
  role: string
  content: string
  // 推理内容（DeepSeek R1 等模型）
  reasoning_content?: string
  // 推理内容（OpenAI-compat 一些供应商使用 reasoning 字段）
  reasoning?: string
  // 图片数据
  image_url?: string
  image_base64?: string
  image_mime_type?: string
  // Function Calling 工具调用
  tool_calls?: OpenAIToolCall[]
}

export interface Choice {
  index: number
  message: ChoiceMessage
  finish_reason: string
}

// 使用量信息
export interface UsageInfo {
  prompt_tokens: number
  completion_tokens: number
  total_tokens: number
}

// 聊天完成响应
export interface ChatCompletionResponse {
  id: string
  object: string
  created: number
  model: string
  choices: Choice[]
  usage: UsageInfo
}

// API 错误响应
export interface ApiErrorResponse {
  error: ApiError
}

export interface ApiError {
  message: string
  type: string
  code: string
}

// 模型列表响应
export interface ModelsListResponse {
  object: string
  data: ModelData[]
}

export interface ModelData {
  id: string
  object: string
  created: number
  owned_by: string
}

// AI API 服务配置
export interface AIApiConfig {
  providerId: string
  providerType: ProviderType
  apiStyle: ApiStyle
  apiKey: string
  baseUrl: string
  apiPath?: string  // 可选的自定义 API 路径（如 /v1/chat/completions）
  // 模型参数（可选）
  topP?: number
  presencePenalty?: number
  frequencyPenalty?: number
}

// AI API 响应结果
export interface AIApiResult {
  success: boolean
  content: string
  errorMessage: string
  usage: UsageInfo | null
  // 新增：推理内容（用于支持 o1, DeepSeek R1 等推理模型）
  reasoningContent: string
  // 图片数据（非流式响应）
  imageData?: string
  imageMimeType?: string
  // Function Calling 相关字段
  toolCalls?: ToolCall[]     // AI 请求的工具调用
  finishReason?: string      // 完成原因: "stop" | "tool_calls"
}

// 模型列表结果
export interface ModelsListResult {
  success: boolean
  models: string[]
  errorMessage: string
}

// Anthropic 图片来源接口
interface AnthropicImageSource {
  type: string
  media_type: string
  data: string
}

// Anthropic 响应内容
interface AnthropicContent {
  type: string
  text?: string
  // 图片数据
  source?: AnthropicImageSource
}

// Anthropic 响应格式
interface AnthropicResponse {
  id: string
  content: AnthropicContent[]
  usage: UsageInfo
}

// Google Gemini 请求体接口
interface GoogleContentPart {
  text?: string
  inline_data?: GoogleInlineData
}

interface GoogleInlineData {
  mime_type: string
  data: string
}

interface GoogleContent {
  role: string
  parts: GoogleContentPart[]
}

interface GoogleGenerationConfig {
  temperature: number
  maxOutputTokens: number
}

interface GoogleRequestBody {
  contents: GoogleContent[]
  generationConfig: GoogleGenerationConfig
}

// Google Gemini 响应接口
interface GoogleCandidate {
  content: GoogleContent
}

interface GoogleResponse {
  candidates: GoogleCandidate[]
}

// OpenAI 流式响应块增量
// MiniMax reasoning_details 项
interface MiniMaxReasoningDetail {
  text?: string
}

// 流式响应中的工具调用增量
interface OpenAIStreamToolCallFunction {
  name?: string
  arguments?: string
}

interface OpenAIStreamToolCall {
  index: number
  id?: string
  type?: string
  function?: OpenAIStreamToolCallFunction
}

interface OpenAIStreamDelta {
  content?: string
  // 推理内容（DeepSeek R1 等模型）
  reasoning_content?: string
  // 推理内容（OpenAI-compat 一些供应商使用 reasoning 字段）
  reasoning?: string
  // MiniMax 推理内容（数组格式，每个元素有 text 字段）
  reasoning_details?: MiniMaxReasoningDetail[]
  // 图片数据（兼容 OpenAI DALL-E 或第三方服务的图片响应）
  image_url?: string  // 图片 URL
  image_base64?: string  // base64 编码的图片数据
  image_mime_type?: string  // 图片 MIME 类型
  // Function Calling 工具调用增量
  tool_calls?: OpenAIStreamToolCall[]
}

// OpenAI 流式响应块选择项
interface OpenAIStreamChoice {
  delta: OpenAIStreamDelta
  finish_reason?: string
}

// OpenAI 流式响应块
interface OpenAIStreamChunk {
  choices: OpenAIStreamChoice[]
}

// Anthropic 流式响应块增量
interface AnthropicStreamDelta {
  text?: string
  // 图片数据（Anthropic image_block 增量）
  image_source?: AnthropicImageSource
}

// Anthropic 流式响应块
interface AnthropicStreamChunk {
  type: string
  delta?: AnthropicStreamDelta
}

// Google 流式响应块部分
interface GoogleStreamPart {
  text?: string
  inline_data?: GoogleStreamInlineData
}

// Google 流式响应块内联数据（图片等）
interface GoogleStreamInlineData {
  mime_type: string
  data: string
}

// Google 流式响应块内容
interface GoogleStreamContent {
  parts: GoogleStreamPart[]
}

// Google 流式响应块候选
interface GoogleStreamCandidate {
  content: GoogleStreamContent
}

// Google 流式响应块
interface GoogleStreamChunk {
  candidates: GoogleStreamCandidate[]
}

// 流式响应块解析结果
interface StreamChunkResult {
  content: string
  reasoningContent: string
  // 推理内容是否来自结构化字段（reasoning/reasoning_content/reasoning_details 等）。
  // 若来自 <think> 标签解析，则为 false/undefined（避免做 overlap 裁剪等“猜测”）。
  reasoningIsStructured?: boolean
  // 图片数据（Gemini 生成图片时返回）
  imageData?: string
  imageMimeType?: string
  // Function Calling 工具调用增量
  toolCallDeltas?: ToolCallDelta[]
  finishReason?: string
}

// 工具调用增量（用于流式响应累积）
interface ToolCallDelta {
  index: number
  id?: string
  functionName?: string
  arguments?: string
}

// AI API 服务
export class AIApiService {
  private static instance: AIApiService | null = null
  private httpService: HttpService
  // DeepSeek-R1 <think> 标签解析状态
  private isInThinkingBlock: boolean = false
  // MiniMax reasoning_details 累积内容缓冲区（用于计算增量）
  private minimaxReasoningBuffer: string = ''
  // MiniMax content 累积内容缓冲区（用于计算增量，因为 MiniMax 的 content 也是累积的）
  private minimaxContentBuffer: string = ''
  // 部分标签缓冲区（处理跨 chunk 的标签）
  private partialTagBuffer: string = ''
  // Function Calling 工具调用累积状态（流式响应）
  private streamToolCalls: Map<number, ToolCall> = new Map()

  private constructor() {
    this.httpService = getHttpService()
  }

  // 重置 thinking 状态（每次新请求前调用）
  resetThinkingState(): void {
    this.isInThinkingBlock = false
    this.minimaxReasoningBuffer = ''
    this.minimaxContentBuffer = ''
    this.partialTagBuffer = ''
    this.streamToolCalls = new Map()
  }

  // 获取累积的工具调用（流式响应完成后调用）
  getAccumulatedToolCalls(): ToolCall[] {
    const result: ToolCall[] = []
    this.streamToolCalls.forEach((toolCall, index) => {
      const normalizedId = this.normalizeToolCallId(toolCall.id, index)
      const normalizedName = this.normalizeToolFunctionName(toolCall.functionName)
      const normalizedArgs = this.normalizeToolArguments(toolCall.arguments)
      result.push(new ToolCall(normalizedId, normalizedName, normalizedArgs))
    })
    return result
  }

  private normalizeToolCallId(rawId: string, index: number): string {
    const value = rawId as string | null | undefined
    if (value === undefined || value === null || value.trim() === '') {
      return `tool_call_${Date.now()}_${index}`
    }
    return value.trim()
  }

  private normalizeToolFunctionName(rawName: string): string {
    const value = rawName as string | null | undefined
    if (value === undefined || value === null) {
      return ''
    }
    const trimmed = value.trim()
    if (trimmed === '') {
      return ''
    }
    const normalized = trimmed.toLowerCase().replace(/[\s\-]+/g, '_')
    if (normalized === 'exa_search' || normalized === 'websearch' || normalized === 'search_web'
      || normalized === 'internet_search' || normalized === 'web_search_exa') {
      return 'web_search'
    }
    if (normalized === 'weather' || normalized === 'weather_search' || normalized === 'get_weather'
      || normalized === 'query_weather' || normalized === 'weather_lookup') {
      return 'weather_query'
    }
    return trimmed
  }

  private mergeToolFunctionName(previousName: string, incomingName: string): string {
    const prev = this.normalizeToolFunctionName(previousName)
    const next = this.normalizeToolFunctionName(incomingName)
    if (next === '') {
      return prev
    }
    if (prev === '') {
      return next
    }
    if (next.startsWith(prev)) {
      return next
    }
    if (prev.startsWith(next)) {
      return prev
    }
    if (next.endsWith(prev)) {
      return next
    }
    if (prev.endsWith(next)) {
      return prev
    }
    return prev + next
  }

  private normalizeToolArguments(rawArgs: string): string {
    const value = rawArgs as string | Object | null | undefined
    if (value === undefined || value === null) {
      return '{}'
    }
    if (typeof value === 'string') {
      const trimmed = value.trim()
      return trimmed !== '' ? trimmed : '{}'
    }
    try {
      return JSON.stringify(value)
    } catch (error) {
      console.warn('AIApiService', `Failed to stringify tool arguments: ${JSON.stringify(error)}`)
      return '{}'
    }
  }

  private normalizeToolArgumentsChunk(rawArgs: string): string {
    const value = rawArgs as string | Object | null | undefined
    if (value === undefined || value === null) {
      return ''
    }
    if (typeof value === 'string') {
      return value
    }
    try {
      return JSON.stringify(value)
    } catch (error) {
      console.warn('AIApiService', `Failed to stringify tool argument chunk: ${JSON.stringify(error)}`)
      return ''
    }
  }

  // 说明：不做“内容像推理”的启发式判断（Kelivo 策略）
  // 若供应商未提供结构化推理字段（reasoning_content/reasoning_details 等）或显式 <think> 标签，
  // 则不尝试拆分，避免出现“推理被拆出一部分、另一部分仍在正文”的不一致体验。

  static getInstance(): AIApiService {
    if (AIApiService.instance === null) {
      AIApiService.instance = new AIApiService()
    }
    return AIApiService.instance
  }

  // 发送聊天请求
  async sendChatRequest(
    config: AIApiConfig,
    messages: RequestMessage[],
    model: string,
    temperature: number = 0.7,
    maxTokens: number = 4096,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  ): Promise<AIApiResult> {
    const url = this.buildChatUrl(config, model)
    const headers = this.buildHeaders(config)
    const requestBody = this.buildRequestBody(config, messages, model, temperature, maxTokens, reasoningLevel)

    const response = await this.httpService.postWithTimeout(
      url,
      JSON.stringify(requestBody),
      headers,
      120000 // 2分钟超时
    )

    if (!response.success) {
      const result: AIApiResult = {
        success: false,
        content: '',
        errorMessage: response.errorMessage,
        usage: null,
        reasoningContent: ''
      }
      return result
    }

    return this.parseResponse(config.apiStyle, response.data)
  }

  // 测试连接
  async testConnection(config: AIApiConfig, modelId: string = ''): Promise<AIApiResult> {
    const testMessages: RequestMessage[] = [
      new RequestMessage('user', 'Hi')
    ]

    const testModel = modelId !== '' ? modelId : this.getDefaultModel(config.apiStyle)
    const url = this.buildChatUrl(config, testModel)
    const headers = this.buildHeaders(config)

    // 根据 API 风格构建测试请求
    let requestBodyStr: string
    if (config.apiStyle === ApiStyle.GOOGLE) {
      const googleBody: GoogleRequestBody = {
        contents: [{ role: 'user', parts: [{ text: 'Hi' }] }],
        generationConfig: { temperature: 0.7, maxOutputTokens: 10 }
      }
      requestBodyStr = JSON.stringify(googleBody)
    } else if (config.apiStyle === ApiStyle.ANTHROPIC) {
      const anthropicBody: AnthropicRequestBody = {
        model: testModel,
        messages: [{ role: 'user', content: 'Hi' }],
        max_tokens: 10,
        temperature: 0.7
      }
      requestBodyStr = JSON.stringify(anthropicBody)
    } else {
      const openaiBody: TestRequestBody = {
        model: testModel,
        messages: testMessages,
        max_tokens: 10
      }
      requestBodyStr = JSON.stringify(openaiBody)
    }

    const response = await this.httpService.postWithTimeout(
      url,
      requestBodyStr,
      headers,
      15000 // 15秒超时
    )

    if (!response.success) {
      const result: AIApiResult = {
        success: false,
        content: '',
        errorMessage: response.errorMessage,
        usage: null,
        reasoningContent: ''
      }
      return result
    }

    // 检查响应是否为有效的 JSON
    try {
      const errorData = JSON.parse(response.data) as ApiErrorResponse
      // 检查是否有错误字段
      if (errorData.error !== undefined && errorData.error !== null) {
        const result: AIApiResult = {
          success: false,
          content: '',
          errorMessage: errorData.error.message,
          usage: null,
          reasoningContent: ''
        }
        return result
      }
      const successResult: AIApiResult = {
        success: true,
        content: 'Connection successful',
        errorMessage: '',
        usage: null,
        reasoningContent: ''
      }
      return successResult
    } catch (error) {
      const errorResult: AIApiResult = {
        success: false,
        content: '',
        errorMessage: 'Invalid response format',
        usage: null,
        reasoningContent: ''
      }
      return errorResult
    }
  }

  // 获取模型列表
  async getModels(config: AIApiConfig): Promise<ModelsListResult> {
    const url = this.buildModelsUrl(config)
    const headers = this.buildHeaders(config)

    const response = await this.httpService.get(url, headers)

    if (!response.success) {
      const result: ModelsListResult = {
        success: false,
        models: [],
        errorMessage: response.errorMessage
      }
      return result
    }

    try {
      const modelsResponse = JSON.parse(response.data) as ModelsListResponse
      const modelIds: string[] = []
      if (modelsResponse.data !== undefined && modelsResponse.data !== null) {
        for (let i = 0; i < modelsResponse.data.length; i++) {
          modelIds.push(modelsResponse.data[i].id)
        }
      }
      const result: ModelsListResult = {
        success: true,
        models: modelIds,
        errorMessage: ''
      }
      return result
    } catch (error) {
      const result: ModelsListResult = {
        success: false,
        models: [],
        errorMessage: 'Failed to parse models list'
      }
      return result
    }
  }

  // 构建聊天 API URL
  private buildChatUrl(config: AIApiConfig, model: string = ''): string {
    // 如果提供了自定义 apiPath，直接使用
    if (config.apiPath && config.apiPath.trim() !== '') {
      return ApiUrlResolver.buildUrl(config.baseUrl, config.apiPath)
    }

    let baseUrl = config.baseUrl
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.slice(0, -1)
    }

    // 根据 API 风格构建 URL
    if (config.apiStyle === ApiStyle.GOOGLE) {
      // Google Gemini API: https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
      if (baseUrl.includes('googleapis.com')) {
        return `${baseUrl}/v1beta/models/${model}:generateContent?key=${config.apiKey}`
      }
      return `${baseUrl}/v1beta/models/${model}:generateContent`
    }

    if (config.apiStyle === ApiStyle.ANTHROPIC) {
      return `${baseUrl}/v1/messages`
    }

    // OpenAI 兼容格式
    // 检查 baseUrl 是否已包含版本路径（如 /v1、/v2、/v3 等）
    if (/\/v\d+/.test(baseUrl)) {
      return `${baseUrl}/chat/completions`
    }
    return `${baseUrl}/v1/chat/completions`
  }

  // 构建模型列表 API URL
  private buildModelsUrl(config: AIApiConfig): string {
    // 如果提供了自定义 apiPath，推导 models 端点
    if (config.apiPath && config.apiPath.trim() !== '') {
      // 将 /chat/completions 替换为 /models
      const modelsPath = config.apiPath.replace('/chat/completions', '/models').replace('/completions', '/models')
      return ApiUrlResolver.buildUrl(config.baseUrl, modelsPath)
    }

    let baseUrl = config.baseUrl
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.slice(0, -1)
    }

    // 检查 baseUrl 是否已包含版本路径（如 /v1、/v2、/v3 等）
    if (/\/v\d+/.test(baseUrl)) {
      return `${baseUrl}/models`
    }
    return `${baseUrl}/v1/models`
  }

  // 构建请求头
  private buildHeaders(config: AIApiConfig): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    }

    if (config.apiStyle === ApiStyle.ANTHROPIC) {
      headers['x-api-key'] = config.apiKey
      headers['anthropic-version'] = '2023-06-01'
    } else if (config.apiStyle === ApiStyle.GOOGLE) {
      // Google API key 通过 URL 参数传递，不需要额外的 header
    } else if (config.providerType === ProviderType.AZURE) {
      headers['api-key'] = config.apiKey
    } else if (config.apiKey !== '') {
      headers['Authorization'] = `Bearer ${config.apiKey}`
    }

    return headers
  }

  // 构建请求体
  private buildRequestBody(
    config: AIApiConfig,
    messages: RequestMessage[],
    model: string,
    temperature: number,
    maxTokens: number,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    tools?: ToolDefinition[],
    toolChoice?: string
  ): OpenAIRequestBody | AnthropicRequestBody | GoogleRequestBody {
    if (config.apiStyle === ApiStyle.GOOGLE) {
      // Google Gemini 格式
      const googleContents: GoogleContent[] = []

      for (let i = 0; i < messages.length; i++) {
        const msg = messages[i]
        if (msg.role !== 'system') {
          const role = msg.role === 'assistant' ? 'model' : 'user'
          const parts: GoogleContentPart[] = []

          // 添加附件（图片和文件，包括 PDF）
          if (msg.hasAttachments()) {
            for (let j = 0; j < msg.attachments.length; j++) {
              const attachment = msg.attachments[j]
              if (attachment.base64Data !== '') {
                // Google Gemini 支持通过 inline_data 直接发送图片和 PDF
                const inlineDataPart: GoogleContentPart = {
                  inline_data: {
                    mime_type: attachment.mimeType,
                    data: attachment.base64Data
                  }
                }
                parts.push(inlineDataPart)
              }
            }
          }

          // 添加文本
          if (msg.content !== '') {
            const textPart: GoogleContentPart = {
              text: msg.content
            }
            parts.push(textPart)
          }

          const content: GoogleContent = {
            role: role,
            parts: parts
          }
          googleContents.push(content)
        }
      }

      const googleBody: GoogleRequestBody = {
        contents: googleContents,
        generationConfig: {
          temperature: temperature,
          maxOutputTokens: maxTokens
        }
      }
      return googleBody
    }

    if (config.apiStyle === ApiStyle.ANTHROPIC) {
      // Anthropic 格式
      const anthropicMessages: (MessageContent | AnthropicMultimodalMessage)[] = []
      let systemPrompt = ''

      for (let i = 0; i < messages.length; i++) {
        const msg = messages[i]
        if (msg.role === 'system') {
          systemPrompt = msg.content
        } else if (msg.hasAttachments()) {
          // Anthropic 多模态消息（支持图片和 PDF）
          const contentParts: AnthropicContentPart[] = []

          // 添加附件
          for (let j = 0; j < msg.attachments.length; j++) {
            const attachment = msg.attachments[j]
            if (attachment.base64Data !== '') {
              if (attachment.type === AttachmentType.IMAGE) {
                // 图片使用 image 类型
                const imagePart: AnthropicContentPart = {
                  type: 'image',
                  source: {
                    type: 'base64',
                    media_type: attachment.mimeType,
                    data: attachment.base64Data
                  }
                }
                contentParts.push(imagePart)
              } else {
                // PDF 等文件使用 document 类型
                const docPart: AnthropicContentPart = {
                  type: 'document',
                  source: {
                    type: 'base64',
                    media_type: attachment.mimeType,
                    data: attachment.base64Data
                  }
                }
                contentParts.push(docPart)
              }
            }
          }

          // 添加文本
          if (msg.content !== '') {
            const textPart: AnthropicContentPart = {
              type: 'text',
              text: msg.content
            }
            contentParts.push(textPart)
          }

          const multimodalMsg: AnthropicMultimodalMessage = {
            role: msg.role,
            content: contentParts
          }
          anthropicMessages.push(multimodalMsg)
        } else {
          const msgContent: MessageContent = {
            role: msg.role,
            content: msg.content
          }
          anthropicMessages.push(msgContent)
        }
      }

      if (systemPrompt !== '') {
        const bodyWithSystem: AnthropicRequestBody = {
          model: model,
          messages: anthropicMessages,
          max_tokens: maxTokens,
          temperature: temperature,
          system: systemPrompt
        }
        // 添加 Anthropic 推理配置
        if (reasoningLevel !== ReasoningLevel.OFF) {
          bodyWithSystem.thinking = {
            type: 'enabled',
            budget_tokens: this.getAnthropicThinkingBudget(reasoningLevel)
          }
        }
        return bodyWithSystem
      }

      const body: AnthropicRequestBody = {
        model: model,
        messages: anthropicMessages,
        max_tokens: maxTokens,
        temperature: temperature
      }
      // 添加 Anthropic 推理配置
      if (reasoningLevel !== ReasoningLevel.OFF) {
        body.thinking = {
          type: 'enabled',
          budget_tokens: this.getAnthropicThinkingBudget(reasoningLevel)
        }
      }
      return body
    }

    // OpenAI 兼容格式
    const openaiMessages: (MessageContent | MultimodalMessageContent | ToolResultMessageContent | AssistantMessageWithToolCalls)[] = []
    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i]

      // 处理工具结果消息（tool 角色）
      if (msg.isToolResultMessage()) {
        const toolResultMsg: ToolResultMessageContent = {
          role: 'tool',
          tool_call_id: msg.toolCallId,
          content: msg.content
        }
        openaiMessages.push(toolResultMsg)
        continue
      }

      // 处理带工具调用的 assistant 消息
      if (msg.hasToolCalls()) {
        const toolCallsForApi: OpenAIToolCall[] = []
        for (let j = 0; j < msg.toolCalls.length; j++) {
          const tc = msg.toolCalls[j]
          const apiToolCall: OpenAIToolCall = {
            id: tc.id,
            type: 'function',
            function: {
              name: tc.functionName,
              arguments: tc.arguments
            }
          }
          toolCallsForApi.push(apiToolCall)
        }
        const assistantWithTools: AssistantMessageWithToolCalls = {
          role: 'assistant',
          content: msg.content !== '' ? msg.content : null,
          tool_calls: toolCallsForApi
        }
        openaiMessages.push(assistantWithTools)
        continue
      }

      // 检查是否有附件
      if (msg.hasAttachments()) {
        // 构建多模态消息
        const contentParts: MultimodalContentPart[] = []
        let fileTextContent = ''

        // 处理附件
        for (let j = 0; j < msg.attachments.length; j++) {
          const attachment = msg.attachments[j]
          if (attachment.base64Data !== '') {
            if (attachment.type === AttachmentType.IMAGE) {
              // 图片使用 image_url 类型
              const imagePart: MultimodalContentPart = {
                type: 'image_url',
                image_url: {
                  url: `data:${attachment.mimeType};base64,${attachment.base64Data}`,
                  detail: 'auto'
                }
              }
              contentParts.push(imagePart)
            } else {
              // OpenAI 不原生支持 PDF，将文件信息添加到文本中提示
              // 注意：某些 OpenAI 兼容的第三方 API 可能支持文件
              fileTextContent += `[附件: ${attachment.name} (${attachment.mimeType})]`
            }
          }
        }

        // 添加文本（包含文件提示信息）
        let textContent = msg.content
        if (fileTextContent !== '') {
          textContent = fileTextContent + '\n' + textContent
        }
        if (textContent !== '') {
          const textPart: MultimodalContentPart = {
            type: 'text',
            text: textContent
          }
          contentParts.push(textPart)
        }

        const multimodalMsg: MultimodalMessageContent = {
          role: msg.role,
          content: contentParts
        }
        openaiMessages.push(multimodalMsg)
      } else {
        // 纯文本消息
        const msgContent: MessageContent = {
          role: msg.role,
          content: msg.content
        }
        openaiMessages.push(msgContent)
      }
    }

    const requestBody: OpenAIRequestBody = {
      model: model,
      messages: openaiMessages,
      temperature: temperature,
      max_tokens: maxTokens
    }

    // 添加模型参数（如果配置中提供）
    if (config.topP !== undefined) {
      requestBody.top_p = config.topP
    }
    if (config.presencePenalty !== undefined) {
      requestBody.presence_penalty = config.presencePenalty
    }
    if (config.frequencyPenalty !== undefined) {
      requestBody.frequency_penalty = config.frequencyPenalty
    }

    // 添加 OpenAI 推理配置（适用于 o1/o3 系列模型）
    if (reasoningLevel !== ReasoningLevel.OFF) {
      requestBody.reasoning_effort = this.getOpenAIReasoningEffort(reasoningLevel)
    }
    // 通过模型 ID 检测特定供应商，添加对应的推理参数
    const modelLower = model.toLowerCase()
    // MiniMax API: 添加 reasoning_split 参数以启用 reasoning_details 字段
    // MiniMax 模型 ID 通常以 abab 或 minimax 开头
    if (modelLower.startsWith('abab') || modelLower.startsWith('minimax')) {
      requestBody.reasoning_split = true
    }
    // 小米 MiMo / 智谱 GLM API: 添加 thinking 参数以启用思维链
    // MiMo 模型 ID 以 mimo 开头（如 mimo-v2-flash）
    // GLM 模型 ID 以 glm 开头（如 glm-4.7）
    const isMiMo = modelLower.startsWith('mimo')
    const isGLM = modelLower.startsWith('glm')
    if (isMiMo || isGLM) {
      if (reasoningLevel !== ReasoningLevel.OFF) {
        // GLM 需要 clear_thinking: false 以保留历史推理内容，提高缓存命中率
        if (isGLM) {
          requestBody.thinking = { type: 'enabled', clear_thinking: false }
        } else {
          requestBody.thinking = { type: 'enabled' }
        }
      } else {
        requestBody.thinking = { type: 'disabled' }
      }
    }
    // 添加 Function Calling 工具定义
    if (tools !== undefined && tools.length > 0) {
      const openaiTools: OpenAITool[] = []
      for (let i = 0; i < tools.length; i++) {
        const tool = tools[i]
        const openaiTool: OpenAITool = {
          type: 'function',
          function: {
            name: tool.function.name,
            description: tool.function.description,
            parameters: tool.function.parameters.toJsonObject()
          }
        }
        openaiTools.push(openaiTool)
      }
      requestBody.tools = openaiTools
      if (toolChoice !== undefined && toolChoice !== '') {
        requestBody.tool_choice = toolChoice
      }
    }
    return requestBody
  }

  // 解析响应
  private parseResponse(apiStyle: ApiStyle, responseData: string): AIApiResult {
    try {
      // 先尝试解析为错误响应
      const errorCheck = JSON.parse(responseData) as ApiErrorResponse
      if (errorCheck.error !== undefined && errorCheck.error !== null) {
        const result: AIApiResult = {
          success: false,
          content: '',
          errorMessage: errorCheck.error.message,
          usage: null,
          reasoningContent: ''
        }
        return result
      }

      if (apiStyle === ApiStyle.GOOGLE) {
        // Google Gemini 响应格式
        return this.parseGoogleResponse(responseData)
      }

      if (apiStyle === ApiStyle.ANTHROPIC) {
        // Anthropic 响应格式
        return this.parseAnthropicResponse(responseData)
      }

      // OpenAI 兼容响应格式
      return this.parseOpenAIResponse(responseData)
    } catch (error) {
      const result: AIApiResult = {
        success: false,
        content: '',
        errorMessage: `Failed to parse response: ${JSON.stringify(error)}`,
        usage: null,
        reasoningContent: ''
      }
      return result
    }
  }

  // 解析 OpenAI 响应
  private parseOpenAIResponse(responseData: string): AIApiResult {
    const response = JSON.parse(responseData) as ChatCompletionResponse
    if (response.choices !== undefined && response.choices.length > 0) {
      const choice = response.choices[0]
      const structuredReasoning = (choice.message.reasoning_content !== undefined && choice.message.reasoning_content !== '')
        || (choice.message.reasoning !== undefined && choice.message.reasoning !== '')
      const result: AIApiResult = {
        success: true,
        content: choice.message.content || '',
        errorMessage: '',
        usage: response.usage,
        reasoningContent: choice.message.reasoning_content || choice.message.reasoning || '',
        finishReason: choice.finish_reason
      }
      if (structuredReasoning && result.reasoningContent !== '' && result.content !== '') {
        result.content = this.stripReasoningOverlap(result.content, result.reasoningContent, false)
      }

      // 处理图片响应（base64 格式）
      if (choice.message.image_base64 && choice.message.image_mime_type) {
        result.imageData = choice.message.image_base64
        result.imageMimeType = choice.message.image_mime_type
      }
      // 处理图片 URL
      else if (choice.message.image_url) {
        result.imageData = choice.message.image_url
        result.imageMimeType = 'image/jpeg'
      }

      // 解析 Function Calling 工具调用
      if (choice.message.tool_calls !== undefined && choice.message.tool_calls.length > 0) {
        const toolCalls: ToolCall[] = []
        for (let i = 0; i < choice.message.tool_calls.length; i++) {
          const tc = choice.message.tool_calls[i]
          const normalizedId = this.normalizeToolCallId(tc.id, i)
          const rawName = tc.function !== undefined ? tc.function.name : ''
          const rawArgs = tc.function !== undefined ? tc.function.arguments : ''
          const normalizedName = this.normalizeToolFunctionName(rawName)
          const normalizedArgs = this.normalizeToolArguments(rawArgs)
          const toolCall = new ToolCall(
            normalizedId,
            normalizedName,
            normalizedArgs
          )
          toolCalls.push(toolCall)
        }
        result.toolCalls = toolCalls
      }

      return result
    }
    const result: AIApiResult = {
      success: false,
      content: '',
      errorMessage: 'No choices in response',
      usage: null,
      reasoningContent: ''
    }
    return result
  }

  // 解析 Anthropic 响应
  private parseAnthropicResponse(responseData: string): AIApiResult {
    const response = JSON.parse(responseData) as AnthropicResponse
    if (response.content !== undefined && response.content.length > 0) {
      let content = ''
      let reasoningContent = ''
      let imageData = ''
      let imageMimeType = ''

      for (let i = 0; i < response.content.length; i++) {
        const block = response.content[i]
        if (block.type === 'text') {
          content += block.text
        } else if (block.type === 'thinking') {
          // Anthropic 的思考内容
          reasoningContent += block.text
        } else if (block.type === 'image' && block.source) {
          // Anthropic 的图片响应
          imageData = block.source.data
          imageMimeType = block.source.media_type
          console.info('AIApiService', `Received Anthropic image: ${imageMimeType}, size: ${imageData.length}`)
        }
      }

      const result: AIApiResult = {
        success: true,
        content: content,
        errorMessage: '',
        usage: response.usage,
        reasoningContent: reasoningContent
      }

      // 添加图片数据
      if (imageData && imageMimeType) {
        result.imageData = imageData
        result.imageMimeType = imageMimeType
      }

      return result
    }
    const result: AIApiResult = {
      success: false,
      content: '',
      errorMessage: 'No content in response',
      usage: null,
      reasoningContent: ''
    }
    return result
  }

  // 解析 Google Gemini 响应
  private parseGoogleResponse(responseData: string): AIApiResult {
    const response = JSON.parse(responseData) as GoogleResponse
    if (response.candidates !== undefined && response.candidates.length > 0) {
      const candidate = response.candidates[0]
      if (candidate.content !== undefined && candidate.content.parts !== undefined && candidate.content.parts.length > 0) {
        let content = ''
        for (let i = 0; i < candidate.content.parts.length; i++) {
          content += candidate.content.parts[i].text
        }
        const result: AIApiResult = {
          success: true,
          content: content,
          errorMessage: '',
          usage: null,
          reasoningContent: ''
        }
        return result
      }
    }
    const result: AIApiResult = {
      success: false,
      content: '',
      errorMessage: 'No candidates in response',
      usage: null,
      reasoningContent: ''
    }
    return result
  }

  // 获取默认模型
  private getDefaultModel(apiStyle: ApiStyle): string {
    if (apiStyle === ApiStyle.OPENAI) {
      return 'gpt-3.5-turbo'
    } else if (apiStyle === ApiStyle.ANTHROPIC) {
      return 'claude-3-haiku-20240307'
    } else if (apiStyle === ApiStyle.GOOGLE) {
      return 'gemini-pro'
    }
    return 'gpt-3.5-turbo'
  }

  // 获取 Anthropic 思考预算（token 数量）
  private getAnthropicThinkingBudget(level: ReasoningLevel): number {
    switch (level) {
      case ReasoningLevel.LOW:
        return 5000
      case ReasoningLevel.MEDIUM:
        return 15000
      case ReasoningLevel.HIGH:
        return 30000
      default:
        return 0
    }
  }

  // 获取 OpenAI 推理强度
  private getOpenAIReasoningEffort(level: ReasoningLevel): string {
    switch (level) {
      case ReasoningLevel.LOW:
        return 'low'
      case ReasoningLevel.MEDIUM:
        return 'medium'
      case ReasoningLevel.HIGH:
        return 'high'
      default:
        return 'low'
    }
  }

  // 流式发送聊天请求
  streamChatRequest(
    config: AIApiConfig,
    messages: RequestMessage[],
    model: string,
    onData: (content: string) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    temperature: number = 0.7,
    maxTokens: number = 4096,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string) => void,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF  // 推理级别参数
  ): http.HttpRequest {
    // 重置 thinking 状态（用于 DeepSeek-R1 的 <think> 标签解析）
    this.resetThinkingState()

    let url = this.buildChatUrl(config, model)
    const headers = this.buildHeaders(config)
    if (config.apiStyle !== ApiStyle.GOOGLE) {
      headers['Accept'] = 'text/event-stream'
    }
    const requestBody = this.buildRequestBody(config, messages, model, temperature, maxTokens, reasoningLevel)

    // 添加流式请求标志
    if (config.apiStyle === ApiStyle.OPENAI) {
      (requestBody as OpenAIRequestBody).stream = true
    } else if (config.apiStyle === ApiStyle.ANTHROPIC) {
      (requestBody as AnthropicRequestBody).stream = true
    }
    // Google API URL 需要改为 streamGenerateContent
    if (config.apiStyle === ApiStyle.GOOGLE) {
       url = url.replace('generateContent', 'streamGenerateContent')
    }

    console.info('AIApiService', `Streaming request to: ${url}`)
    console.info('AIApiService', `Request body: ${JSON.stringify(requestBody).substring(0, 500)}...`)

    const textDecoder = util.TextDecoder.create('utf-8')
    let buffer = ''

    return this.httpService.streamPost(
      url,
      JSON.stringify(requestBody),
      headers,
      (chunk: ArrayBuffer) => {
        try {
          const text = textDecoder.decodeToString(new Uint8Array(chunk), { stream: true })
          buffer += text

          // 处理 buffer 中的每一行
          const lines = buffer.split('\n')
          buffer = lines.pop() || '' // 保留最后一行（可能不完整）

          for (let i = 0; i < lines.length; i++) {
            this.handleStreamLine(config.apiStyle, lines[i], onData, onReasoningData, onImageData)
          }
        } catch (e) {
          console.error('AIApiService', `Stream decode error: ${JSON.stringify(e)}`)
        }
      },
      (response) => {
        if (buffer.trim() !== '') {
          this.handleStreamLine(config.apiStyle, buffer, onData, onReasoningData, onImageData)
          buffer = ''
        }
        if (!response.success) {
          console.error('AIApiService', `Stream response error: ${response.errorMessage}`)
          onError(response.errorMessage)
          return
        }
        console.info('AIApiService', 'Stream completed successfully')
        onComplete()
      },
      (error) => {
        console.error('AIApiService', `Stream error: ${error}`)
        onError(error)
      }
    )
  }

  // 流式发送聊天请求（支持 Function Calling）
  streamChatRequestWithTools(
    config: AIApiConfig,
    messages: RequestMessage[],
    model: string,
    onData: (content: string) => void,
    onComplete: (toolCalls: ToolCall[]) => void,
    onError: (error: string) => void,
    temperature: number = 0.7,
    maxTokens: number = 4096,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string) => void,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    tools?: ToolDefinition[],
    toolChoice?: string,
    onToolCallDelta?: (toolCallDeltas: ToolCallDelta[]) => void
  ): http.HttpRequest {
    // 重置 thinking 状态（用于 DeepSeek-R1 的 <think> 标签解析）
    this.resetThinkingState()

    let url = this.buildChatUrl(config, model)
    const headers = this.buildHeaders(config)
    if (config.apiStyle !== ApiStyle.GOOGLE) {
      headers['Accept'] = 'text/event-stream'
    }
    const requestBody = this.buildRequestBody(config, messages, model, temperature, maxTokens, reasoningLevel, tools, toolChoice)

    // 添加流式请求标志
    if (config.apiStyle === ApiStyle.OPENAI) {
      (requestBody as OpenAIRequestBody).stream = true
    } else if (config.apiStyle === ApiStyle.ANTHROPIC) {
      (requestBody as AnthropicRequestBody).stream = true
    }
    // Google API URL 需要改为 streamGenerateContent
    if (config.apiStyle === ApiStyle.GOOGLE) {
       url = url.replace('generateContent', 'streamGenerateContent')
    }

    console.info('AIApiService', `Streaming request with tools to: ${url}`)
    console.info('AIApiService', `Request body: ${JSON.stringify(requestBody).substring(0, 500)}...`)

    const textDecoder = util.TextDecoder.create('utf-8')
    let buffer = ''

    return this.httpService.streamPost(
      url,
      JSON.stringify(requestBody),
      headers,
      (chunk: ArrayBuffer) => {
        try {
          const text = textDecoder.decodeToString(new Uint8Array(chunk), { stream: true })
          buffer += text

          // 处理 buffer 中的每一行
          const lines = buffer.split('\n')
          buffer = lines.pop() || '' // 保留最后一行（可能不完整）

          for (let i = 0; i < lines.length; i++) {
            this.handleStreamLineWithTools(config.apiStyle, lines[i], onData, onReasoningData, onImageData, onToolCallDelta)
          }
        } catch (e) {
          console.error('AIApiService', `Stream decode error: ${JSON.stringify(e)}`)
        }
      },
      (response) => {
        if (buffer.trim() !== '') {
          this.handleStreamLineWithTools(config.apiStyle, buffer, onData, onReasoningData, onImageData, onToolCallDelta)
          buffer = ''
        }
        if (!response.success) {
          console.error('AIApiService', `Stream response error: ${response.errorMessage}`)
          onError(response.errorMessage)
          return
        }
        console.info('AIApiService', 'Stream completed successfully')
        // 返回累积的工具调用
        const accumulatedToolCalls = this.getAccumulatedToolCalls()
        onComplete(accumulatedToolCalls)
      },
      (error) => {
        console.error('AIApiService', `Stream error: ${error}`)
        onError(error)
      }
    )
  }

  // 处理流式响应行（支持工具调用回调）
  private handleStreamLineWithTools(
    apiStyle: ApiStyle,
    line: string,
    onData: (content: string) => void,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string) => void,
    onToolCallDelta?: (toolCallDeltas: ToolCallDelta[]) => void
  ): void {
    const trimmedLine = line.trim()
    if (trimmedLine === '') {
      return
    }
    if (trimmedLine === 'data: [DONE]' || trimmedLine === 'data:[DONE]' || trimmedLine === '[DONE]') {
      return
    }

    let jsonStr: string = ''
    if (trimmedLine.startsWith('data:')) {
      jsonStr = trimmedLine.substring(5).trim()
    } else if (trimmedLine.startsWith('{') || trimmedLine.startsWith('[')) {
      jsonStr = trimmedLine
    } else {
      return
    }

    if (jsonStr === '[DONE]') {
      return
    }

    try {
      const json = JSON.parse(jsonStr) as object
      this.emitStreamContentWithTools(apiStyle, json, onData, onReasoningData, onImageData, onToolCallDelta)
    } catch (e) {
      // 记录解析错误以便调试
      console.warn('AIApiService', `JSON parse error for line: ${jsonStr.substring(0, 100)}...`)
    }
  }

  // 发送流式内容（支持工具调用回调）
  private emitStreamContentWithTools(
    apiStyle: ApiStyle,
    json: object,
    onData: (content: string) => void,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string) => void,
    onToolCallDelta?: (toolCallDeltas: ToolCallDelta[]) => void
  ): void {
    if (Array.isArray(json)) {
      const items = json as object[]
      for (let i = 0; i < items.length; i++) {
        const result = this.parseStreamChunk(apiStyle, items[i])
        if (result.content !== '') {
          onData(result.content)
        }
        if (result.reasoningContent !== '' && onReasoningData) {
          onReasoningData(result.reasoningContent)
        }
        if (result.imageData && result.imageMimeType && onImageData) {
          try {
            onImageData(result.imageData, result.imageMimeType)
          } catch (e) {
            console.error('AIApiService', `Error in onImageData callback: ${JSON.stringify(e)}`)
          }
        }
        if (result.toolCallDeltas && result.toolCallDeltas.length > 0 && onToolCallDelta) {
          try {
            onToolCallDelta(result.toolCallDeltas)
          } catch (e) {
            console.error('AIApiService', `Error in onToolCallDelta callback: ${JSON.stringify(e)}`)
          }
        }
      }
      return
    }

    const result = this.parseStreamChunk(apiStyle, json)
    if (result.content !== '') {
      onData(result.content)
    }
    if (result.reasoningContent !== '' && onReasoningData) {
      onReasoningData(result.reasoningContent)
    }
    if (result.imageData && result.imageMimeType && onImageData) {
      try {
        onImageData(result.imageData, result.imageMimeType)
      } catch (e) {
        console.error('AIApiService', `Error in onImageData callback: ${JSON.stringify(e)}`)
      }
    }
    if (result.toolCallDeltas && result.toolCallDeltas.length > 0 && onToolCallDelta) {
      try {
        onToolCallDelta(result.toolCallDeltas)
      } catch (e) {
        console.error('AIApiService', `Error in onToolCallDelta callback: ${JSON.stringify(e)}`)
      }
    }
  }

  // 解析 DeepSeek-R1 的 <think>...</think> 标签
  // 处理流式响应中标签可能跨块的情况
  private parseThinkingTags(text: string): StreamChunkResult {
    const result: StreamChunkResult = { content: '', reasoningContent: '' }

    // 将上次缓冲的部分标签与当前文本合并
    let remaining = this.partialTagBuffer + text
    this.partialTagBuffer = ''

    let contentParts: string[] = []
    let reasoningParts: string[] = []

    while (remaining.length > 0) {
      if (this.isInThinkingBlock) {
        // 当前在 <think> 块内，查找 </think>
        const endIndex = remaining.indexOf('</think>')
        if (endIndex !== -1) {
          // 找到结束标签
          reasoningParts.push(remaining.substring(0, endIndex))
          remaining = remaining.substring(endIndex + 8) // 8 = '</think>'.length
          this.isInThinkingBlock = false
        } else {
          // 没有找到完整的结束标签，检查是否有部分标签
          // </think> 的可能前缀: <, </, </t, </th, </thi, </thin, </think
          const partialEndTags = ['</think', '</thin', '</thi', '</th', '</t', '</', '<']
          let foundPartial = false
          for (let i = 0; i < partialEndTags.length; i++) {
            const partial = partialEndTags[i]
            if (remaining.endsWith(partial)) {
              // 找到部分标签，缓冲起来
              this.partialTagBuffer = partial
              reasoningParts.push(remaining.substring(0, remaining.length - partial.length))
              remaining = ''
              foundPartial = true
              break
            }
          }
          if (!foundPartial) {
            // 没有部分标签，整个内容都是推理内容
            reasoningParts.push(remaining)
            remaining = ''
          }
        }
      } else {
        // 当前不在 <think> 块内，查找 <think>
        const startIndex = remaining.indexOf('<think>')
        if (startIndex !== -1) {
          // 找到开始标签
          if (startIndex > 0) {
            contentParts.push(remaining.substring(0, startIndex))
          }
          remaining = remaining.substring(startIndex + 7) // 7 = '<think>'.length
          this.isInThinkingBlock = true
        } else {
          // 没有找到完整的开始标签，检查是否有部分标签
          // <think> 的可能前缀: <, <t, <th, <thi, <thin, <think
          const partialStartTags = ['<think', '<thin', '<thi', '<th', '<t', '<']
          let foundPartial = false
          for (let i = 0; i < partialStartTags.length; i++) {
            const partial = partialStartTags[i]
            if (remaining.endsWith(partial)) {
              // 找到部分标签，缓冲起来
              this.partialTagBuffer = partial
              contentParts.push(remaining.substring(0, remaining.length - partial.length))
              remaining = ''
              foundPartial = true
              break
            }
          }
          if (!foundPartial) {
            // 没有部分标签，整个内容都是正常内容
            contentParts.push(remaining)
            remaining = ''
          }
        }
      }
    }

    result.content = contentParts.join('')
    result.reasoningContent = reasoningParts.join('')
    return result
  }

  private parseStreamChunk(apiStyle: ApiStyle, json: object): StreamChunkResult {
    const result: StreamChunkResult = { content: '', reasoningContent: '' }
    let hasReasoningDetails: boolean = false

    if (apiStyle === ApiStyle.OPENAI) {
      const chunk = json as OpenAIStreamChunk
      if (chunk.choices && chunk.choices.length > 0) {
        const delta = chunk.choices[0].delta
        let rawContent = delta?.content || ''
        // 处理推理内容（支持多种格式）
        // 1. MiniMax reasoning_details (数组格式，优先处理)
        if (delta?.reasoning_details && delta.reasoning_details.length > 0) {
          hasReasoningDetails = true
          result.reasoningIsStructured = true
          const details: MiniMaxReasoningDetail[] = delta.reasoning_details
          for (let i = 0; i < details.length; i++) {
            const detail = details[i]
            if (detail.text && detail.text.length > 0) {
              // MiniMax 返回的是累积的完整内容，需要计算增量
              const fullText = detail.text
              if (fullText.length > this.minimaxReasoningBuffer.length) {
                result.reasoningContent = fullText.substring(this.minimaxReasoningBuffer.length)
                this.minimaxReasoningBuffer = fullText
              }
            }
          }
          // MiniMax 的 content 字段也是累积的，需要计算增量并过滤 <think> 标签
          if (rawContent !== '' && rawContent.length > this.minimaxContentBuffer.length) {
            const incrementalContent = rawContent.substring(this.minimaxContentBuffer.length)
            this.minimaxContentBuffer = rawContent
            const parsed = this.parseThinkingTags(incrementalContent)
            result.content = parsed.content
            // 如果 reasoning_details 为空但 content 中有 <think> 标签，也提取推理内容
            if (result.reasoningContent === '' && parsed.reasoningContent !== '') {
              result.reasoningContent = parsed.reasoningContent
            }
          } else {
            result.content = ''
          }
        }
        // 2. 其他 API 的 reasoning_content (字符串格式)
        else if (delta?.reasoning_content && delta.reasoning_content.length > 0) {
          result.reasoningContent = delta.reasoning_content
          result.reasoningIsStructured = true
          result.content = rawContent || ''
        }
        // 2.1 其他 API 的 reasoning (字符串格式)
        else if (delta?.reasoning && delta.reasoning.length > 0) {
          result.reasoningContent = delta.reasoning
          result.reasoningIsStructured = true
          result.content = rawContent || ''
        }
        // 3. MiniMax 后续 chunk（没有 reasoning_details 但之前已处理过）
        // 通过 minimaxReasoningBuffer 不为空来判断是 MiniMax 响应
        else if (this.minimaxReasoningBuffer !== '' && rawContent !== '') {
          // MiniMax 的 content 字段也是累积的，需要计算增量并过滤 <think> 标签
          if (rawContent.length > this.minimaxContentBuffer.length) {
            const incrementalContent = rawContent.substring(this.minimaxContentBuffer.length)
            this.minimaxContentBuffer = rawContent
            const parsed = this.parseThinkingTags(incrementalContent)
            result.content = parsed.content
            // 如果 content 中有 <think> 标签内容，也提取推理内容
            if (parsed.reasoningContent !== '') {
              result.reasoningContent = parsed.reasoningContent
            }
          } else {
            result.content = ''
          }
        }
        // 4. DeepSeek-R1 的标签（在 content 中）
        else if (rawContent !== '') {
          const parsed = this.parseThinkingTags(rawContent)
          result.content = parsed.content
          result.reasoningContent = parsed.reasoningContent
        } else {
          result.content = rawContent
        }

        // 处理图片响应（base64 格式）
        if (delta?.image_base64 && delta?.image_mime_type) {
          result.imageData = delta.image_base64
          result.imageMimeType = delta.image_mime_type
          console.info('AIApiService', `Received OpenAI image: ${delta.image_mime_type}, size: ${delta.image_base64.length}`)
        }
        // 处理图片 URL（需要下载或直接使用）
        else if (delta?.image_url) {
          // 暂时将 URL 作为图片数据传递，ViewModel 可选择下载或直接显示
          result.imageData = delta.image_url
          result.imageMimeType = 'image/jpeg' // 默认 MIME 类型，实际应从响应中获取
          console.info('AIApiService', `Received OpenAI image URL: ${delta.image_url}`)
        }

        // 处理 Function Calling 工具调用增量
        if (delta?.tool_calls && delta.tool_calls.length > 0) {
          const toolCallDeltas: ToolCallDelta[] = []
          for (let i = 0; i < delta.tool_calls.length; i++) {
            const tc = delta.tool_calls[i]
            const incomingName = this.normalizeToolFunctionName(tc.function?.name || '')
            const incomingArgs = this.normalizeToolArgumentsChunk(tc.function?.arguments || '')
            const tcDelta: ToolCallDelta = {
              index: tc.index,
              id: tc.id,
              functionName: incomingName !== '' ? incomingName : undefined,
              arguments: incomingArgs !== '' ? incomingArgs : undefined
            }
            toolCallDeltas.push(tcDelta)

            // 累积工具调用
            let existingToolCall = this.streamToolCalls.get(tc.index)
            if (existingToolCall === undefined) {
              existingToolCall = new ToolCall('', '', '')
              this.streamToolCalls.set(tc.index, existingToolCall)
            }
            const incomingId = tc.id as string | null | undefined
            if (incomingId !== undefined && incomingId !== null && incomingId !== '') {
              existingToolCall.id = incomingId
            }
            if (incomingName !== '') {
              existingToolCall.functionName = this.mergeToolFunctionName(existingToolCall.functionName, incomingName)
            }
            if (incomingArgs !== '') {
              existingToolCall.arguments += incomingArgs
            }
          }
          result.toolCallDeltas = toolCallDeltas
        }

        // 记录 finish_reason
        const finishReason = chunk.choices[0].finish_reason
        if (finishReason !== undefined && finishReason !== null) {
          result.finishReason = finishReason
        }
      }
    } else if (apiStyle === ApiStyle.ANTHROPIC) {
      const chunk = json as AnthropicStreamChunk
      if (chunk.type === 'content_block_delta' && chunk.delta?.text) {
        result.content = chunk.delta.text
      }
      // Anthropic 思考内容处理
      if (chunk.type === 'thinking_delta' && chunk.delta?.text) {
        result.reasoningContent = chunk.delta.text
        result.reasoningIsStructured = true
      }
      // Anthropic 图片响应处理（image_block_delta）
      if (chunk.type === 'content_block_delta' && chunk.delta?.image_source) {
        result.imageData = chunk.delta.image_source.data
        result.imageMimeType = chunk.delta.image_source.media_type
        console.info('AIApiService', `Received Anthropic image: ${chunk.delta.image_source.media_type}, size: ${chunk.delta.image_source.data.length}`)
      }
    } else if (apiStyle === ApiStyle.GOOGLE) {
      const chunk = json as GoogleStreamChunk
      if (chunk.candidates && chunk.candidates.length > 0) {
        const candidate = chunk.candidates[0]
        if (candidate.content && candidate.content.parts && candidate.content.parts.length > 0) {
          // 遍历所有 parts，处理文本和图片
          for (let i = 0; i < candidate.content.parts.length; i++) {
            const part = candidate.content.parts[i]
            if (part.text) {
              result.content += part.text
            } else if (part.inline_data) {
              // Gemini 生成的图片
              result.imageData = part.inline_data.data
              result.imageMimeType = part.inline_data.mime_type
              console.info('AIApiService', `Received image: ${part.inline_data.mime_type}, size: ${part.inline_data.data.length}`)
            }
          }
        }
      }
    }
    if (result.reasoningIsStructured === true && result.reasoningContent !== '' && result.content !== '') {
      result.content = this.stripReasoningOverlap(result.content, result.reasoningContent, hasReasoningDetails)
    }
    return result
  }

  private stripReasoningOverlap(content: string, reasoning: string, aggressive: boolean = false): string {
    if (content === '' || reasoning === '') {
      return content
    }
    const lead = content.length - content.trimStart().length
    const c = content.substring(lead)
    const r = reasoning.trimStart()
    if (c === '' || r === '') {
      return content
    }

    const aggressiveMin = 6
    if (aggressive && r.length >= aggressiveMin) {
      if (c.startsWith(r)) {
        const stripped = content.substring(lead + r.length)
        return this.trimLeadingPunctuationAfterStrip(stripped)
      }
      if (r.startsWith(c) && c.length >= aggressiveMin) {
        return ''
      }
    }

    let i = 0
    const max = Math.min(c.length, r.length)
    while (i < max && c.charAt(i) === r.charAt(i)) {
      i++
    }
    if (i >= 16) {
      const stripped = content.substring(lead + i)
      return this.trimLeadingPunctuationAfterStrip(stripped)
    }
    if (i === c.length && c.length >= 8) {
      return ''
    }
    return content
  }

  private trimLeadingPunctuationAfterStrip(text: string): string {
    if (text === '') {
      return text
    }
    const trimmed = text.trimStart()
    if (trimmed === '') {
      return trimmed
    }
    const first = trimmed.charAt(0)
    // overlap 裁剪后，如果正文以“逗号/句号”等开头，通常是裁剪到了句中；这里做最小化清理。
    const punctuations = [',', '，', '。', ';', '；', ':', '：']
    for (let i = 0; i < punctuations.length; i++) {
      if (first === punctuations[i]) {
        return trimmed.substring(1).trimStart()
      }
    }
    return trimmed
  }

  private handleStreamLine(
    apiStyle: ApiStyle,
    line: string,
    onData: (content: string) => void,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string) => void
  ): void {
    const trimmedLine = line.trim()
    if (trimmedLine === '') {
      return
    }
    if (trimmedLine === 'data: [DONE]' || trimmedLine === 'data:[DONE]' || trimmedLine === '[DONE]') {
      return
    }

    let jsonStr: string = ''
    if (trimmedLine.startsWith('data:')) {
      jsonStr = trimmedLine.substring(5).trim()
    } else if (trimmedLine.startsWith('{') || trimmedLine.startsWith('[')) {
      jsonStr = trimmedLine
    } else {
      return
    }

    if (jsonStr === '[DONE]') {
      return
    }

    try {
      const json = JSON.parse(jsonStr) as object
      this.emitStreamContent(apiStyle, json, onData, onReasoningData, onImageData)
    } catch (e) {
      // 记录解析错误以便调试
      console.warn('AIApiService', `JSON parse error for line: ${jsonStr.substring(0, 100)}...`)
    }
  }

  private emitStreamContent(
    apiStyle: ApiStyle,
    json: object,
    onData: (content: string) => void,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string) => void
  ): void {
    if (Array.isArray(json)) {
      const items = json as object[]
      for (let i = 0; i < items.length; i++) {
        const result = this.parseStreamChunk(apiStyle, items[i])
        if (result.content !== '') {
          onData(result.content)
        }
        if (result.reasoningContent !== '' && onReasoningData) {
          onReasoningData(result.reasoningContent)
        }
        if (result.imageData && result.imageMimeType && onImageData) {
          // 使用 try-catch 包装，防止异常阻断流程
          try {
            onImageData(result.imageData, result.imageMimeType)
          } catch (e) {
            console.error('AIApiService', `Error in onImageData callback: ${JSON.stringify(e)}`)
          }
        }
      }
      return
    }

    const result = this.parseStreamChunk(apiStyle, json)
    if (result.content !== '') {
      onData(result.content)
    }
    if (result.reasoningContent !== '' && onReasoningData) {
      onReasoningData(result.reasoningContent)
    }
    if (result.imageData && result.imageMimeType && onImageData) {
      // 使用 try-catch 包装，防止异常阻断流程
      try {
        onImageData(result.imageData, result.imageMimeType)
      } catch (e) {
        console.error('AIApiService', `Error in onImageData callback: ${JSON.stringify(e)}`)
      }
    }
  }
}

// 导出单例实例获取方法
export function getAIApiService(): AIApiService {
  return AIApiService.getInstance()
}
