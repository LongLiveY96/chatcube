export function parseToolIdsFromRouteRaw(raw: string): string[] {
  const ids: string[] = []
  if (raw === '') {
    return ids
  }
  const parts = raw.split(',')
  for (let i = 0; i < parts.length; i++) {
    const id = parts[i].trim()
    if (id !== '' && !ids.includes(id)) {
      ids.push(id)
    }
  }
  return ids
}

export function appendUniqueToolId(ids: string[], toolId: string): void {
  if (toolId === '') {
    return
  }
  if (!ids.includes(toolId)) {
    ids.push(toolId)
  }
}
