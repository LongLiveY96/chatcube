// AI 任务服务 - 处理标题生成和翻译
import { getAIApiService, AIApiService, AIApiConfig, RequestMessage } from './AIApiService'
import { getDefaultModelService, DefaultModelService } from './DefaultModelService'
import { getProviderViewModel, ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { ModelRole } from '../models/ChatModels'
import { getEffectiveApiKey } from '../config/PresetProviders'

// 翻译/标题生成结果
export interface AITaskResult {
  success: boolean
  content: string
  errorMessage: string
}

// AI 任务服务 - 单例模式
export class AITaskService {
  private static instance: AITaskService | null = null
  private aiApiService: AIApiService
  private defaultModelService: DefaultModelService
  private providerViewModel: ProviderViewModel

  private constructor() {
    this.aiApiService = getAIApiService()
    this.defaultModelService = getDefaultModelService()
    this.providerViewModel = getProviderViewModel()
  }

  static getInstance(): AITaskService {
    if (AITaskService.instance === null) {
      AITaskService.instance = new AITaskService()
    }
    return AITaskService.instance
  }

  // 截断内容用于标题生成（最多500字符/6行）
  private truncateContentForTitle(content: string): string {
    const maxChars = 500
    const maxLines = 6

    // 按行分割
    const lines = content.split('\n')
    let result = ''
    let lineCount = 0

    for (let i = 0; i < lines.length; i++) {
      if (lineCount >= maxLines) {
        break
      }
      const line = lines[i]
      if (result.length + line.length + 1 > maxChars) {
        // 截断当前行
        const remaining = maxChars - result.length
        if (remaining > 0) {
          result += line.substring(0, remaining)
        }
        break
      }
      if (result !== '') {
        result += '\n'
      }
      result += line
      lineCount++
    }

    return result
  }

  // 检测文本语言（简单判断：中文字符占比）
  private detectLanguage(text: string): string {
    const chineseRegex = /[\u4e00-\u9fa5]/g
    const chineseMatches = text.match(chineseRegex)
    const chineseCount = chineseMatches !== null ? chineseMatches.length : 0
    const totalChars = text.replace(/\s/g, '').length

    if (totalChars === 0) {
      return 'Chinese'
    }

    // 中文字符占比超过 30% 认为是中文
    const chineseRatio = chineseCount / totalChars
    return chineseRatio > 0.3 ? 'Chinese' : 'English'
  }

  // 获取标题语言（优先 App 设置，其次自动检测）
  private getTitleLocale(content: string): string {
    // TODO: 未来可以从 AppStateManager 获取 App 语言设置
    // 目前使用自动检测
    return this.detectLanguage(content)
  }

  // 清理标题（去引号、换行、前缀、思考标签）
  private cleanTitle(rawTitle: string): string {
    let title = rawTitle.trim()

    // 去除模型思考标签（Qwen3 等模型的 <think>...</think>）
    title = title.replace(/<think>[\s\S]*?<\/think>/g, '').trim()

    // 去除首尾引号
    title = title.replace(/^["'""'']+|["'""'']+$/g, '')

    // 去除换行，只取第一行有效内容
    const lines = title.split(/[\r\n]+/)
    title = ''
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line !== '') {
        title = line
        break
      }
    }

    // 去除多余空格
    title = title.replace(/\s+/g, ' ')

    // 去除常见前缀
    const prefixes = ['标题：', '标题:', 'Title:', 'Title：', '主题：', '主题:']
    for (let i = 0; i < prefixes.length; i++) {
      if (title.startsWith(prefixes[i])) {
        title = title.substring(prefixes[i].length).trim()
        break
      }
    }

    // 再次去除引号（去前缀后可能暴露出引号）
    title = title.replace(/^["'""'']+|["'""'']+$/g, '')

    return title.trim()
  }

  // 验证标题有效性
  private isValidTitle(title: string): boolean {
    if (title === '') {
      return false
    }
    // 长度检查：4-20 字符
    if (title.length < 4 || title.length > 20) {
      return false
    }
    // 不能全是标点符号
    const punctuationOnly = /^[\s\p{P}]+$/u
    if (punctuationOnly.test(title)) {
      return false
    }
    return true
  }

  // 降级方案：从用户消息提取标题（提取关键词而非原样截取）
  private extractFallbackTitle(content: string, locale: string): string {
    // 提取第一条用户消息
    const lines = content.split('\n')
    let userMessage = ''

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.startsWith('user:') || line.startsWith('USER:')) {
        userMessage = line.substring(5).trim()
        break
      }
    }

    if (userMessage === '') {
      // 如果没有找到 user: 前缀，使用第一行非空内容
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim()
        if (line !== '') {
          userMessage = line
          break
        }
      }
    }

    if (userMessage === '') {
      return ''
    }

    // 去除口语化前缀，提炼核心内容
    let title = userMessage
    const prefixes = [
      '请问', '请帮我', '帮我', '麻烦', '请',
      '我想知道', '我想了解', '我想问',
      '能不能', '可以', '可不可以',
      '怎么', '如何', '为什么', '什么是',
      '帮忙', '告诉我',
      'please ', 'can you ', 'could you ', 'how to ', 'what is ', 'how do '
    ]
    for (let i = 0; i < prefixes.length; i++) {
      const lower = title.toLowerCase()
      if (lower.startsWith(prefixes[i])) {
        title = title.substring(prefixes[i].length).trim()
        break
      }
    }

    // 去除末尾的疑问词和标点
    title = title.replace(/[？?。.！!，,]+$/g, '')
    title = title.replace(/[呢吗呀啊吧嘛]+$/g, '')

    // 截取合适长度
    if (title.length > 20) {
      title = title.substring(0, 17) + '...'
    }

    // 如果清理后太短，使用原始消息截取
    if (title.length < 2) {
      title = userMessage
      if (title.length > 20) {
        title = title.substring(0, 17) + '...'
      }
    }

    return title
  }

  // 生成对话标题
  async generateTitle(conversationContent: string, locale?: string): Promise<string> {
    const titleModel = this.defaultModelService.getModel(ModelRole.TITLE)

    // 获取供应商信息（使用异步方法，确保缓存已加载）
    const provider = await this.providerViewModel.getProviderByIdAsync(titleModel.providerId)

    if (provider === null) {
      console.error('AITaskService', 'Provider not found: ' + titleModel.providerId)
      return this.extractFallbackTitle(conversationContent, locale || 'Chinese')
    }

    // 获取有效的 API Key（优先用户配置，其次预设）
    const effectiveApiKey = getEffectiveApiKey(provider.id, provider.apiKey)
    if (effectiveApiKey === '') {
      console.error('AITaskService', 'No API Key configured for provider: ' + provider.id)
      return this.extractFallbackTitle(conversationContent, locale || 'Chinese')
    }

    // 截断内容
    const truncatedContent = this.truncateContentForTitle(conversationContent)

    // 自动检测语言（如果未指定）
    const effectiveLocale = locale !== undefined && locale !== '' ? locale : this.getTitleLocale(truncatedContent)

    // 构建 API 配置
    const apiConfig: AIApiConfig = {
      providerId: provider.id,
      providerType: provider.type,
      apiStyle: provider.apiStyle,
      apiKey: effectiveApiKey,
      baseUrl: provider.baseUrl
    }

    // 构建 Prompt（使用 system + user 双消息模式）
    const systemPrompt = this.defaultModelService.getTitleSystemPrompt(effectiveLocale)
    const userPrompt = this.defaultModelService.getTitleUserPrompt(truncatedContent)
    const messages: RequestMessage[] = [
      new RequestMessage('system', systemPrompt),
      new RequestMessage('user', userPrompt)
    ]

    try {
      const result = await this.aiApiService.sendChatRequest(
        apiConfig,
        messages,
        titleModel.modelId,
        0.3, // 低温度以获得更稳定的输出
        100  // 标题只需要少量 token
      )

      if (result.success) {
        // 清理标题
        let title = this.cleanTitle(result.content)

        // 限制长度为 20 字符
        if (title.length > 20) {
          title = title.substring(0, 20)
        }

        // 验证标题有效性
        if (this.isValidTitle(title)) {
          return title
        } else {
          console.warn('AITaskService', 'Generated title invalid, using fallback: ' + title)
          return this.extractFallbackTitle(conversationContent, effectiveLocale)
        }
      } else {
        console.error('AITaskService', 'Failed to generate title: ' + result.errorMessage)
        return this.extractFallbackTitle(conversationContent, effectiveLocale)
      }
    } catch (error) {
      console.error('AITaskService', 'Error generating title: ' + JSON.stringify(error))
      return this.extractFallbackTitle(conversationContent, effectiveLocale)
    }
  }

  // 翻译文本
  async translateText(sourceText: string, targetLang: string = ''): Promise<AITaskResult> {
    const translateModel = this.defaultModelService.getModel(ModelRole.TRANSLATE)

    // 获取供应商信息（使用异步方法，确保缓存已加载）
    const provider = await this.providerViewModel.getProviderByIdAsync(translateModel.providerId)

    if (provider === null) {
      console.error('AITaskService', 'Provider not found: ' + translateModel.providerId)
      return { success: false, content: '', errorMessage: '未找到翻译模型对应的服务商' }
    }

    // 获取有效的 API Key（优先用户配置，其次预设）
    const effectiveApiKey = getEffectiveApiKey(provider.id, provider.apiKey)
    if (effectiveApiKey === '') {
      console.error('AITaskService', 'No API Key configured for provider: ' + provider.id)
      return { success: false, content: '', errorMessage: `请为 ${provider.name} 配置 API Key` }
    }

    // 构建 API 配置
    const apiConfig: AIApiConfig = {
      providerId: provider.id,
      providerType: provider.type,
      apiStyle: provider.apiStyle,
      apiKey: effectiveApiKey,
      baseUrl: provider.baseUrl
    }

    // 构建 Prompt
    const prompt = this.defaultModelService.getTranslatePrompt(sourceText, targetLang)
    const messages: RequestMessage[] = [
      new RequestMessage('user', prompt)
    ]

    try {
      const result = await this.aiApiService.sendChatRequest(
        apiConfig,
        messages,
        translateModel.modelId,
        0.3,  // 低温度以获得更准确的翻译
        4096  // 翻译可能需要较多 token
      )

      if (result.success) {
        return { success: true, content: result.content.trim(), errorMessage: '' }
      } else {
        // 检查是否是 401 认证错误
        let errorMessage = result.errorMessage
        if (errorMessage.includes('401') || errorMessage.toLowerCase().includes('unauthorized') || errorMessage.toLowerCase().includes('authentication')) {
          errorMessage = `API Key 认证失败，请检查 ${provider.name} 的 API Key 是否正确`
        }
        console.error('AITaskService', 'Failed to translate: ' + result.errorMessage)
        return { success: false, content: '', errorMessage: errorMessage }
      }
    } catch (error) {
      console.error('AITaskService', 'Error translating: ' + JSON.stringify(error))
      return { success: false, content: '', errorMessage: '翻译失败：' + JSON.stringify(error) }
    }
  }
}

// 导出单例实例获取方法
export function getAITaskService(): AITaskService {
  return AITaskService.getInstance()
}
