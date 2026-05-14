export const LEGACY_WEB_SEARCH_TOOL_ID: string = 'web_search'
export const SEARCH_WEB_TOOL_ID: string = 'search_web'
export const SCRAPE_WEB_TOOL_ID: string = 'scrape_web'
export const ASK_USER_TOOL_ID: string = 'ask_user'
export const GET_TIME_INFO_TOOL_ID: string = 'get_time_info'

export function normalizeToolFunctionName(raw: string): string {
  const value = raw as string | null | undefined
  if (value === undefined || value === null) {
    return ''
  }
  return value.trim().toLowerCase().replace(/[\s\-]+/g, '_')
}

export function isSearchToolId(toolId: string): boolean {
  const normalized = normalizeToolFunctionName(toolId)
  return normalized === LEGACY_WEB_SEARCH_TOOL_ID ||
    normalized === SEARCH_WEB_TOOL_ID ||
    normalized === SCRAPE_WEB_TOOL_ID
}

export function isScrapeWebFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === SCRAPE_WEB_TOOL_ID
}

export function isSearchWebFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === LEGACY_WEB_SEARCH_TOOL_ID ||
    normalized === SEARCH_WEB_TOOL_ID ||
    normalized === 'exa_search' ||
    normalized === 'websearch' ||
    normalized === 'internet_search' ||
    normalized === 'web_search_exa'
}

export function isSearchToolFunctionName(functionName: string): boolean {
  return isSearchWebFunctionName(functionName) || isScrapeWebFunctionName(functionName)
}

export function isAskUserFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === ASK_USER_TOOL_ID ||
    normalized === 'user_input' ||
    normalized === 'ask'
}

export function getSearchToolIds(): string[] {
  return [LEGACY_WEB_SEARCH_TOOL_ID, SEARCH_WEB_TOOL_ID, SCRAPE_WEB_TOOL_ID]
}
