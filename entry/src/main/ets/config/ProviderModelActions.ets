import { ModelInfo } from '../models/ChatModels'
import { ProviderModelGroup } from './ProviderDetailShared'

// 将全部模型设置为同一启用状态，并返回新数组引用（触发 @State 刷新）
export function setAllModelsEnabled(models: ModelInfo[], enabled: boolean): ModelInfo[] {
  const newModels: ModelInfo[] = []
  for (let i = 0; i < models.length; i++) {
    const model = models[i]
    model.isEnabled = enabled
    newModels.push(model)
  }
  return newModels
}

// 设置分组内全部模型的启用状态
export function setGroupModelsEnabled(group: ProviderModelGroup, enabled: boolean): void {
  for (let i = 0; i < group.models.length; i++) {
    group.models[i].isEnabled = enabled
  }
}

// 判断全部模型是否都启用
export function isAllModelsEnabled(models: ModelInfo[]): boolean {
  if (models.length === 0) {
    return false
  }
  for (let i = 0; i < models.length; i++) {
    if (!models[i].isEnabled) {
      return false
    }
  }
  return true
}

// 判断分组模型是否全部启用
export function isGroupAllEnabled(group: ProviderModelGroup): boolean {
  for (let i = 0; i < group.models.length; i++) {
    if (!group.models[i].isEnabled) {
      return false
    }
  }
  return true
}

// 统计分组内已启用数量（用于构建稳定 key）
export function getGroupEnabledCount(group: ProviderModelGroup): number {
  let count = 0
  for (let i = 0; i < group.models.length; i++) {
    if (group.models[i].isEnabled) {
      count++
    }
  }
  return count
}

// 过滤删除指定模型
export function removeModelById(models: ModelInfo[], modelId: string): ModelInfo[] {
  const newModels: ModelInfo[] = []
  for (let i = 0; i < models.length; i++) {
    if (models[i].id !== modelId) {
      newModels.push(models[i])
    }
  }
  return newModels
}

// 根据已选模型 ID 构建新模型列表，并尽可能保留历史配置
export function buildSelectedModelsWithPreservedConfig(existingModels: ModelInfo[], selectedIds: string[]): ModelInfo[] {
  const existingConfigMap = new Map<string, ModelInfo>()
  for (let i = 0; i < existingModels.length; i++) {
    const model = existingModels[i]
    existingConfigMap.set(model.id, model)
  }

  const newModels: ModelInfo[] = []
  for (let i = 0; i < selectedIds.length; i++) {
    const modelId = selectedIds[i]
    const existingModel = existingConfigMap.get(modelId)
    if (existingModel !== undefined) {
      newModels.push(existingModel)
    } else {
      newModels.push(new ModelInfo(modelId, modelId, 4096, true, false))
    }
  }
  return newModels
}

