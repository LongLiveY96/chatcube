/**
 * 聊天工具栏组件
 * 包含工具选择入口、推理开关等功能按钮
 */

import { ReasoningLevel } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'

@ComponentV2
export struct ChatToolbar {
  @Param webSearchAvailable: boolean = false
  @Param webSearchEnabled: boolean = false
  @Event onToggleWebSearch: () => void = (): void => {}
  @Param toolSelectionAvailable: boolean = false
  @Param hasSelectedTools: boolean = false
  @Event onOpenTools: () => void = (): void => {}
  // 当前模型是否支持推理
  @Param reasoningAvailable: boolean = false
  // 推理级别状态
  @Param reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  @Event onReasoningLevelChange: (value: ReasoningLevel) => void = (_value: ReasoningLevel): void => {}

  // 主题颜色
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  build() {
    Row() {
      if (this.webSearchAvailable) {
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(16)
              .fontColor([this.webSearchEnabled ? Color.White : $r('app.color.text_secondary')])

            Text($r('app.string.chat_toolbar_web_search'))
              .fontSize(14)
              .fontColor(this.webSearchEnabled ? Color.White : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .clip(true)
        .backgroundColor(this.webSearchEnabled ? this.themePrimary : $r('app.color.surface'))
        .border(this.webSearchEnabled ? undefined : {
          width: 0.5,
          color: $r('app.color.divider')
        })
        .animation({ duration: 200, curve: Curve.EaseOut })
        .onClick(() => {
          this.onToggleWebSearch()
        })
      }

      if (this.toolSelectionAvailable) {
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(16)
              .fontColor([this.hasSelectedTools ? Color.White : $r('app.color.text_secondary')])

            Text($r('app.string.chat_toolbar_tools'))
              .fontSize(14)
              .fontColor(this.hasSelectedTools ? Color.White : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .clip(true)
        .backgroundColor(this.hasSelectedTools ? this.themePrimary : $r('app.color.surface'))
        .border(this.hasSelectedTools ? undefined : {
          width: 0.5,
          color: $r('app.color.divider')
        })
        .margin({ left: this.webSearchAvailable ? 8 : 0 })
        .animation({ duration: 200, curve: Curve.EaseOut })
        .onClick(() => {
          this.onOpenTools()
        })
      }

      if (this.reasoningAvailable) {
        // 推理开关按钮
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(16)
              .fontColor([this.isReasoningEnabled() ? Color.White : $r('app.color.text_secondary')])

            Text($r('app.string.chat_toolbar_reasoning'))
              .fontSize(14)
              .fontColor(this.isReasoningEnabled() ? Color.White : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .clip(true)
        .backgroundColor(this.isReasoningEnabled() ? this.themePrimary : $r('app.color.surface'))
        .margin({ left: this.webSearchAvailable || this.toolSelectionAvailable ? 8 : 0 })
        .border(this.isReasoningEnabled() ? undefined : {
          width: 0.5,
          color: $r('app.color.divider')
        })
        .animation({ duration: 200, curve: Curve.EaseOut })
        .onClick(() => {
          this.onReasoningLevelChange(this.isReasoningEnabled() ? ReasoningLevel.OFF : ReasoningLevel.MEDIUM)
        })
      }

      Blank()
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
    .margin({ bottom: 8 })
  }

  private isReasoningEnabled(): boolean {
    return this.reasoningLevel !== ReasoningLevel.OFF
  }
}

