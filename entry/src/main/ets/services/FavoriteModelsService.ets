/**
 * 收藏模型服务
 * 管理用户收藏的模型列表，支持持久化存储
 */

import { PreferencesService, getPreferencesService } from './PreferencesService'

// 收藏模型记录
export interface FavoriteModel {
  modelId: string
  providerId: string
  modelName: string
  providerName: string
  addedAt: number // 收藏时间戳
}

// 存储键名
const FAVORITE_MODELS_KEY = 'favorite_models'

/**
 * 收藏模型服务 - 单例模式
 */
export class FavoriteModelsService {
  private static instance: FavoriteModelsService | null = null
  private preferencesService: PreferencesService
  private favoriteModels: FavoriteModel[] = []
  private isLoaded: boolean = false

  private constructor() {
    this.preferencesService = getPreferencesService()
  }

  static getInstance(): FavoriteModelsService {
    if (FavoriteModelsService.instance === null) {
      FavoriteModelsService.instance = new FavoriteModelsService()
    }
    return FavoriteModelsService.instance
  }

  /**
   * 加载收藏列表
   */
  async load(): Promise<void> {
    if (this.isLoaded) {
      return
    }
    try {
      const jsonStr = await this.preferencesService.getString(FAVORITE_MODELS_KEY, '[]')
      const parsed = JSON.parse(jsonStr) as FavoriteModel[]
      this.favoriteModels = parsed
      this.isLoaded = true
    } catch (error) {
      console.error('FavoriteModelsService', `Failed to load favorites: ${JSON.stringify(error)}`)
      this.favoriteModels = []
      this.isLoaded = true
    }
  }

  /**
   * 保存收藏列表到持久化存储
   */
  private async save(): Promise<void> {
    try {
      const jsonStr = JSON.stringify(this.favoriteModels)
      await this.preferencesService.setString(FAVORITE_MODELS_KEY, jsonStr)
    } catch (error) {
      console.error('FavoriteModelsService', `Failed to save favorites: ${JSON.stringify(error)}`)
    }
  }

  /**
   * 添加收藏
   * @param modelId 模型 ID
   * @param providerId 供应商 ID
   * @param modelName 模型名称
   * @param providerName 供应商名称
   */
  async addFavorite(modelId: string, providerId: string, modelName: string, providerName: string): Promise<void> {
    // 检查是否已收藏（需要同时匹配 modelId 和 providerId）
    if (this.isFavorite(modelId, providerId)) {
      return
    }

    const favorite: FavoriteModel = {
      modelId: modelId,
      providerId: providerId,
      modelName: modelName,
      providerName: providerName,
      addedAt: Date.now()
    }

    this.favoriteModels.unshift(favorite) // 新收藏放在前面
    await this.save()
  }

  /**
   * 移除收藏
   * @param modelId 模型 ID
   * @param providerId 供应商 ID
   */
  async removeFavorite(modelId: string, providerId: string): Promise<void> {
    const index = this.favoriteModels.findIndex(f => f.modelId === modelId && f.providerId === providerId)
    if (index >= 0) {
      this.favoriteModels.splice(index, 1)
      await this.save()
    }
  }

  /**
   * 切换收藏状态
   * @param modelId 模型 ID
   * @param providerId 供应商 ID
   * @param modelName 模型名称
   * @param providerName 供应商名称
   * @returns 新的收藏状态
   */
  async toggleFavorite(modelId: string, providerId: string, modelName: string, providerName: string): Promise<boolean> {
    if (this.isFavorite(modelId, providerId)) {
      await this.removeFavorite(modelId, providerId)
      return false
    } else {
      await this.addFavorite(modelId, providerId, modelName, providerName)
      return true
    }
  }

  /**
   * 检查是否已收藏
   * @param modelId 模型 ID
   * @param providerId 供应商 ID（可选，兼容旧调用）
   * @returns 是否已收藏
   */
  isFavorite(modelId: string, providerId?: string): boolean {
    if (providerId !== undefined) {
      // 精确匹配：同时匹配 modelId 和 providerId
      return this.favoriteModels.some(f => f.modelId === modelId && f.providerId === providerId)
    }
    // 兼容旧调用：仅按 modelId 匹配（用于向后兼容）
    return this.favoriteModels.some(f => f.modelId === modelId)
  }

  /**
   * 获取所有收藏的模型
   * @returns 收藏模型列表
   */
  getFavorites(): FavoriteModel[] {
    return this.favoriteModels.slice() // 返回副本
  }

  /**
   * 获取收藏模型的 ID 列表
   * @returns 模型 ID 列表
   */
  getFavoriteIds(): string[] {
    return this.favoriteModels.map(f => f.modelId)
  }

  /**
   * 获取收藏模型的复合键列表（providerId::modelId 格式）
   * @returns 复合键列表
   */
  getFavoriteKeys(): string[] {
    return this.favoriteModels.map(f => this.getFavoriteKey(f.providerId, f.modelId))
  }

  /**
   * 生成收藏复合键
   * @param providerId 供应商 ID
   * @param modelId 模型 ID
   * @returns 复合键（providerId::modelId 格式）
   */
  getFavoriteKey(providerId: string, modelId: string): string {
    return `${providerId}::${modelId}`
  }

  /**
   * 获取收藏数量
   * @returns 收藏数量
   */
  getCount(): number {
    return this.favoriteModels.length
  }

  /**
   * 清空所有收藏
   */
  async clearAll(): Promise<void> {
    this.favoriteModels = []
    await this.save()
  }
}

/**
 * 获取收藏模型服务实例
 */
export function getFavoriteModelsService(): FavoriteModelsService {
  return FavoriteModelsService.getInstance()
}
