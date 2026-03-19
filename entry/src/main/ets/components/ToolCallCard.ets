import { ToolCall, ToolResult } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { buildToolArgumentsPreview, buildToolResultPreview, ToolPayloadPreview } from '../utils/ToolPayloadSummaryUtils'

// 获取工具显示名称
function getToolDisplayName(toolCall: ToolCall): string | Resource {
  if (toolCall.displayName.trim() !== '') {
    return toolCall.displayName
  }
  const raw = toolCall.functionName as string | null | undefined
  if (raw === undefined || raw === null || raw.trim() === '') {
    return '未知工具'
  }
  const normalized = raw.toLowerCase().replace(/[\s\-]+/g, '_')
  if (normalized === 'web_search' || normalized === 'exa_search' || normalized === 'websearch'
    || normalized === 'search_web' || normalized === 'internet_search' || normalized === 'web_search_exa') {
    return $r('app.string.web_search')
  }
  return raw
}

// 工具调用卡片组件
@ComponentV2
export struct ToolCallCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param toolResult: ToolResult | null = null
  @Param isExecuting: boolean = false
  @Local isExpanded: boolean = false
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
        // 工具图标
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(14)
          .fontColor([this.isExecuting ? this.themePrimary : $r('app.color.text_secondary')])

        // 工具名称
        Text(getToolDisplayName(this.toolCall))
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
            Text(this.isExpanded ? $r('app.string.common_collapse') : $r('app.string.common_details'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))

            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([$r('app.color.text_tertiary')])
              .rotate({ angle: this.isExpanded ? 180 : 0 })
              .animation({ duration: 200, curve: Curve.EaseOut })
              .margin({ left: 2 })
          }
          .onClick(() => {
            this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
              if (this.isExpanded) {
                this.showRawArguments = false
                this.showRawResult = false
              }
              this.isExpanded = !this.isExpanded
            })
          })
        }
      }
      .width('100%')
      .height(32)
      .padding({ left: 10, right: 10 })

      // 展开的详情内容
      if (this.isExpanded && this.toolResult !== null) {
        Column({ space: 8 }) {
          Row() {
            Text($r('app.string.tool_call_args_label'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .width(56)

            Text(this.getArgumentPreview().summary)
              .fontSize(11)
              .lineHeight(16)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
          }
          .width('100%')

          Row() {
            Blank()
            Text(this.showRawArguments ? '收起原始参数' : '查看原始参数')
              .fontSize(10)
              .fontColor(this.themePrimary)
              .onClick(() => {
                this.showRawArguments = !this.showRawArguments
              })
          }
          .width('100%')

          if (this.showRawArguments) {
            Scroll() {
              Text(this.getArgumentPreview().rawPreview)
                .width('100%')
                .fontSize(11)
                .lineHeight(16)
                .fontFamily('monospace')
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .constraintSize({ maxHeight: 160 })
            .padding(10)
            .borderRadius(10)
            .backgroundColor(this.isDarkMode ? '#14171F' : '#F6F8FC')
          }

          Row() {
            Text($r('app.string.tool_call_result_label'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .width(56)

            Text(this.getResultPreview().summary)
              .fontSize(11)
              .lineHeight(16)
              .fontColor(this.hasFailedResult() ? $r('app.color.status_error') : $r('app.color.text_secondary'))
              .layoutWeight(1)
          }
          .width('100%')

          Row() {
            Blank()
            Text(this.showRawResult ? '收起原始结果' : '查看原始结果')
              .fontSize(10)
              .fontColor(this.themePrimary)
              .onClick(() => {
                this.showRawResult = !this.showRawResult
              })
          }
          .width('100%')

          if (this.showRawResult) {
            Scroll() {
              Text(this.getResultPreview().rawPreview)
                .width('100%')
                .fontSize(11)
                .lineHeight(16)
                .fontFamily('monospace')
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .constraintSize({ maxHeight: 180 })
            .padding(10)
            .borderRadius(10)
            .backgroundColor(this.isDarkMode ? '#14171F' : '#F6F8FC')
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 8 })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.divider'))
    .borderRadius(8)
    .clip(true)
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
}

