import { ChatSession } from '../../models/ChatModels'
import { SessionFilterType, SessionGroupData } from './IndexPageTypes'

export function getFilteredSessionsForIndex(sessions: ChatSession[], searchText: string,
  filterType: SessionFilterType): ChatSession[] {
  const filtered: ChatSession[] = []
  const keyword = searchText.trim().toLowerCase()

  for (let i = 0; i < sessions.length; i++) {
    const session = sessions[i]
    if (filterType === SessionFilterType.FAVORITE && !session.isFavorite) {
      continue
    }
    if (keyword !== '') {
      const titleMatched = session.title.toLowerCase().includes(keyword)
      const previewMatched = session.lastMessagePreview.toLowerCase().includes(keyword)
      if (!titleMatched && !previewMatched) {
        continue
      }
    }
    filtered.push(session)
  }

  filtered.sort((a: ChatSession, b: ChatSession) => {
    return b.updatedAt - a.updatedAt
  })

  return filtered
}

function getSessionGroupKey(timestamp: number): string {
  const now = new Date()
  now.setHours(0, 0, 0, 0)
  const target = new Date(timestamp)
  target.setHours(0, 0, 0, 0)
  const diffDays = Math.floor((now.getTime() - target.getTime()) / (24 * 60 * 60 * 1000))
  if (diffDays <= 0) {
    return 'today'
  }
  if (diffDays === 1) {
    return 'yesterday'
  }
  if (diffDays <= 6) {
    return 'last7days'
  }
  return 'older'
}

export function buildSessionGroupsForIndex(filteredSessions: ChatSession[]): SessionGroupData[] {
  const todaySessions: ChatSession[] = []
  const yesterdaySessions: ChatSession[] = []
  const last7DaysSessions: ChatSession[] = []
  const olderSessions: ChatSession[] = []

  for (let i = 0; i < filteredSessions.length; i++) {
    const session = filteredSessions[i]
    const groupKey = getSessionGroupKey(session.updatedAt)
    if (groupKey === 'today') {
      todaySessions.push(session)
    } else if (groupKey === 'yesterday') {
      yesterdaySessions.push(session)
    } else if (groupKey === 'last7days') {
      last7DaysSessions.push(session)
    } else {
      olderSessions.push(session)
    }
  }

  const groups: SessionGroupData[] = []
  if (todaySessions.length > 0) {
    groups.push(new SessionGroupData('today', todaySessions))
  }
  if (yesterdaySessions.length > 0) {
    groups.push(new SessionGroupData('yesterday', yesterdaySessions))
  }
  if (last7DaysSessions.length > 0) {
    groups.push(new SessionGroupData('last7days', last7DaysSessions))
  }
  if (olderSessions.length > 0) {
    groups.push(new SessionGroupData('older', olderSessions))
  }
  return groups
}

export function buildSessionGroupRenderKey(group: SessionGroupData, filterType: SessionFilterType, searchText: string):
  string {
  let orderSignature = ''
  for (let i = 0; i < group.sessions.length; i++) {
    const session = group.sessions[i]
    orderSignature += `${session.id}_${session.isFavorite ? '1' : '0'}|`
  }
  return `${group.key}_${filterType.toString()}_${searchText}_${orderSignature}`
}
