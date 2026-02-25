// 搜索查询通用工具：用于统一查询清洗、时间归一和优化触发判断

function hasExplicitDateInQuery(text: string): boolean {
  return /(\d{4})[年\/\-.](\d{1,2})[月\/\-.]?(\d{1,2})日?/.test(text)
}

function getRelativeDayOffset(text: string): number {
  if (text.includes('昨天') || text.includes('昨日')) {
    return -1
  }
  if (text.includes('明天')) {
    return 1
  }
  if (text.includes('今天') || text.includes('今日') || text.includes('现在') || text.includes('当前')) {
    return 0
  }
  return 99
}

function hasCurrentYearIntent(text: string): boolean {
  const normalized = text.toLowerCase()
  return normalized.includes('今年') || normalized.includes('本年') || normalized.includes('最新')
    || normalized.includes('当前') || normalized.includes('目前') || normalized.includes('现在')
    || normalized.includes('latest') || normalized.includes('recent') || normalized.includes('now')
}

function getDateTextByOffset(dayOffset: number): string {
  const date = new Date()
  date.setDate(date.getDate() + dayOffset)
  const year = date.getFullYear()
  const month = date.getMonth() + 1
  const day = date.getDate()
  return `${year}年${month}月${day}日`
}

function isNewsIntent(text: string): boolean {
  const t = text.replace(/\s+/g, '')
  const keywords: string[] = [
    '新闻', '快讯', '资讯', '头条', '热点', '动态', '发布会', '通报', 'news'
  ]
  for (let i = 0; i < keywords.length; i++) {
    if (t.toLowerCase().includes(keywords[i].toLowerCase())) {
      return true
    }
  }
  return false
}

// 去除口语化前缀、多余空格，保留核心关键词
export function cleanSearchQuery(query: string): string {
  let cleaned = query.trim()

  cleaned = cleaned.replace(/^(?:帮我|麻烦|请|请帮我|帮忙)?(?:查询|搜索|查找|查|搜)(?:一下|下)?[\s，,。:：-]*/i, '')

  const prefixes: string[] = [
    '帮我搜索',
    '搜索一下',
    '搜索下',
    '查一下',
    '查下',
    '搜一下',
    '搜下',
    '帮我查',
    '帮我查一下',
    '帮我查下',
    '请搜索',
    '请查',
    '请查一下',
    '请查下',
    '帮我找',
    '帮我找一下',
    '帮我找下',
    '找一下',
    '找下'
  ]
  for (let i = 0; i < prefixes.length; i++) {
    if (cleaned.startsWith(prefixes[i])) {
      cleaned = cleaned.substring(prefixes[i].length).trim()
      break
    }
  }

  cleaned = cleaned.replace(/\s+/g, ' ')
  return cleaned !== '' ? cleaned : query
}

// 将相对时间词转为具体日期（仅在必要场景做增强，避免过度改写）
export function normalizeRelativeTimeForSearchQuery(userQuery: string, candidateQuery: string): string {
  const normalizedUserQuery = cleanSearchQuery(userQuery)
  const normalizedCandidate = cleanSearchQuery(candidateQuery)
  if (normalizedCandidate === '') {
    return normalizedUserQuery
  }
  const userHasExplicitDate = hasExplicitDateInQuery(normalizedUserQuery)

  const dayOffset = getRelativeDayOffset(normalizedUserQuery)
  if (hasExplicitDateInQuery(normalizedCandidate)) {
    if (dayOffset !== 99 && !userHasExplicitDate) {
      const targetDateText = getDateTextByOffset(dayOffset)
      if (normalizedCandidate.includes(targetDateText)) {
        return normalizedCandidate
      }
      return normalizedCandidate.replace(/(\d{4})[年\/\-.](\d{1,2})[月\/\-.]?(\d{1,2})日?/, targetDateText)
    }
    if (!userHasExplicitDate && hasCurrentYearIntent(normalizedUserQuery)) {
      const currentYear = `${new Date().getFullYear()}`
      return normalizedCandidate.replace(/(\d{4})(?=[年\/\-.])/, currentYear)
    }
    return normalizedCandidate
  }

  if (dayOffset === 99) {
    return normalizedCandidate
  }

  if (!isNewsIntent(normalizedUserQuery)) {
    return normalizedCandidate
  }

  const targetDateText = getDateTextByOffset(dayOffset)
  return `${targetDateText} ${normalizedCandidate}`.trim()
}

// 是否值得做 LLM 关键词优化：避免简单关键词也额外走一轮模型
export function shouldApplyLlmOptimizationByQuery(rawQuery: string, cleanedQuery: string): boolean {
  const raw = rawQuery.trim()
  const cleaned = cleanedQuery.trim()
  if (cleaned === '') {
    return false
  }

  if (raw !== cleaned) {
    return true
  }

  if (cleaned.length >= 24) {
    return true
  }

  if (/(今天|今日|昨天|昨日|明天|后天|现在|当前|最新|近期|最近|今年|本年|目前)/.test(cleaned)) {
    return true
  }

  if (/\b(today|yesterday|tomorrow|now|latest|recent|current)\b/i.test(cleaned)) {
    return true
  }

  if (/(那里|这边|那边|这个|那个|它|他|她)/.test(cleaned)) {
    return true
  }

  if (/\b(there|this|that|it|them)\b/i.test(cleaned)) {
    return true
  }

  return false
}
