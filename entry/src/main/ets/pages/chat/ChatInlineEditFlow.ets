import { ChatMessage, MessageAttachment, ReasoningLevel } from '../../models/ChatModels'
import { MessageDataSource } from '../../datasource/MessageDataSource'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'
import { collectTailMessageIds, findMessageIndexById } from './ChatMessageActionHelper'

export class ChatInlineEditFlowDependencies {
  chatViewModel: ChatViewModel
  messageDataSource: MessageDataSource
  getMessages: () => ChatMessage[]
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

  constructor(
    chatViewModel: ChatViewModel,
    messageDataSource: MessageDataSource,
    getMessages: () => ChatMessage[],
    onSyncMessages: () => void,
    onResetEditState: () => void,
    onApplySavedDraft: (
      content: string,
      attachments: MessageAttachment[],
      webSearchEnabled: boolean,
      reasoningLevel: ReasoningLevel
    ) => void,
    onSetSending: (value: boolean) => void,
    onTriggerSend: () => void,
    onShowToast: (message: string | Resource) => void
  ) {
    this.chatViewModel = chatViewModel
    this.messageDataSource = messageDataSource
    this.getMessages = getMessages
    this.onSyncMessages = onSyncMessages
    this.onResetEditState = onResetEditState
    this.onApplySavedDraft = onApplySavedDraft
    this.onSetSending = onSetSending
    this.onTriggerSend = onTriggerSend
    this.onShowToast = onShowToast
  }
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
      const savedWebSearch = editingWebSearchEnabled
      const savedReasoningLevel = editingReasoningLevel
      const messageIdsToDelete = collectTailMessageIds(messages, messageIndex)

      await this.deps.chatViewModel.deleteMessagesFromIndex(messageIdsToDelete)
      const remainingMessages = messages.slice(0, messageIndex)
      this.deps.messageDataSource.setAllMessages(remainingMessages)
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
