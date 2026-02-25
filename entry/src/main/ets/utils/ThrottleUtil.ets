import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0002
const TAG = 'ThrottleUtil'

/**
 * 节流工具类
 * 用于减少高频事件的触发频率，如流式输出时的 UI 更新
 */
export class ThrottleUtil {
  // 上次执行时间
  private lastExecuteTime: number = 0
  // 待执行的内容缓存
  private pendingContent: string = ''
  // 定时器 ID
  private timerId: number = -1
  // 节流间隔（毫秒）
  private readonly interval: number
  // 是否已启用
  private enabled: boolean = true

  constructor(interval: number = 150) {
    this.interval = interval
    hilog.debug(DOMAIN, TAG, '🚀 ThrottleUtil 初始化 (间隔: %{public}dms)', interval)
  }

  /**
   * 节流执行
   * @param content 新增的内容
   * @param callback 执行回调，参数为累积的内容
   */
  throttle(content: string, callback: (content: string) => void): void {
    if (!this.enabled) {
      // 节流禁用时，直接执行回调
      callback(content)
      return
    }

    const now = Date.now()

    // 累积待执行内容
    this.pendingContent += content

    // 清除之前的定时器
    if (this.timerId !== -1) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }

    // 检查是否可以立即执行
    if (now - this.lastExecuteTime >= this.interval) {
      // 立即执行
      this.execute(callback)
    } else {
      // 设置定时器延迟执行
      const delay = this.interval - (now - this.lastExecuteTime)
      this.timerId = setTimeout(() => {
        this.execute(callback)
      }, delay)
    }
  }

  /**
   * 执行回调并重置状态
   */
  private execute(callback: (content: string) => void): void {
    if (this.pendingContent === '') {
      return
    }

    const contentToExecute = this.pendingContent
    this.pendingContent = ''
    this.lastExecuteTime = Date.now()
    this.timerId = -1

    callback(contentToExecute)
  }

  /**
   * 立即刷新（强制执行待处理内容）
   * 用于确保在操作完成时所有内容都被处理
   */
  flush(callback: (content: string) => void): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }

    if (this.pendingContent !== '') {
      this.execute(callback)
    }
  }

  /**
   * 重置节流器状态
   */
  reset(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
    this.pendingContent = ''
    this.lastExecuteTime = 0
    hilog.debug(DOMAIN, TAG, '🔄 节流器已重置')
  }

  /**
   * 启用节流
   */
  enable(): void {
    this.enabled = true
    hilog.debug(DOMAIN, TAG, '✅ 节流已启用')
  }

  /**
   * 禁用节流
   */
  disable(): void {
    this.enabled = false
    hilog.debug(DOMAIN, TAG, '⛔ 节流已禁用')
  }

  /**
   * 检查是否有待处理的内容
   */
  hasPending(): boolean {
    return this.pendingContent !== '' || this.timerId !== -1
  }
}

/**
 * 创建节流工具实例
 * @param interval 节流间隔（毫秒），默认 150ms
 * @returns ThrottleUtil 实例
 */
export function createThrottle(interval: number = 150): ThrottleUtil {
  return new ThrottleUtil(interval)
}

/**
 * 滚动节流器（专门用于滚动操作）
 * 滚动操作可以使用更长的节流间隔
 */
export class ScrollThrottle {
  private lastExecuteTime: number = 0
  private readonly interval: number
  private timerId: number = -1
  private enabled: boolean = true

  constructor(interval: number = 100) {
    this.interval = interval
  }

  throttle(callback: () => void): void {
    if (!this.enabled) {
      callback()
      return
    }

    const now = Date.now()

    if (this.timerId !== -1) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }

    if (now - this.lastExecuteTime >= this.interval) {
      this.lastExecuteTime = now
      callback()
    } else {
      const delay = this.interval - (now - this.lastExecuteTime)
      this.timerId = setTimeout(() => {
        this.lastExecuteTime = Date.now()
        callback()
      }, delay)
    }
  }

  reset(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
    this.lastExecuteTime = 0
  }
}

