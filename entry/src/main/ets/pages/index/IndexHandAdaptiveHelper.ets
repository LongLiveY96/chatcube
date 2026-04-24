import { motion } from '@kit.MultimodalAwarenessKit'

export const INDEX_NEW_CHAT_FAB_SIZE = 58
export const INDEX_NEW_CHAT_FAB_STACK_WIDTH = 58
export const INDEX_NEW_CHAT_FAB_STACK_HEIGHT = 58
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
  return -(INDEX_NEW_CHAT_FAB_SIZE + 20)
}

export function getFabOffsetYForIndex(bottomOverlayHeightVp: number): number {
  return -(INDEX_NEW_CHAT_FAB_STACK_HEIGHT + bottomOverlayHeightVp + INDEX_NEW_CHAT_FAB_BOTTOM_SPACING)
}
