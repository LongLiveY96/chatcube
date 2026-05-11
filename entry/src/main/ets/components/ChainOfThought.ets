/**
 * ChainOfThought 时间线组件
 *
 * 用于承载一组推理步骤 + 工具调用步骤的链式内容,
 * 与 rikkahub 同名组件的口径对齐:
 * - 左侧一条竖线串联所有步骤
 * - 每个步骤有 icon + label + extra + 可展开内容
 * - 步骤数超过 collapsedVisibleCount 时自动折叠,顶部提供 "显示更多 / 收起" 切换
 * - 子步骤通过 ChainOfThoughtStep 子组件传入, 各自管理展开/折叠状态
 *
 * 本版本用 @BuilderParam 让父级以内联方式提供每步的内容, 复杂度最低。
 */

import { getAppUiState } from '../state/AppUiState'

@ComponentV2
export struct ChainOfThought {
  // 步骤总数
  @Param stepCount: number = 0
  // 未展开时默认保留可见的尾部步骤数
  @Param collapsedVisibleCount: number = 2
  // 父级提供的步骤渲染: 只要调用 (index) 即可把指定步骤塞进来
  @BuilderParam renderStep: (visibleIndex: number, absoluteIndex: number) => void
  // 是否处于 "展开全部步骤" 状态;由父级外部控制更灵活,这里内部维护默认态
  @Local expanded: boolean = false

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private canCollapse(): boolean {
    return this.stepCount > this.collapsedVisibleCount
  }

  private getVisibleRange(): number[] {
    // 可见步骤的绝对索引列表(按渲染顺序)
    if (this.expanded || !this.canCollapse()) {
      const all: number[] = []
      for (let i = 0; i < this.stepCount; i++) {
        all.push(i)
      }
      return all
    }
    const tail: number[] = []
    const start = this.stepCount - this.collapsedVisibleCount
    for (let i = start; i < this.stepCount; i++) {
      tail.push(i)
    }
    return tail
  }

  build() {
    Column() {
      // 顶部折叠切换
      if (this.canCollapse()) {
        Row() {
          SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([this.themePrimary])
            .width(24)

          Text(this.expanded
            ? $r('app.string.chain_of_thought_collapse')
            : this.buildShowMoreLabel(this.stepCount - this.collapsedVisibleCount))
            .fontSize(12)
            .fontColor(this.themePrimary)
            .margin({ left: 4 })
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
        .onClick(() => {
          this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
            this.expanded = !this.expanded
          })
        })
      }

      // 步骤列表:左侧 12vp 位置画一条竖线(用 Stack 背景色条实现),
      // 每步的图标绘制时覆盖一个 AI 气泡色的小方块来遮住线条,视觉上就是 “线串珠”
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width(1)
          .layoutWeight(1)
          .margin({ left: 12, top: 16, bottom: 16 })
          .backgroundColor($r('app.color.divider'))

        Column() {
          ForEach(this.getVisibleRange(), (absIndex: number, visIdx: number) => {
            this.renderStep(visIdx, absIndex)
          }, (absIndex: number) => absIndex.toString())
        }
        .width('100%')
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.themeAiBubble)
    .borderRadius(10)
  }

  private buildShowMoreLabel(count: number): ResourceStr {
    // HarmonyOS 的 $r 插值需要显式传 count, 这里用 plain string 拼,避免本地化插值复杂度
    return `显示更多 ${count} 步`
  }
}

/**
 * 单个时间线步骤, 内部维护展开/折叠状态;
 * content 为空时表示该步不可展开, 只显示标题行。
 */
@ComponentV2
export struct ChainOfThoughtStep {
  @BuilderParam icon: () => void
  @Param label: Resource | string = ''
  @Param extra: Resource | string = ''
  // 标题整体可点击,用于诸如 “详情(打开 sheet)” 的自定义交互;若提供则覆盖 expand/collapse
  @Param onLabelClick: () => void = () => {}
  @Param hasOnLabelClick: boolean = false
  @BuilderParam content: () => void
  @Param hasContent: boolean = false
  @Param initialExpanded: boolean = false
  // 外部受控:传入后覆盖内部 expanded
  @Param controlledExpanded: boolean = false
  @Param isControlled: boolean = false
  @Event $controlledExpanded: (value: boolean) => void = () => {}
  @Local private expandedInternal: boolean = false

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  aboutToAppear(): void {
    this.expandedInternal = this.initialExpanded
  }

  private isExpanded(): boolean {
    return this.isControlled ? this.controlledExpanded : this.expandedInternal
  }

  private setExpanded(next: boolean): void {
    if (this.isControlled) {
      this.$controlledExpanded(next)
    } else {
      this.expandedInternal = next
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        // 图标在左侧,用不透明背景色遮住背后的竖线
        Stack() {
          Column()
            .width(20)
            .height(20)
            .borderRadius(10)
            .backgroundColor(this.themeAiBubble)
          Column() {
            this.icon()
          }
          .width(16)
          .height(16)
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
        }
        .width(24)
        .height(24)

        Text(this.label)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.extra !== '' && this.extra !== undefined) {
          Text(this.extra)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 6 })
        }

        if (this.hasOnLabelClick) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(12)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ left: 4 })
        } else if (this.hasContent) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([$r('app.color.text_tertiary')])
            .rotate({ angle: this.isExpanded() ? 180 : 0 })
            .animation({ duration: 200, curve: Curve.EaseOut })
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
      .onClick(() => {
        if (this.hasOnLabelClick) {
          this.onLabelClick()
          return
        }
        if (this.hasContent) {
          this.setExpanded(!this.isExpanded())
        }
      })

      if (this.hasContent && this.isExpanded()) {
        Column() {
          this.content()
        }
        .width('100%')
        .padding({ left: 32, top: 4, bottom: 8 })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }
    .width('100%')
  }
}
