/**
 * 聊天工具栏组件
 * 包含联网查询开关、推理级别选择等功能按钮
 */

import { ReasoningLevel } from '../models/ChatModels'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { getAppUiState } from '../state/AppUiState'

@ComponentV2
export struct ChatToolbar {
  // 联网查询全局可用状态（工具中心控制）
  @Param webSearchAvailable: boolean = false
  // 联网查询本会话开关状态（聊天页面控制）
  @Param webSearchEnabled: boolean = false
  @Event onWebSearchEnabledChange: (value: boolean) => void = (_value: boolean): void => {}
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
      // 联网查询开关（仅在工具中心启用时展示）
      if (this.webSearchAvailable) {
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph($r('sys.symbol.worldclock'))
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
        // 背景色过渡动画
        .animation({ duration: 200, curve: Curve.EaseOut })
        .onClick(() => {
          const newValue = !this.webSearchEnabled
          this.onWebSearchEnabledChange(newValue)
          const prefsService = getPreferencesService()
          prefsService.setBoolean(PreferenceKeys.SEARCH_CONVERSATION_ENABLED, newValue)
        })
      }

      if (this.reasoningAvailable) {
        // 推理级别按钮
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(16)
              .fontColor([this.reasoningLevel !== ReasoningLevel.OFF ? Color.White : $r('app.color.text_secondary')])

            Text(this.getReasoningLevelText())
              .fontSize(14)
              .fontColor(this.reasoningLevel !== ReasoningLevel.OFF ? Color.White : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .clip(true)
        .backgroundColor(this.reasoningLevel !== ReasoningLevel.OFF ? this.themePrimary : $r('app.color.surface'))
        .margin({ left: this.webSearchAvailable ? 8 : 0 })
        .border(this.reasoningLevel !== ReasoningLevel.OFF ? undefined : {
          width: 0.5,
          color: $r('app.color.divider')
        })
        // 背景色过渡动画
        .animation({ duration: 200, curve: Curve.EaseOut })
        .bindMenu(this.ReasoningMenuBuilder(), {
          placement: Placement.TopLeft
        })
      }

      Blank()
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
    .margin({ bottom: 8 })
  }

  // 获取推理级别显示文本
  private getReasoningLevelText(): Resource {
    switch (this.reasoningLevel) {
      case ReasoningLevel.OFF:
        return $r('app.string.chat_toolbar_reasoning')
      case ReasoningLevel.LOW:
        return $r('app.string.chat_toolbar_reasoning_low')
      case ReasoningLevel.MEDIUM:
        return $r('app.string.chat_toolbar_reasoning_medium')
      case ReasoningLevel.HIGH:
        return $r('app.string.chat_toolbar_reasoning_high')
      default:
        return $r('app.string.chat_toolbar_reasoning')
    }
  }

  // 推理级别菜单构建器
  @Builder
  ReasoningMenuBuilder() {
    Column() {
      // 关闭选项
      this.ReasoningMenuItem(ReasoningLevel.OFF, $r('app.string.chat_toolbar_reasoning_off'))
      Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
      // 轻度推理
      this.ReasoningMenuItem(ReasoningLevel.LOW, $r('app.string.chat_toolbar_reasoning_low'))
      Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
      // 中度推理
      this.ReasoningMenuItem(ReasoningLevel.MEDIUM, $r('app.string.chat_toolbar_reasoning_medium'))
      Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
      // 重度推理
      this.ReasoningMenuItem(ReasoningLevel.HIGH, $r('app.string.chat_toolbar_reasoning_high'))
    }
    .width(160)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  ReasoningMenuItem(level: ReasoningLevel, label: string | Resource) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor(this.reasoningLevel === level ? this.themePrimary : $r('app.color.text_primary'))

      Blank()

      if (this.reasoningLevel === level) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([this.themePrimary])
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      this.onReasoningLevelChange(level)
    })
  }
}

