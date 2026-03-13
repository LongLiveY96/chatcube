/**
 * 带 Loading 圆环旋转动效的底部居中"回到底部"按钮
 * 仅在 AI 流式生成中且用户不在底部时显示
 */

import {
  createButtonTouchHandler,
  getButtonScale,
  getButtonAnimation
} from '../utils/ButtonAnimationUtils'
import { getAppUiState } from '../state/AppUiState'

@ComponentV2
export struct ScrollToBottomLoadingButton {
  @Param isVisible: boolean = false
  @Param isInputBarVisible: boolean = true
  @Param bottomAvoidHeight: number = 0
  @Event onScrollToBottom: () => void = () => {}

  @Local private btnPressed: boolean = false
  @Local private loadingAngle: number = 0
  private rotationTimer: number = -1
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    if (this.isVisible) {
      this.startLoadingRotation()
    }
  }

  aboutToDisappear(): void {
    this.stopLoadingRotation()
  }

  @Monitor('isVisible')
  onVisibleChange(): void {
    if (this.isVisible) {
      this.startLoadingRotation()
      return
    }
    this.stopLoadingRotation()
  }

  private startLoadingRotation(): void {
    if (this.rotationTimer !== -1) {
      return
    }
    this.loadingAngle = 0
    this.rotationTimer = setInterval(() => {
      this.loadingAngle = (this.loadingAngle + 12) % 360
    }, 16)
  }

  private stopLoadingRotation(): void {
    if (this.rotationTimer !== -1) {
      clearInterval(this.rotationTimer)
      this.rotationTimer = -1
    }
    this.loadingAngle = 0
  }

  build() {
    if (this.isVisible) {
      Stack({ alignContent: Alignment.Center }) {
        // 外围 loading 圆环
        Progress({ value: 25, total: 100, type: ProgressType.Ring })
          .width(48)
          .height(48)
          .color(this.themePrimary)
          .backgroundColor('transparent')
          .style({ strokeWidth: 2.5 })
          .rotate({ angle: this.loadingAngle })

        // 中心向下箭头按钮
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(20)
            .fontColor([this.themePrimary])
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.surface'))
        .shadow({ radius: 8, color: 'rgba(0,0,0,0.15)', offsetX: 0, offsetY: 2 })
        .scale(getButtonScale(this.btnPressed))
        .animation(getButtonAnimation())
        .onTouch(createButtonTouchHandler((pressed: boolean) => {
          this.btnPressed = pressed
        }))
        .onClick(() => {
          this.onScrollToBottom()
        })
      }
      .position({ x: '50%', y: '100%' })
      .translate({
        x: '-50%',
        y: this.isInputBarVisible
          ? (-140 - this.bottomAvoidHeight)
          : (-72 - this.bottomAvoidHeight)
      })
      .transition(
        TransitionEffect.OPACITY.combine(
          TransitionEffect.scale({ x: 0.8, y: 0.8 })
        ).animation({ duration: 200, curve: Curve.EaseOut })
      )
    }
  }
}

