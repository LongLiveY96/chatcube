// 默认模型配置服务
import { getPreferencesService, PreferencesService, PreferenceKeys } from './PreferencesService'
import { DefaultModelConfig, ModelRole } from '../models/ChatModels'
import { DefaultPrompts } from '../config/DefaultPrompts'
import { getAppSettingsStore, AppSettingsStore } from '../state/AppSettingsStore'

// 默认模型服务 - 单例模式
//
// 本轮重构：
// - 4 个 role 的 DefaultModelConfig（chat / title / translate / search opt）迁到 AppSettingsStore，
//   对外 getModel / setModel 语义不变。loadConfig / initialize 委托 Store 的 ensure 机制。
// - Prompt 相关字段（titlePrompt / translatePrompt / translateTargetLanguage）仍在本服务缓存与落盘，
//   避免单次 commit 扩散到其他订阅端（getTitlePrompt 等在 AITaskService 是高频路径）。
export class DefaultModelService {
  private static instance: DefaultModelService | null = null
  private preferencesService: PreferencesService
  private store: AppSettingsStore

  // 缓存 Prompt 配置
  private titlePrompt: string = ''
  private translatePrompt: string = ''
  private translateTargetLanguage: string = ''
  private promptsLoaded: boolean = false

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

  // 加载所有配置：model 部分走 Store，Prompt 部分走本地
  async loadConfig(): Promise<void> {
    await this.store.ensureDefaultModelsInitialized()
    if (!this.promptsLoaded) {
      await this.loadPrompts()
      this.promptsLoaded = true
    }
  }

  private async loadPrompts(): Promise<void> {
    this.titlePrompt = await this.preferencesService.getString(
      PreferenceKeys.TITLE_PROMPT_TEMPLATE,
      DefaultPrompts.TITLE_PROMPT
    )
    this.translatePrompt = await this.preferencesService.getString(
      PreferenceKeys.TRANSLATE_PROMPT_TEMPLATE,
      DefaultPrompts.TRANSLATE_PROMPT
    )
    this.translateTargetLanguage = await this.preferencesService.getString(
      PreferenceKeys.TRANSLATE_TARGET_LANGUAGE,
      DefaultPrompts.DEFAULT_TARGET_LANGUAGE
    )
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
  // Prompt（仍在本服务内落盘）
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

  // 旧版兼容：自定义 Prompt 场景下的标题生成
  getTitlePrompt(content: string, locale: string): string {
    let prompt = this.titlePrompt
    prompt = prompt.replace('{content}', content)
    prompt = prompt.replace('{locale}', locale)
    return prompt
  }

  getTranslatePrompt(sourceText: string, targetLang: string = ''): string {
    const lang = targetLang !== '' ? targetLang : this.translateTargetLanguage
    let prompt = this.translatePrompt
    prompt = prompt.replace('{source_text}', sourceText)
    prompt = prompt.replace('{target_lang}', lang)
    return prompt
  }

  getTitlePromptTemplate(): string {
    return this.titlePrompt
  }

  getTranslatePromptTemplate(): string {
    return this.translatePrompt
  }

  getTranslateTargetLanguage(): string {
    return this.translateTargetLanguage
  }

  async setTitlePromptTemplate(prompt: string): Promise<void> {
    this.titlePrompt = prompt
    await this.preferencesService.setString(PreferenceKeys.TITLE_PROMPT_TEMPLATE, prompt)
  }

  async setTranslatePromptTemplate(prompt: string): Promise<void> {
    this.translatePrompt = prompt
    await this.preferencesService.setString(PreferenceKeys.TRANSLATE_PROMPT_TEMPLATE, prompt)
  }

  async setTranslateTargetLanguage(language: string): Promise<void> {
    this.translateTargetLanguage = language
    await this.preferencesService.setString(PreferenceKeys.TRANSLATE_TARGET_LANGUAGE, language)
  }

  async resetTitlePrompt(): Promise<void> {
    this.titlePrompt = DefaultPrompts.TITLE_PROMPT
    await this.preferencesService.setString(PreferenceKeys.TITLE_PROMPT_TEMPLATE, DefaultPrompts.TITLE_PROMPT)
  }

  async resetTranslatePrompt(): Promise<void> {
    this.translatePrompt = DefaultPrompts.TRANSLATE_PROMPT
    await this.preferencesService.setString(PreferenceKeys.TRANSLATE_PROMPT_TEMPLATE, DefaultPrompts.TRANSLATE_PROMPT)
  }

  isDefaultTitlePrompt(): boolean {
    return this.titlePrompt === DefaultPrompts.TITLE_PROMPT
  }

  isDefaultTranslatePrompt(): boolean {
    return this.translatePrompt === DefaultPrompts.TRANSLATE_PROMPT
  }
}

// 导出单例实例获取方法
export function getDefaultModelService(): DefaultModelService {
  return DefaultModelService.getInstance()
}
