/**
 * 聊天工具栏组件
 * 包含工具选择入口、推理开关等功能按钮
 */

import { ReasoningLevel } from '../models/ChatModels'
import { ReasoningControlMode } from '../services/registry/CompatibilityResolver'
import { getAppUiState } from '../state/AppUiState'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'

// 联网菜单中的引擎条目: id = SearchEngine 枚举字符串值, label = 引擎显示名
export interface SearchEngineMenuOption {
  id: string
  label: string
}

@ComponentV2
export struct ChatToolbar {
  @Param webSearchAvailable: boolean = false
  @Param webSearchEnabled: boolean = false
  // 已配置的引擎列表(Bing 永远在内, 其它引擎填了 API Key 才出现); 用于联网 chip 的下拉菜单。
  @Param availableSearchEngines: SearchEngineMenuOption[] = []
  // 当前选中的引擎 id(SearchEngine 枚举字符串)。即使 webSearchEnabled=false 也会保留以便切回时复用。
  @Param activeSearchEngineId: string = ''
  // 用户在菜单里点了某个引擎(传入引擎 id)或"禁用联网"(传入空串)。
  @Event onSearchEngineSelect: (engineId: string) => void = (_id: string): void => {}
  @Param toolSelectionAvailable: boolean = false
  @Param hasSelectedTools: boolean = false
  @Event onOpenTools: () => void = (): void => {}
  // 当前模型是否支持推理
  @Param reasoningAvailable: boolean = false
  @Param reasoningControlMode: ReasoningControlMode = ReasoningControlMode.NONE
  @Param reasoningXhighAvailable: boolean = false
  // 推理级别状态
  @Param reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  @Event onReasoningLevelChange: (value: ReasoningLevel) => void =
    (_value: ReasoningLevel): void => {}

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

  // 联网 chip 启用时显示当前选中的引擎名(过长省略号截断, 防止撞 FAB),
  // 禁用 / 找不到匹配 label 时回退到固定文案"联网"。
  // 单 chip 同时承载"开关 + 当前引擎 + 切换菜单"三个意图, 用户一眼可见当前用什么引擎。
  private getWebSearchChipText(): string {
    if (this.webSearchEnabled && this.activeSearchEngineId !== '') {
      for (let i = 0; i < this.availableSearchEngines.length; i++) {
        if (this.availableSearchEngines[i].id === this.activeSearchEngineId) {
          const label = this.availableSearchEngines[i].label.trim()
          if (label !== '') {
            return label
          }
          break
        }
      }
    }
    return pickLocalizedText('联网', 'Web search')
  }

  build() {
    Row() {
      if (this.webSearchAvailable) {
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(16)
              .fontColor([this.webSearchEnabled ? this.themePrimary : $r('app.color.text_secondary')])

            Text(this.getWebSearchChipText())
              .fontSize(14)
              .fontColor(this.webSearchEnabled ? this.themePrimary : $r('app.color.text_secondary'))
              .fontWeight(this.webSearchEnabled ? FontWeight.Medium : FontWeight.Regular)
              .margin({ left: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 96 })

            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([this.webSearchEnabled ? this.themePrimary : $r('app.color.text_secondary')])
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
          color: this.webSearchEnabled ? this.getActiveChipBorderColor() : this.getInactiveChipBorderColor()
        })
        .shadow({ radius: 10, color: this.getChipShadowColor(), offsetX: 0, offsetY: 2 })
        .animation({ duration: 200, curve: Curve.EaseOut })
        .bindMenu(this.WebSearchMenuBuilder(), {
          placement: Placement.BottomLeft,
          offset: { x: 0, y: 8 },
          backgroundColor: this.themeSurface,
          backgroundBlurStyle: BlurStyle.Regular
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
        // 推理控制按钮: 启用时只显示 level(自动/低/中/高/超高), 禁用时显示"推理"label。
        // 旧版同时显示 "推理 + level" 在小屏会和联网/工具 chip 一起把工具栏挤满, 这里精简为单 Text。
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(16)
              .fontColor([this.isReasoningEnabled() ? this.themePrimary : $r('app.color.text_secondary')])

            Text(this.getReasoningChipText())
              .fontSize(14)
              .fontColor(this.isReasoningEnabled() ? this.themePrimary : $r('app.color.text_secondary'))
              .fontWeight(this.isReasoningEnabled() ? FontWeight.Medium : FontWeight.Regular)
              .margin({ left: 4 })

            SymbolGlyph($r('sys.symbol.chevron_up'))
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
          backgroundColor: this.themeSurface,
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

  private supportsHighMaxLevels(): boolean {
    return this.reasoningControlMode === ReasoningControlMode.HIGH_MAX
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
      default:
        return $r('app.string.reasoning_level_off')
    }
  }

  // 推理 chip 单文本: 启用时只显示级别(自动/低/中/高/超高), 禁用时显示"推理"避免显示成"关闭"。
  private getReasoningChipText(): ResourceStr {
    if (this.isReasoningEnabled()) {
      return this.getReasoningLevelText(this.reasoningLevel)
    }
    return $r('app.string.chat_toolbar_reasoning')
  }

  @Builder
  private WebSearchMenuBuilder() {
    Menu() {
      ForEach(this.availableSearchEngines, (engine: SearchEngineMenuOption): void => {
        this.WebSearchEngineMenuItem(engine.id, engine.label)
      }, (engine: SearchEngineMenuOption): string => engine.id)
      this.WebSearchDisableMenuItem()
    }
  }

  @Builder
  private WebSearchEngineMenuItem(engineId: string, label: string) {
    if (this.webSearchEnabled && this.activeSearchEngineId === engineId) {
      MenuItem({
        startIcon: $r('sys.symbol.checkmark'),
        content: label
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.onSearchEngineSelect(engineId)
        })
    } else {
      MenuItem({
        content: label
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.onSearchEngineSelect(engineId)
        })
    }
  }

  @Builder
  private WebSearchDisableMenuItem() {
    if (!this.webSearchEnabled) {
      MenuItem({
        startIcon: $r('sys.symbol.checkmark'),
        content: $r('app.string.chat_search_menu_disable')
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.onSearchEngineSelect('')
        })
    } else {
      MenuItem({
        content: $r('app.string.chat_search_menu_disable')
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.onSearchEngineSelect('')
        })
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
      } else if (this.supportsHighMaxLevels()) {
        this.ReasoningMenuItem(ReasoningLevel.HIGH)
        if (this.reasoningXhighAvailable) {
          this.ReasoningMenuItem(ReasoningLevel.XHIGH)
        }
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
          this.onReasoningLevelChange(level)
        })
    } else {
      MenuItem({
        content: this.getReasoningLevelText(level)
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.onReasoningLevelChange(level)
        })
    }
  }
}
