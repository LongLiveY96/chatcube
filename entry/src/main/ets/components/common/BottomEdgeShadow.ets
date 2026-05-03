/**
 * 页面底部安全区上方的柔和阴影叠层
 * - 自动跟随深浅色模式切换强度
 * - 不响应点击,纯视觉装饰
 * - 通常以 alignBottom 的 Stack 子项形式叠在页面底部
 */

import { getAppUiState } from '../../state/AppUiState'

@ComponentV2
export struct BottomEdgeShadow {
  @Param height: number = 32
  // 浅色模式下的最大透明度(0-1)
  @Param lightAlpha: number = 0.10
  // 深色模式下的最大透明度(0-1)
  @Param darkAlpha: number = 0.40

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private buildBottomColor(): string {
    const alpha = this.isDarkMode ? this.darkAlpha : this.lightAlpha
    return `rgba(0, 0, 0, ${alpha})`
  }

  build() {
    Column()
      .width('100%')
      .height(this.height)
      .linearGradient({
        angle: 180, // 由顶向下:顶端透明 → 底端柔和黑
        colors: [
          ['rgba(0, 0, 0, 0)', 0.0],
          [this.buildBottomColor(), 1.0]
        ]
      })
      .hitTestBehavior(HitTestMode.None)
  }
}
