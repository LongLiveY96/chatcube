import { motion } from '@kit.MultimodalAwarenessKit'

export function isHandAdaptiveActiveForIndex(enabled: boolean, newChatEnabled: boolean): boolean {
  if (!enabled) {
    return false
  }
  return newChatEnabled
}

export function shouldPlaceFabOnLeftForIndex(handAdaptiveEnabled: boolean, handAdaptiveNewChat: boolean,
  handAdaptiveUnsupported: boolean, currentHoldingHand: motion.HoldingHandStatus): boolean {
  if (!handAdaptiveEnabled || !handAdaptiveNewChat || handAdaptiveUnsupported) {
    return false
  }
  return currentHoldingHand === motion.HoldingHandStatus.LEFT_HAND_HELD
}

export function getFabOffsetXForIndex(placeOnLeft: boolean): number {
  if (placeOnLeft) {
    return 20
  }
  return -64
}

export function getFabOffsetYForIndex(bottomAvoidHeightVp: number): number {
  const fabHeight = 44
  const tabBarHeight = 56
  const bottomSpacing = 20
  return -(fabHeight + tabBarHeight + bottomAvoidHeightVp + bottomSpacing)
}
