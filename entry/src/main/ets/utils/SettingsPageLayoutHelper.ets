import { getCenteredPageMaxWidth, LayoutSizeClass } from '../config/LayoutProfile'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'

export function isLandscapeExpandedLayout(layoutSizeClass: string, windowWidthVp: number, windowHeightVp: number): boolean {
  if (layoutSizeClass !== LayoutSizeClass.EXPANDED) {
    return false
  }
  if (windowWidthVp <= 0 || windowHeightVp <= 0) {
    return false
  }
  return windowWidthVp > windowHeightVp
}

export function isSettingsPageExpandedLayout(layoutSizeClass: string, settingsDetailPresentationMode: string,
  windowWidthVp: number, windowHeightVp: number): boolean {
  if (settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE) {
    return false
  }
  return isLandscapeExpandedLayout(layoutSizeClass, windowWidthVp, windowHeightVp)
}

export function getSettingsPageContentMaxWidth(layoutSizeClass: string, windowWidthVp: number,
  settingsDetailPresentationMode: string, windowHeightVp: number): number {
  if (!isSettingsPageExpandedLayout(layoutSizeClass, settingsDetailPresentationMode, windowWidthVp, windowHeightVp)) {
    return 99999
  }
  return getCenteredPageMaxWidth(windowWidthVp)
}
