/**
 * 聊天工具栏组件
 * 包含工具选择入口、推理开关等功能按钮
 */

import { ReasoningLevel } from '../models/ChatModels'
import { ReasoningControlMode } from '../services/ProviderCompatibilityRegistry'
import { getAppUiState } from '../state/AppUiState'

const REASONING_BUDGET_OFF: number = 0
const REASONING_BUDGET_AUTO: number = -1
const REASONING_BUDGET_LOW: number = 1024
const REASONING_BUDGET_MEDIUM: number = 16000
const REASONING_BUDGET_HIGH: number = 32000
const REASONING_BUDGET_XHIGH: number = 64000
const REASONING_BUDGET_CUSTOM_DEFAULT: number = 2048

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
  @Param reasoningControlMode: ReasoningControlMode = ReasoningControlMode.NONE
  @Param reasoningXhighAvailable: boolean = false
  // 推理级别状态
  @Param reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  @Param reasoningBudget: number = -1
  @Event onReasoningBudgetChange: (value: ReasoningLevel, budget: number) => void =
    (_value: ReasoningLevel, _budget: number): void => {}

  // 主题颜色
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }

  private get themeDivider(): string {
    return getAppUiState().themeDivider
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private withAlpha(color: string, alphaHex: string): string {
    if (color.startsWith('#') && color.length === 7) {
      return `#${alphaHex}${color.slice(1)}`
    }
    if (color.startsWith('#') && color.length === 9) {
      return `#${alphaHex}${color.slice(3)}`
    }
    return color
  }

  private getChipBackgroundColor(): string {
    return this.withAlpha(this.themeSurface, this.isDarkMode ? '14' : '1A')
  }

  private getInactiveChipBorderColor(): string {
    return this.withAlpha(this.themeDivider, this.isDarkMode ? 'A6' : '73')
  }

  private getActiveChipBorderColor(): string {
    return this.themePrimary
  }

  private getChipShadowColor(): string {
    return this.isDarkMode ? 'rgba(0, 0, 0, 0.18)' : 'rgba(15, 23, 42, 0.06)'
  }

  build() {
    Row() {
      if (this.webSearchAvailable) {
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(16)
              .fontColor([this.webSearchEnabled ? this.themePrimary : $r('app.color.text_secondary')])

            Text($r('app.string.chat_toolbar_web_search'))
              .fontSize(14)
              .fontColor(this.webSearchEnabled ? this.themePrimary : $r('app.color.text_secondary'))
              .fontWeight(this.webSearchEnabled ? FontWeight.Medium : FontWeight.Regular)
              .margin({ left: 4 })
          }
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .borderRadius(16)
        .backgroundColor(this.getChipBackgroundColor())
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .border({
          width: 1,
          color: this.webSearchEnabled ? this.getActiveChipBorderColor() : this.getInactiveChipBorderColor()
        })
        .shadow({ radius: 10, color: this.getChipShadowColor(), offsetX: 0, offsetY: 2 })
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
              .fontColor([this.hasSelectedTools ? this.themePrimary : $r('app.color.text_secondary')])

            Text($r('app.string.chat_toolbar_tools'))
              .fontSize(14)
              .fontColor(this.hasSelectedTools ? this.themePrimary : $r('app.color.text_secondary'))
              .fontWeight(this.hasSelectedTools ? FontWeight.Medium : FontWeight.Regular)
              .margin({ left: 4 })
          }
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .borderRadius(16)
        .backgroundColor(this.getChipBackgroundColor())
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .border({
          width: 1,
          color: this.hasSelectedTools ? this.getActiveChipBorderColor() : this.getInactiveChipBorderColor()
        })
        .shadow({ radius: 10, color: this.getChipShadowColor(), offsetX: 0, offsetY: 2 })
        .margin({ left: this.webSearchAvailable ? 8 : 0 })
        .animation({ duration: 200, curve: Curve.EaseOut })
        .onClick(() => {
          this.onOpenTools()
        })
      }

      if (this.reasoningAvailable) {
        // 推理控制按钮
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(16)
              .fontColor([this.isReasoningEnabled() ? this.themePrimary : $r('app.color.text_secondary')])

            Text($r('app.string.chat_toolbar_reasoning'))
              .fontSize(14)
              .fontColor(this.isReasoningEnabled() ? this.themePrimary : $r('app.color.text_secondary'))
              .fontWeight(this.isReasoningEnabled() ? FontWeight.Medium : FontWeight.Regular)
              .margin({ left: 4 })

            Text(this.getReasoningLevelText(this.reasoningLevel))
              .fontSize(13)
              .fontColor(this.isReasoningEnabled() ? this.themePrimary : $r('app.color.text_secondary'))
              .fontWeight(this.isReasoningEnabled() ? FontWeight.Medium : FontWeight.Regular)
              .margin({ left: 6 })

            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([this.isReasoningEnabled() ? this.themePrimary : $r('app.color.text_secondary')])
              .margin({ left: 2 })
          }
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .borderRadius(16)
        .backgroundColor(this.getChipBackgroundColor())
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .border({
          width: 1,
          color: this.isReasoningEnabled() ? this.getActiveChipBorderColor() : this.getInactiveChipBorderColor()
        })
        .shadow({ radius: 10, color: this.getChipShadowColor(), offsetX: 0, offsetY: 2 })
        .margin({ left: this.webSearchAvailable || this.toolSelectionAvailable ? 8 : 0 })
        .animation({ duration: 200, curve: Curve.EaseOut })
        .bindMenu(this.ReasoningMenuBuilder(), {
          placement: Placement.BottomLeft,
          offset: { x: 0, y: 8 },
          backgroundColor: $r('app.color.surface'),
          backgroundBlurStyle: BlurStyle.Regular
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

  private supportsEffortLevels(): boolean {
    return this.reasoningControlMode === ReasoningControlMode.EFFORT
  }

  private getBudgetForLevel(level: ReasoningLevel): number {
    switch (level) {
      case ReasoningLevel.OFF:
        return REASONING_BUDGET_OFF
      case ReasoningLevel.AUTO:
        return REASONING_BUDGET_AUTO
      case ReasoningLevel.LOW:
        return REASONING_BUDGET_LOW
      case ReasoningLevel.MEDIUM:
        return REASONING_BUDGET_MEDIUM
      case ReasoningLevel.HIGH:
        return REASONING_BUDGET_HIGH
      case ReasoningLevel.XHIGH:
        return REASONING_BUDGET_XHIGH
      case ReasoningLevel.CUSTOM:
        return this.reasoningBudget >= REASONING_BUDGET_LOW ? this.reasoningBudget : REASONING_BUDGET_CUSTOM_DEFAULT
      default:
        return REASONING_BUDGET_AUTO
    }
  }

  private getReasoningLevelText(level: ReasoningLevel): ResourceStr {
    switch (level) {
      case ReasoningLevel.AUTO:
        return $r('app.string.reasoning_level_auto')
      case ReasoningLevel.LOW:
        return $r('app.string.reasoning_level_low')
      case ReasoningLevel.MEDIUM:
        return $r('app.string.reasoning_level_medium')
      case ReasoningLevel.HIGH:
        return $r('app.string.reasoning_level_high')
      case ReasoningLevel.XHIGH:
        return $r('app.string.reasoning_level_xhigh')
      case ReasoningLevel.CUSTOM:
        return this.reasoningBudget >= REASONING_BUDGET_LOW ?
          `${this.reasoningBudget} tokens` :
          $r('app.string.reasoning_budget_custom')
      default:
        return $r('app.string.reasoning_level_off')
    }
  }

  @Builder
  private ReasoningMenuBuilder() {
    Menu() {
      this.ReasoningMenuItem(ReasoningLevel.OFF)
      this.ReasoningMenuItem(ReasoningLevel.AUTO)
      if (this.supportsEffortLevels()) {
        this.ReasoningMenuItem(ReasoningLevel.LOW)
        this.ReasoningMenuItem(ReasoningLevel.MEDIUM)
        this.ReasoningMenuItem(ReasoningLevel.HIGH)
        if (this.reasoningXhighAvailable) {
          this.ReasoningMenuItem(ReasoningLevel.XHIGH)
        }
        this.ReasoningMenuItem(ReasoningLevel.CUSTOM)
      }
    }
  }

  @Builder
  private ReasoningMenuItem(level: ReasoningLevel) {
    if (this.reasoningLevel === level) {
      MenuItem({
        startIcon: $r('sys.symbol.checkmark'),
        content: this.getReasoningLevelText(level)
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.onReasoningBudgetChange(level, this.getBudgetForLevel(level))
        })
    } else {
      MenuItem({
        content: this.getReasoningLevelText(level)
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.onReasoningBudgetChange(level, this.getBudgetForLevel(level))
        })
    }
  }
}
