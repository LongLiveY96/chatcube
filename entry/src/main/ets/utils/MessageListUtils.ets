/**
 * 消息列表工具函数
 * 提取消息列表相关逻辑
 */

import { ChatMessage, MessageRole } from '../models/ChatModels'

/**
 * 判断是否需要显示消息头部（模型信息）
 * 只在以下情况显示：首条消息、模型切换、时间间隔超过5分钟
 * @param message 当前消息
 * @param index 消息索引
 * @param getMessageAt 获取指定索引消息的函数
 * @returns 是否需要显示头部
 */
export function shouldShowMessageHeader(
  message: ChatMessage,
  index: number,
  getMessageAt: (index: number) => ChatMessage
): boolean {
  // 用户消息不显示头部
  if (message.role === MessageRole.USER) {
    return false
  }

  // 首条消息显示头部
  if (index === 0) {
    return true
  }

  const prevMessage = getMessageAt(index - 1)

  // 如果上一条消息不存在（数据不一致），显示头部
  if (prevMessage === undefined || prevMessage === null) {
    return true
  }

  // 上一条是用户消息，显示头部
  if (prevMessage.role === MessageRole.USER) {
    return true
  }

  // 模型名称不同，显示头部
  if (prevMessage.modelName !== message.modelName) {
    return true
  }

  // 时间间隔超过5分钟，显示头部
  const timeGap = message.timestamp - prevMessage.timestamp
  if (timeGap > 5 * 60 * 1000) {
    return true
  }

  return false
}
