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
  // 按钮"左上角距屏幕底"基线(vp), 与 ScrollToBottomButton 共享同一基线
  @Param fixedBottomOffset: number = 128
  @Param bottomAvoidHeight: number = 0
  @Event onScrollToBottom: () => void = () => {}

  @Local private btnPressed: boolean = false
  @Local private loadingAngle: number = 0
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDark(): boolean {
    return getAppUiState().isDarkMode
  }

  private get materialBg(): string {
    return this.isDark ? 'rgba(30, 30, 30, 0.72)' : 'rgba(255, 255, 255, 0.72)'
  }

  private get materialBorder(): string {
    return this.isDark ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.06)'
  }

  // 用 animateTo iterations:-1 让旋转走系统动画线程, 不再依赖 setInterval(16ms) JS 计时器
  // 抢占主线程。组件 if(isVisible) 条件渲染, 销毁时动画自然停, 无需 cancel API。
  // expectedFrameRateRange 在高刷屏 (120Hz) 上限制 expected 60 避免过度刷新。
  // 注意: 必须在 Progress 节点的 onAppear 启动动画。若放在 aboutToAppear, 此时
  // 父组件 ScrollToBottomLoadingButton 实例已创建但 if(isVisible)=false, UI 树里
  // 没有 rotate 目标节点, 隐式动画无法绑定; 等 isVisible 变 true 时 aboutToAppear
  // 不会再触发, 旋转就停在 0°。
  private startSpinAnimation(): void {
    this.loadingAngle = 0
    this.getUIContext()?.animateTo({
      duration: 1000,
      curve: Curve.Linear,
      iterations: -1,
      playMode: PlayMode.Normal,
      expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
    }, () => {
      this.loadingAngle = 360
    })
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
          .onAppear(() => {
            // 节点真正挂载到 UI 树时启动旋转, 隐式动画才能绑定到 rotate
            this.startSpinAnimation()
          })

        // 中心向下箭头按钮
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(20)
            .fontColor([this.themePrimary])
        }
        .width(40)
        .height(40)
        .backgroundColor(this.materialBg)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .border({
          width: 0.5,
          color: this.materialBorder
        })
        .shadow({ radius: 8, color: this.isDark ? 'rgba(0,0,0,0.4)' : 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 2 })
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
        y: -(this.fixedBottomOffset + this.bottomAvoidHeight)
      })
      // 与 ScrollToBottomButton 同步, 跟随输入区高度变化时平滑过渡
      .animation({ duration: 200, curve: Curve.EaseOut })
      .transition(
        TransitionEffect.OPACITY.combine(
          TransitionEffect.scale({ x: 0.8, y: 0.8 })
        ).animation({ duration: 200, curve: Curve.EaseOut })
      )
    }
  }
}
