export function isSelfOptimizedSearchEngineForChat(engineName: string): boolean {
  const normalizedName = engineName.trim().toLowerCase()
  return normalizedName === 'exa'
}

export function shouldApplyLlmQueryOptimizationForChat(engineName: string, globalEnabled: boolean): boolean {
  if (!globalEnabled) {
    return false
  }
  return !isSelfOptimizedSearchEngineForChat(engineName)
}
