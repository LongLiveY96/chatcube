/**
 * 按钮动画工具函数
 * 提取重复的按钮按下动画逻辑
 */

/**
 * 按钮动画配置
 */
export interface ButtonAnimationConfig {
  pressedScale: number        // 按下时的缩放比例，默认 0.95
  animationDuration: number   // 动画时长（毫秒），默认 150
  animationCurve: Curve       // 动画曲线，默认 EaseOut
}

/**
 * 默认按钮动画配置
 */
export const DEFAULT_BUTTON_ANIMATION_CONFIG: ButtonAnimationConfig = {
  pressedScale: 0.95,
  animationDuration: 150,
  animationCurve: Curve.EaseOut
}

/**
 * 创建按钮触摸事件处理器
 * @param onPressedChange 按下状态变化回调
 * @returns 触摸事件处理函数
 */
export function createButtonTouchHandler(
  onPressedChange: (pressed: boolean) => void
): (event: TouchEvent) => void {
  return (event: TouchEvent): void => {
    if (event.type === TouchType.Down) {
      onPressedChange(true)
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      onPressedChange(false)
    }
  }
}

/**
 * 获取按钮缩放值
 * @param isPressed 是否按下
 * @param config 动画配置（可选）
 * @returns 缩放配置对象
 */
export function getButtonScale(
  isPressed: boolean,
  config: ButtonAnimationConfig = DEFAULT_BUTTON_ANIMATION_CONFIG
): ScaleOptions {
  const scale = isPressed ? config.pressedScale : 1
  return { x: scale, y: scale }
}

/**
 * 获取按钮动画配置
 * @param config 动画配置（可选）
 * @returns 动画属性对象
 */
export function getButtonAnimation(
  config: ButtonAnimationConfig = DEFAULT_BUTTON_ANIMATION_CONFIG
): AnimateParam {
  return {
    duration: config.animationDuration,
    curve: config.animationCurve
  }
}
