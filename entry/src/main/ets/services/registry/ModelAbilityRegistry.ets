/**
 * 模型能力注册表（移植自 RikkaHub ModelRegistry）
 * 使用 Token 子序列匹配 + 得分竞争识别模型能力
 */

import { tokenize, sequenceMatchWithRegex } from './matcher'
import { ModelMatchSpec } from './types'

// ============ 能力枚举 ============

export enum ModelAbility {
  TOOL = 'tool',
  REASONING = 'reasoning'
}

export enum ModelModality {
  TEXT = 'text',
  IMAGE = 'image'
}

// ============ 内部定义结构 ============

interface AbilityDef {
  match: ModelMatchSpec[]
  abilities: ModelAbility[]
  input: ModelModality[]
  output: ModelModality[]
}

// ============ 评分逻辑 ============

const EXACT_BONUS: number = 1000

function scoreSpec(modelId: string, tokens: string[], spec: ModelMatchSpec): number | null {
  if (spec.exactId !== undefined) {
    return modelId.toLowerCase() === spec.exactId.toLowerCase() ? EXACT_BONUS + tokens.length : null
  }
  if (spec.notTokens !== undefined && spec.notTokens.length > 0) {
    const lowered: string[] = spec.notTokens.map((t) => t.toLowerCase())
    return sequenceMatchWithRegex(tokens, lowered) === null ? 0 : null
  }
  if (spec.tokens !== undefined && spec.tokens.length > 0) {
    const lowered: string[] = spec.tokens.map((t) => t.toLowerCase())
    return sequenceMatchWithRegex(tokens, lowered)
  }
  return null
}

function scoreDef(modelId: string, def: AbilityDef): number | null {
  if (def.match.length === 0) {
    return null
  }
  const tokens = tokenize(modelId)
  let total = 0
  for (let i = 0; i < def.match.length; i++) {
    const s = scoreSpec(modelId, tokens, def.match[i])
    if (s === null) {
      return null
    }
    total += s
  }
  return total
}

// ============ 便捷构造 ============

const T = ModelModality.TEXT
const I = ModelModality.IMAGE
const TOOL = ModelAbility.TOOL
const REASON = ModelAbility.REASONING

function def(match: ModelMatchSpec[], abilities: ModelAbility[], input: ModelModality[] = [T],
  output: ModelModality[] = [T]): AbilityDef {
  return { match, abilities, input, output }
}

// ============ 模型定义（移植自 RikkaHub） ============

const DEFS: AbilityDef[] = [
  // --- OpenAI ---
  def([{ tokens: ['gpt', '4', 'o'] }], [TOOL], [T, I]),
  def([{ tokens: ['gpt', '4', '1'] }], [TOOL], [T, I]),
  def([{ tokens: ['^o$', '^\\d+$'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['gpt', 'oss'] }], [TOOL, REASON]),
  def([{ tokens: ['gpt', '5'] }, { notTokens: ['gpt', '5', '.'] }, { notTokens: ['gpt', '5', 'chat'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['gpt', '5', '1'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['gpt', '5', '2'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['gpt', '5', '3'] }], [TOOL], [T, I]),
  def([{ tokens: ['gpt', '5', '4'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['gpt', '5', '5'] }], [TOOL, REASON], [T, I]),

  // --- Gemini ---
  def([{ tokens: ['gemini', '2', '0', 'flash'] }], [TOOL], [T, I]),
  def([{ tokens: ['gemini', '2', '5', 'flash'] }, { notTokens: ['image'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['gemini', '2', '5', 'pro'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['gemini', '2', '5', 'flash', 'image'] }], [], [T, I], [T, I]),
  def([{ tokens: ['gemini', '3', 'pro', 'image'] }], [], [T, I], [T, I]),
  def([{ tokens: ['gemini', '3', 'pro'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['gemini', '3', 'flash'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['gemini', '3', '1', 'flash', 'image'] }], [REASON], [T, I], [T, I]),
  def([{ tokens: ['gemini', '3', '1', 'pro', 'preview'] }], [TOOL, REASON], [T, I]),
  def([{ exactId: 'gemini-flash-latest' }], [TOOL, REASON], [T, I]),
  def([{ exactId: 'gemini-pro-latest' }], [TOOL, REASON], [T, I]),

  // --- Claude ---
  def([{ tokens: ['claude', '3', '5', 'sonnet'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['claude', '3', '7', 'sonnet'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['claude', '4'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['claude', '4', '5'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['claude', 'sonnet', '4', '6'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['claude', 'opus', '4', '6'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['claude', 'opus', '4', '7'] }], [TOOL, REASON], [T, I]),

  // --- DeepSeek ---
  def([{ tokens: ['deepseek', 'v', '3'] }], [TOOL]),
  def([{ tokens: ['deepseek', 'chat'] }], [TOOL]),
  def([{ tokens: ['deepseek', 'r', '1'] }], [TOOL, REASON]),
  def([{ tokens: ['deepseek', 'reasoner'] }], [TOOL, REASON]),
  def([{ tokens: ['deepseek', 'v', '4', 'flash'] }], [TOOL, REASON]),
  def([{ tokens: ['deepseek', 'v', '4', 'pro'] }], [TOOL, REASON]),
  def([{ tokens: ['deepseek', 'v', '3', '1'] }], [TOOL, REASON]),
  def([{ tokens: ['deepseek', 'v', '3', '2'] }], [TOOL, REASON]),

  // --- Qwen ---
  def([{ tokens: ['qwen', '3'] }], [TOOL, REASON]),
  def([{ tokens: ['qwen', '3', '5'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['qwen', '3', '6'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['qwq'] }], [TOOL, REASON]),
  def([{ tokens: ['qvq'] }], [TOOL, REASON], [T, I]),

  // --- 豆包 ---
  def([{ tokens: ['doubao', '1', '6'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['doubao', '1', '8'] }], [TOOL, REASON], [T, I]),

  // --- Grok ---
  def([{ tokens: ['grok', '4'] }], [TOOL, REASON], [T, I]),

  // --- Kimi ---
  def([{ tokens: ['kimi', 'k', '2'] }], [TOOL, REASON]),
  def([{ tokens: ['kimi', 'k', '2', '5'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['kimi', 'k', '2', '6'] }], [TOOL, REASON], [T, I]),

  // --- Step ---
  def([{ tokens: ['step', '3'] }], [TOOL, REASON], [T, I]),

  // --- InternLM ---
  def([{ tokens: ['intern', 's', '1'] }], [TOOL, REASON], [T, I]),

  // --- GLM ---
  def([{ tokens: ['glm', '4', '5'] }], [TOOL, REASON]),
  def([{ tokens: ['glm', '4', '6'] }], [TOOL, REASON]),
  def([{ tokens: ['glm', '4', '7'] }], [TOOL, REASON]),
  def([{ tokens: ['glm', '5'] }], [TOOL, REASON]),
  def([{ tokens: ['glm', '5', '1'] }], [TOOL, REASON]),

  // --- MiniMax ---
  def([{ tokens: ['minimax', 'm', '2'] }], [TOOL, REASON]),
  def([{ tokens: ['minimax', 'm', '2', '5'] }], [TOOL, REASON]),
  def([{ tokens: ['minimax', 'm', '2', '7'] }], [TOOL, REASON]),

  // --- MiMo ---
  def([{ tokens: ['mimo', 'v', '2'] }], [TOOL, REASON]),
  def([{ tokens: ['mimo', 'v', '2', 'pro'] }], [TOOL, REASON]),
  def([{ tokens: ['mimo', 'v', '2', '5'] }], [TOOL, REASON], [T, I]),
  def([{ tokens: ['mimo', 'v', '2', '5', 'pro'] }], [TOOL, REASON]),
]

// ============ 查询结果 ============

export interface ModelAbilityResult {
  abilities: ModelAbility[]
  inputModalities: ModelModality[]
  outputModalities: ModelModality[]
}

const EMPTY_RESULT: ModelAbilityResult = {
  abilities: [],
  inputModalities: [T],
  outputModalities: [T]
}

// ============ 公开 API ============

export function lookupModelAbilities(modelId: string): ModelAbilityResult {
  let bestScore: number | null = null
  let bestDef: AbilityDef | null = null

  for (let i = 0; i < DEFS.length; i++) {
    const score = scoreDef(modelId, DEFS[i])
    if (score === null) {
      continue
    }
    if (bestScore === null || score > bestScore) {
      bestScore = score
      bestDef = DEFS[i]
    }
  }

  if (bestDef === null) {
    return EMPTY_RESULT
  }
  return {
    abilities: bestDef.abilities,
    inputModalities: bestDef.input,
    outputModalities: bestDef.output
  }
}

export function modelSupportsTools(modelId: string): boolean {
  return lookupModelAbilities(modelId).abilities.includes(ModelAbility.TOOL)
}

export function modelSupportsReasoning(modelId: string): boolean {
  return lookupModelAbilities(modelId).abilities.includes(ModelAbility.REASONING)
}

export function modelSupportsVision(modelId: string): boolean {
  return lookupModelAbilities(modelId).inputModalities.includes(ModelModality.IMAGE)
}

export function modelSupportsImageOutput(modelId: string): boolean {
  return lookupModelAbilities(modelId).outputModalities.includes(ModelModality.IMAGE)
}
