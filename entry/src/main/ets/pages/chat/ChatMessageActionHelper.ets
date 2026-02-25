import { ChatMessage, MessageRole } from '../../models/ChatModels'

export function findMessageIndexById(messages: ChatMessage[], messageId: string): number {
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].id === messageId) {
      return i
    }
  }
  return -1
}

export function resolveUserMessageIndexForRegenerate(messages: ChatMessage[], targetMessage: ChatMessage): number {
  const index = findMessageIndexById(messages, targetMessage.id)
  if (index < 0) {
    return -1
  }
  if (targetMessage.role === MessageRole.USER) {
    return index
  }
  for (let i = index - 1; i >= 0; i--) {
    if (messages[i].role === MessageRole.USER) {
      return i
    }
  }
  return -1
}

export function collectTailMessageIds(messages: ChatMessage[], startIndex: number): string[] {
  const ids: string[] = []
  if (startIndex < 0 || startIndex >= messages.length) {
    return ids
  }
  for (let i = startIndex; i < messages.length; i++) {
    ids.push(messages[i].id)
  }
  return ids
}

export function collectSelectedMessages(messages: ChatMessage[], selectedIds: string[]): ChatMessage[] {
  const selectedMessages: ChatMessage[] = []
  for (let i = 0; i < messages.length; i++) {
    if (selectedIds.includes(messages[i].id)) {
      selectedMessages.push(messages[i])
    }
  }
  return selectedMessages
}

export function filterMessagesByRemovedIds(messages: ChatMessage[], removedIds: string[]): ChatMessage[] {
  const remainingMessages: ChatMessage[] = []
  for (let i = 0; i < messages.length; i++) {
    if (!removedIds.includes(messages[i].id)) {
      remainingMessages.push(messages[i])
    }
  }
  return remainingMessages
}

export function collectAllMessageIds(messages: ChatMessage[]): string[] {
  const ids: string[] = []
  for (let i = 0; i < messages.length; i++) {
    ids.push(messages[i].id)
  }
  return ids
}

export function toListScrollIndexForMessage(messageIndex: number): number {
  return messageIndex + 1
}
