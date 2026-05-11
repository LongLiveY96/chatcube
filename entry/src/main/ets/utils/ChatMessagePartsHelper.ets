/**
 * ChatMessage 旧字段(content/reasoningContent/toolCalls/toolResults)和新 parts 结构之间的桥接。
 *
 * 写流程保持 ChatViewModel 仍然写旧字段,这里在保存/渲染前 "按需" 合成 parts。
 * 读流程优先用 message.parts;为空时 fallback 到旧字段合成的保守顺序,
 * 以便旧会话仍能正常展示。
 */

import { ChatMessage, ToolCall, ToolResult } from '../models/ChatModels'
import {
  MessagePart,
  MessagePartKind,
  ToolPartStatus
} from '../models/MessageParts'

export function createToolPart(toolCall: ToolCall, result: ToolResult | null): MessagePart {
  const part = new MessagePart(MessagePartKind.TOOL)
  part.toolCallId = toolCall.id
  part.toolName = toolCall.functionName
  part.toolDisplayName = toolCall.displayName
  part.toolArguments = toolCall.arguments
  part.toolSourceType = toolCall.sourceType
  part.toolSourceLabel = toolCall.sourceLabel
  part.toolPermissionLevel = toolCall.permissionLevel
  if (result !== null) {
    part.toolResult = result.content
    part.toolIsError = result.isError
    part.toolStatus = result.isError ? ToolPartStatus.FAILED : ToolPartStatus.SUCCEEDED
  } else {
    part.toolStatus = ToolPartStatus.PENDING
  }
  return part
}

/**
 * 消息已经有 parts 时直接返回;否则用旧字段合成一个保守的顺序 parts,
 * 仅用于 UI 渲染,不写回到 message.parts(避免污染未完成消息)。
 */
export function resolveMessageParts(message: ChatMessage): MessagePart[] {
  if (message.parts.length > 0) {
    return message.parts
  }
  const parts: MessagePart[] = []
  if (message.reasoningContent.trim() !== '') {
    parts.push(MessagePart.reasoning(message.reasoningContent))
  }
  for (let i = 0; i < message.toolCalls.length; i++) {
    const result = i < message.toolResults.length ? message.toolResults[i] : null
    parts.push(createToolPart(message.toolCalls[i], result))
  }
  if (message.content.trim() !== '') {
    parts.push(MessagePart.text(message.content))
  }
  return parts
}

/**
 * 分组:连续的 reasoning 和 tool part 归到一个 "思考块",
 * 遇到 text/image 等 part 时 flush。用于时间线 UI 渲染。
 */
export enum MessagePartBlockKind {
  THINKING = 'thinking',
  CONTENT = 'content'
}

export class MessagePartBlock {
  kind: MessagePartBlockKind = MessagePartBlockKind.CONTENT
  parts: MessagePart[] = []
}

export function groupMessageParts(parts: MessagePart[]): MessagePartBlock[] {
  const blocks: MessagePartBlock[] = []
  let thinkingBuffer: MessagePart[] = []

  const flush = () => {
    if (thinkingBuffer.length > 0) {
      const block = new MessagePartBlock()
      block.kind = MessagePartBlockKind.THINKING
      block.parts = thinkingBuffer
      blocks.push(block)
      thinkingBuffer = []
    }
  }

  for (let i = 0; i < parts.length; i++) {
    const part = parts[i]
    if (part.kind === MessagePartKind.REASONING || part.kind === MessagePartKind.TOOL) {
      thinkingBuffer.push(part)
    } else {
      flush()
      const block = new MessagePartBlock()
      block.kind = MessagePartBlockKind.CONTENT
      block.parts = [part]
      blocks.push(block)
    }
  }
  flush()
  return blocks
}
