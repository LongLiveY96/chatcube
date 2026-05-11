import {
  isScrapeWebFunctionName,
  isSearchWebFunctionName,
  normalizeToolFunctionName
} from './SearchToolIdentityUtils'

// 常见内置 / MCP 工具的 functionName 前缀归类。仅覆盖主流命名;无法命中的走 fallback 的齿轮。
// 选择 sys.symbol.* 时优先复用仓库里已出现过、能在 HarmonyOS 6 渲染的符号,避免编译期找不到资源。
const MEMORY_KEYWORDS: string[] = [
  'memory', 'add_memory', 'save_memory', 'update_memory', 'delete_memory', 'memory_tool'
]
const CLIPBOARD_KEYWORDS: string[] = [
  'clipboard', 'copy_text', 'clipboard_tool', 'read_clipboard', 'write_clipboard'
]
const TIME_KEYWORDS: string[] = [
  'get_time', 'time', 'current_time', 'now', 'get_time_info'
]
const TTS_KEYWORDS: string[] = [
  'tts', 'text_to_speech', 'speak', 'speech_generate'
]
const ASK_USER_KEYWORDS: string[] = [
  'ask_user', 'user_input', 'ask', 'questionnaire'
]
const SKILL_KEYWORDS: string[] = [
  'use_skill', 'skill', 'invoke_skill'
]

function matchesAny(name: string, keywords: string[]): boolean {
  for (let i = 0; i < keywords.length; i++) {
    if (name === keywords[i]) {
      return true
    }
    if (name.startsWith(keywords[i] + '_')) {
      return true
    }
  }
  return false
}

/**
 * 根据工具 functionName 返回最合适的 sys.symbol 资源。
 * 所有传入值会先通过 normalizeToolFunctionName 小写化并统一分隔符。
 */
export function resolveToolSymbol(functionName: string): Resource {
  const raw = functionName as string | null | undefined
  if (raw === undefined || raw === null || raw.trim() === '') {
    return $r('sys.symbol.gearshape')
  }
  const name = normalizeToolFunctionName(raw)
  if (isSearchWebFunctionName(name)) {
    return $r('sys.symbol.magnifyingglass')
  }
  if (isScrapeWebFunctionName(name)) {
    return $r('sys.symbol.globe_badge_message')
  }
  if (matchesAny(name, MEMORY_KEYWORDS)) {
    return $r('sys.symbol.square_and_pencil')
  }
  if (matchesAny(name, CLIPBOARD_KEYWORDS)) {
    return $r('sys.symbol.doc_plaintext')
  }
  if (matchesAny(name, TIME_KEYWORDS)) {
    return $r('sys.symbol.clock')
  }
  if (matchesAny(name, TTS_KEYWORDS)) {
    return $r('sys.symbol.speaker_wave_2')
  }
  if (matchesAny(name, ASK_USER_KEYWORDS)) {
    return $r('sys.symbol.message')
  }
  if (matchesAny(name, SKILL_KEYWORDS)) {
    return $r('sys.symbol.wand_and_stars')
  }
  return $r('sys.symbol.gearshape')
}
