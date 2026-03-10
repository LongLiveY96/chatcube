export enum LayoutSizeClass {
  COMPACT = 'compact',
  MEDIUM = 'medium',
  EXPANDED = 'expanded'
}

const COMPACT_MAX_WIDTH_VP = 600
const EXPANDED_MIN_WIDTH_VP = 840

export function resolveLayoutSizeClass(widthVp: number): LayoutSizeClass {
  if (widthVp < COMPACT_MAX_WIDTH_VP) {
    return LayoutSizeClass.COMPACT
  }
  if (widthVp < EXPANDED_MIN_WIDTH_VP) {
    return LayoutSizeClass.MEDIUM
  }
  return LayoutSizeClass.EXPANDED
}

export function isExpandedLayoutClass(sizeClass: string): boolean {
  return sizeClass === LayoutSizeClass.EXPANDED
}

export function getIndexChatListPaneWidth(widthVp: number): number {
  if (widthVp >= 1360) {
    return 420
  }
  if (widthVp >= 1120) {
    return 380
  }
  return 340
}

export function getIndexPageHorizontalPadding(widthVp: number): number {
  if (widthVp >= 1360) {
    return 20
  }
  if (widthVp >= 1120) {
    return 16
  }
  return 12
}

export function getChatContentMaxWidth(widthVp: number): number {
  if (widthVp >= 1360) {
    return 960
  }
  if (widthVp >= 1120) {
    return 880
  }
  return 760
}

export function getCenteredPageMaxWidth(widthVp: number): number {
  if (widthVp >= 1360) {
    return 980
  }
  if (widthVp >= 1120) {
    return 900
  }
  return 760
}
