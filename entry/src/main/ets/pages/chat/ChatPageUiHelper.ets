export function shouldShowScrollToTopButtonForChat(
  isMultiSelectMode: boolean,
  totalMessages: number,
  isAtTop: boolean,
  currentScrollOffsetVp: number,
  viewportHeightVp: number
): boolean {
  const minimumVisibleOffsetVp = 24
  if (isMultiSelectMode) {
    return false
  }
  if (totalMessages <= 0) {
    return false
  }
  if (viewportHeightVp <= 0) {
    return false
  }
  if (currentScrollOffsetVp <= minimumVisibleOffsetVp) {
    return false
  }
  return !isAtTop
}

export function getListBottomPaddingForChat(pendingAttachmentCount: number, isEditingMessage: boolean,
  bottomAvoidHeightVp: number): number {
  let base = 90
  if (pendingAttachmentCount > 0) {
    base += 80
  }
  if (isEditingMessage) {
    base += 80
  }
  return base + bottomAvoidHeightVp
}

export function getPreviewTimeTextForChat(date: Date): string {
  const hours = date.getHours()
  const minutes = date.getMinutes()
  const ampm = hours >= 12 ? 'PM' : 'AM'
  const h = hours > 12 ? hours - 12 : (hours === 0 ? 12 : hours)
  const m = minutes < 10 ? '0' + minutes.toString() : minutes.toString()
  return h.toString() + ':' + m + ' ' + ampm
}
