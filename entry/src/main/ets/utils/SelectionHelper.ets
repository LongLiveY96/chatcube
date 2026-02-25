export function toggleSelectionById(currentIds: string[], targetId: string): string[] {
  const index = currentIds.indexOf(targetId)
  if (index >= 0) {
    const next: string[] = []
    for (let i = 0; i < currentIds.length; i++) {
      if (i !== index) {
        next.push(currentIds[i])
      }
    }
    return next
  }
  return [...currentIds, targetId]
}

export function mergeSelectAllIds(currentIds: string[], candidateIds: string[]): string[] {
  const nextIds = [...currentIds]
  for (let i = 0; i < candidateIds.length; i++) {
    if (!nextIds.includes(candidateIds[i])) {
      nextIds.push(candidateIds[i])
    }
  }
  return nextIds
}

export function removeCandidateIds(currentIds: string[], candidateIds: string[]): string[] {
  const nextIds: string[] = []
  for (let i = 0; i < currentIds.length; i++) {
    let shouldKeep = true
    for (let j = 0; j < candidateIds.length; j++) {
      if (currentIds[i] === candidateIds[j]) {
        shouldKeep = false
        break
      }
    }
    if (shouldKeep) {
      nextIds.push(currentIds[i])
    }
  }
  return nextIds
}

export function countSelectedIdsInCandidates(currentIds: string[], candidateIds: string[]): number {
  let count = 0
  for (let i = 0; i < candidateIds.length; i++) {
    if (currentIds.includes(candidateIds[i])) {
      count = count + 1
    }
  }
  return count
}
