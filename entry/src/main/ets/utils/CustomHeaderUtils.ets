export interface CustomHeaderEntry {
  name: string
  value: string
}

export interface CustomHeaderValidationOptions {
  emptyEntryMessage: string
  reservedHeaderMessage: (name: string) => string
  duplicateHeaderMessage: (name: string) => string
}

const DEFAULT_SENSITIVE_HEADER_KEYWORDS: string[] = [
  'authorization',
  'token',
  'secret',
  'key',
  'cookie'
]

export function normalizeCustomHeaderName(name: string): string {
  return name.trim().toLowerCase()
}

export function parseCustomHeaderEntries(raw: string): CustomHeaderEntry[] {
  if (raw.trim() === '') {
    return []
  }
  try {
    const parsed = JSON.parse(raw) as Record<string, Object>
    const keys = Object.keys(parsed)
    const entries: CustomHeaderEntry[] = []
    for (let i = 0; i < keys.length; i++) {
      entries.push({
        name: keys[i],
        value: `${parsed[keys[i]]}`
      })
    }
    return entries
  } catch (_error) {
    return []
  }
}

export function buildCustomHeadersJson(entries: CustomHeaderEntry[]): string {
  const headers = JSON.parse('{}') as Record<string, string>
  let count = 0
  for (let i = 0; i < entries.length; i++) {
    const name = entries[i].name.trim()
    const value = entries[i].value.trim()
    if (name === '' && value === '') {
      continue
    }
    headers[name] = value
    count += 1
  }
  if (count === 0) {
    return ''
  }
  return JSON.stringify(headers)
}

export function parseCustomHeadersMap(raw: string): Record<string, string> {
  const entries = parseCustomHeaderEntries(raw)
  const headers = JSON.parse('{}') as Record<string, string>
  for (let i = 0; i < entries.length; i++) {
    const name = entries[i].name.trim()
    const value = entries[i].value.trim()
    if (name === '' || value === '') {
      continue
    }
    headers[name] = value
  }
  return headers
}


export function validateCustomHeaderEntries(
  entries: CustomHeaderEntry[],
  reservedHeaderNames: string[],
  options: CustomHeaderValidationOptions
): string {
  const seenNames: string[] = []
  for (let i = 0; i < entries.length; i++) {
    const name = entries[i].name.trim()
    const value = entries[i].value.trim()
    if (name === '' && value === '') {
      continue
    }
    if (name === '' || value === '') {
      return options.emptyEntryMessage
    }
    const normalizedName = normalizeCustomHeaderName(name)
    if (reservedHeaderNames.includes(normalizedName)) {
      return options.reservedHeaderMessage(name)
    }
    if (seenNames.includes(normalizedName)) {
      return options.duplicateHeaderMessage(name)
    }
    seenNames.push(normalizedName)
  }
  return ''
}

export function isSensitiveCustomHeaderName(name: string): boolean {
  const normalized = normalizeCustomHeaderName(name)
  for (let i = 0; i < DEFAULT_SENSITIVE_HEADER_KEYWORDS.length; i++) {
    if (normalized.includes(DEFAULT_SENSITIVE_HEADER_KEYWORDS[i])) {
      return true
    }
  }
  return false
}
