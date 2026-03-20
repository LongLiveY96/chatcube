import { ChatMessage, MessageAttachment, SearchReference, ToolCall, ToolResult } from '../../models/ChatModels'

function encodeValue(value: string): string {
  return `${value.length}:${value};`
}

function encodeNumber(value: number): string {
  return encodeValue(value.toString())
}

function encodeBoolean(value: boolean): string {
  return encodeValue(value ? '1' : '0')
}

function buildSearchReferenceSignature(reference: SearchReference): string {
  return [
    encodeValue(reference.id),
    encodeValue(reference.title),
    encodeValue(reference.url),
    encodeValue(reference.snippet),
    encodeNumber(reference.timestamp)
  ].join('')
}

function buildToolCallSignature(toolCall: ToolCall): string {
  return [
    encodeValue(toolCall.id),
    encodeValue(toolCall.type),
    encodeValue(toolCall.functionName),
    encodeValue(toolCall.arguments),
    encodeValue(toolCall.toolId),
    encodeValue(toolCall.displayName),
    encodeValue(toolCall.sourceType),
    encodeValue(toolCall.sourceLabel),
    encodeValue(toolCall.permissionLevel)
  ].join('')
}

function buildToolResultSignature(toolResult: ToolResult): string {
  return [
    encodeValue(toolResult.toolCallId),
    encodeValue(toolResult.content),
    encodeBoolean(toolResult.isError),
    encodeValue(toolResult.displayName),
    encodeValue(toolResult.sourceLabel)
  ].join('')
}

function buildStringListSignature(items: string[]): string {
  let signature = encodeNumber(items.length)
  for (let i = 0; i < items.length; i++) {
    signature += encodeValue(items[i])
  }
  return signature
}

function buildAttachmentSignature(attachments: MessageAttachment[]): string {
  const segments: string[] = [encodeNumber(attachments.length)]
  for (let i = 0; i < attachments.length; i++) {
    const attachment = attachments[i]
    segments.push([
      encodeValue(attachment.id),
      encodeValue(attachment.type),
      encodeValue(attachment.name),
      encodeValue(attachment.filePath),
      encodeValue(attachment.mimeType),
      encodeNumber(attachment.size),
      encodeNumber(attachment.base64Data.length)
    ].join(''))
  }
  return segments.join('')
}

function buildSearchReferenceListSignature(searchReferences: SearchReference[]): string {
  const signatures: string[] = []
  for (let i = 0; i < searchReferences.length; i++) {
    signatures.push(buildSearchReferenceSignature(searchReferences[i]))
  }
  return buildStringListSignature(signatures)
}

function buildToolCallListSignature(toolCalls: ToolCall[]): string {
  const signatures: string[] = []
  for (let i = 0; i < toolCalls.length; i++) {
    signatures.push(buildToolCallSignature(toolCalls[i]))
  }
  return buildStringListSignature(signatures)
}

function buildToolResultListSignature(toolResults: ToolResult[]): string {
  const signatures: string[] = []
  for (let i = 0; i < toolResults.length; i++) {
    signatures.push(buildToolResultSignature(toolResults[i]))
  }
  return buildStringListSignature(signatures)
}

export function buildChatMessageRowRenderSignature(
  message: ChatMessage,
  showDateDivider: boolean,
  showHeader: boolean,
  isSelected: boolean,
  isEditing: boolean,
  isDimmed: boolean,
  currentModelId: string,
  chatFontSize: number,
  themeRenderKey: string,
  previewContent: string = '',
  previewAttachments: MessageAttachment[] = []
): string {
  return [
    encodeValue(message.id),
    encodeValue(message.role),
    encodeNumber(message.timestamp),
    encodeBoolean(showDateDivider),
    encodeBoolean(showHeader),
    encodeBoolean(isSelected),
    encodeBoolean(isEditing),
    encodeBoolean(isDimmed),
    encodeBoolean(message.isGenerating),
    encodeBoolean(message.isSearching),
    encodeValue(currentModelId),
    encodeNumber(chatFontSize),
    encodeValue(themeRenderKey),
    encodeValue(message.modelId),
    encodeValue(message.modelName),
    encodeValue(message.content),
    encodeValue(message.reasoningContent),
    encodeValue(message.searchQuery),
    encodeValue(message.searchEngine),
    encodeValue(message.searchSource),
    buildAttachmentSignature(message.attachments),
    buildSearchReferenceListSignature(message.searchReferences),
    buildToolCallListSignature(message.toolCalls),
    buildToolResultListSignature(message.toolResults),
    encodeValue(message.toolCallId),
    encodeValue(isEditing ? previewContent : ''),
    isEditing ? buildAttachmentSignature(previewAttachments) : buildAttachmentSignature([])
  ].join('')
}

export class ChatMessageRowData {
  message: ChatMessage
  showDateDivider: boolean
  showHeader: boolean
  isSelected: boolean
  isEditing: boolean
  isDimmed: boolean
  renderSignature: string
  private readonly renderKey: string

  constructor(
    message: ChatMessage,
    showDateDivider: boolean,
    showHeader: boolean,
    isSelected: boolean,
    isEditing: boolean,
    isDimmed: boolean,
    renderSignature: string
  ) {
    this.message = message
    this.showDateDivider = showDateDivider
    this.showHeader = showHeader
    this.isSelected = isSelected
    this.isEditing = isEditing
    this.isDimmed = isDimmed
    this.renderSignature = renderSignature
    this.renderKey = `${message.id}|${renderSignature}`
  }

  get key(): string {
    return this.renderKey
  }

  get stableId(): string {
    return this.message.id
  }
}

export class ChatMessageListDataSource implements IDataSource {
  private items: ChatMessageRowData[] = []
  private listeners: DataChangeListener[] = []

  constructor(items: ChatMessageRowData[] = []) {
    this.items = items
  }

  totalCount(): number {
    return this.items.length
  }

  getData(index: number): ChatMessageRowData {
    return this.items[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.includes(listener)) {
      return
    }
    this.listeners.push(listener)
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener)
  }

  setItems(items: ChatMessageRowData[], forceReload: boolean = false): void {
    const previousItems = this.items
    this.items = items

    if (forceReload) {
      this.notifyDataReloaded()
      return
    }

    if (previousItems.length !== items.length) {
      this.notifyDataReloaded()
      return
    }

    for (let i = 0; i < items.length; i++) {
      if (previousItems[i].stableId !== items[i].stableId) {
        this.notifyDataReloaded()
        return
      }
    }

    const changedIndexes: number[] = []
    for (let i = 0; i < items.length; i++) {
      if (this.hasRowStateChanged(previousItems[i], items[i])) {
        changedIndexes.push(i)
      }
    }

    if (changedIndexes.length <= 0) {
      return
    }
    this.notifyDataChanged(changedIndexes)
  }

  private hasRowStateChanged(previousItem: ChatMessageRowData, nextItem: ChatMessageRowData): boolean {
    return previousItem.renderSignature !== nextItem.renderSignature
  }

  private notifyDataReloaded(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }

  private notifyDataChanged(indexes: number[]): void {
    for (let listenerIndex = 0; listenerIndex < this.listeners.length; listenerIndex++) {
      const listener = this.listeners[listenerIndex]
      for (let index = 0; index < indexes.length; index++) {
        listener.onDataChange(indexes[index])
      }
    }
  }
}
