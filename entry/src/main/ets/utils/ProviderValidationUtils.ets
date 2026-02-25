/**
 * Provider 验证工具函数
 * 提取重复的服务商配置验证逻辑
 */

import { ModelProvider, ProviderType } from '../models/ChatModels'
import { getEffectiveApiKey } from '../config/PresetProviders'

/**
 * Provider 验证结果
 */
export interface ProviderValidationResult {
  isValid: boolean
  errorMessage: string
  effectiveApiKey: string
}

/**
 * 验证 Provider 配置
 * @param provider 服务商配置
 * @returns 验证结果
 */
export function validateProviderConfig(
  provider: ModelProvider | null
): ProviderValidationResult {
  // 检查 provider 是否存在
  if (provider === null) {
    return {
      isValid: false,
      errorMessage: '请先配置 AI 服务商',
      effectiveApiKey: ''
    }
  }

  // 获取有效的 API Key（优先使用用户配置的，否则使用预设的）
  const effectiveApiKey = getEffectiveApiKey(provider.id, provider.apiKey)

  // Ollama 不需要 API Key
  if (effectiveApiKey === '' && provider.type !== ProviderType.OLLAMA) {
    return {
      isValid: false,
      errorMessage: '请先配置 API Key',
      effectiveApiKey: ''
    }
  }

  return {
    isValid: true,
    errorMessage: '',
    effectiveApiKey: effectiveApiKey
  }
}
