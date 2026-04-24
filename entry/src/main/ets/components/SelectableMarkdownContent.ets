import { LengthMetrics } from '@kit.ArkUI'

class MarkdownTextSegment {
  text: string = ''
  isHeading: boolean = false
  headingLevel: number = 0
  isCode: boolean = false
  isQuote: boolean = false

  constructor(text: string, isHeading: boolean, headingLevel: number, isCode: boolean, isQuote: boolean) {
    this.text = text
    this.isHeading = isHeading
    this.headingLevel = headingLevel
    this.isCode = isCode
    this.isQuote = isQuote
  }
}

class MarkdownLineResult {
  text: string = ''
  isHeading: boolean = false
  headingLevel: number = 0
  isCode: boolean = false
  isQuote: boolean = false

  constructor(text: string, isHeading: boolean, headingLevel: number, isCode: boolean, isQuote: boolean) {
    this.text = text
    this.isHeading = isHeading
    this.headingLevel = headingLevel
    this.isCode = isCode
    this.isQuote = isQuote
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
    const segments = this.parseMarkdown(this.content)
    let displayText = ''
    const styles: SpanStyle[] = []
    let cursor = 0

    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i]
      if (segment.text.length === 0) {
        continue
      }
      const start = cursor
      displayText += segment.text
      cursor += segment.text.length
      this.appendSegmentStyle(styles, start, segment.text.length, segment)
    }

    if (displayText.length === 0) {
      displayText = ' '
    }

    this.textController.setStyledString(new MutableStyledString(displayText, styles))
  }

  private appendSegmentStyle(styles: SpanStyle[], start: number, length: number, segment: MarkdownTextSegment): void {
    if (length <= 0) {
      return
    }

    let segmentFontSize = this.fontSize
    let segmentFontWeight: FontWeight | number | string = FontWeight.Normal
    let segmentFontStyle = FontStyle.Normal
    let segmentFontFamily = 'HarmonyOS Sans'
    let segmentColor = this.textColor

    if (segment.isHeading) {
      segmentFontWeight = FontWeight.Bold
      if (segment.headingLevel === 1) {
        segmentFontSize = Math.round(this.fontSize * 1.35)
      } else if (segment.headingLevel === 2) {
        segmentFontSize = Math.round(this.fontSize * 1.22)
      } else {
        segmentFontSize = Math.round(this.fontSize * 1.12)
      }
    } else if (segment.isCode) {
      segmentFontFamily = 'monospace'
      segmentFontSize = Math.round(this.fontSize * 0.94)
    } else if (segment.isQuote) {
      segmentFontStyle = FontStyle.Italic
    }

    styles.push({
      start: start,
      length: length,
      styledKey: StyledStringKey.FONT,
      styledValue: new TextStyle({
        fontColor: segmentColor,
        fontSize: LengthMetrics.fp(segmentFontSize),
        fontWeight: segmentFontWeight,
        fontStyle: segmentFontStyle,
        fontFamily: segmentFontFamily
      })
    })
  }

  private parseMarkdown(markdown: string): MarkdownTextSegment[] {
    const normalized = markdown.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
    const lines = normalized.split('\n')
    const segments: MarkdownTextSegment[] = []
    let inCodeBlock = false

    for (let i = 0; i < lines.length; i++) {
      const rawLine = lines[i]
      const trimmedLine = rawLine.trim()

      if (trimmedLine.startsWith('```')) {
        inCodeBlock = !inCodeBlock
        continue
      }

      if (inCodeBlock) {
        this.pushLineSegment(segments, new MarkdownLineResult(rawLine, false, 0, true, false), i, lines.length)
        continue
      }

      if (this.isDividerLine(trimmedLine)) {
        continue
      }

      const result = this.parseMarkdownLine(rawLine)
      this.pushLineSegment(segments, result, i, lines.length)
    }

    return segments
  }

  private pushLineSegment(segments: MarkdownTextSegment[], result: MarkdownLineResult, index: number, total: number): void {
    let lineText = result.text
    if (index < total - 1) {
      lineText += '\n'
    }
    segments.push(new MarkdownTextSegment(lineText, result.isHeading, result.headingLevel, result.isCode, result.isQuote))
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
      let headingText = workingLine.substring(headingLevel).trim()
      headingText = this.cleanInlineMarkdown(headingText)
      return new MarkdownLineResult(headingText, true, headingLevel, false, isQuote)
    }

    workingLine = this.cleanListPrefix(workingLine)
    workingLine = this.cleanTableLine(workingLine)
    workingLine = this.cleanInlineMarkdown(workingLine)
    return new MarkdownLineResult(workingLine, false, 0, false, isQuote)
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

  private cleanListPrefix(line: string): string {
    let result = line
    result = result.replace(/^[-*+]\s+\[[ xX]\]\s+/, '• ')
    result = result.replace(/^[-*+]\s+/, '• ')
    result = result.replace(/^\d+[.)]\s+/, '• ')
    return result
  }

  private cleanTableLine(line: string): string {
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

  private cleanInlineMarkdown(text: string): string {
    let result = text
    result = result.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
    result = result.replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    result = result.replace(/`([^`]*)`/g, '$1')
    result = result.replace(/\*\*([^*]+)\*\*/g, '$1')
    result = result.replace(/__([^_]+)__/g, '$1')
    result = result.replace(/~~([^~]+)~~/g, '$1')
    result = result.replace(/\*([^*]+)\*/g, '$1')
    result = result.replace(/_([^_]+)_/g, '$1')
    result = result.replace(/<br\s*\/?>/gi, '\n')
    result = result.replace(/<[^>]+>/g, '')
    return result
  }

  private isDividerLine(line: string): boolean {
    return /^[-*_]{3,}$/.test(line.replace(/\s/g, ''))
  }

  build() {
    Text(undefined, { controller: this.textController })
      .fontSize(this.fontSize)
      .fontColor(this.textColor)
      .lineHeight(Math.round(this.fontSize * 1.5))
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
      line = line.replace(/^\d+[.)]\s+/, '• ')
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
