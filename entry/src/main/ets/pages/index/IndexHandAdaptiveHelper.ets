import { motion } from '@kit.MultimodalAwarenessKit'

export const INDEX_NEW_CHAT_FAB_SIZE = 48
export const INDEX_NEW_CHAT_FAB_BOTTOM_SPACING = 20

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
  return -68
}

export function getFabOffsetYForIndex(bottomOverlayHeightVp: number): number {
  return -(INDEX_NEW_CHAT_FAB_SIZE + bottomOverlayHeightVp + INDEX_NEW_CHAT_FAB_BOTTOM_SPACING)
}
