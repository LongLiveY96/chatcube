import { ChatMessage } from '../../models/ChatModels'

export interface ChatScrollUiFlowDependencies {
  scroller: Scroller
  messages: ChatMessage[]
  getLastScrollOffset: () => number
  setLastScrollOffset: (value: number) => void
  getInputBarShowThreshold: () => number
  getInputBarHideThreshold: () => number
  getIsAtTop: () => boolean
  getIsAtBottom: () => boolean
  getIsInputBarVisible: () => boolean
  getIsSending: () => boolean
  getIsInputFocused: () => boolean
  getIsEditingMessage: () => boolean
  getEditingMessageId: () => string
  hasDraftContent: () => boolean
  onSetIsAtTopState: (value: boolean) => void
  onSetIsAtBottomState: (value: boolean) => void
  onSetInputBarVisibleState: (value: boolean) => void
  onAnimate: (duration: number, curve: Curve, updater: () => void) => void
}

export class ChatScrollUiFlow {
  private deps: ChatScrollUiFlowDependencies

  constructor(deps: ChatScrollUiFlowDependencies) {
    this.deps = deps
  }

  private scrollEdgeAfterLayout(edge: Edge): void {
    setTimeout(() => {
      this.deps.scroller.scrollEdge(edge)
    }, 0)
    setTimeout(() => {
      this.deps.scroller.scrollEdge(edge)
    }, 50)
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

  handleMessageListDidScroll(scrollOffset: number, scrollState: ScrollState): void {
    if (scrollState === ScrollState.Scroll && scrollOffset < 0) {
      this.setIsAtBottom(false)
    }

    if (scrollState === ScrollState.Scroll && scrollOffset !== 0) {
      this.setIsAtTop(false)
    }

    if (scrollState === ScrollState.Scroll || scrollState === ScrollState.Fling) {
      const offsetDelta = scrollOffset - this.deps.getLastScrollOffset()

      if (offsetDelta > this.deps.getInputBarShowThreshold()) {
        this.setInputBarVisible(true)
      } else if (scrollState === ScrollState.Scroll && offsetDelta < -this.deps.getInputBarHideThreshold()) {
        if (!this.deps.getIsAtBottom() &&
          !this.deps.getIsSending() &&
          !this.deps.hasDraftContent() &&
          !this.deps.getIsInputFocused() &&
          !this.deps.getIsEditingMessage()) {
          this.setInputBarVisible(false)
        }
      }

      this.deps.setLastScrollOffset(scrollOffset)
    }
  }

  onDraftContentChanged(): void {
    if (!this.deps.getIsEditingMessage() && this.deps.getEditingMessageId() === '' &&
      this.deps.hasDraftContent()) {
      setTimeout(() => {
        this.deps.scroller.scrollEdge(Edge.Bottom)
      }, 50)
    }
  }

  scrollToBottomWithAnimation(): void {
    this.setIsAtBottom(true)
    this.setIsAtTop(false)
    this.setInputBarVisible(true)
    this.deps.scroller.scrollEdge(Edge.Bottom)
    this.scrollEdgeAfterLayout(Edge.Bottom)
  }

  scrollToTopWithAnimation(): void {
    if (this.deps.messages.length <= 0) {
      return
    }
    this.setIsAtTop(true)
    this.setIsAtBottom(false)
    this.setInputBarVisible(true)
    this.deps.scroller.scrollEdge(Edge.Top)
  }
}
