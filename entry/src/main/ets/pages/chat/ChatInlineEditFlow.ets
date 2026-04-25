import { ChatMessage, MessageAttachment, ReasoningLevel } from '../../models/ChatModels'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'
import { collectTailMessageIds, findMessageIndexById } from './ChatMessageActionHelper'

export interface ChatInlineEditFlowDependencies {
  chatViewModel: ChatViewModel
  getMessages: () => ChatMessage[]
  onValidateBeforeCommit: (
    content: string,
    attachments: MessageAttachment[],
    webSearchEnabled: boolean,
    selectedToolIds: string[],
    reasoningLevel: ReasoningLevel,
    reasoningBudget: number
  ) => boolean
  onSyncMessages: () => void
  onResetEditState: () => void
  onApplySavedDraft: (
    content: string,
    attachments: MessageAttachment[],
    webSearchEnabled: boolean,
    selectedToolIds: string[],
    reasoningLevel: ReasoningLevel,
    reasoningBudget: number
  ) => void
  onTriggerSend: (
    content: string,
    attachments: MessageAttachment[],
    webSearchEnabled: boolean,
    selectedToolIds: string[],
    reasoningLevel: ReasoningLevel,
    reasoningBudget: number
  ) => Promise<void>
  onShowToast: (message: string | Resource) => void
}

export class ChatInlineEditFlow {
  private deps: ChatInlineEditFlowDependencies

  constructor(deps: ChatInlineEditFlowDependencies) {
    this.deps = deps
  }

  async saveAndSendInline(
    editingMessageId: string,
    inputText: string,
    pendingAttachments: MessageAttachment[],
    editingWebSearchEnabled: boolean,
    editingSelectedToolIds: string[],
    editingReasoningLevel: ReasoningLevel,
    editingReasoningBudget: number
  ): Promise<void> {
    if (editingMessageId === '') {
      console.warn('ChatInlineEditFlow', '[saveAndSendInline] editingMessageId is empty')
      return
    }

    const messages = this.deps.getMessages()
    const messageIndex = findMessageIndexById(messages, editingMessageId)
    if (messageIndex < 0) {
      console.warn('ChatInlineEditFlow', '[saveAndSendInline] message not found:', editingMessageId)
      return
    }

    const hasContent = inputText.trim() !== ''
    const hasAttachments = pendingAttachments.length > 0
    if (!hasContent && !hasAttachments) {
      this.deps.onShowToast($r('app.string.message_content_empty'))
      return
    }

    try {
      const savedAttachments = pendingAttachments.slice()
      const savedContent = inputText.trim()
      const savedWebSearchEnabled = editingWebSearchEnabled
      const savedToolIds = [...editingSelectedToolIds]
      const savedReasoningLevel = editingReasoningLevel
      const savedReasoningBudget = editingReasoningBudget

      // 在真正改写消息链之前，先复用正常发送链路做一次前置校验。
      // 失败时保留原消息和当前编辑态，避免“内容没了但也没发出去”的烂体验。
      const canCommit = this.deps.onValidateBeforeCommit(
        savedContent,
        savedAttachments,
        savedWebSearchEnabled,
        savedToolIds,
        savedReasoningLevel,
        savedReasoningBudget
      )
      if (!canCommit) {
        return
      }

      const messageIdsToDelete = collectTailMessageIds(messages, messageIndex)

      await this.deps.chatViewModel.deleteMessagesFromIndex(messageIdsToDelete)
      this.deps.getMessages().splice(messageIndex)
      this.deps.onSyncMessages()

      this.deps.onResetEditState()
      this.deps.onApplySavedDraft(
        savedContent,
        savedAttachments,
        savedWebSearchEnabled,
        savedToolIds,
        savedReasoningLevel,
        savedReasoningBudget
      )
      await this.deps.onTriggerSend(
        savedContent,
        savedAttachments,
        savedWebSearchEnabled,
        savedToolIds,
        savedReasoningLevel,
        savedReasoningBudget
      )
    } catch (error) {
      console.error('ChatInlineEditFlow', `[saveAndSendInline] Error: ${JSON.stringify(error)}`)
      this.deps.onShowToast($r('app.string.action_failed_retry'))
    }
  }
}
