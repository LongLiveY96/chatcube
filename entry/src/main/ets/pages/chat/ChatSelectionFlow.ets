import { ChatMessage } from '../../models/ChatModels'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'
import { MessageDataSource } from '../../datasource/MessageDataSource'
import {
  countSelectedIdsInCandidates,
  mergeSelectAllIds,
  removeCandidateIds,
  toggleSelectionById
} from '../../utils/SelectionHelper'
import { collectAllMessageIds, collectSelectedMessages, filterMessagesByRemovedIds } from './ChatMessageActionHelper'

export class ChatSelectionFlowDependencies {
  chatViewModel: ChatViewModel
  messageDataSource: MessageDataSource
  getMessages: () => ChatMessage[]
  onSetMessages: (messages: ChatMessage[]) => void
  onSyncMessages: () => void
  onSetMultiSelectMode: (value: boolean) => void
  onSetSelectedMessageIds: (ids: string[]) => void
  onSetInputBarVisible: (value: boolean) => void
  onSetShareMessages: (messages: ChatMessage[]) => void
  onSetShowSharePreview: (value: boolean) => void
  onShowToast: (message: string | Resource) => void

  constructor(
    chatViewModel: ChatViewModel,
    messageDataSource: MessageDataSource,
    getMessages: () => ChatMessage[],
    onSetMessages: (messages: ChatMessage[]) => void,
    onSyncMessages: () => void,
    onSetMultiSelectMode: (value: boolean) => void,
    onSetSelectedMessageIds: (ids: string[]) => void,
    onSetInputBarVisible: (value: boolean) => void,
    onSetShareMessages: (messages: ChatMessage[]) => void,
    onSetShowSharePreview: (value: boolean) => void,
    onShowToast: (message: string | Resource) => void
  ) {
    this.chatViewModel = chatViewModel
    this.messageDataSource = messageDataSource
    this.getMessages = getMessages
    this.onSetMessages = onSetMessages
    this.onSyncMessages = onSyncMessages
    this.onSetMultiSelectMode = onSetMultiSelectMode
    this.onSetSelectedMessageIds = onSetSelectedMessageIds
    this.onSetInputBarVisible = onSetInputBarVisible
    this.onSetShareMessages = onSetShareMessages
    this.onSetShowSharePreview = onSetShowSharePreview
    this.onShowToast = onShowToast
  }
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
    const allIds = collectAllMessageIds(this.deps.getMessages())
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
    const remainingMessages = filterMessagesByRemovedIds(this.deps.getMessages(), selectedMessageIds)
    this.deps.onSetMessages(remainingMessages)
    this.deps.messageDataSource.setAllMessages(remainingMessages)
    this.deps.onSyncMessages()
    this.exitMode()
    this.deps.onShowToast($r('app.string.messages_deleted'))
  }

  openSharePreview(selectedMessageIds: string[]): void {
    if (selectedMessageIds.length === 0) {
      return
    }

    const selectedMessages = collectSelectedMessages(this.deps.getMessages(), selectedMessageIds)
    if (selectedMessages.length === 0) {
      this.deps.onShowToast($r('app.string.selected_message_not_found'))
      return
    }

    this.deps.onSetShareMessages(selectedMessages)
    this.deps.onSetShowSharePreview(true)
  }
}
