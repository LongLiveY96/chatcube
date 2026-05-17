/**
 * 大字符串的轻量指纹: 用 length + head 16 + tail 16 替代 O(N) 整串编码,
 * 让 LazyForEach diff / @Monitor 缓存失效判定在 O(1) 完成。
 *
 * 适用场景: message.content / reasoningContent / serializedParts 这类
 * 流式增量追加的字符串 — 一定改 tail, 所以指纹一定变化。
 *
 * 已知失真: 长度相同 + 首尾 16 字符都没变的"中间替换"会漏判,
 * 但实际业务里 (translate 同长度替换 / stop+regenerate) 几乎不会触发,
 * 且流式刷新走 syncVersion+1 → setItems(changedIndex) 强制下发, 不依赖指纹 diff,
 * 见 feedback_arkts_v2_lazyforeach_reactivity 与 feedback_arkts_v2_reusablev2_listitem。
 */
export function fingerprintLongString(value: string): string {
  const len = value.length
  if (len === 0) {
    return '0|'
  }
  if (len <= 32) {
    return `${len}|${value}`
  }
  return `${len}|${value.substring(0, 16)}|${value.substring(len - 16)}`
}
