import { ChatMessage } from '../models/ChatModels'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0003
const TAG = 'MessageDataSource'

// 数据源统计信息
interface DataSourceStats {
  totalCount: number
  listenerCount: number
}

/**
 * 消息数据源
 * 实现 IDataSource 接口，用于 LazyForEach 的数据懒加载
 */
export class MessageDataSource implements IDataSource {
  // 数据监听器列表
  private listeners: DataChangeListener[] = []
  // 消息数据数组
  private dataArray: ChatMessage[] = []

  constructor(messages: ChatMessage[] = []) {
    this.dataArray = messages
    hilog.info(DOMAIN, TAG, '🚀 MessageDataSource 初始化 (消息数: %{public}d)', this.dataArray.length)
  }

  /**
   * 获取数据总数
   */
  totalCount(): number {
    return this.dataArray.length
  }

  /**
   * 获取指定索引的数据
   */
  getData(index: number): ChatMessage {
    return this.dataArray[index]
  }

  /**
   * 获取所有消息（用于访问完整数据）
   */
  getAllMessages(): ChatMessage[] {
    return this.dataArray
  }

  /**
   * 设置所有消息（用于初始化）
   * 注意：创建数组副本，避免与外部数组共享引用
   */
  setAllMessages(messages: ChatMessage[]): void {
    // 创建数组副本，避免与外部数组共享引用导致重复添加
    this.dataArray = []
    for (let i = 0; i < messages.length; i++) {
      this.dataArray.push(messages[i])
    }
    hilog.info(DOMAIN, TAG, '📥 设置消息列表 (总数: %{public}d)', this.dataArray.length)
    this.notifyDataReload()
  }

  /**
   * 注册数据变化监听器
   */
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
      hilog.debug(DOMAIN, TAG, '➕ 注册监听器 (当前监听器数: %{public}d)', this.listeners.length)
    }
  }

  /**
   * 注销数据变化监听器
   */
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
      hilog.debug(DOMAIN, TAG, '➖ 注销监听器 (当前监听器数: %{public}d)', this.listeners.length)
    }
  }

  /**
   * 添加消息到末尾
   */
  addMessage(message: ChatMessage): void {
    this.dataArray.push(message)
    const index = this.dataArray.length - 1
    hilog.debug(DOMAIN, TAG, '➕ 添加消息 (索引: %{public}d, ID: %{public}s)', index, message.id)
    this.notifyDataAdd(index)
  }

  /**
   * 批量添加消息
   */
  addMessages(messages: ChatMessage[]): void {
    if (messages.length === 0) {
      return
    }
    const startIndex = this.dataArray.length
    for (let i = 0; i < messages.length; i++) {
      this.dataArray.push(messages[i])
    }
    hilog.debug(DOMAIN, TAG, '➕ 批量添加消息 (起始索引: %{public}d, 数量: %{public}d)', startIndex, messages.length)
    // 通知所有新添加的消息
    for (let i = 0; i < messages.length; i++) {
      this.notifyDataAdd(startIndex + i)
    }
  }

  /**
   * 更新指定索引的消息
   */
  updateMessage(index: number, message: ChatMessage): void {
    if (index >= 0 && index < this.dataArray.length) {
      this.dataArray[index] = message
      hilog.debug(DOMAIN, TAG, '🔄 更新消息 (索引: %{public}d, ID: %{public}s)', index, message.id)
      this.notifyDataChange(index)
    }
  }

  /**
   * 更新最后一条消息（优化流式输出场景）
   */
  updateLastMessage(message: ChatMessage): void {
    if (this.dataArray.length > 0) {
      const index = this.dataArray.length - 1
      this.dataArray[index] = message
      hilog.debug(DOMAIN, TAG, '🔄 更新最后一条消息 (索引: %{public}d, ID: %{public}s)', index, message.id)
      this.notifyDataChange(index)
    }
  }

  /**
   * 强制通知最后一条消息已变化（用于停止生成等场景）
   * 当消息对象属性变化但引用未变时，调用此方法强制触发 UI 更新
   */
  notifyLastMessageChanged(): void {
    if (this.dataArray.length > 0) {
      const index = this.dataArray.length - 1
      hilog.info(DOMAIN, TAG, '🔔 强制通知最后一条消息变化 (索引: %{public}d)', index)
      this.notifyDataChange(index)
    }
  }

  /**
   * 删除指定索引的消息
   */
  removeMessage(index: number): void {
    if (index >= 0 && index < this.dataArray.length) {
      const messageId = this.dataArray[index].id
      this.dataArray.splice(index, 1)
      hilog.debug(DOMAIN, TAG, '🗑️ 删除消息 (索引: %{public}d, ID: %{public}s)', index, messageId)
      this.notifyDataDelete(index)
    }
  }

  /**
   * 根据 ID 查找消息索引
   */
  findMessageIndex(messageId: string): number {
    for (let i = 0; i < this.dataArray.length; i++) {
      if (this.dataArray[i].id === messageId) {
        return i
      }
    }
    return -1
  }

  /**
   * 根据 ID 删除消息
   */
  removeMessageById(messageId: string): boolean {
    const index = this.findMessageIndex(messageId)
    if (index >= 0) {
      this.removeMessage(index)
      return true
    }
    return false
  }

  /**
   * 清空所有消息
   */
  clear(): void {
    const count = this.dataArray.length
    this.dataArray = []
    hilog.info(DOMAIN, TAG, '🧹 清空所有消息 (清除 %{public}d 条)', count)
    this.notifyDataReload()
  }

  /**
   * 重载数据（通知 LazyForEach 重新渲染所有子组件）
   */
  reload(): void {
    hilog.debug(DOMAIN, TAG, '🔄 重载数据')
    this.notifyDataReload()
  }

  // ========== IDataSource 通知方法 ==========

  /**
   * 通知数据重载
   */
  private notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded()
    })
  }

  /**
   * 通知数据添加
   */
  private notifyDataAdd(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataAdd(index)
    })
  }

  /**
   * 通知数据变化
   */
  private notifyDataChange(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataChange(index)
    })
  }

  /**
   * 通知数据删除
   */
  private notifyDataDelete(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataDelete(index)
    })
  }

  /**
   * 通知数据移动
   */
  private notifyDataMove(from: number, to: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataMove(from, to)
    })
  }

  /**
   * 获取数据源统计信息
   */
  getStats(): DataSourceStats {
    const stats: DataSourceStats = {
      totalCount: this.dataArray.length,
      listenerCount: this.listeners.length
    }
    return stats
  }
}

/**
 * 创建消息数据源
 */
export function createMessageDataSource(messages: ChatMessage[] = []): MessageDataSource {
  return new MessageDataSource(messages)
}
