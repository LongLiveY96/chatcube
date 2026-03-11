import { ChatMessage } from '../../models/ChatModels'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'
import {
  countSelectedIdsInCandidates,
  mergeSelectAllIds,
  removeCandidateIds,
  toggleSelectionById
} from '../../utils/SelectionHelper'
import { collectAllMessageIds, collectSelectedMessages, filterMessagesByRemovedIds } from './ChatMessageActionHelper'

export interface ChatSelectionFlowDependencies {
  chatViewModel: ChatViewModel
  messages: ChatMessage[]
  onSyncMessages: () => void
  onSetMultiSelectMode: (value: boolean) => void
  onSetSelectedMessageIds: (ids: string[]) => void
  onSetInputBarVisible: (value: boolean) => void
  onSetShareMessages: (messages: ChatMessage[]) => void
  onSetShowSharePreview: (value: boolean) => void
  onShowToast: (message: string | Resource) => void
}

export class ChatSelectionFlow {
  private deps: ChatSelectionFlowDependencies

  constructor(deps: ChatSelectionFlowDependencies) {
    this.deps = deps
  }

  enterModeWithMessage(messageId: string): void {
    this.deps.onSetMultiSelectMode(true)
    this.deps.onSetSelectedMessageIds([messageId])
    this.deps.onSetInputBarVisible(false)
  }

  exitMode(): void {
    this.deps.onSetMultiSelectMode(false)
    this.deps.onSetSelectedMessageIds([])
    this.deps.onSetInputBarVisible(true)
  }

  toggleSelection(selectedMessageIds: string[], messageId: string): string[] {
    return toggleSelectionById(selectedMessageIds, messageId)
  }

  toggleSelectAll(selectedMessageIds: string[]): string[] {
    const allIds = collectAllMessageIds(this.deps.messages)
    const selectedCount = countSelectedIdsInCandidates(selectedMessageIds, allIds)
    if (selectedCount === allIds.length) {
      return removeCandidateIds(selectedMessageIds, allIds)
    }
    return mergeSelectAllIds(selectedMessageIds, allIds)
  }

  async deleteSelectedMessages(selectedMessageIds: string[]): Promise<void> {
    if (selectedMessageIds.length === 0) {
      return
    }

    await this.deps.chatViewModel.deleteMessagesFromIndex(selectedMessageIds)
    const remainingMessages = filterMessagesByRemovedIds(this.deps.messages, selectedMessageIds)
    this.deps.messages.splice(0, this.deps.messages.length, ...remainingMessages)
    this.deps.onSyncMessages()
    this.exitMode()
    this.deps.onShowToast($r('app.string.messages_deleted'))
  }

  openSharePreview(selectedMessageIds: string[]): void {
    if (selectedMessageIds.length === 0) {
      return
    }

    const selectedMessages = collectSelectedMessages(this.deps.messages, selectedMessageIds)
    if (selectedMessages.length === 0) {
      this.deps.onShowToast($r('app.string.selected_message_not_found'))
      return
    }

    this.deps.onSetShareMessages(selectedMessages)
    this.deps.onSetShowSharePreview(true)
  }
}
