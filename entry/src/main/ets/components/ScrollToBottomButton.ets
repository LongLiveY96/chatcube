/**
 * 快速滚动按钮组件
 * 支持快速到顶部 / 快速到底部
 */

import {
  createButtonTouchHandler,
  getButtonScale,
  getButtonAnimation
} from '../utils/ButtonAnimationUtils'

@Component
export struct ScrollToBottomButton {
  // 是否显示按钮
  @Prop isVisible: boolean = false
  // 输入栏是否可见（用于计算按钮位置）
  @Prop isInputBarVisible: boolean = true
  // 底部安全区域高度（vp）
  @Prop bottomAvoidHeight: number = 0
  // 按钮方向：0=向下（到底部）, 1=向上（到顶部）
  @Prop buttonDirection: number = 0
  // 额外纵向偏移（用于多按钮错位摆放）
  @Prop extraOffsetY: number = 0
  // 点击回调
  onScrollToBottom: () => void = () => {}
  onScrollToTop: () => void = () => {}

  // 按钮按下状态
  @State private scrollBtnPressed: boolean = false
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'

  build() {
    if (this.isVisible) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(this.buttonDirection === 1 ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(20)
          .fontColor([this.themePrimary])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.surface'))
      .shadow({
        radius: this.scrollBtnPressed ? 16 : 8,
        color: this.scrollBtnPressed ? this.themePrimary + '33' : 'rgba(0, 0, 0, 0.15)',
        offsetX: 0,
        offsetY: this.scrollBtnPressed ? 4 : 2
      })
      .scale(getButtonScale(this.scrollBtnPressed))
      .animation(getButtonAnimation())
      .position({ x: '100%', y: '100%' })
      .translate({
        x: -56,
        y: (this.isInputBarVisible ?
          (-140 - this.bottomAvoidHeight) :
          (-72 - this.bottomAvoidHeight)) + this.extraOffsetY
      })
      .onTouch(createButtonTouchHandler((pressed: boolean) => {
        this.scrollBtnPressed = pressed
      }))
      .onClick(() => {
        if (this.buttonDirection === 1) {
          this.onScrollToTop()
        } else {
          this.onScrollToBottom()
        }
      })
      .transition(
        TransitionEffect.OPACITY.combine(
          TransitionEffect.scale({ x: 0.8, y: 0.8 })
        ).animation({ duration: 200, curve: Curve.EaseOut })
      )
    }
  }
}
