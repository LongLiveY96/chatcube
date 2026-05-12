import {
  CompatibilityProviderInfo,
  ProviderMatchSpec,
  ProviderProfileDef,
  ProviderProfileFallback,
  ModelMatchSpec,
  ModelProfileDef
} from './types'

// 规范化 baseUrl:去尾斜杠 + 小写,跟旧 ProviderCompatibilityRegistry 行为完全等价
export function normalizeCompatibilityBaseUrl(baseUrl: string): string {
  let normalized = baseUrl.trim().toLowerCase()
  if (normalized.endsWith('/')) {
    normalized = normalized.slice(0, -1)
  }
  return normalized
}

// ============ Provider 匹配 ============

function matchProviderSpec(info: CompatibilityProviderInfo, spec: ProviderMatchSpec): boolean {
  const normalizedBaseUrl = normalizeCompatibilityBaseUrl(info.baseUrl)
  if (spec.providerIds !== undefined) {
    for (let i = 0; i < spec.providerIds.length; i++) {
      if (info.providerId === spec.providerIds[i]) {
        return true
      }
    }
  }
  if (spec.baseUrlIncludesAny !== undefined) {
    for (let i = 0; i < spec.baseUrlIncludesAny.length; i++) {
      if (normalizedBaseUrl.includes(spec.baseUrlIncludesAny[i])) {
        return true
      }
    }
  }
  if (spec.baseUrlEqualsAny !== undefined) {
    for (let i = 0; i < spec.baseUrlEqualsAny.length; i++) {
      if (normalizedBaseUrl === spec.baseUrlEqualsAny[i]) {
        return true
      }
    }
  }
  return false
}

// 在 def 列表中找到第一个 apiStyle + match 同时命中的;失败则在 fallback 列表里找 apiStyle 命中的;再失败返回 null
export function lookupProviderProfile(
  info: CompatibilityProviderInfo,
  defs: ProviderProfileDef[],
  fallbacks: ProviderProfileFallback[]
): ProviderProfileDef | ProviderProfileFallback | null {
  for (let i = 0; i < defs.length; i++) {
    const def = defs[i]
    if (def.apiStyle !== info.apiStyle) {
      continue
    }
    if (matchProviderSpec(info, def.match)) {
      return def
    }
  }
  for (let i = 0; i < fallbacks.length; i++) {
    if (fallbacks[i].apiStyle === info.apiStyle) {
      return fallbacks[i]
    }
  }
  return null
}

// ============ Model id 分词 + 评分(rikkahub ModelDsl 思路移植) ============

function isLowerLetter(code: number): boolean {
  return code >= 97 && code <= 122 // a-z
}

function isDigit(code: number): boolean {
  return code >= 48 && code <= 57 // 0-9
}

export function tokenize(modelId: string): string[] {
  const tokens: string[] = []
  const input = modelId.toLowerCase()
  let i = 0
  while (i < input.length) {
    const code = input.charCodeAt(i)
    if (isLowerLetter(code)) {
      const start = i
      i++
      while (i < input.length && isLowerLetter(input.charCodeAt(i))) {
        i++
      }
      tokens.push(input.substring(start, i))
    } else if (isDigit(code)) {
      const start = i
      i++
      while (i < input.length && isDigit(input.charCodeAt(i))) {
        i++
      }
      tokens.push(input.substring(start, i))
    } else {
      tokens.push(input.charAt(i))
      i++
    }
  }
  return tokens
}

// 顺序子序列匹配:tokens 中按顺序包含 specTokens 即视为命中,得分等于 specTokens.length
function sequenceMatchLength(modelTokens: string[], specTokens: string[]): number | null {
  if (specTokens.length === 0) {
    return null
  }
  let si = 0
  for (let i = 0; i < modelTokens.length; i++) {
    if (modelTokens[i] === specTokens[si]) {
      si++
      if (si === specTokens.length) {
        return specTokens.length
      }
    }
  }
  return null
}

// 判断 token spec 是否为正则模式（以 ^ 开头或 $ 结尾）
function isRegexSpec(spec: string): boolean {
  return spec.startsWith('^') || spec.endsWith('$')
}

// 支持正则 token 的子序列匹配（用于 ModelAbilityRegistry）
export function sequenceMatchWithRegex(modelTokens: string[], specTokens: string[]): number | null {
  if (specTokens.length === 0) {
    return null
  }
  let si = 0
  for (let i = 0; i < modelTokens.length; i++) {
    const spec = specTokens[si]
    let matched = false
    if (isRegexSpec(spec)) {
      const regex = new RegExp(spec, 'i')
      matched = regex.test(modelTokens[i])
    } else {
      matched = modelTokens[i] === spec
    }
    if (matched) {
      si++
      if (si === specTokens.length) {
        return specTokens.length
      }
    }
  }
  return null
}

const EXACT_ID_BONUS: number = 1000

function scoreModelMatchSpec(modelId: string, modelTokens: string[], spec: ModelMatchSpec): number | null {
  if (spec.exactId !== undefined) {
    if (modelId.toLowerCase() === spec.exactId.toLowerCase()) {
      return EXACT_ID_BONUS + modelTokens.length
    }
    return null
  }
  if (spec.startsWith !== undefined && spec.startsWith.length > 0) {
    const lowered = modelId.toLowerCase()
    const prefix = spec.startsWith.toLowerCase()
    return lowered.startsWith(prefix) ? prefix.length : null
  }
  if (spec.tokens !== undefined && spec.tokens.length > 0) {
    const lowered: string[] = []
    for (let i = 0; i < spec.tokens.length; i++) {
      lowered.push(spec.tokens[i].toLowerCase())
    }
    return sequenceMatchLength(modelTokens, lowered)
  }
  if (spec.notTokens !== undefined && spec.notTokens.length > 0) {
    const lowered: string[] = []
    for (let i = 0; i < spec.notTokens.length; i++) {
      lowered.push(spec.notTokens[i].toLowerCase())
    }
    return sequenceMatchLength(modelTokens, lowered) === null ? 0 : null
  }
  return null
}

export function scoreModelDef(modelId: string, def: ModelProfileDef): number | null {
  if (def.match.length === 0) {
    return null
  }
  const modelTokens = tokenize(modelId)
  let total = 0
  for (let i = 0; i < def.match.length; i++) {
    const score = scoreModelMatchSpec(modelId, modelTokens, def.match[i])
    if (score === null) {
      return null
    }
    total += score
  }
  return total
}

// 在 def 列表中找最高分(并列时取首个),无命中返回 null
export function lookupBestModelDef(modelId: string, defs: ModelProfileDef[]): ModelProfileDef | null {
  let bestScore: number | null = null
  let bestDef: ModelProfileDef | null = null
  for (let i = 0; i < defs.length; i++) {
    const def = defs[i]
    const score = scoreModelDef(modelId, def)
    if (score === null) {
      continue
    }
    if (bestScore === null || score > bestScore) {
      bestScore = score
      bestDef = def
    }
  }
  return bestDef
}
