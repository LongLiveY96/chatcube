import { MarkdownController } from '@luvi/lv-markdown-in'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0002
const TAG = 'MarkdownRenderCache'

// 缓存项
interface CacheItem {
  controller: MarkdownController
  lastAccessTime: number
  contentHash: string
  isDarkMode: boolean
}

// 缓存统计信息
interface CacheStats {
  size: number
  maxSize: number
}

/**
 * Markdown 渲染缓存管理器
 * 使用 LRU 策略缓存 MarkdownController 实例，避免重复创建和渲染
 */
export class MarkdownRenderCacheManager {
  // 单例实例
  private static instance: MarkdownRenderCacheManager | null = null

  // 缓存映射：key = "contentHash_isDarkMode"
  private cache: Map<string, CacheItem> = new Map<string, CacheItem>()

  // 最大缓存数量
  private readonly MAX_CACHE_SIZE: number = 50

  // 当前深色模式状态（用于生成缓存键）
  private currentIsDarkMode: boolean = false

  private constructor() {
    hilog.info(DOMAIN, TAG, '🚀 MarkdownRenderCacheManager 初始化')
  }

  /**
   * 获取单例实例
   */
  static getInstance(): MarkdownRenderCacheManager {
    if (MarkdownRenderCacheManager.instance === null) {
      MarkdownRenderCacheManager.instance = new MarkdownRenderCacheManager()
    }
    return MarkdownRenderCacheManager.instance
  }

  /**
   * 更新当前深色模式状态
   * 在深色模式切换时调用，用于生成正确的缓存键
   */
  updateDarkModeState(isDarkMode: boolean): void {
    if (this.currentIsDarkMode !== isDarkMode) {
      hilog.info(DOMAIN, TAG, '🌓 深色模式状态更新: %{public}s -> %{public}s',
        this.currentIsDarkMode ? '深色' : '浅色', isDarkMode ? '深色' : '浅色')
      this.currentIsDarkMode = isDarkMode
    }
  }

  /**
   * 生成内容哈希（简化版，使用内容长度和部分字符生成）
   * 完整哈希可以使用 crypto 模块，但这里使用简化版本提高性能
   */
  private generateContentHash(content: string): string {
    if (content.length === 0) {
      return 'empty'
    }

    // 使用内容长度 + 前50字符 + 后50字符生成哈希
    const prefix = content.substring(0, 50)
    const suffix = content.length > 100 ? content.substring(content.length - 50) : ''

    let hash = 0
    const hashContent = prefix + suffix + content.length.toString()

    for (let i = 0; i < hashContent.length; i++) {
      const char = hashContent.charCodeAt(i)
      hash = ((hash << 5) - hash) + char
      hash = hash & hash // 转换为32位整数
    }

    return Math.abs(hash).toString(36)
  }

  /**
   * 生成缓存键
   */
  private generateCacheKey(content: string): string {
    const contentHash = this.generateContentHash(content)
    return `${contentHash}_${this.currentIsDarkMode ? 'dark' : 'light'}`
  }

  /**
   * 获取或创建 MarkdownController
   */
  getController(content: string): MarkdownController {
    const cacheKey = this.generateCacheKey(content)

    // 检查缓存是否存在
    if (this.cache.has(cacheKey)) {
      const item = this.cache.get(cacheKey)
      if (item !== undefined) {
        // 更新最后访问时间
        item.lastAccessTime = Date.now()
        hilog.debug(DOMAIN, TAG, '✅ 命中缓存: %{public}s', cacheKey)
        return item.controller
      }
    }

    // 缓存未命中，创建新的 Controller
    const controller = new MarkdownController()
    const newItem: CacheItem = {
      controller: controller,
      lastAccessTime: Date.now(),
      contentHash: this.generateContentHash(content),
      isDarkMode: this.currentIsDarkMode
    }

    // 添加到缓存
    this.cache.set(cacheKey, newItem)

    // 检查缓存大小，必要时淘汰旧缓存
    this.evictIfNeeded()

    hilog.debug(DOMAIN, TAG, '➕ 创建新缓存: %{public}s (当前缓存数: %{public}d/%{public}d)',
      cacheKey, this.cache.size, this.MAX_CACHE_SIZE)

    return controller
  }

  /**
   * 检查并淘汰旧缓存（LRU 策略）
   */
  private evictIfNeeded(): void {
    if (this.cache.size <= this.MAX_CACHE_SIZE) {
      return
    }

    // 找到最久未使用的缓存项
    let oldestKey: string = ''
    let oldestTime: number = Date.now()

    this.cache.forEach((item: CacheItem, key: string) => {
      if (item.lastAccessTime < oldestTime) {
        oldestTime = item.lastAccessTime
        oldestKey = key
      }
    })

    // 删除最久未使用的缓存
    if (oldestKey !== '') {
      this.cache.delete(oldestKey)
      hilog.debug(DOMAIN, TAG, '🗑️ 淘汰旧缓存: %{public}s', oldestKey)
    }
  }

  /**
   * 清空所有缓存（在深色模式切换时调用）
   * 注意：这里我们不会清空缓存，而是通过不同的缓存键区分深色/浅色模式
   */
  clear(): void {
    const size = this.cache.size
    this.cache.clear()
    hilog.info(DOMAIN, TAG, '🧹 缓存已清空 (清除 %{public}d 项)', size)
  }

  /**
   * 获取缓存统计信息
   */
  getStats(): CacheStats {
    const stats: CacheStats = {
      size: this.cache.size,
      maxSize: this.MAX_CACHE_SIZE
    }
    return stats
  }

  /**
   * 预热缓存（可选，用于在加载会话时预先缓存已知内容）
   */
  warmUp(contents: string[]): void {
    hilog.info(DOMAIN, TAG, '🔥 开始预热缓存 (%{public}d 项)', contents.length)
    for (let i = 0; i < contents.length; i++) {
      this.getController(contents[i])
    }
    hilog.info(DOMAIN, TAG, '✅ 缓存预热完成')
  }
}

// 导出单例获取方法
export function getMarkdownRenderCache(): MarkdownRenderCacheManager {
  return MarkdownRenderCacheManager.getInstance()
}
