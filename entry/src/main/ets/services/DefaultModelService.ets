// 默认模型配置服务
import { getPreferencesService, PreferencesService } from './PreferencesService'
import { DefaultModelConfig, ModelRole } from '../models/ChatModels'
import { DefaultPrompts } from '../config/DefaultPrompts'
import { getAppSettingsStore, AppSettingsStore } from '../state/AppSettingsStore'

// 默认模型服务 - 单例模式
//
// 已迁移到 AppSettingsStore：
// - 4 个 role 的 DefaultModelConfig（chat / title / translate / search opt）
// - 3 个 Prompt 模板字段（title / translate 模板 + translateTargetLanguage）
//
// 本服务目前只剩纯派生（System/User Prompt 格式化）+ facade 委托，
// 方便后续进一步拆解或合并到 Store
export class DefaultModelService {
  private static instance: DefaultModelService | null = null
  private preferencesService: PreferencesService
  private store: AppSettingsStore

  private constructor() {
    this.preferencesService = getPreferencesService()
    this.store = getAppSettingsStore()
  }

  static getInstance(): DefaultModelService {
    if (DefaultModelService.instance === null) {
      DefaultModelService.instance = new DefaultModelService()
    }
    return DefaultModelService.instance
  }

  // 初始化加载配置（幂等）
  async initialize(): Promise<void> {
    await this.loadConfig()
  }

  // 加载所有配置（model + prompt 都走 Store）
  async loadConfig(): Promise<void> {
    await this.store.ensureDefaultModelsInitialized()
    await this.store.ensurePromptsInitialized()
  }

  // ============================================================================
  // Model（委托 Store）
  // ============================================================================

  getModel(role: ModelRole): DefaultModelConfig {
    return this.store.getDefaultModel(role)
  }

  async setModel(role: ModelRole, config: DefaultModelConfig): Promise<void> {
    await this.store.setDefaultModel(role, config)
  }

  // ============================================================================
  // 纯派生 Prompt（不依赖缓存，保留在本服务）
  // ============================================================================

  getTitleSystemPrompt(locale: string): string {
    let prompt = DefaultPrompts.TITLE_SYSTEM_PROMPT
    prompt = prompt.replace('{locale}', locale)
    return prompt
  }

  getTitleUserPrompt(content: string): string {
    let prompt = DefaultPrompts.TITLE_USER_PROMPT
    prompt = prompt.replace('{content}', content)
    return prompt
  }

  // ============================================================================
  // Prompt 模板（委托 Store）
  // ============================================================================

  // 旧版兼容：自定义 Prompt 场景下的标题生成
  getTitlePrompt(content: string, locale: string): string {
    let prompt = this.store.getTitlePromptTemplate()
    prompt = prompt.replace('{content}', content)
    prompt = prompt.replace('{locale}', locale)
    return prompt
  }

  getTranslatePrompt(sourceText: string, targetLang: string = ''): string {
    const lang = targetLang !== '' ? targetLang : this.store.getTranslateTargetLanguage()
    let prompt = this.store.getTranslatePromptTemplate()
    prompt = prompt.replace('{source_text}', sourceText)
    prompt = prompt.replace('{target_lang}', lang)
    return prompt
  }

  getTitlePromptTemplate(): string {
    return this.store.getTitlePromptTemplate()
  }

  getTranslatePromptTemplate(): string {
    return this.store.getTranslatePromptTemplate()
  }

  getTranslateTargetLanguage(): string {
    return this.store.getTranslateTargetLanguage()
  }

  async setTitlePromptTemplate(prompt: string): Promise<void> {
    await this.store.setTitlePromptTemplate(prompt)
  }

  async setTranslatePromptTemplate(prompt: string): Promise<void> {
    await this.store.setTranslatePromptTemplate(prompt)
  }

  async setTranslateTargetLanguage(language: string): Promise<void> {
    await this.store.setTranslateTargetLanguage(language)
  }

  async resetTitlePrompt(): Promise<void> {
    await this.store.resetTitlePromptTemplate()
  }

  async resetTranslatePrompt(): Promise<void> {
    await this.store.resetTranslatePromptTemplate()
  }

  isDefaultTitlePrompt(): boolean {
    return this.store.getTitlePromptTemplate() === DefaultPrompts.TITLE_PROMPT
  }

  isDefaultTranslatePrompt(): boolean {
    return this.store.getTranslatePromptTemplate() === DefaultPrompts.TRANSLATE_PROMPT
  }
}

// 导出单例实例获取方法
export function getDefaultModelService(): DefaultModelService {
  return DefaultModelService.getInstance()
}
