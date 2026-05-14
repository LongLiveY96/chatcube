import { ToolCall, ToolResult } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { buildToolArgumentsPreview, buildToolResultPreview, ToolPayloadPreview } from '../utils/ToolPayloadSummaryUtils'
import { isScrapeWebFunctionName, isSearchWebFunctionName } from '../utils/SearchToolIdentityUtils'
import { resolveToolSymbol } from '../utils/ToolIconMapping'
import { buildToolTitle } from '../utils/ToolTitleBuilder'

// 获取工具显示名称
function getToolDisplayName(toolCall: ToolCall): string | Resource {
  if (toolCall.displayName.trim() !== '') {
    return toolCall.displayName
  }
  const raw = toolCall.functionName as string | null | undefined
  if (raw === undefined || raw === null || raw.trim() === '') {
    return '未知工具'
  }
  if (isScrapeWebFunctionName(raw)) {
    return $r('app.string.web_scrape')
  }
  if (isSearchWebFunctionName(raw)) {
    return $r('app.string.web_search')
  }
  if (raw.startsWith('mcp__')) {
    const parts = raw.split('__')
    if (parts.length >= 3) {
      return parts[2]
    }
  }
  return raw
}

// 工具调用卡片组件
@ComponentV2
export struct ToolCallCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param toolResult: ToolResult | null = null
  @Param isExecuting: boolean = false
  @Local showDetailSheet: boolean = false
  @Local showRawArguments: boolean = false
  @Local showRawResult: boolean = false
  // 跳动点动画状态
  @Local dot1Scale: number = 0.6
  @Local dot2Scale: number = 0.6
  @Local dot3Scale: number = 0.6
  // 主题颜色
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private dotAnimationTimer: number = -1

  aboutToAppear(): void {
    if (this.isExecuting) {
      this.startDotAnimation()
    }
  }

  aboutToDisappear(): void {
    this.stopDotAnimation()
  }

  @Monitor('isExecuting')
  onExecutingStateChange(): void {
    if (this.isExecuting) {
      this.startDotAnimation()
      return
    }
    this.stopDotAnimation()
  }

  // 启动跳动点动画
  private startDotAnimation(): void {
    if (this.dotAnimationTimer !== -1) {
      return
    }
    let step = 0
    this.dotAnimationTimer = setInterval(() => {
      const currentDot = step % 3
      this.getUIContext().animateTo({
        duration: 300,
        curve: Curve.EaseInOut
      }, () => {
        this.dot1Scale = 0.6
        this.dot2Scale = 0.6
        this.dot3Scale = 0.6
        if (currentDot === 0) {
          this.dot1Scale = 1.0
        } else if (currentDot === 1) {
          this.dot2Scale = 1.0
        } else {
          this.dot3Scale = 1.0
        }
      })
      step++
    }, 300)
  }

  // 停止跳动点动画
  private stopDotAnimation(): void {
    if (this.dotAnimationTimer !== -1) {
      clearInterval(this.dotAnimationTimer)
      this.dotAnimationTimer = -1
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        // 工具图标 - 按 functionName 映射不同符号(搜索/抓取/记忆/剪贴板/TTS/询问/技能/MCP)
        SymbolGlyph(resolveToolSymbol(this.toolCall.functionName))
          .fontSize(14)
          .fontColor([this.isExecuting ? this.themePrimary : $r('app.color.text_secondary')])

        // 工具名称
        Text(this.getToolTitle())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isExecuting ? this.themePrimary : $r('app.color.text_secondary'))
          .margin({ left: 6 })

        if (this.toolCall.sourceLabel.trim() !== '') {
          Text(this.toolCall.sourceLabel)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 6 })
        }

        // 审批状态徽章(pending/denied): 让用户在卡片上直接看到工具执行被拦住/拒绝
        if (this.toolCall.approvalState === 'pending') {
          Text('待确认')
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor(this.themePrimary)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
            .margin({ left: 8 })
        } else if (this.toolCall.approvalState === 'denied') {
          Text('已拒绝')
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.status_error'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
            .margin({ left: 8 })
        }

        // 执行状态
        if (this.isExecuting) {
          // 执行中：显示跳动点
          Row({ space: 2 }) {
            Column()
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor(this.themePrimary)
              .scale({ x: this.dot1Scale, y: this.dot1Scale })

            Column()
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor(this.themePrimary)
              .scale({ x: this.dot2Scale, y: this.dot2Scale })

            Column()
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor(this.themePrimary)
              .scale({ x: this.dot3Scale, y: this.dot3Scale })
          }
          .margin({ left: 8 })
        } else if (this.toolResult !== null) {
          // 已完成：根据结果显示成功/失败状态
          SymbolGlyph(this.getResultStatusSymbol())
            .fontSize(14)
            .fontColor([this.getResultStatusColor()])
            .margin({ left: 8 })
        }

        Blank()

        // 展开/折叠按钮（仅在有结果时显示）
        if (this.toolResult !== null) {
          Row() {
            Text($r('app.string.common_details'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))

            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([$r('app.color.text_tertiary')])
              .rotate({ angle: 0 })
              .animation({ duration: 200, curve: Curve.EaseOut })
              .margin({ left: 2 })
          }
          .onClick(() => {
            this.showDetailSheet = true
          })
        }
      }
      .width('100%')
      .height(32)
      .padding({ left: 10, right: 10 })
    }
    .width('100%')
    .backgroundColor($r('app.color.divider'))
    .borderRadius(8)
    .clip(true)
    .onClick(() => {
      if (this.toolResult !== null || this.toolCall.arguments.trim() !== '') {
        this.showDetailSheet = true
      }
    })
    .bindSheet($$this.showDetailSheet, this.ToolDetailSheetBuilder(), {
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      preferType: SheetType.BOTTOM,
      onDisappear: () => {
        this.showRawArguments = false
        this.showRawResult = false
      }
    })
  }

  // 按 functionName + arguments 构造带上下文的标题,如 “搜索:xx”、“朗读:xx”、“保存记忆”
  // 若 toolCall 已经由上游显式指定了 displayName(通常来自 MCP 服务端),保留其原意;其他情况走 buildToolTitle 派发
  private getToolTitle(): string {
    const display = this.toolCall.displayName.trim()
    if (display !== '' && display !== this.toolCall.functionName) {
      return display
    }
    return buildToolTitle(this.toolCall)
  }

  private getArgumentPreview(): ToolPayloadPreview {
    return buildToolArgumentsPreview(this.toolCall.arguments, 3, 600)
  }

  private getResultPreview(): ToolPayloadPreview {
    if (this.toolResult === null) {
      return new ToolPayloadPreview('执行中...', [], '执行中...', false)
    }
    return buildToolResultPreview(this.toolResult.content, 3, 900)
  }

  private hasFailedResult(): boolean {
    if (this.toolResult === null) {
      return false
    }
    if (this.toolResult.isError) {
      return true
    }
    try {
      const parsed = JSON.parse(this.toolResult.content) as Record<string, Object>
      return parsed.isError === true || parsed.error !== undefined
    } catch (_error) {
      return false
    }
  }

  private getResultStatusSymbol(): Resource {
    return this.hasFailedResult() ? $r('sys.symbol.xmark_circle') : $r('sys.symbol.checkmark_circle')
  }

  private getResultStatusColor(): ResourceColor {
    return this.hasFailedResult() ? $r('app.color.status_error') : $r('app.color.status_success')
  }

  // ============== Bottom Sheet 详情 ==============

  @Builder
  private ToolDetailSheetBuilder() {
    Column() {
      // 顶部标题条
      Row() {
        SymbolGlyph(resolveToolSymbol(this.toolCall.functionName))
          .fontSize(16)
          .fontColor([this.themePrimary])

        Text(this.getToolTitle())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.toolResult !== null) {
          SymbolGlyph(this.getResultStatusSymbol())
            .fontSize(16)
            .fontColor([this.getResultStatusColor()])
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 12 })

      // 主体内容:按工具类型分派
      Scroll() {
        Column() {
          if (this.isScrapeTool()) {
            this.ScrapeDetail()
          } else if (this.isSearchTool()) {
            this.SearchDetail()
          } else {
            this.GenericDetail()
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private SectionLabel(label: Resource | string) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .margin({ top: 4, bottom: 6 })
  }

  @Builder
  private CodeBox(text: string) {
    Text(text)
      .width('100%')
      .fontSize(11)
      .lineHeight(16)
      .fontFamily('monospace')
      .fontColor($r('app.color.text_secondary'))
      .padding(10)
      .borderRadius(10)
      .backgroundColor(this.isDarkMode ? '#14171F' : '#F6F8FC')
      .copyOption(CopyOptions.LocalDevice)
  }

  // search 工具:展示查询词 + 结果列表(title/url/snippet)
  @Builder
  private SearchDetail() {
    Column() {
      this.SectionLabel('查询')
      Text(this.getSearchQueryPreview())
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 12 })

      if (this.toolResult !== null) {
        this.SectionLabel(`搜索结果 (${this.getSearchResultCount()})`)
        if (this.getSearchResultSummary() !== '') {
          Text(this.getSearchResultSummary())
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .margin({ bottom: 10 })
        }
        ForEach(this.getSearchResultItems(), (item: SearchResultItemVM, _index: number) => {
          Column() {
            Text(item.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (item.url !== '') {
              Text(item.url)
                .fontSize(11)
                .fontColor(this.themePrimary)
                .margin({ top: 2 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }

            if (item.snippet !== '') {
              Text(item.snippet)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 4 })
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.divider'))
          .borderRadius(10)
          .margin({ bottom: 8 })
        }, (item: SearchResultItemVM, index: number) => item.url + '_' + index.toString())

        if (this.getSearchResultItems().length === 0) {
          this.SectionLabel('原始结果')
          this.CodeBox(this.getResultPreview().rawPreview)
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // scrape 工具:url 列表 + 文本预览
  @Builder
  private ScrapeDetail() {
    Column() {
      this.SectionLabel('目标')
      Text(this.getScrapeTargetPreview())
        .fontSize(13)
        .fontColor(this.themePrimary)
        .margin({ bottom: 12 })

      if (this.toolResult !== null) {
        this.SectionLabel('抓取内容')
        Text(this.getScrapeContentPreview())
          .width('100%')
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.text_primary'))
          .padding(12)
          .backgroundColor($r('app.color.divider'))
          .borderRadius(10)
          .copyOption(CopyOptions.LocalDevice)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 通用:直接把 arguments 和 result 按 JSON 渲染
  @Builder
  private GenericDetail() {
    Column() {
      this.SectionLabel('参数')
      this.CodeBox(this.getArgumentPreview().rawPreview)

      if (this.toolResult !== null) {
        this.SectionLabel('结果')
        this.CodeBox(this.getResultPreview().rawPreview)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private isSearchTool(): boolean {
    return isSearchWebFunctionName(this.toolCall.functionName)
  }

  private isScrapeTool(): boolean {
    return isScrapeWebFunctionName(this.toolCall.functionName)
  }

  private getArgumentsObject(): Record<string, Object> {
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      if (parsed === null || parsed === undefined) {
        return {} as Record<string, Object>
      }
      return parsed
    } catch (_e) {
      return {} as Record<string, Object>
    }
  }

  private getResultObject(): Record<string, Object> {
    if (this.toolResult === null) {
      return {} as Record<string, Object>
    }
    try {
      const parsed = JSON.parse(this.toolResult.content) as Record<string, Object>
      if (parsed === null || parsed === undefined) {
        return {} as Record<string, Object>
      }
      return parsed
    } catch (_e) {
      return {} as Record<string, Object>
    }
  }

  private getSearchQueryPreview(): string {
    const args = this.getArgumentsObject()
    const candidates: string[] = ['query', 'q', 'keyword']
    for (let i = 0; i < candidates.length; i++) {
      const v = args[candidates[i]] as string | undefined
      if (v !== undefined && typeof v === 'string' && v.trim() !== '') {
        return v.trim()
      }
    }
    return '(空查询)'
  }

  private getSearchResultSummary(): string {
    const result = this.getResultObject()
    const answer = result['answer'] as string | undefined
    if (answer !== undefined && typeof answer === 'string') {
      return answer.trim()
    }
    return ''
  }

  private getSearchResultItems(): SearchResultItemVM[] {
    const result = this.getResultObject()
    const rawItems = result['items'] as Object
    const out: SearchResultItemVM[] = []
    if (Array.isArray(rawItems)) {
      const items = rawItems as Object[]
      for (let i = 0; i < items.length; i++) {
        const it = items[i] as Record<string, Object>
        if (it === null || it === undefined) {
          continue
        }
        const title = (it['title'] as string | undefined) ?? ''
        const url = (it['url'] as string | undefined) ?? ''
        const snippet = (it['text'] as string | undefined) ?? (it['snippet'] as string | undefined) ?? ''
        if (title !== '' || url !== '') {
          out.push({ title: title, url: url, snippet: snippet })
        }
      }
    }
    return out
  }

  private getSearchResultCount(): number {
    return this.getSearchResultItems().length
  }

  private getScrapeTargetPreview(): string {
    const args = this.getArgumentsObject()
    const url = args['url'] as string | undefined
    if (url !== undefined && typeof url === 'string' && url.trim() !== '') {
      return url.trim()
    }
    const urls = args['urls'] as Object
    if (Array.isArray(urls)) {
      const arr = urls as string[]
      return arr.join('\n')
    }
    return '(无)'
  }

  private getScrapeContentPreview(): string {
    const result = this.getResultObject()
    const content = result['content'] as string | undefined
    if (content !== undefined && typeof content === 'string' && content.trim() !== '') {
      return content
    }
    const text = result['text'] as string | undefined
    if (text !== undefined && typeof text === 'string' && text.trim() !== '') {
      return text
    }
    // fallback 到原始 JSON
    return this.getResultPreview().rawPreview
  }
}

interface SearchResultItemVM {
  title: string
  url: string
  snippet: string
}
