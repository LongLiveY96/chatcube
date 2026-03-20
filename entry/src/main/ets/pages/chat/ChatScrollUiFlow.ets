import { ChatMessage } from '../../models/ChatModels'

export interface ChatScrollUiFlowDependencies {
  scroller: Scroller
  messages: ChatMessage[]
  getBottomAnchorIndex: () => number
  getCurrentScrollOffset: () => number
  syncCurrentScrollOffset: () => number
  syncIsAtBottomBoundary: () => boolean
  getLastScrollOffset: () => number
  setLastScrollOffset: (value: number) => void
  getMaxScrollOffset: () => number
  setMaxScrollOffset: (value: number) => void
  getInputBarShowThreshold: () => number
  getInputBarHideThreshold: () => number
  getIsAtTop: () => boolean
  getIsAtBottom: () => boolean
  getIsInputBarVisible: () => boolean
  getIsSending: () => boolean
  getIsEditingMessage: () => boolean
  getEditingMessageId: () => string
  hasDraftContent: () => boolean
  onSetIsAtTopState: (value: boolean) => void
  onSetIsAtBottomState: (value: boolean) => void
  onSetInputBarVisibleState: (value: boolean) => void
  onSetCurrentScrollOffsetState: (value: number) => void
  onSetScrollProgressState: (value: number) => void
  onAnimate: (duration: number, curve: Curve, updater: () => void) => void
}

export class ChatScrollUiFlow {
  private static readonly BOTTOM_OFFSET_TOLERANCE_VP: number = 8
  private deps: ChatScrollUiFlowDependencies
  private pinnedBottomAlignmentTimerIds: number[] = []
  private pinnedBottomAlignmentCompletionTimerId: number = -1
  private pendingPinnedBottomAlignment: boolean = false

  constructor(deps: ChatScrollUiFlowDependencies) {
    this.deps = deps
  }

  private normalizeScrollOffset(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0
    }
    return value
  }

  private clampProgress(value: number): number {
    if (!Number.isFinite(value)) {
      return 0
    }
    if (value <= 0) {
      return 0
    }
    if (value >= 1) {
      return 1
    }
    return value
  }

  private setScrollProgress(value: number): void {
    this.deps.onSetScrollProgressState(this.clampProgress(value))
  }

  private setCurrentScrollOffset(value: number): void {
    this.deps.onSetCurrentScrollOffsetState(this.normalizeScrollOffset(value))
  }

  private isWithinBottomTolerance(offset: number): boolean {
    const maxScrollOffset = this.deps.getMaxScrollOffset()
    if (maxScrollOffset <= 0) {
      return false
    }
    return maxScrollOffset - offset <= ChatScrollUiFlow.BOTTOM_OFFSET_TOLERANCE_VP
  }

  private resolveStableBottomOffset(offset: number): number {
    const maxScrollOffset = this.deps.getMaxScrollOffset()
    if (maxScrollOffset <= 0) {
      return offset
    }
    return Math.max(offset, maxScrollOffset)
  }

  private getCurrentScrollProgress(): number {
    const maxScrollOffset = this.deps.getMaxScrollOffset()
    if (maxScrollOffset <= 0) {
      return 0
    }
    const normalizedOffset = this.normalizeScrollOffset(this.deps.getCurrentScrollOffset())
    return this.clampProgress(normalizedOffset / maxScrollOffset)
  }

  private updateScrollProgress(): void {
    const maxScrollOffset = this.deps.getMaxScrollOffset()
    if (maxScrollOffset <= 0) {
      this.setScrollProgress(0)
      return
    }
    if (this.deps.getIsAtBottom()) {
      this.setScrollProgress(1)
      return
    }
    const normalizedOffset = this.normalizeScrollOffset(this.deps.getCurrentScrollOffset())
    if (normalizedOffset <= 0 || this.deps.getIsAtTop()) {
      this.setScrollProgress(0)
      return
    }
    this.setScrollProgress(normalizedOffset / maxScrollOffset)
  }

  private captureBottomScrollBaseline(): void {
    const currentOffset = this.normalizeScrollOffset(this.deps.syncCurrentScrollOffset())
    this.setCurrentScrollOffset(currentOffset)
    this.deps.setLastScrollOffset(currentOffset)
    if (currentOffset > this.deps.getMaxScrollOffset()) {
      this.deps.setMaxScrollOffset(currentOffset)
    }
    if (this.deps.getMaxScrollOffset() > 0) {
      this.setScrollProgress(1)
      return
    }
    if (this.deps.getIsAtTop()) {
      this.setScrollProgress(0)
      return
    }
    if (currentOffset > 0) {
      this.setScrollProgress(1)
    }
  }

  private clearPinnedBottomAlignmentTimers(): void {
    for (let i = 0; i < this.pinnedBottomAlignmentTimerIds.length; i++) {
      clearTimeout(this.pinnedBottomAlignmentTimerIds[i])
    }
    this.pinnedBottomAlignmentTimerIds = []
    if (this.pinnedBottomAlignmentCompletionTimerId >= 0) {
      clearTimeout(this.pinnedBottomAlignmentCompletionTimerId)
      this.pinnedBottomAlignmentCompletionTimerId = -1
    }
    this.pendingPinnedBottomAlignment = false
  }

  private syncBottomScrollBaselineAfterLayout(): void {
    setTimeout(() => {
      this.captureBottomScrollBaseline()
    }, 0)
    setTimeout(() => {
      this.captureBottomScrollBaseline()
    }, 50)
  }

  private scrollBottomAnchor(smooth: boolean): void {
    const bottomAnchorIndex = this.deps.getBottomAnchorIndex()
    if (bottomAnchorIndex >= 0) {
      this.deps.scroller.scrollToIndex(bottomAnchorIndex, smooth, ScrollAlign.END)
      return
    }
    this.deps.scroller.scrollEdge(Edge.Bottom)
  }

  private scrollEdgeAfterLayout(edge: Edge): void {
    setTimeout(() => {
      this.deps.scroller.scrollEdge(edge)
    }, 0)
    setTimeout(() => {
      this.deps.scroller.scrollEdge(edge)
    }, 50)
  }

  alignToBottomAfterLayout(): void {
    setTimeout(() => {
      this.scrollBottomAnchor(false)
    }, 0)
    setTimeout(() => {
      this.scrollBottomAnchor(false)
    }, 50)
    this.syncBottomScrollBaselineAfterLayout()
  }

  private schedulePinnedBottomAlignmentAfterLayout(): void {
    if (this.pendingPinnedBottomAlignment) {
      return
    }
    this.pendingPinnedBottomAlignment = true
    const delays: number[] = [0, 50]
    for (let i = 0; i < delays.length; i++) {
      const timerId = setTimeout(() => {
        if (!this.pendingPinnedBottomAlignment || !this.deps.getIsAtBottom()) {
          this.clearPinnedBottomAlignmentTimers()
          return
        }
        this.scrollBottomAnchor(false)
        this.captureBottomScrollBaseline()
      }, delays[i])
      this.pinnedBottomAlignmentTimerIds.push(timerId)
    }
    this.pinnedBottomAlignmentCompletionTimerId = setTimeout(() => {
      this.clearPinnedBottomAlignmentTimers()
    }, 120)
  }

  alignToBottomIfPinned(): void {
    if (!this.deps.getIsAtBottom()) {
      return
    }
    this.schedulePinnedBottomAlignmentAfterLayout()
  }

  setIsAtTop(value: boolean): void {
    if (this.deps.getIsAtTop() === value) {
      return
    }
    this.deps.onAnimate(200, Curve.EaseOut, () => {
      this.deps.onSetIsAtTopState(value)
    })
  }

  setIsAtBottom(value: boolean): void {
    if (this.deps.getIsAtBottom() === value) {
      return
    }
    this.deps.onAnimate(200, Curve.EaseOut, () => {
      this.deps.onSetIsAtBottomState(value)
    })
  }

  setInputBarVisible(value: boolean): void {
    if (this.deps.getIsInputBarVisible() === value) {
      return
    }
    this.deps.onAnimate(300, Curve.FastOutSlowIn, () => {
      this.deps.onSetInputBarVisibleState(value)
    })
  }

  handleMessageListDidScroll(scrollOffset: number, scrollState: ScrollState): boolean {
    const lastScrollOffset = this.deps.getLastScrollOffset()
    const measuredOffset = this.normalizeScrollOffset(this.deps.syncCurrentScrollOffset())
    const reportedOffset = this.normalizeScrollOffset(scrollOffset)
    const cumulativeOffset = measuredOffset > 0 ? measuredOffset : reportedOffset
    const keepPinnedToBottom = this.deps.syncIsAtBottomBoundary() ||
      (this.deps.getIsAtBottom() && this.isWithinBottomTolerance(cumulativeOffset))
    const effectiveOffset = keepPinnedToBottom ? this.resolveStableBottomOffset(cumulativeOffset) : cumulativeOffset

    this.setCurrentScrollOffset(effectiveOffset)
    const positionDelta = effectiveOffset - lastScrollOffset
    const userScrolledAwayFromBottom = !keepPinnedToBottom && positionDelta < 0 &&
      (scrollState === ScrollState.Scroll || scrollState === ScrollState.Fling)

    if (userScrolledAwayFromBottom) {
      this.clearPinnedBottomAlignmentTimers()
    }

    if (keepPinnedToBottom) {
      this.setIsAtBottom(true)
      this.setInputBarVisible(true)
    } else if (userScrolledAwayFromBottom && this.deps.getIsAtBottom()) {
      this.setIsAtBottom(false)
    }

    if (scrollState === ScrollState.Scroll && effectiveOffset > 0) {
      this.setIsAtTop(false)
    }

    if (scrollState === ScrollState.Scroll || scrollState === ScrollState.Fling) {
      if (positionDelta > this.deps.getInputBarShowThreshold()) {
        this.setInputBarVisible(true)
      } else if (positionDelta < -this.deps.getInputBarHideThreshold()) {
        if (!this.deps.getIsAtBottom() &&
          !this.deps.getIsSending() &&
          !this.deps.getIsEditingMessage() &&
          this.getCurrentScrollProgress() > 0.2) {
          this.setInputBarVisible(false)
        }
      }

      this.deps.setLastScrollOffset(effectiveOffset)
      this.updateScrollProgress()
    }

    return userScrolledAwayFromBottom
  }

  onDraftContentChanged(): void {
    if (!this.deps.getIsEditingMessage() && this.deps.getEditingMessageId() === '' &&
      this.deps.hasDraftContent()) {
      this.alignToBottomAfterLayout()
    }
  }

  scrollToBottomWithAnimation(): void {
    this.clearPinnedBottomAlignmentTimers()
    this.setIsAtBottom(true)
    this.setIsAtTop(false)
    this.setInputBarVisible(true)
    this.scrollBottomAnchor(true)
    this.captureBottomScrollBaseline()
    this.alignToBottomAfterLayout()
  }

  scrollToTopWithAnimation(): void {
    if (this.deps.messages.length <= 0) {
      return
    }
    this.clearPinnedBottomAlignmentTimers()
    this.setIsAtTop(true)
    this.setIsAtBottom(false)
    this.setInputBarVisible(true)
    this.setCurrentScrollOffset(0)
    this.setScrollProgress(0)
    this.deps.scroller.scrollEdge(Edge.Top)
    this.scrollEdgeAfterLayout(Edge.Top)
  }

  handleReachStart(): void {
    this.setCurrentScrollOffset(0)
    this.deps.setLastScrollOffset(0)
    this.setIsAtTop(true)
    this.setScrollProgress(0)
  }

  handleReachEnd(): void {
    const cumulativeOffset = this.deps.syncCurrentScrollOffset()
    this.deps.setLastScrollOffset(cumulativeOffset)
    this.setIsAtBottom(true)
    this.setInputBarVisible(true)
    this.captureBottomScrollBaseline()
  }
}
