import { InAppTaskAlertPayloadData, OpenSessionPayloadData } from '../models/TaskAlertModels'

export function parseOpenSessionPayload(payloadText: string): OpenSessionPayloadData | null {
  if (payloadText === '') {
    return null
  }
  try {
    const payload = JSON.parse(payloadText) as OpenSessionPayloadData
    if (payload.sessionId === '') {
      return null
    }
    return payload
  } catch (_error) {
    return null
  }
}

export function parseInAppTaskAlertPayload(payloadText: string): InAppTaskAlertPayloadData | null {
  if (payloadText === '') {
    return null
  }
  try {
    return JSON.parse(payloadText) as InAppTaskAlertPayloadData
  } catch (_error) {
    return null
  }
}

export function tryParseUnreadBySessionMap(jsonText: string): Map<string, number> | null {
  const map: Map<string, number> = new Map()
  if (jsonText === '') {
    return map
  }
  try {
    const parsed = JSON.parse(jsonText) as Record<string, number>
    const keys = Object.keys(parsed)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      const value = parsed[key]
      if (value > 0) {
          map.set(key, value)
        }
      }
  } catch (_error) {
    return null
  }
  return map
}

export function parseUnreadBySessionMap(jsonText: string): Map<string, number> {
  const parsed = tryParseUnreadBySessionMap(jsonText)
  if (parsed === null) {
    return new Map()
  }
  return parsed
}

export function getUnreadCountBySession(unreadBySession: Map<string, number>, sessionId: string): number {
  const count = unreadBySession.get(sessionId)
  if (count === undefined) {
    return 0
  }
  return count
}

export function getTotalUnreadCount(unreadBySession: Map<string, number>): number {
  let total = 0
  unreadBySession.forEach((value: number) => {
    total = total + value
  })
  return total
}

export function getTotalUnreadCountExcludeSession(unreadBySession: Map<string, number>, sessionId: string): number {
  let total = 0
  unreadBySession.forEach((value: number, key: string) => {
    if (key !== sessionId) {
      total = total + value
    }
  })
  return total
}
