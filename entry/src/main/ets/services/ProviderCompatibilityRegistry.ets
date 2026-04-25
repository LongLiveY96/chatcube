import { ApiStyle, ReasoningLevel } from '../models/ChatModels'

export interface CompatibilityProviderInfo {
  providerId: string
  baseUrl: string
  apiStyle: ApiStyle
}

export enum ModelDiscoveryStrategy {
  REMOTE_ENDPOINT = 'remote_endpoint',
  STATIC_CATALOG = 'static_catalog'
}

export enum AnthropicAuthStrategy {
  API_KEY = 'api_key',
  BEARER = 'bearer'
}

export enum OpenAIStreamContentMode {
  INCREMENTAL = 'incremental',
  CUMULATIVE = 'cumulative'
}

export enum ReasoningControlMode {
  NONE = 'none',
  TOGGLE = 'toggle',
  EFFORT = 'effort'
}

export enum ReasoningRequestStrategy {
  NONE = 'none',
  OPENAI_REASONING_EFFORT = 'openai_reasoning_effort',
  OPENAI_COMPAT_REASONING_EFFORT = 'openai_compat_reasoning_effort',
  OPENAI_REASONING_SPLIT = 'openai_reasoning_split',
  OPENROUTER_REASONING = 'openrouter_reasoning',
  ANTHROPIC_THINKING = 'anthropic_thinking',
  DEEPSEEK_THINKING = 'deepseek_thinking',
  ZHIPU_THINKING = 'zhipu_thinking',
  DASHSCOPE_THINKING_BUDGET = 'dashscope_thinking_budget',
  KIMI_THINKING = 'kimi_thinking',
  GOOGLE_THINKING_CONFIG = 'google_thinking_config',
  SILICONFLOW_THINKING_BUDGET = 'siliconflow_thinking_budget'
}

export interface ProviderCompatibilityProfile {
  modelDiscoveryStrategy: ModelDiscoveryStrategy
  staticModels: string[]
  defaultTestModel: string
  anthropicAuthStrategy: AnthropicAuthStrategy
  anthropicBearerRetryOnAuthFailure: boolean
  openAIStreamContentMode: OpenAIStreamContentMode
  preserveAssistantReasoningDetails: boolean
  reasoningControlMode: ReasoningControlMode
  defaultReasoningRequestStrategy: ReasoningRequestStrategy
}

export const MINIMAX_COMPATIBLE_MODELS: string[] = [
  'MiniMax-M2.5',
  'MiniMax-M2.5-highspeed',
  'MiniMax-M2.1',
  'MiniMax-M2.1-highspeed',
  'MiniMax-M2'
]

const DEFAULT_PROFILE: ProviderCompatibilityProfile = {
  modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
  staticModels: [],
  defaultTestModel: '',
  anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
  anthropicBearerRetryOnAuthFailure: false,
  openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
  preserveAssistantReasoningDetails: false,
  reasoningControlMode: ReasoningControlMode.NONE,
  defaultReasoningRequestStrategy: ReasoningRequestStrategy.NONE
}

export function normalizeCompatibilityBaseUrl(baseUrl: string): string {
  let normalized = baseUrl.trim().toLowerCase()
  if (normalized.endsWith('/')) {
    normalized = normalized.slice(0, -1)
  }
  return normalized
}

export function isMiniMaxCompatibleProvider(info: CompatibilityProviderInfo): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  return normalizedBaseUrl.includes('api.minimaxi.com') ||
    normalizedBaseUrl.includes('api.minimax.chat') ||
    normalizedBaseUrl.includes('api.minimax.io') ||
    info.providerId === 'minimax'
}

function isOfficialOpenAIProvider(info: CompatibilityProviderInfo): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  return info.providerId === 'openai' || normalizedBaseUrl.includes('api.openai.com')
}

function isOfficialAnthropicProvider(info: CompatibilityProviderInfo): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  return info.providerId === 'anthropic' || normalizedBaseUrl.includes('api.anthropic.com')
}

function isOfficialZhipuProvider(info: CompatibilityProviderInfo): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  return info.providerId === 'zhipu' || normalizedBaseUrl.includes('open.bigmodel.cn')
}

function isDashScopeProvider(info: CompatibilityProviderInfo): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  return info.providerId === 'qwen' ||
    normalizedBaseUrl.includes('dashscope.aliyuncs.com') ||
    normalizedBaseUrl.includes('dashscope-intl.aliyuncs.com')
}

function isMoonshotProvider(info: CompatibilityProviderInfo): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  return info.providerId === 'moonshot' ||
    info.providerId === 'kimi' ||
    normalizedBaseUrl.includes('api.moonshot.cn') ||
    normalizedBaseUrl.includes('api.moonshot.ai') ||
    normalizedBaseUrl.includes('platform.moonshot')
}

function isOfficialDeepSeekProvider(info: CompatibilityProviderInfo): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  return info.providerId === 'deepseek' || normalizedBaseUrl === 'https://api.deepseek.com/v1' ||
    normalizedBaseUrl === 'https://api.deepseek.com'
}

function isOfficialGoogleProvider(info: CompatibilityProviderInfo): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  return info.providerId === 'gemini' ||
    info.providerId === 'google' ||
    normalizedBaseUrl.includes('generativelanguage.googleapis.com')
}

function isOpenRouterProvider(info: CompatibilityProviderInfo): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  return info.providerId === 'openrouter' || normalizedBaseUrl.includes('openrouter.ai')
}

function isSiliconFlowProvider(info: CompatibilityProviderInfo): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  return info.providerId === 'siliconflow' || normalizedBaseUrl.includes('api.siliconflow.cn')
}

export function isMiniMaxModelId(modelId: string): boolean {
  const modelLower = modelId.trim().toLowerCase()
  return modelLower.startsWith('abab') || modelLower.startsWith('minimax')
}

function isDashScopeThinkingModelId(modelId: string): boolean {
  const modelLower = modelId.trim().toLowerCase()
  return modelLower.startsWith('qwen') ||
    modelLower.startsWith('qwq') ||
    modelLower.startsWith('qvq') ||
    modelLower.includes('/qwen') ||
    modelLower.includes('/qwq') ||
    modelLower.includes('/qvq')
}

function isKimiThinkingModelId(modelId: string): boolean {
  const modelLower = modelId.trim().toLowerCase()
  return modelLower.includes('kimi-k2-thinking') ||
    modelLower.includes('kimi-k2.5')
}

function supportsOpenAIReasoningEffortModel(modelId: string): boolean {
  const modelLower = modelId.trim().toLowerCase()
  return modelLower.startsWith('o1') ||
    modelLower.startsWith('o3') ||
    modelLower.startsWith('o4') ||
    modelLower.startsWith('gpt-5')
}

function supportsOpenAIXhighReasoningModel(modelId: string): boolean {
  const modelLower = modelId.trim().toLowerCase()
  return modelLower.startsWith('gpt-5.4') ||
    modelLower.startsWith('gpt-5.3-codex') ||
    modelLower.startsWith('gpt-5.3-chat-latest') ||
    modelLower.startsWith('gpt-5.2')
}

function supportsZhipuThinkingModel(modelId: string): boolean {
  return modelId.trim().toLowerCase().startsWith('glm')
}

function supportsGoogleThinkingModel(modelId: string): boolean {
  const modelLower = modelId.trim().toLowerCase().replace(/^models\//, '')
  return modelLower.startsWith('gemini-2.5') ||
    modelLower.startsWith('gemini-3') ||
    modelLower.startsWith('gemini-robotics')
}

function supportsSiliconFlowThinkingModel(modelId: string): boolean {
  const modelLower = modelId.trim().toLowerCase()
  return modelLower.startsWith('pro/zai-org/glm-5') ||
    modelLower.startsWith('pro/zai-org/glm-4.7') ||
    modelLower.startsWith('zai-org/glm-4.6') ||
    modelLower.startsWith('zai-org/glm-4.5v') ||
    modelLower.startsWith('deepseek-ai/deepseek-v3.2') ||
    modelLower.startsWith('pro/deepseek-ai/deepseek-v3.2') ||
    modelLower.startsWith('deepseek-ai/deepseek-v3.1-terminus') ||
    modelLower.startsWith('pro/deepseek-ai/deepseek-v3.1-terminus') ||
    modelLower.startsWith('qwen/qwen3') ||
    modelLower === 'tencent/hunyuan-a13b-instruct'
}

export function resolveProviderCompatibilityProfile(info: CompatibilityProviderInfo): ProviderCompatibilityProfile {
  if (isMiniMaxCompatibleProvider(info) && info.apiStyle === ApiStyle.OPENAI) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.STATIC_CATALOG,
      staticModels: MINIMAX_COMPATIBLE_MODELS,
      defaultTestModel: MINIMAX_COMPATIBLE_MODELS[0],
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.CUMULATIVE,
      preserveAssistantReasoningDetails: true,
      reasoningControlMode: ReasoningControlMode.TOGGLE,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.OPENAI_REASONING_SPLIT
    }
  }

  if (isMiniMaxCompatibleProvider(info) && info.apiStyle === ApiStyle.ANTHROPIC) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.STATIC_CATALOG,
      staticModels: MINIMAX_COMPATIBLE_MODELS,
      defaultTestModel: MINIMAX_COMPATIBLE_MODELS[0],
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: true,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.NONE,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.NONE
    }
  }

  if (info.apiStyle === ApiStyle.ANTHROPIC && isOfficialAnthropicProvider(info)) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.EFFORT,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.ANTHROPIC_THINKING
    }
  }

  if (info.apiStyle === ApiStyle.ANTHROPIC) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: true,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.NONE,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.NONE
    }
  }

  if (info.apiStyle === ApiStyle.OPENAI && isOfficialOpenAIProvider(info)) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.EFFORT,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.OPENAI_REASONING_EFFORT
    }
  }

  if (info.apiStyle === ApiStyle.OPENAI && isOfficialDeepSeekProvider(info)) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.TOGGLE,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.DEEPSEEK_THINKING
    }
  }

  if (info.apiStyle === ApiStyle.OPENAI && isOfficialZhipuProvider(info)) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.TOGGLE,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.ZHIPU_THINKING
    }
  }

  if (info.apiStyle === ApiStyle.OPENAI && isDashScopeProvider(info)) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.EFFORT,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.DASHSCOPE_THINKING_BUDGET
    }
  }

  if (info.apiStyle === ApiStyle.OPENAI && isMoonshotProvider(info)) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.TOGGLE,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.KIMI_THINKING
    }
  }

  if (info.apiStyle === ApiStyle.OPENAI && isOpenRouterProvider(info)) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.EFFORT,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.OPENROUTER_REASONING
    }
  }

  if (info.apiStyle === ApiStyle.OPENAI && isSiliconFlowProvider(info)) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.EFFORT,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.SILICONFLOW_THINKING_BUDGET
    }
  }

  if (info.apiStyle === ApiStyle.GOOGLE && isOfficialGoogleProvider(info)) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.EFFORT,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG
    }
  }

  if (info.apiStyle === ApiStyle.OPENAI) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.EFFORT,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT
    }
  }

  return DEFAULT_PROFILE
}

export function resolveReasoningRequestStrategy(
  info: CompatibilityProviderInfo,
  modelId: string
): ReasoningRequestStrategy {
  const profile = resolveProviderCompatibilityProfile(info)
  switch (profile.defaultReasoningRequestStrategy) {
    case ReasoningRequestStrategy.OPENAI_REASONING_EFFORT:
      return supportsOpenAIReasoningEffortModel(modelId)
        ? ReasoningRequestStrategy.OPENAI_REASONING_EFFORT
        : ReasoningRequestStrategy.NONE
    case ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT:
      if (isMiniMaxModelId(modelId)) {
        return ReasoningRequestStrategy.OPENAI_REASONING_SPLIT
      }
      if (isDashScopeThinkingModelId(modelId)) {
        return ReasoningRequestStrategy.DASHSCOPE_THINKING_BUDGET
      }
      if (isKimiThinkingModelId(modelId)) {
        return ReasoningRequestStrategy.KIMI_THINKING
      }
      return ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT
    case ReasoningRequestStrategy.OPENAI_REASONING_SPLIT:
      return isMiniMaxModelId(modelId)
        ? ReasoningRequestStrategy.OPENAI_REASONING_SPLIT
        : ReasoningRequestStrategy.NONE
    case ReasoningRequestStrategy.OPENROUTER_REASONING:
      return ReasoningRequestStrategy.OPENROUTER_REASONING
    case ReasoningRequestStrategy.DEEPSEEK_THINKING:
      return ReasoningRequestStrategy.DEEPSEEK_THINKING
    case ReasoningRequestStrategy.ZHIPU_THINKING:
      return supportsZhipuThinkingModel(modelId)
        ? ReasoningRequestStrategy.ZHIPU_THINKING
        : ReasoningRequestStrategy.NONE
    case ReasoningRequestStrategy.DASHSCOPE_THINKING_BUDGET:
      return ReasoningRequestStrategy.DASHSCOPE_THINKING_BUDGET
    case ReasoningRequestStrategy.KIMI_THINKING:
      return isKimiThinkingModelId(modelId)
        ? ReasoningRequestStrategy.KIMI_THINKING
        : ReasoningRequestStrategy.NONE
    case ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG:
      return supportsGoogleThinkingModel(modelId)
        ? ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG
        : ReasoningRequestStrategy.NONE
    case ReasoningRequestStrategy.SILICONFLOW_THINKING_BUDGET:
      return supportsSiliconFlowThinkingModel(modelId)
        ? ReasoningRequestStrategy.SILICONFLOW_THINKING_BUDGET
        : ReasoningRequestStrategy.NONE
    default:
      return profile.defaultReasoningRequestStrategy
  }
}

function parseReasoningStrategyOverride(rawOverride?: string): ReasoningRequestStrategy | null {
  switch (rawOverride) {
    case ReasoningRequestStrategy.NONE:
      return ReasoningRequestStrategy.NONE
    case ReasoningRequestStrategy.OPENAI_REASONING_EFFORT:
      return ReasoningRequestStrategy.OPENAI_REASONING_EFFORT
    case ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT:
      return ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT
    case ReasoningRequestStrategy.OPENAI_REASONING_SPLIT:
      return ReasoningRequestStrategy.OPENAI_REASONING_SPLIT
    case ReasoningRequestStrategy.OPENROUTER_REASONING:
      return ReasoningRequestStrategy.OPENROUTER_REASONING
    case ReasoningRequestStrategy.ANTHROPIC_THINKING:
      return ReasoningRequestStrategy.ANTHROPIC_THINKING
    case ReasoningRequestStrategy.DEEPSEEK_THINKING:
      return ReasoningRequestStrategy.DEEPSEEK_THINKING
    case ReasoningRequestStrategy.ZHIPU_THINKING:
      return ReasoningRequestStrategy.ZHIPU_THINKING
    case ReasoningRequestStrategy.DASHSCOPE_THINKING_BUDGET:
      return ReasoningRequestStrategy.DASHSCOPE_THINKING_BUDGET
    case ReasoningRequestStrategy.KIMI_THINKING:
      return ReasoningRequestStrategy.KIMI_THINKING
    case ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG:
      return ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG
    case ReasoningRequestStrategy.SILICONFLOW_THINKING_BUDGET:
      return ReasoningRequestStrategy.SILICONFLOW_THINKING_BUDGET
    default:
      return null
  }
}

function getReasoningControlModeForStrategy(strategy: ReasoningRequestStrategy): ReasoningControlMode {
  switch (strategy) {
    case ReasoningRequestStrategy.OPENAI_REASONING_EFFORT:
    case ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT:
    case ReasoningRequestStrategy.OPENROUTER_REASONING:
    case ReasoningRequestStrategy.ANTHROPIC_THINKING:
    case ReasoningRequestStrategy.DASHSCOPE_THINKING_BUDGET:
    case ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG:
    case ReasoningRequestStrategy.SILICONFLOW_THINKING_BUDGET:
      return ReasoningControlMode.EFFORT
    case ReasoningRequestStrategy.OPENAI_REASONING_SPLIT:
    case ReasoningRequestStrategy.DEEPSEEK_THINKING:
    case ReasoningRequestStrategy.ZHIPU_THINKING:
    case ReasoningRequestStrategy.KIMI_THINKING:
      return ReasoningControlMode.TOGGLE
    default:
      return ReasoningControlMode.NONE
  }
}

export function resolveReasoningControlMode(
  info: CompatibilityProviderInfo,
  modelId: string,
  modelSupportsReasoning: boolean,
  rawOverride?: string
): ReasoningControlMode {
  if (!modelSupportsReasoning) {
    return ReasoningControlMode.NONE
  }

  const overrideStrategy = parseReasoningStrategyOverride(rawOverride)
  if (overrideStrategy !== null) {
    return getReasoningControlModeForStrategy(overrideStrategy)
  }

  const profile = resolveProviderCompatibilityProfile(info)
  if (profile.reasoningControlMode === ReasoningControlMode.NONE) {
    return ReasoningControlMode.NONE
  }

  const strategy = resolveReasoningRequestStrategy(info, modelId)
  return getReasoningControlModeForStrategy(strategy)
}

export function resolveReasoningRequestStrategyWithOverride(
  info: CompatibilityProviderInfo,
  modelId: string,
  rawOverride?: string
): ReasoningRequestStrategy {
  const overrideStrategy = parseReasoningStrategyOverride(rawOverride)
  if (overrideStrategy !== null) {
    return overrideStrategy
  }
  return resolveReasoningRequestStrategy(info, modelId)
}

export function supportsReasoningControl(
  info: CompatibilityProviderInfo,
  modelId: string,
  modelSupportsReasoning: boolean,
  rawOverride?: string
): boolean {
  return resolveReasoningControlMode(info, modelId, modelSupportsReasoning, rawOverride) !== ReasoningControlMode.NONE
}

export function supportsReasoningXhighControl(
  info: CompatibilityProviderInfo,
  modelId: string,
  modelSupportsReasoning: boolean,
  rawOverride?: string
): boolean {
  if (resolveReasoningControlMode(info, modelId, modelSupportsReasoning, rawOverride) !== ReasoningControlMode.EFFORT) {
    return false
  }
  const strategy = resolveReasoningRequestStrategyWithOverride(info, modelId, rawOverride)
  if (strategy === ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT) {
    return true
  }
  if (strategy === ReasoningRequestStrategy.OPENAI_REASONING_EFFORT) {
    return supportsOpenAIXhighReasoningModel(modelId)
  }
  return false
}

export function normalizeReasoningLevelForControl(
  level: ReasoningLevel,
  controlMode: ReasoningControlMode = ReasoningControlMode.EFFORT
): ReasoningLevel {
  if (controlMode === ReasoningControlMode.NONE) {
    return ReasoningLevel.OFF
  }
  if (level === ReasoningLevel.OFF) {
    return ReasoningLevel.OFF
  }
  if (controlMode === ReasoningControlMode.TOGGLE) {
    return ReasoningLevel.AUTO
  }
  switch (level) {
    case ReasoningLevel.AUTO:
    case ReasoningLevel.LOW:
    case ReasoningLevel.MEDIUM:
    case ReasoningLevel.HIGH:
    case ReasoningLevel.XHIGH:
    case ReasoningLevel.CUSTOM:
      return level
    default:
      return ReasoningLevel.AUTO
  }
}
