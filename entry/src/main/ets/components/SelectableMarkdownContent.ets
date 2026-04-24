import { LengthMetrics } from '@kit.ArkUI'
import { getMarkdownTextLineHeight, getMarkdownTitleSizes } from '../utils/MarkdownTypographyUtils'

class MarkdownInlineSpan {
  text: string = ''
  isBold: boolean = false
  isItalic: boolean = false
  isCode: boolean = false
  isLink: boolean = false

  constructor(text: string, isBold: boolean, isItalic: boolean, isCode: boolean, isLink: boolean) {
    this.text = text
    this.isBold = isBold
    this.isItalic = isItalic
    this.isCode = isCode
    this.isLink = isLink
  }
}

class MarkdownLineResult {
  spans: MarkdownInlineSpan[] = []
  isHeading: boolean = false
  headingLevel: number = 0
  isCodeBlock: boolean = false
  isQuote: boolean = false

  constructor(spans: MarkdownInlineSpan[], isHeading: boolean, headingLevel: number, isCodeBlock: boolean, isQuote: boolean) {
    this.spans = spans
    this.isHeading = isHeading
    this.headingLevel = headingLevel
    this.isCodeBlock = isCodeBlock
    this.isQuote = isQuote
  }
}

class MarkdownStyleState {
  isBold: boolean = false
  isItalic: boolean = false
  isCode: boolean = false
  isLink: boolean = false

  constructor(isBold: boolean, isItalic: boolean, isCode: boolean, isLink: boolean) {
    this.isBold = isBold
    this.isItalic = isItalic
    this.isCode = isCode
    this.isLink = isLink
  }
}

@ComponentV2
export struct SelectableMarkdownContent {
  @Param content: string = ''
  @Param fontSize: number = 15
  @Param textColor: ResourceColor = Color.Black
  private textController: TextController = new TextController()

  @Monitor('content')
  onContentChange(): void {
    this.refreshStyledString()
  }

  @Monitor('fontSize')
  onFontSizeChange(): void {
    this.refreshStyledString()
  }

  @Monitor('textColor')
  onTextColorChange(): void {
    this.refreshStyledString()
  }

  aboutToAppear(): void {
    this.refreshStyledString()
  }

  private refreshStyledString(): void {
    const lines = this.parseMarkdown(this.content)
    let displayText = ''
    const styles: SpanStyle[] = []
    let cursor = 0

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      for (let j = 0; j < line.spans.length; j++) {
        const span = line.spans[j]
        if (span.text.length === 0) {
          continue
        }
        const start = cursor
        displayText += span.text
        cursor += span.text.length
        this.appendSpanStyle(styles, start, span.text.length, line, span)
      }
      if (i < lines.length - 1) {
        displayText += '\n'
        cursor++
      }
    }

    if (displayText.length === 0) {
      displayText = ' '
    }

    this.textController.setStyledString(new MutableStyledString(displayText, styles))
  }

  private appendSpanStyle(styles: SpanStyle[], start: number, length: number, line: MarkdownLineResult, span: MarkdownInlineSpan): void {
    if (length <= 0) {
      return
    }

    let spanFontSize = this.fontSize
    let spanFontWeight: FontWeight | number | string = span.isBold ? FontWeight.Bold : FontWeight.Normal
    let spanFontStyle = span.isItalic || line.isQuote ? FontStyle.Italic : FontStyle.Normal
    let spanFontFamily = span.isCode || line.isCodeBlock ? 'monospace' : 'HarmonyOS Sans'
    let spanColor = this.textColor

    if (line.isHeading) {
      const titleSizes = getMarkdownTitleSizes(this.fontSize)
      spanFontSize = titleSizes[line.headingLevel - 1]
      spanFontWeight = FontWeight.Bold
    }

    styles.push({
      start: start,
      length: length,
      styledKey: StyledStringKey.FONT,
      styledValue: new TextStyle({
        fontColor: spanColor,
        fontSize: LengthMetrics.fp(spanFontSize),
        fontWeight: spanFontWeight,
        fontStyle: spanFontStyle,
        fontFamily: spanFontFamily
      })
    })

    if (span.isLink) {
      styles.push({
        start: start,
        length: length,
        styledKey: StyledStringKey.DECORATION,
        styledValue: new DecorationStyle({
          type: TextDecorationType.Underline,
          color: spanColor,
          style: TextDecorationStyle.SOLID
        })
      })
    }
  }

  private parseMarkdown(markdown: string): MarkdownLineResult[] {
    const normalized = markdown.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
    const rawLines = normalized.split('\n')
    const lines: MarkdownLineResult[] = []
    let inCodeBlock = false

    for (let i = 0; i < rawLines.length; i++) {
      const rawLine = rawLines[i]
      const trimmedLine = rawLine.trim()

      if (trimmedLine.startsWith('```')) {
        inCodeBlock = !inCodeBlock
        continue
      }

      if (inCodeBlock) {
        lines.push(new MarkdownLineResult([new MarkdownInlineSpan(rawLine, false, false, true, false)], false, 0, true, false))
        continue
      }

      if (this.isDividerLine(trimmedLine)) {
        continue
      }

      const parsedLine = this.parseMarkdownLine(rawLine)
      lines.push(parsedLine)
    }

    return lines
  }

  private parseMarkdownLine(line: string): MarkdownLineResult {
    let workingLine = line.trim()
    let isQuote = false

    if (workingLine.startsWith('>')) {
      isQuote = true
      workingLine = workingLine.substring(1).trim()
      workingLine = '│ ' + workingLine
    }

    const headingLevel = this.getHeadingLevel(workingLine)
    if (headingLevel > 0) {
      const headingText = workingLine.substring(headingLevel).trim()
      return new MarkdownLineResult(this.parseInlineSpans(headingText), true, headingLevel, false, isQuote)
    }

    workingLine = this.normalizeListPrefix(workingLine)
    workingLine = this.normalizeTableLine(workingLine)
    return new MarkdownLineResult(this.parseInlineSpans(workingLine), false, 0, false, isQuote)
  }

  private getHeadingLevel(line: string): number {
    let level = 0
    const maxLevel = Math.min(6, line.length)
    for (let i = 0; i < maxLevel; i++) {
      if (line.charAt(i) === '#') {
        level++
      } else {
        break
      }
    }
    if (level > 0 && line.length > level && line.charAt(level) === ' ') {
      return level
    }
    return 0
  }

  private normalizeListPrefix(line: string): string {
    let result = line
    result = result.replace(/^[-*+]\s+\[[ xX]\]\s+/, '• ')
    result = result.replace(/^[-*+]\s+/, '• ')
    return result
  }

  private normalizeTableLine(line: string): string {
    const trimmedLine = line.trim()
    if (trimmedLine.indexOf('|') < 0) {
      return line
    }
    if (/^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$/.test(trimmedLine)) {
      return ''
    }
    let result = trimmedLine
    if (result.startsWith('|')) {
      result = result.substring(1)
    }
    if (result.endsWith('|')) {
      result = result.substring(0, result.length - 1)
    }
    return result.split('|').map((item: string) => item.trim()).join('    ')
  }

  private parseInlineSpans(text: string): MarkdownInlineSpan[] {
    const spans: MarkdownInlineSpan[] = []
    let cursor = 0
    let buffer = ''
    let state = new MarkdownStyleState(false, false, false, false)

    while (cursor < text.length) {
      const remaining = text.substring(cursor)

      if (remaining.startsWith('<br/>') || remaining.startsWith('<br />') || remaining.startsWith('<br>')) {
        this.flushInlineBuffer(spans, buffer, state)
        buffer = ''
        spans.push(new MarkdownInlineSpan('\n', state.isBold, state.isItalic, state.isCode, state.isLink))
        if (remaining.startsWith('<br />')) {
          cursor += 6
        } else if (remaining.startsWith('<br/>')) {
          cursor += 5
        } else {
          cursor += 4
        }
        continue
      }

      if (remaining.startsWith('![')) {
        const imageEnd = this.findMarkdownLinkEnd(text, cursor + 2)
        if (imageEnd > cursor) {
          const labelEnd = text.indexOf(']', cursor + 2)
          if (labelEnd > cursor) {
            buffer += text.substring(cursor + 2, labelEnd)
            cursor = imageEnd + 1
            continue
          }
        }
      }

      if (remaining.startsWith('[')) {
        const linkEnd = this.findMarkdownLinkEnd(text, cursor + 1)
        if (linkEnd > cursor) {
          const labelEnd = text.indexOf(']', cursor + 1)
          if (labelEnd > cursor) {
            this.flushInlineBuffer(spans, buffer, state)
            buffer = ''
            const linkText = text.substring(cursor + 1, labelEnd)
            const linkSpans = this.parseInlineSpans(linkText)
            for (let i = 0; i < linkSpans.length; i++) {
              const linkSpan = linkSpans[i]
              spans.push(new MarkdownInlineSpan(linkSpan.text, linkSpan.isBold || state.isBold, linkSpan.isItalic || state.isItalic, linkSpan.isCode || state.isCode, true))
            }
            cursor = linkEnd + 1
            continue
          }
        }
      }

      if (remaining.startsWith('**')) {
        this.flushInlineBuffer(spans, buffer, state)
        buffer = ''
        state = new MarkdownStyleState(!state.isBold, state.isItalic, state.isCode, state.isLink)
        cursor += 2
        continue
      }

      if (remaining.startsWith('__')) {
        this.flushInlineBuffer(spans, buffer, state)
        buffer = ''
        state = new MarkdownStyleState(!state.isBold, state.isItalic, state.isCode, state.isLink)
        cursor += 2
        continue
      }

      if (remaining.startsWith('~~')) {
        cursor += 2
        continue
      }

      const currentChar = text.charAt(cursor)
      if (currentChar === '`') {
        this.flushInlineBuffer(spans, buffer, state)
        buffer = ''
        state = new MarkdownStyleState(state.isBold, state.isItalic, !state.isCode, state.isLink)
        cursor++
        continue
      }

      if (currentChar === '*' || currentChar === '_') {
        this.flushInlineBuffer(spans, buffer, state)
        buffer = ''
        state = new MarkdownStyleState(state.isBold, !state.isItalic, state.isCode, state.isLink)
        cursor++
        continue
      }

      if (currentChar === '<') {
        const tagEnd = text.indexOf('>', cursor)
        if (tagEnd > cursor) {
          cursor = tagEnd + 1
          continue
        }
      }

      buffer += currentChar
      cursor++
    }

    this.flushInlineBuffer(spans, buffer, state)
    return spans
  }

  private flushInlineBuffer(spans: MarkdownInlineSpan[], buffer: string, state: MarkdownStyleState): void {
    if (buffer.length === 0) {
      return
    }
    spans.push(new MarkdownInlineSpan(buffer, state.isBold, state.isItalic, state.isCode, state.isLink))
  }

  private findMarkdownLinkEnd(text: string, labelStart: number): number {
    const labelEnd = text.indexOf(']', labelStart)
    if (labelEnd < 0 || labelEnd + 1 >= text.length || text.charAt(labelEnd + 1) !== '(') {
      return -1
    }
    const targetEnd = text.indexOf(')', labelEnd + 2)
    return targetEnd
  }

  private isDividerLine(line: string): boolean {
    return /^[-*_]{3,}$/.test(line.replace(/\s/g, ''))
  }

  build() {
    Text(undefined, { controller: this.textController })
      .fontSize(this.fontSize)
      .fontColor(this.textColor)
      .lineHeight(getMarkdownTextLineHeight(this.fontSize))
      .copyOption(CopyOptions.LocalDevice)
      .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
      .width('100%')
  }
}

export function getSelectableMarkdownPlainText(markdown: string): string {
  const normalized = markdown.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
  const lines = normalized.split('\n')
  const output: string[] = []
  let inCodeBlock = false

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i].trim()
    if (line.startsWith('```')) {
      inCodeBlock = !inCodeBlock
      continue
    }
    if (!inCodeBlock && /^[-*_]{3,}$/.test(line.replace(/\s/g, ''))) {
      continue
    }
    if (!inCodeBlock) {
      if (line.startsWith('>')) {
        line = line.substring(1).trim()
      }
      line = line.replace(/^#{1,6}\s+/, '')
      line = line.replace(/^[-*+]\s+\[[ xX]\]\s+/, '• ')
      line = line.replace(/^[-*+]\s+/, '• ')
      if (line.indexOf('|') >= 0) {
        if (/^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$/.test(line)) {
          line = ''
        } else {
          if (line.startsWith('|')) {
            line = line.substring(1)
          }
          if (line.endsWith('|')) {
            line = line.substring(0, line.length - 1)
          }
          line = line.split('|').map((item: string) => item.trim()).join('    ')
        }
      }
      line = line.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
      line = line.replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
      line = line.replace(/`([^`]*)`/g, '$1')
      line = line.replace(/\*\*([^*]+)\*\*/g, '$1')
      line = line.replace(/__([^_]+)__/g, '$1')
      line = line.replace(/~~([^~]+)~~/g, '$1')
      line = line.replace(/\*([^*]+)\*/g, '$1')
      line = line.replace(/_([^_]+)_/g, '$1')
      line = line.replace(/<br\s*\/?>/gi, '\n')
      line = line.replace(/<[^>]+>/g, '')
    }
    output.push(line)
  }

  return output.join('\n').trim()
}
