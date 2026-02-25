import { ApiStyle, ModelInfo } from '../models/ChatModels'

export interface ApiStyleOption {
  style: ApiStyle
  name: string
  description: string
}

export interface ProviderModelGroup {
  name: string
  models: ModelInfo[]
  isExpanded: boolean
}

const BRAND_ORDER: string[] = ['openai', 'claude', 'gemini', 'deepseek', 'other']

export function getDefaultApiStyleOptions(): ApiStyleOption[] {
  return [
    {
      style: ApiStyle.OPENAI,
      name: 'OpenAI',
      description: '兼容 OpenAI API 格式'
    },
    {
      style: ApiStyle.ANTHROPIC,
      name: 'Claude',
      description: 'Anthropic Claude API 格式'
    },
    {
      style: ApiStyle.GOOGLE,
      name: 'Google',
      description: 'Google Gemini API 格式'
    }
  ]
}

export function filterProviderModelsByKeyword(models: ModelInfo[], keyword: string): ModelInfo[] {
  if (keyword.trim() === '') {
    return models
  }
  const lowerKeyword = keyword.toLowerCase()
  const result: ModelInfo[] = []
  for (let i = 0; i < models.length; i++) {
    const model = models[i]
    if (model.name.toLowerCase().includes(lowerKeyword) || model.id.toLowerCase().includes(lowerKeyword)) {
      result.push(model)
    }
  }
  return result
}

export function buildProviderModelGroups(models: ModelInfo[]): ProviderModelGroup[] {
  const groups: Map<string, ModelInfo[]> = new Map()

  for (let i = 0; i < models.length; i++) {
    const model = models[i]
    const brand = getModelBrand(model.id)
    const existing = groups.get(brand)
    if (existing !== undefined) {
      existing.push(model)
    } else {
      groups.set(brand, [model])
    }
  }

  const result: ProviderModelGroup[] = []
  for (let i = 0; i < BRAND_ORDER.length; i++) {
    const brand = BRAND_ORDER[i]
    const brandModels = groups.get(brand)
    if (brandModels !== undefined && brandModels.length > 0) {
      result.push({
        name: getBrandDisplayName(brand),
        models: brandModels,
        isExpanded: true
      })
    }
  }
  return result
}

function getModelBrand(modelId: string): string {
  const id = modelId.toLowerCase()
  if (id.includes('gpt') || id.includes('o1') || id.includes('o3') || id.includes('chatgpt')) {
    return 'openai'
  }
  if (id.includes('claude')) {
    return 'claude'
  }
  if (id.includes('gemini')) {
    return 'gemini'
  }
  if (id.includes('deepseek')) {
    return 'deepseek'
  }
  return 'other'
}

function getBrandDisplayName(brand: string): string {
  if (brand === 'openai') {
    return 'OpenAI'
  }
  if (brand === 'claude') {
    return 'Claude'
  }
  if (brand === 'gemini') {
    return 'Gemini'
  }
  if (brand === 'deepseek') {
    return 'DeepSeek'
  }
  return '其他模型'
}

