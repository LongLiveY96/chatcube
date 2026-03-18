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
  TOGGLE = 'toggle'
}

export enum ReasoningRequestStrategy {
  NONE = 'none',
  OPENAI_REASONING_EFFORT = 'openai_reasoning_effort',
  OPENAI_REASONING_SPLIT = 'openai_reasoning_split',
  ANTHROPIC_THINKING = 'anthropic_thinking',
  ZHIPU_THINKING = 'zhipu_thinking',
  GOOGLE_THINKING_CONFIG = 'google_thinking_config'
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

function isOfficialGoogleProvider(info: CompatibilityProviderInfo): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  return info.providerId === 'gemini' ||
    info.providerId === 'google' ||
    normalizedBaseUrl.includes('generativelanguage.googleapis.com')
}

export function isMiniMaxModelId(modelId: string): boolean {
  const modelLower = modelId.trim().toLowerCase()
  return modelLower.startsWith('abab') || modelLower.startsWith('minimax')
}

function supportsOpenAIReasoningEffortModel(modelId: string): boolean {
  const modelLower = modelId.trim().toLowerCase()
  return modelLower.startsWith('o1') ||
    modelLower.startsWith('o3') ||
    modelLower.startsWith('o4') ||
    modelLower.startsWith('gpt-5')
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
      reasoningControlMode: ReasoningControlMode.TOGGLE,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.ANTHROPIC_THINKING
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
      reasoningControlMode: ReasoningControlMode.TOGGLE,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.OPENAI_REASONING_EFFORT
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

  if (info.apiStyle === ApiStyle.GOOGLE && isOfficialGoogleProvider(info)) {
    return {
      modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
      staticModels: [],
      defaultTestModel: '',
      anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
      anthropicBearerRetryOnAuthFailure: false,
      openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
      preserveAssistantReasoningDetails: false,
      reasoningControlMode: ReasoningControlMode.TOGGLE,
      defaultReasoningRequestStrategy: ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG
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
    case ReasoningRequestStrategy.OPENAI_REASONING_SPLIT:
      return isMiniMaxModelId(modelId)
        ? ReasoningRequestStrategy.OPENAI_REASONING_SPLIT
        : ReasoningRequestStrategy.NONE
    case ReasoningRequestStrategy.ZHIPU_THINKING:
      return supportsZhipuThinkingModel(modelId)
        ? ReasoningRequestStrategy.ZHIPU_THINKING
        : ReasoningRequestStrategy.NONE
    case ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG:
      return supportsGoogleThinkingModel(modelId)
        ? ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG
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
    case ReasoningRequestStrategy.OPENAI_REASONING_SPLIT:
      return ReasoningRequestStrategy.OPENAI_REASONING_SPLIT
    case ReasoningRequestStrategy.ANTHROPIC_THINKING:
      return ReasoningRequestStrategy.ANTHROPIC_THINKING
    case ReasoningRequestStrategy.ZHIPU_THINKING:
      return ReasoningRequestStrategy.ZHIPU_THINKING
    case ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG:
      return ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG
    default:
      return null
  }
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
  if (!modelSupportsReasoning) {
    return false
  }
  const profile = resolveProviderCompatibilityProfile(info)
  if (profile.reasoningControlMode === ReasoningControlMode.NONE) {
    return false
  }
  return resolveReasoningRequestStrategyWithOverride(info, modelId, rawOverride) !== ReasoningRequestStrategy.NONE
}

export function normalizeReasoningLevelForControl(level: ReasoningLevel): ReasoningLevel {
  return level === ReasoningLevel.OFF ? ReasoningLevel.OFF : ReasoningLevel.MEDIUM
}
