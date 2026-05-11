/**
 * MessagePart 数据模型
 *
 * 用于替代 ChatMessage 扁平的 content / reasoningContent / toolCalls / toolResults 四元字段,
 * 以顺序列表形式表达助手消息的真实生成时序, 支持 reasoning↔tool↔text 交错渲染。
 *
 * ArkTS 不支持判别联合类型(discriminated union), 因此用一个带 kind 字段的 class 承载所有
 * 变体字段; 取数时按 kind 判断再访问对应字段。未使用的字段留空。
 *
 * 本文件刻意不 import ChatModels, 避免和 ChatMessage/ToolCall 产生循环依赖。
 * 从 ToolCall/ToolResult 构造 MessagePart 的逻辑放在调用方(ChatMessagePartsHelper)里。
 */

export enum MessagePartKind {
  TEXT = 'text',
  REASONING = 'reasoning',
  TOOL = 'tool',
  IMAGE = 'image',
  VIDEO = 'video',
  AUDIO = 'audio',
  DOCUMENT = 'document'
}

export enum ToolPartStatus {
  // 工具调用已发起,尚未执行(还在流式累积参数 / 等待外部审批)
  PENDING = 'pending',
  // 工具执行中
  RUNNING = 'running',
  // 工具执行成功
  SUCCEEDED = 'succeeded',
  // 工具执行失败
  FAILED = 'failed',
  // 用户人工拒绝(配合审批机制)
  DENIED = 'denied',
  // 人工答复 (ask_user)
  ANSWERED = 'answered'
}

@ObservedV2
export class MessagePart {
  @Trace kind: MessagePartKind = MessagePartKind.TEXT

  // text / reasoning 公用
  @Trace text: string = ''

  // reasoning 字段
  @Trace reasoningCreatedAt: number = 0
  @Trace reasoningFinishedAt: number = 0

  // tool 字段
  @Trace toolCallId: string = ''
  @Trace toolName: string = ''
  @Trace toolDisplayName: string = ''
  @Trace toolArguments: string = ''      // 原始参数 JSON 字符串
  @Trace toolResult: string = ''         // 原始结果 JSON 字符串(空表示尚未执行)
  @Trace toolIsError: boolean = false
  @Trace toolStatus: string = ToolPartStatus.PENDING  // 取值为 ToolPartStatus 枚举字符串
  @Trace toolSourceType: string = ''
  @Trace toolSourceLabel: string = ''
  @Trace toolPermissionLevel: string = ''
  @Trace toolApprovalReason: string = '' // 人工拒绝时的原因/答复

  // 媒体字段 (image/video/audio/document)
  @Trace mediaUrl: string = ''
  @Trace mediaMime: string = ''
  @Trace mediaName: string = ''

  constructor(kind: MessagePartKind = MessagePartKind.TEXT) {
    this.kind = kind
  }

  static text(content: string): MessagePart {
    const part = new MessagePart(MessagePartKind.TEXT)
    part.text = content
    return part
  }

  static reasoning(content: string, createdAt: number = Date.now()): MessagePart {
    const part = new MessagePart(MessagePartKind.REASONING)
    part.text = content
    part.reasoningCreatedAt = createdAt
    part.reasoningFinishedAt = 0
    return part
  }
}

// JSON 持久化结构(用于数据库和导入导出)
export interface MessagePartJson {
  kind: string
  text?: string
  reasoningCreatedAt?: number
  reasoningFinishedAt?: number
  toolCallId?: string
  toolName?: string
  toolDisplayName?: string
  toolArguments?: string
  toolResult?: string
  toolIsError?: boolean
  toolStatus?: string
  toolSourceType?: string
  toolSourceLabel?: string
  toolPermissionLevel?: string
  toolApprovalReason?: string
  mediaUrl?: string
  mediaMime?: string
  mediaName?: string
}

export function messagePartToJson(part: MessagePart): MessagePartJson {
  const json: MessagePartJson = { kind: part.kind }
  if (part.text !== '') {
    json.text = part.text
  }
  if (part.reasoningCreatedAt !== 0) {
    json.reasoningCreatedAt = part.reasoningCreatedAt
  }
  if (part.reasoningFinishedAt !== 0) {
    json.reasoningFinishedAt = part.reasoningFinishedAt
  }
  if (part.toolCallId !== '') {
    json.toolCallId = part.toolCallId
  }
  if (part.toolName !== '') {
    json.toolName = part.toolName
  }
  if (part.toolDisplayName !== '') {
    json.toolDisplayName = part.toolDisplayName
  }
  if (part.toolArguments !== '') {
    json.toolArguments = part.toolArguments
  }
  if (part.toolResult !== '') {
    json.toolResult = part.toolResult
  }
  if (part.toolIsError) {
    json.toolIsError = part.toolIsError
  }
  if (part.toolStatus !== '' && part.toolStatus !== ToolPartStatus.PENDING) {
    json.toolStatus = part.toolStatus
  }
  if (part.toolSourceType !== '') {
    json.toolSourceType = part.toolSourceType
  }
  if (part.toolSourceLabel !== '') {
    json.toolSourceLabel = part.toolSourceLabel
  }
  if (part.toolPermissionLevel !== '') {
    json.toolPermissionLevel = part.toolPermissionLevel
  }
  if (part.toolApprovalReason !== '') {
    json.toolApprovalReason = part.toolApprovalReason
  }
  if (part.mediaUrl !== '') {
    json.mediaUrl = part.mediaUrl
  }
  if (part.mediaMime !== '') {
    json.mediaMime = part.mediaMime
  }
  if (part.mediaName !== '') {
    json.mediaName = part.mediaName
  }
  return json
}

export function messagePartFromJson(json: MessagePartJson): MessagePart {
  let kind: MessagePartKind = MessagePartKind.TEXT
  switch (json.kind) {
    case MessagePartKind.REASONING:
      kind = MessagePartKind.REASONING
      break
    case MessagePartKind.TOOL:
      kind = MessagePartKind.TOOL
      break
    case MessagePartKind.IMAGE:
      kind = MessagePartKind.IMAGE
      break
    case MessagePartKind.VIDEO:
      kind = MessagePartKind.VIDEO
      break
    case MessagePartKind.AUDIO:
      kind = MessagePartKind.AUDIO
      break
    case MessagePartKind.DOCUMENT:
      kind = MessagePartKind.DOCUMENT
      break
    default:
      kind = MessagePartKind.TEXT
  }
  const part = new MessagePart(kind)
  part.text = json.text ?? ''
  part.reasoningCreatedAt = json.reasoningCreatedAt ?? 0
  part.reasoningFinishedAt = json.reasoningFinishedAt ?? 0
  part.toolCallId = json.toolCallId ?? ''
  part.toolName = json.toolName ?? ''
  part.toolDisplayName = json.toolDisplayName ?? ''
  part.toolArguments = json.toolArguments ?? ''
  part.toolResult = json.toolResult ?? ''
  part.toolIsError = json.toolIsError === true
  part.toolStatus = json.toolStatus !== undefined ? json.toolStatus : ToolPartStatus.PENDING
  part.toolSourceType = json.toolSourceType ?? ''
  part.toolSourceLabel = json.toolSourceLabel ?? ''
  part.toolPermissionLevel = json.toolPermissionLevel ?? ''
  part.toolApprovalReason = json.toolApprovalReason ?? ''
  part.mediaUrl = json.mediaUrl ?? ''
  part.mediaMime = json.mediaMime ?? ''
  part.mediaName = json.mediaName ?? ''
  return part
}

export function serializeMessageParts(parts: MessagePart[]): string {
  if (parts.length === 0) {
    return ''
  }
  const array: MessagePartJson[] = []
  for (let i = 0; i < parts.length; i++) {
    array.push(messagePartToJson(parts[i]))
  }
  try {
    return JSON.stringify(array)
  } catch (_e) {
    return ''
  }
}

export function deserializeMessageParts(text: string): MessagePart[] {
  if (text.trim() === '') {
    return []
  }
  try {
    const raw = JSON.parse(text) as Object
    if (!Array.isArray(raw)) {
      return []
    }
    const arr = raw as MessagePartJson[]
    const out: MessagePart[] = []
    for (let i = 0; i < arr.length; i++) {
      out.push(messagePartFromJson(arr[i]))
    }
    return out
  } catch (_e) {
    return []
  }
}
