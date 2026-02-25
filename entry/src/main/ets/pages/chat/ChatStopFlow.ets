import { MessageRole } from '../../models/ChatModels'
import { MessageDataSource } from '../../datasource/MessageDataSource'
import { ChatTaskOrchestratorService } from '../../services/ChatTaskOrchestratorService'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'

export class ChatStopFlowDependencies {
  chatViewModel: ChatViewModel
  chatTaskOrchestrator: ChatTaskOrchestratorService
  messageDataSource: MessageDataSource
  getCurrentTaskId: () => string
  onSetCurrentTaskId: (taskId: string) => void
  onSetSearchCancelled: (value: boolean) => void
  onCancelManualSearchRequests: () => void
  onSyncMessages: () => void
  onSetSending: (value: boolean) => void
  onSetLoading: (value: boolean) => void
  onClearForcedToolIds: () => void
  onMarkAutoTaskFailed: (message: string) => void

  constructor(
    chatViewModel: ChatViewModel,
    chatTaskOrchestrator: ChatTaskOrchestratorService,
    messageDataSource: MessageDataSource,
    getCurrentTaskId: () => string,
    onSetCurrentTaskId: (taskId: string) => void,
    onSetSearchCancelled: (value: boolean) => void,
    onCancelManualSearchRequests: () => void,
    onSyncMessages: () => void,
    onSetSending: (value: boolean) => void,
    onSetLoading: (value: boolean) => void,
    onClearForcedToolIds: () => void,
    onMarkAutoTaskFailed: (message: string) => void
  ) {
    this.chatViewModel = chatViewModel
    this.chatTaskOrchestrator = chatTaskOrchestrator
    this.messageDataSource = messageDataSource
    this.getCurrentTaskId = getCurrentTaskId
    this.onSetCurrentTaskId = onSetCurrentTaskId
    this.onSetSearchCancelled = onSetSearchCancelled
    this.onCancelManualSearchRequests = onCancelManualSearchRequests
    this.onSyncMessages = onSyncMessages
    this.onSetSending = onSetSending
    this.onSetLoading = onSetLoading
    this.onClearForcedToolIds = onClearForcedToolIds
    this.onMarkAutoTaskFailed = onMarkAutoTaskFailed
  }
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
    if (this.deps.messageDataSource.totalCount() <= 0) {
      return
    }

    const lastMessage = this.deps.messageDataSource.getData(this.deps.messageDataSource.totalCount() - 1)
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
      this.deps.messageDataSource.removeMessageById(lastMessage.id)
      this.deps.chatViewModel.discardPendingAIMessage(lastMessage.id)
      this.deps.onSyncMessages()
      console.info('ChatStopFlow', '[stopCurrentTask] 移除停止后空白的临时 AI 消息')
      return
    }

    let needUpdate = false
    if (lastMessage.isGenerating) {
      lastMessage.isGenerating = false
      needUpdate = true
    }
    if (lastMessage.isSearching) {
      lastMessage.isSearching = false
      needUpdate = true
    }
    if (!needUpdate) {
      return
    }

    this.deps.messageDataSource.notifyLastMessageChanged()
    this.deps.onSyncMessages()
  }
}
