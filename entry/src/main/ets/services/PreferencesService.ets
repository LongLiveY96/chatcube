import { preferences } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { AppError, AppErrorCode, toErrorDetail } from '../models/AppError'

// 偏好设置键名常量
export class PreferenceKeys {
  static readonly CURRENT_MODEL_ID: string = 'current_model_id'
  static readonly CURRENT_MODEL_NAME: string = 'current_model_name'
  static readonly CURRENT_PROVIDER_ID: string = 'current_provider_id'
  static readonly DEFAULT_TEMPERATURE: string = 'default_temperature'
  static readonly DEFAULT_MAX_TOKENS: string = 'default_max_tokens'
  static readonly THEME_MODE: string = 'theme_mode'
  static readonly LANGUAGE: string = 'language'
  static readonly PROVIDERS_CONFIG: string = 'providers_config'

  // 默认模型配置
  static readonly DEFAULT_CHAT_MODEL_ID: string = 'default_chat_model_id'
  static readonly DEFAULT_CHAT_PROVIDER_ID: string = 'default_chat_provider_id'
  static readonly DEFAULT_CHAT_MODEL_NAME: string = 'default_chat_model_name'
  static readonly DEFAULT_CHAT_PROVIDER_NAME: string = 'default_chat_provider_name'
  static readonly DEFAULT_TITLE_MODEL_ID: string = 'default_title_model_id'
  static readonly DEFAULT_TITLE_PROVIDER_ID: string = 'default_title_provider_id'
  static readonly DEFAULT_TITLE_MODEL_NAME: string = 'default_title_model_name'
  static readonly DEFAULT_TITLE_PROVIDER_NAME: string = 'default_title_provider_name'
  static readonly DEFAULT_TRANSLATE_MODEL_ID: string = 'default_translate_model_id'
  static readonly DEFAULT_TRANSLATE_PROVIDER_ID: string = 'default_translate_provider_id'
  static readonly DEFAULT_TRANSLATE_MODEL_NAME: string = 'default_translate_model_name'
  static readonly DEFAULT_TRANSLATE_PROVIDER_NAME: string = 'default_translate_provider_name'
  static readonly DEFAULT_SEARCH_OPTIMIZATION_MODEL_ID: string = 'default_search_optimization_model_id'
  static readonly DEFAULT_SEARCH_OPTIMIZATION_PROVIDER_ID: string = 'default_search_optimization_provider_id'
  static readonly DEFAULT_SEARCH_OPTIMIZATION_MODEL_NAME: string = 'default_search_optimization_model_name'
  static readonly DEFAULT_SEARCH_OPTIMIZATION_PROVIDER_NAME: string = 'default_search_optimization_provider_name'

  // Prompt 配置
  static readonly TITLE_PROMPT_TEMPLATE: string = 'title_prompt_template'
  static readonly TRANSLATE_PROMPT_TEMPLATE: string = 'translate_prompt_template'
  static readonly TRANSLATE_TARGET_LANGUAGE: string = 'translate_target_language'
  static readonly CUSTOM_SYSTEM_PROMPT: string = 'custom_system_prompt'

  // 搜索服务配置
  static readonly SEARCH_SERVICE_ENABLED: string = 'search_service_enabled'
  static readonly SEARCH_CONVERSATION_ENABLED: string = 'search_conversation_enabled'
  static readonly WEATHER_QUERY_ENABLED: string = 'weather_query_enabled'
  static readonly SEARCH_ENGINE: string = 'search_engine'
  static readonly SEARCH_MAX_RESULTS: string = 'search_max_results'
  static readonly SEARCH_TIMEOUT: string = 'search_timeout'
  static readonly SEARCH_AUTO_TEST: string = 'search_auto_test'
  static readonly SEARCH_QUERY_OPTIMIZATION_ENABLED: string = 'search_query_optimization_enabled'
  static readonly SEARCH_EXA_API_KEY: string = 'search_exa_api_key'
  static readonly SEARCH_EXA_BASE_URL: string = 'search_exa_base_url'

  // 华为官方智能体入口配置
  static readonly HUAWEI_AGENT_ENTRIES: string = 'huawei_agent_entries'
  static readonly HUAWEI_AGENT_FEATURE_FLAG: string = 'huawei_agent_feature_flag'

  // 主题配色
  static readonly COLOR_THEME: string = 'color_theme'

  // 通知配置
  static readonly NOTIFY_ENABLED: string = 'notify_enabled'
  static readonly NOTIFY_ON_COMPLETE: string = 'notify_on_complete'
  static readonly NOTIFY_ON_FAILED: string = 'notify_on_failed'

  // 握姿自适应配置
  static readonly HAND_ADAPTIVE_ENABLED: string = 'hand_adaptive_enabled'
  static readonly HAND_ADAPTIVE_NEW_CHAT: string = 'hand_adaptive_new_chat'

  // models.dev 能力匹配配置
  static readonly MODELS_DEV_BASE_URL: string = 'models_dev_base_url'
  static readonly MODELS_DEV_ENABLED: string = 'models_dev_enabled'
  static readonly MODEL_LOGO_INDEX_JSON: string = 'model_logo_index_json'
}

// 主题模式枚举
export enum ThemeMode {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

// 语言枚举
export enum AppLanguage {
  SYSTEM = 'system',
  ZH_CN = 'zh-CN',
  EN_US = 'en-US'
}

// 偏好设置服务 - 单例模式
export class PreferencesService {
  private static instance: PreferencesService | null = null
  private dataPreferences: preferences.Preferences | null = null
  private readonly PREFERENCES_NAME: string = 'chatbox_preferences'
  private isInitialized: boolean = false

  private constructor() {
  }

  static getInstance(): PreferencesService {
    if (PreferencesService.instance === null) {
      PreferencesService.instance = new PreferencesService()
    }
    return PreferencesService.instance
  }

  async initialize(context: Context): Promise<void> {
    if (this.isInitialized) {
      return
    }
    try {
      // 获取偏好设置实例
      this.dataPreferences = await preferences.getPreferences(context, this.PREFERENCES_NAME)
      // 标记为已初始化
      this.isInitialized = true
    } catch (error) {
      // 捕获并记录初始化错误
      console.error('PreferencesService', `Failed to initialize preferences: ${JSON.stringify(error)}`)
      throw new AppError(
        AppErrorCode.PREFERENCES_INIT_FAILED,
        '偏好设置初始化失败',
        toErrorDetail(error as Object),
        false
      )
    }
  }

  // 获取字符串值
  async getString(key: string, defaultValue: string = ''): Promise<string> {
    if (this.dataPreferences === null) {
      return defaultValue
    }
    try {
      const value = await this.dataPreferences.get(key, defaultValue)
      return value as string
    } catch (error) {
      console.error('PreferencesService', `Failed to get string: ${JSON.stringify(error)}`)
      return defaultValue
    }
  }

  // 设置字符串值
  async setString(key: string, value: string): Promise<void> {
    if (this.dataPreferences === null) {
      return
    }
    try {
      await this.dataPreferences.put(key, value)
      await this.dataPreferences.flush()
    } catch (error) {
      console.error('PreferencesService', `Failed to set string: ${JSON.stringify(error)}`)
    }
  }

  // 获取数值
  async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    if (this.dataPreferences === null) {
      return defaultValue
    }
    try {
      const value = await this.dataPreferences.get(key, defaultValue)
      return value as number
    } catch (error) {
      console.error('PreferencesService', `Failed to get number: ${JSON.stringify(error)}`)
      return defaultValue
    }
  }

  // 设置数值
  async setNumber(key: string, value: number): Promise<void> {
    if (this.dataPreferences === null) {
      return
    }
    try {
      await this.dataPreferences.put(key, value)
      await this.dataPreferences.flush()
    } catch (error) {
      console.error('PreferencesService', `Failed to set number: ${JSON.stringify(error)}`)
    }
  }

  // 获取布尔值
  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    if (this.dataPreferences === null) {
      return defaultValue
    }
    try {
      const value = await this.dataPreferences.get(key, defaultValue)
      return value as boolean
    } catch (error) {
      console.error('PreferencesService', `Failed to get boolean: ${JSON.stringify(error)}`)
      return defaultValue
    }
  }

  // 设置布尔值
  async setBoolean(key: string, value: boolean): Promise<void> {
    if (this.dataPreferences === null) {
      return
    }
    try {
      await this.dataPreferences.put(key, value)
      await this.dataPreferences.flush()
    } catch (error) {
      console.error('PreferencesService', `Failed to set boolean: ${JSON.stringify(error)}`)
    }
  }

  // 删除键值
  async remove(key: string): Promise<void> {
    if (this.dataPreferences === null) {
      return
    }
    try {
      await this.dataPreferences.delete(key)
      await this.dataPreferences.flush()
    } catch (error) {
      console.error('PreferencesService', `Failed to remove key: ${JSON.stringify(error)}`)
    }
  }

  // 检查键是否存在
  async has(key: string): Promise<boolean> {
    if (this.dataPreferences === null) {
      return false
    }
    try {
      return await this.dataPreferences.has(key)
    } catch (error) {
      console.error('PreferencesService', `Failed to check key: ${JSON.stringify(error)}`)
      return false
    }
  }

  // 获取所有键值对
  async getAll(): Promise<Map<string, preferences.ValueType>> {
    const result = new Map<string, preferences.ValueType>()
    if (this.dataPreferences === null) {
      return result
    }
    try {
      const allData = await this.dataPreferences.getAll()
      const keys = Object.keys(allData)
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i]
        // 使用 get 方法逐个读取，避免索引访问
        const value = await this.dataPreferences.get(key, '')
        result.set(key, value)
      }
    } catch (error) {
      console.error('PreferencesService', `Failed to get all preferences: ${JSON.stringify(error)}`)
    }
    return result
  }

  // 设置任意类型值（批量导入用）
  async putValue(key: string, value: preferences.ValueType): Promise<void> {
    if (this.dataPreferences === null) {
      return
    }
    try {
      await this.dataPreferences.put(key, value)
      await this.dataPreferences.flush()
    } catch (error) {
      console.error('PreferencesService', `Failed to put value: ${JSON.stringify(error)}`)
    }
  }

  // 清空所有数据
  async clear(): Promise<void> {
    if (this.dataPreferences === null) {
      return
    }
    try {
      await this.dataPreferences.clear()
      await this.dataPreferences.flush()
    } catch (error) {
      console.error('PreferencesService', `Failed to clear preferences: ${JSON.stringify(error)}`)
    }
  }

  // ============ 便捷方法 ============

  // 获取当前选中的模型ID
  async getCurrentModelId(): Promise<string> {
    return await this.getString(PreferenceKeys.CURRENT_MODEL_ID, '')
  }

  // 设置当前选中的模型ID
  async setCurrentModelId(modelId: string): Promise<void> {
    await this.setString(PreferenceKeys.CURRENT_MODEL_ID, modelId)
  }

  // 获取当前选中的模型名称
  async getCurrentModelName(): Promise<string> {
    return await this.getString(PreferenceKeys.CURRENT_MODEL_NAME, '')
  }

  // 设置当前选中的模型名称
  async setCurrentModelName(modelName: string): Promise<void> {
    await this.setString(PreferenceKeys.CURRENT_MODEL_NAME, modelName)
  }

  // 获取当前选中的服务商ID
  async getCurrentProviderId(): Promise<string> {
    return await this.getString(PreferenceKeys.CURRENT_PROVIDER_ID, '')
  }

  // 设置当前选中的服务商ID
  async setCurrentProviderId(providerId: string): Promise<void> {
    await this.setString(PreferenceKeys.CURRENT_PROVIDER_ID, providerId)
  }

  // 获取默认温度
  async getDefaultTemperature(): Promise<number> {
    return await this.getNumber(PreferenceKeys.DEFAULT_TEMPERATURE, 0.7)
  }

  // 设置默认温度
  async setDefaultTemperature(temperature: number): Promise<void> {
    await this.setNumber(PreferenceKeys.DEFAULT_TEMPERATURE, temperature)
  }

  // 获取默认最大token数
  async getDefaultMaxTokens(): Promise<number> {
    return await this.getNumber(PreferenceKeys.DEFAULT_MAX_TOKENS, 4096)
  }

  // 设置默认最大token数
  async setDefaultMaxTokens(maxTokens: number): Promise<void> {
    await this.setNumber(PreferenceKeys.DEFAULT_MAX_TOKENS, maxTokens)
  }

  // 获取主题模式
  async getThemeMode(): Promise<ThemeMode> {
    const mode = await this.getString(PreferenceKeys.THEME_MODE, ThemeMode.SYSTEM)
    return mode as ThemeMode
  }

  // 设置主题模式
  async setThemeMode(mode: ThemeMode): Promise<void> {
    await this.setString(PreferenceKeys.THEME_MODE, mode)
  }

  // 获取语言设置
  async getLanguage(): Promise<AppLanguage> {
    const lang = await this.getString(PreferenceKeys.LANGUAGE, AppLanguage.SYSTEM)
    return lang as AppLanguage
  }

  // 设置语言
  async setLanguage(lang: AppLanguage): Promise<void> {
    await this.setString(PreferenceKeys.LANGUAGE, lang)
  }

  // 获取通知总开关
  async getNotifyEnabled(): Promise<boolean> {
    return await this.getBoolean(PreferenceKeys.NOTIFY_ENABLED, true)
  }

  // 设置通知总开关
  async setNotifyEnabled(enabled: boolean): Promise<void> {
    await this.setBoolean(PreferenceKeys.NOTIFY_ENABLED, enabled)
  }

  // 获取“完成时通知”开关
  async getNotifyOnComplete(): Promise<boolean> {
    return await this.getBoolean(PreferenceKeys.NOTIFY_ON_COMPLETE, true)
  }

  // 设置“完成时通知”开关
  async setNotifyOnComplete(enabled: boolean): Promise<void> {
    await this.setBoolean(PreferenceKeys.NOTIFY_ON_COMPLETE, enabled)
  }

  // 获取“失败时通知”开关
  async getNotifyOnFailed(): Promise<boolean> {
    return await this.getBoolean(PreferenceKeys.NOTIFY_ON_FAILED, true)
  }

  // 设置“失败时通知”开关
  async setNotifyOnFailed(enabled: boolean): Promise<void> {
    await this.setBoolean(PreferenceKeys.NOTIFY_ON_FAILED, enabled)
  }
}

// 导出单例实例获取方法
export function getPreferencesService(): PreferencesService {
  return PreferencesService.getInstance()
}
