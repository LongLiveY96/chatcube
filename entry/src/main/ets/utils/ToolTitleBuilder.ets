import { ToolCall } from '../models/ChatModels'
import {
  isScrapeWebFunctionName,
  isSearchWebFunctionName,
  normalizeToolFunctionName
} from './SearchToolIdentityUtils'

interface ToolArgumentDict {
  query?: string
  q?: string
  keyword?: string
  url?: string
  urls?: string[] | string
  action?: string
  content?: string
  text?: string
  message?: string
  name?: string
  path?: string
  question?: string
  questions?: Object[] | string
}

const MAX_SNIPPET = 24

function safeParseArguments(raw: string): ToolArgumentDict {
  const trimmed = raw.trim()
  if (trimmed === '') {
    return {} as ToolArgumentDict
  }
  try {
    const parsed = JSON.parse(trimmed) as ToolArgumentDict
    if (parsed === null || parsed === undefined) {
      return {} as ToolArgumentDict
    }
    return parsed
  } catch (_e) {
    return {} as ToolArgumentDict
  }
}

function truncate(value: string, maxLength: number = MAX_SNIPPET): string {
  const trimmed = value.trim()
  if (trimmed.length === 0) {
    return ''
  }
  if (trimmed.length <= maxLength) {
    return trimmed
  }
  return trimmed.substring(0, maxLength) + '…'
}

function coerceString(value: string | undefined): string {
  if (value === undefined || value === null) {
    return ''
  }
  return value
}

function arrayLengthOf(value: string[] | string | undefined): number {
  if (value === undefined || value === null) {
    return 0
  }
  if (Array.isArray(value)) {
    return (value as string[]).length
  }
  return 0
}

function firstNonEmpty(candidates: string[]): string {
  for (let i = 0; i < candidates.length; i++) {
    const v = candidates[i]
    if (v.trim() !== '') {
      return v.trim()
    }
  }
  return ''
}

/**
 * 根据 functionName + arguments 构造标题文本。返回值用于直接塞进 Text(title)。
 * 未命中任何定制分支时回退到 toolCall.displayName 或 functionName。
 */
export function buildToolTitle(toolCall: ToolCall): string {
  const fn = normalizeToolFunctionName(toolCall.functionName)
  const args = safeParseArguments(toolCall.arguments)
  const fallback = toolCall.displayName.trim() !== ''
    ? toolCall.displayName.trim()
    : (toolCall.functionName.trim() !== '' ? toolCall.functionName.trim() : '工具调用')

  if (isSearchWebFunctionName(fn)) {
    const q = firstNonEmpty([coerceString(args.query), coerceString(args.q), coerceString(args.keyword)])
    return q !== '' ? `搜索："${truncate(q)}"` : '联网搜索'
  }
  if (isScrapeWebFunctionName(fn)) {
    const url = coerceString(args.url)
    if (url !== '') {
      return `抓取：${truncate(url, 32)}`
    }
    const count = arrayLengthOf(args.urls)
    if (count > 0) {
      return `抓取 ${count} 个链接`
    }
    return '网页抓取'
  }
  if (fn === 'memory' || fn.startsWith('memory_') || fn.endsWith('_memory')) {
    const action = coerceString(args.action).toLowerCase()
    if (action === 'create' || action === 'add' || fn.startsWith('add_')) {
      return '保存记忆'
    }
    if (action === 'edit' || action === 'update' || fn.startsWith('update_')) {
      return '更新记忆'
    }
    if (action === 'delete' || action === 'remove' || fn.startsWith('delete_')) {
      return '删除记忆'
    }
    return '记忆工具'
  }
  if (fn === 'clipboard' || fn === 'clipboard_tool' || fn.startsWith('clipboard_') ||
    fn === 'read_clipboard' || fn === 'write_clipboard') {
    const action = coerceString(args.action).toLowerCase()
    if (action === 'write' || fn === 'write_clipboard') {
      return '写入剪贴板'
    }
    if (action === 'read' || fn === 'read_clipboard') {
      return '读取剪贴板'
    }
    return '剪贴板'
  }
  if (fn === 'get_time' || fn === 'time' || fn === 'current_time' || fn === 'now' ||
    fn === 'get_time_info') {
    return '获取当前时间'
  }
  if (fn === 'tts' || fn === 'text_to_speech' || fn === 'speak' || fn === 'speech_generate') {
    const text = firstNonEmpty([coerceString(args.text), coerceString(args.message), coerceString(args.content)])
    return text !== '' ? `朗读："${truncate(text)}"` : '朗读'
  }
  if (fn === 'ask_user' || fn === 'user_input' || fn === 'ask') {
    const count = arrayLengthOf(args.questions as string[] | string | undefined)
    if (count > 1) {
      return `向你询问 ${count} 个问题`
    }
    const q = firstNonEmpty([coerceString(args.question), coerceString(args.message)])
    return q !== '' ? `询问：${truncate(q, 40)}` : '等待你的回答'
  }
  if (fn === 'use_skill' || fn === 'skill' || fn === 'invoke_skill') {
    const name = coerceString(args.name)
    const path = coerceString(args.path)
    if (name !== '' && path !== '') {
      return `技能：${truncate(name, 16)} / ${truncate(path, 16)}`
    }
    if (name !== '') {
      return `技能：${truncate(name, 32)}`
    }
    return '执行技能'
  }

  return fallback
}
