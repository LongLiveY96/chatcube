/**
 * 日期格式化工具函数
 * 提取日期分隔符相关逻辑
 */

/**
 * 格式化日期分隔符显示文本
 * @param timestamp 时间戳
 * @returns 格式化后的日期文本（今天、昨天、具体日期）
 */
export function formatDateDivider(timestamp: number): string {
  const date = new Date(timestamp)
  const now = new Date()
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000)
  const messageDate = new Date(date.getFullYear(), date.getMonth(), date.getDate())

  if (messageDate.getTime() === today.getTime()) {
    return '今天'
  } else if (messageDate.getTime() === yesterday.getTime()) {
    return '昨天'
  } else if (date.getFullYear() === now.getFullYear()) {
    // 同年，显示月日
    return `${date.getMonth() + 1}月${date.getDate()}日`
  } else {
    // 不同年，显示年月日
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`
  }
}

/**
 * 判断是否需要显示日期分隔符
 * @param currentTimestamp 当前消息时间戳
 * @param previousTimestamp 上一条消息时间戳（如果是首条消息则为 null）
 * @returns 是否需要显示日期分隔符
 */
export function shouldShowDateDivider(
  currentTimestamp: number,
  previousTimestamp: number | null
): boolean {
  // 首条消息显示日期
  if (previousTimestamp === null) {
    return true
  }

  // 比较日期（只比较年月日）
  const currentDate = new Date(currentTimestamp)
  const prevDate = new Date(previousTimestamp)

  return currentDate.getFullYear() !== prevDate.getFullYear() ||
         currentDate.getMonth() !== prevDate.getMonth() ||
         currentDate.getDate() !== prevDate.getDate()
}

/**
 * 判断两个时间戳是否在同一天
 * @param timestamp1 时间戳1
 * @param timestamp2 时间戳2
 * @returns 是否在同一天
 */
export function isSameDay(timestamp1: number, timestamp2: number): boolean {
  const date1 = new Date(timestamp1)
  const date2 = new Date(timestamp2)

  return date1.getFullYear() === date2.getFullYear() &&
         date1.getMonth() === date2.getMonth() &&
         date1.getDate() === date2.getDate()
}
