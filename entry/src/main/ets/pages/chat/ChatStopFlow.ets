import { ChatMessage, MessageRole } from '../../models/ChatModels'
import { ChatTaskOrchestratorService } from '../../services/ChatTaskOrchestratorService'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'

export interface ChatStopFlowDependencies {
  chatViewModel: ChatViewModel
  chatTaskOrchestrator: ChatTaskOrchestratorService
  messages: ChatMessage[]
  getCurrentTaskId: () => string
  onSetCurrentTaskId: (taskId: string) => void
  onSetSearchCancelled: (value: boolean) => void
  onCancelManualSearchRequests: () => void
  onSyncMessages: () => void
  onSetSending: (value: boolean) => void
  onSetLoading: (value: boolean) => void
  onClearForcedToolIds: () => void
  onMarkAutoTaskFailed: (message: string) => void
}

export class ChatStopFlow {
  private deps: ChatStopFlowDependencies

  constructor(deps: ChatStopFlowDependencies) {
    this.deps = deps
  }

  stopCurrentTask(): void {
    this.deps.onSetSearchCancelled(true)
    this.deps.onCancelManualSearchRequests()

    const currentTaskId = this.deps.getCurrentTaskId()
    if (currentTaskId !== '') {
      this.deps.chatTaskOrchestrator.cancelTask(currentTaskId)
      this.deps.onSetCurrentTaskId('')
    } else {
      this.deps.chatViewModel.stopGeneration()
    }

    this.resetLastAssistantMessageState()

    this.deps.onSetSending(false)
    this.deps.onSetLoading(false)
    this.deps.onClearForcedToolIds()
    this.deps.onMarkAutoTaskFailed('用户已取消任务')
  }

  private resetLastAssistantMessageState(): void {
    if (this.deps.messages.length <= 0) {
      return
    }

    const lastMessage = this.deps.messages[this.deps.messages.length - 1]
    if (lastMessage.role !== MessageRole.ASSISTANT) {
      return
    }

    const isEmptyAssistantPlaceholder =
      lastMessage.content.trim().length === 0 &&
      lastMessage.reasoningContent.trim().length === 0 &&
      lastMessage.attachments.length === 0 &&
      lastMessage.searchReferences.length === 0 &&
      lastMessage.toolCalls.length === 0 &&
      lastMessage.toolResults.length === 0
    if (isEmptyAssistantPlaceholder && (lastMessage.isSearching || lastMessage.isGenerating)) {
      const idx = this.deps.messages.findIndex((m: ChatMessage) => m.id === lastMessage.id)
      if (idx >= 0) {
        this.deps.messages.splice(idx, 1)
      }
      this.deps.chatViewModel.discardPendingAIMessage(lastMessage.id)
      this.deps.onSyncMessages()
      console.info('ChatStopFlow', '[stopCurrentTask] 移除停止后空白的临时 AI 消息')
      return
    }

    if (lastMessage.isGenerating) {
      lastMessage.isGenerating = false
    }
    if (lastMessage.isSearching) {
      lastMessage.isSearching = false
    }
    this.deps.onSyncMessages()
  }
}
