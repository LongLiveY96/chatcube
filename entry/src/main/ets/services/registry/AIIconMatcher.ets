/**
 * AI 图标匹配器（移植自 RikkaHub AIIconMatcher）
 * 通过正则匹配模型名称/供应商名称，返回本地 rawfile 图标路径
 */

// ============ 图标匹配规则 ============

interface IconRule {
  pattern: RegExp
  icon: string
}

// 模型图标规则（按优先级排序，先匹配先命中）
const MODEL_ICON_RULES: IconRule[] = [
  { pattern: /gpt|openai|o\d/, icon: 'openai' },
  { pattern: /gemini|nano-banana/, icon: 'google' },
  { pattern: /claude/, icon: 'anthropic' },
  { pattern: /deepseek/, icon: 'deepseek' },
  { pattern: /grok/, icon: 'xai' },
  { pattern: /qwen|qwq|qvq/, icon: 'alibaba' },
  { pattern: /doubao/, icon: 'bytedance' },
  { pattern: /zhipu|glm/, icon: 'zhipu' },
  { pattern: /mistral/, icon: 'mistral' },
  { pattern: /meta\b|(?<!o)llama/, icon: 'meta' },
  { pattern: /hunyuan|tencent/, icon: 'tencent' },
  { pattern: /gemma/, icon: 'google' },
  { pattern: /minimax/, icon: 'minimax' },
  { pattern: /kimi|moonshot/, icon: 'moonshot' },
  { pattern: /step|阶跃/, icon: 'stepfun' },
  { pattern: /intern|书生/, icon: 'internlm' },
  { pattern: /cohere|command-.+/, icon: 'cohere' },
  { pattern: /mimo|xiaomi|小米/, icon: 'xiaomi' },
  { pattern: /nvidia/, icon: 'nvidia' },
  { pattern: /cerebras/, icon: 'cerebras' },
  { pattern: /perplexity/, icon: 'perplexity' },
]

// 供应商图标规则
const PROVIDER_ICON_RULES: IconRule[] = [
  { pattern: /openai/, icon: 'openai' },
  { pattern: /anthropic|claude/, icon: 'anthropic' },
  { pattern: /google|gemini/, icon: 'google' },
  { pattern: /deepseek/, icon: 'deepseek' },
  { pattern: /grok|xai/, icon: 'xai' },
  { pattern: /openrouter/, icon: 'openrouter' },
  { pattern: /silicon|硅基/, icon: 'siliconflow' },
  { pattern: /aihubmix/, icon: 'aihubmix' },
  { pattern: /aliyun|阿里云|百炼|dashscope/, icon: 'alibaba' },
  { pattern: /kimi|moonshot|月之暗面/, icon: 'moonshot' },
  { pattern: /zhipu|智谱/, icon: 'zhipu' },
  { pattern: /bytedance|火山|volcengine|doubao/, icon: 'bytedance' },
  { pattern: /minimax/, icon: 'minimax' },
  { pattern: /ollama/, icon: 'ollama' },
  { pattern: /github/, icon: 'github' },
  { pattern: /cloudflare/, icon: 'cloudflare' },
  { pattern: /mimo|xiaomi|小米/, icon: 'xiaomi' },
  { pattern: /groq/, icon: 'groq' },
  { pattern: /mistral/, icon: 'mistral' },
  { pattern: /ppio|派欧/, icon: 'ppio' },
  { pattern: /nvidia/, icon: 'nvidia' },
]

// ============ 图标缓存 ============

const modelIconCache: Map<string, string> = new Map()
const providerIconCache: Map<string, string> = new Map()

// ============ 公开 API ============

/**
 * 根据模型名称/ID 匹配本地图标路径
 * @returns rawfile 路径（如 'icons/xiaomi.svg'），未匹配返回空字符串
 */
export function matchModelIconPath(modelName: string): string {
  const cached = modelIconCache.get(modelName)
  if (cached !== undefined) {
    return cached
  }

  const lower = modelName.toLowerCase()
  let result = ''
  for (let i = 0; i < MODEL_ICON_RULES.length; i++) {
    if (MODEL_ICON_RULES[i].pattern.test(lower)) {
      result = `icons/${MODEL_ICON_RULES[i].icon}.svg`
      break
    }
  }

  modelIconCache.set(modelName, result)
  return result
}

/**
 * 根据供应商名称/ID 匹配本地图标路径
 * @returns rawfile 路径，未匹配返回空字符串
 */
export function matchProviderIconPath(providerName: string): string {
  const cached = providerIconCache.get(providerName)
  if (cached !== undefined) {
    return cached
  }

  const lower = providerName.toLowerCase()
  let result = ''
  for (let i = 0; i < PROVIDER_ICON_RULES.length; i++) {
    if (PROVIDER_ICON_RULES[i].pattern.test(lower)) {
      result = `icons/${PROVIDER_ICON_RULES[i].icon}.svg`
      break
    }
  }

  providerIconCache.set(providerName, result)
  return result
}
