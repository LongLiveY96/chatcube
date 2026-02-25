import { ToolCall, ToolResult } from '../models/ChatModels'

// 获取工具显示名称
function getToolDisplayName(toolId: string): string | Resource {
  const raw = toolId as string | null | undefined
  if (raw === undefined || raw === null || raw.trim() === '') {
    return '未知工具'
  }
  const normalized = raw.toLowerCase().replace(/[\s\-]+/g, '_')
  if (normalized === 'web_search' || normalized === 'exa_search' || normalized === 'websearch'
    || normalized === 'search_web' || normalized === 'internet_search' || normalized === 'web_search_exa') {
    return $r('app.string.web_search')
  }
  if (normalized === 'weather_query' || normalized === 'weather' || normalized === 'weather_search'
    || normalized === 'get_weather' || normalized === 'query_weather' || normalized === 'weather_lookup') {
    return $r('app.string.weather_query')
  }
  return raw
}

// 工具调用卡片组件
@Component
export struct ToolCallCard {
  @ObjectLink toolCall: ToolCall
  @Prop toolResult: ToolResult | null = null
  @Prop isExecuting: boolean = false
  @State isExpanded: boolean = false
  // 跳动点动画状态
  @State dot1Scale: number = 0.6
  @State dot2Scale: number = 0.6
  @State dot3Scale: number = 0.6
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  private dotAnimationTimer: number = -1

  aboutToAppear(): void {
    if (this.isExecuting) {
      this.startDotAnimation()
    }
  }

  aboutToDisappear(): void {
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
        Text(getToolDisplayName(this.toolCall.functionName))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isExecuting ? this.themePrimary : $r('app.color.text_secondary'))
          .margin({ left: 6 })

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
          // 已完成：显示勾选图标
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(14)
            .fontColor([$r('app.color.status_success')])
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
        Column() {
          // 参数
          Row() {
            Text($r('app.string.tool_call_args_label'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))

            Text(this.formatArguments())
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ bottom: 4 })

          // 结果摘要
          Row() {
            Text($r('app.string.tool_call_result_label'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))

            Text(this.formatResultSummary())
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
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

  // 格式化参数显示
  private formatArguments(): string {
    try {
      const args = JSON.parse(this.toolCall.arguments) as Record<string, string>
      const parts: string[] = []
      const keys = Object.keys(args)
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i]
        parts.push(`${key}="${args[key]}"`)
      }
      return parts.join(', ')
    } catch (e) {
      return this.toolCall.arguments
    }
  }

  // 格式化结果摘要
  private formatResultSummary(): string | Resource {
    if (this.toolResult === null) {
      return $r('app.string.tool_call_executing')
    }
    try {
      const result = JSON.parse(this.toolResult.content) as Record<string, Object>
      // 检查是否有错误
      if (result['error'] !== undefined) {
        return `${result['error']}`
      }
      // 检查是否是搜索结果
      if (result['results'] !== undefined) {
        const results = result['results'] as Array<Object>
        return `${results.length}`
      }
      if (result['forecast'] !== undefined) {
        const forecast = result['forecast'] as Array<Object>
        return `${forecast.length}天预报`
      }
      return $r('app.string.tool_call_completed')
    } catch (e) {
      // 如果不是 JSON，返回截断的内容
      const content = this.toolResult.content
      if (content.length > 50) {
        return content.substring(0, 50) + '...'
      }
      return content
    }
  }
}
