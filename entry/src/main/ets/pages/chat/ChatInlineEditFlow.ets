import { ChatMessage, MessageAttachment, ReasoningLevel } from '../../models/ChatModels'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'
import { collectTailMessageIds, findMessageIndexById } from './ChatMessageActionHelper'

export interface ChatInlineEditFlowDependencies {
  chatViewModel: ChatViewModel
  messages: ChatMessage[]
  onSyncMessages: () => void
  onResetEditState: () => void
  onApplySavedDraft: (
    content: string,
    attachments: MessageAttachment[],
    webSearchEnabled: boolean,
    reasoningLevel: ReasoningLevel
  ) => void
  onSetSending: (value: boolean) => void
  onTriggerSend: () => void
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
    editingReasoningLevel: ReasoningLevel
  ): Promise<void> {
    if (editingMessageId === '') {
      console.warn('ChatInlineEditFlow', '[saveAndSendInline] editingMessageId is empty')
      return
    }

    const messageIndex = findMessageIndexById(this.deps.messages, editingMessageId)
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
      const savedWebSearch = editingWebSearchEnabled
      const savedReasoningLevel = editingReasoningLevel
      const messageIdsToDelete = collectTailMessageIds(this.deps.messages, messageIndex)

      await this.deps.chatViewModel.deleteMessagesFromIndex(messageIdsToDelete)
      this.deps.messages.splice(messageIndex)
      this.deps.onSyncMessages()

      this.deps.onResetEditState()
      this.deps.onApplySavedDraft(savedContent, savedAttachments, savedWebSearch, savedReasoningLevel)
      this.deps.onSetSending(false)

      setTimeout(() => {
        this.deps.onTriggerSend()
      }, 50)
    } catch (error) {
      console.error('ChatInlineEditFlow', `[saveAndSendInline] Error: ${JSON.stringify(error)}`)
      this.deps.onShowToast($r('app.string.action_failed_retry'))
    }
  }
}
