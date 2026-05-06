import uiEffect from '@ohos.graphics.uiEffect'
import { LengthMetrics } from '@kit.ArkUI'
import {
  BlurStrategy,
  HdsNavigationTitleBarOptions,
  ScrollEffectType,
  hdsEffect,
  hdsMaterial
} from '@kit.UIDesignKit'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from './ColorAlphaUtils'

const STATUS_BAR_CONTENT_LIGHT: string = '#1F2329'
const STATUS_BAR_CONTENT_DARK: string = '#F5F7FA'

export function buildPointLightBorderEffect(sourceBright: boolean = false): uiEffect.VisualEffect {
  return new hdsEffect.HdsEffectBuilder()
    .pointLight({
      sourceType: sourceBright ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
    })
    .buildEffect()
}

export class HdsTopNavigationBlurOptions {
  startPaddingVp: number = 0
  endPaddingVp: number = 0
  materialType: number = 100
  materialLevel: number = 10
  windowWidthVp: number = 0
  windowHeightVp: number = 0
  maskExtraHeightVp: number = 20
  blurEffectiveEndOffsetVp: number = 28
  stackBuilder: () => void = (): void => {}
}

export function getHdsTopNavigationMaskExtraHeight(windowWidthVp: number, windowHeightVp: number,
  portraitHeightVp: number = 20, landscapeHeightVp: number = 16): number {
  return windowWidthVp > windowHeightVp ? landscapeHeightVp : portraitHeightVp
}

export function getHdsTopNavigationBlurEffectiveEndOffset(windowWidthVp: number, windowHeightVp: number): number {
  return windowWidthVp > windowHeightVp ? 20 : 28
}

export function getHdsTopNavigationContentTopPadding(topAvoidHeightVp: number, windowWidthVp: number,
  windowHeightVp: number, titleHeightVp: number = 56): number {
  return topAvoidHeightVp + titleHeightVp + getHdsTopNavigationMaskExtraHeight(windowWidthVp, windowHeightVp)
}

export function getHdsTopNavigationScrollEffectType(materialType: number): ScrollEffectType {
  if (materialType === 0) {
    return ScrollEffectType.GRADIENT_BLUR
  }
  return ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
}

export function getHdsStatusBarContentColor(): string {
  return getAppUiState().isDarkMode ? STATUS_BAR_CONTENT_DARK : STATUS_BAR_CONTENT_LIGHT
}

export function getHdsTopNavigationInitialBlurRadius(materialType: number): number {
  return materialType === 0 ? 0 : 8
}

function getHdsTopNavigationOriginBackgroundColor(): string {
  return withColorAlpha(getAppUiState().themeBackground, '00')
}

function getHdsTopNavigationScrolledBackgroundColor(): string {
  return withColorAlpha(getAppUiState().themeBackground, 'E6')
}

export function getHdsTopNavigationBlurRadius(materialType: number, materialLevel: number,
  windowWidthVp: number, windowHeightVp: number): number {
  if (materialType === 0) {
    return 0
  }
  const isLandscape = windowWidthVp > windowHeightVp
  if (materialLevel === 0) {
    return isLandscape ? 20 : 26
  }
  if (materialLevel === 1) {
    return isLandscape ? 18 : 22
  }
  if (materialLevel === 2) {
    return isLandscape ? 14 : 18
  }
  return isLandscape ? 16 : 22
}

export function buildHdsTopNavigationTitleBarOptions(
  options: HdsTopNavigationBlurOptions): HdsNavigationTitleBarOptions {
  return {
    padding: {
      start: LengthMetrics.vp(options.startPaddingVp),
      end: LengthMetrics.vp(options.endPaddingVp)
    },
    content: {
      title: {
        mainTitle: ' '
      },
      stackBuilder: options.stackBuilder
    },
    style: {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: getHdsTopNavigationScrollEffectType(options.materialType),
        blurEffectiveStartOffset: LengthMetrics.vp(0),
        blurEffectiveEndOffset: LengthMetrics.vp(options.blurEffectiveEndOffsetVp)
      },
      originalStyle: {
        backgroundStyle: {
          backgroundColor: getHdsTopNavigationOriginBackgroundColor(),
          maskExtraHeight: options.maskExtraHeightVp,
          blurRadius: getHdsTopNavigationInitialBlurRadius(options.materialType)
        }
      },
      scrollEffectStyle: {
        backgroundStyle: {
          backgroundColor: getHdsTopNavigationScrolledBackgroundColor(),
          maskExtraHeight: options.maskExtraHeightVp,
          blurRadius: getHdsTopNavigationBlurRadius(options.materialType, options.materialLevel, options.windowWidthVp,
            options.windowHeightVp)
        }
      },
      blurStrategy: BlurStrategy.ENABLE,
      systemMaterialEffect: {
        materialType: options.materialType as hdsMaterial.MaterialType,
        materialLevel: options.materialLevel as hdsMaterial.MaterialLevel
      }
    },
    avoidLayoutSafeArea: true,
    enableComponentSafeArea: false
  }
}

export function buildHdsTopNavigationTitleBarOptionsForPage(materialType: number, materialLevel: number,
  windowWidthVp: number, windowHeightVp: number, stackBuilder: () => void): HdsNavigationTitleBarOptions {
  const options = new HdsTopNavigationBlurOptions()
  options.materialType = materialType
  options.materialLevel = materialLevel
  options.windowWidthVp = windowWidthVp
  options.windowHeightVp = windowHeightVp
  options.maskExtraHeightVp = getHdsTopNavigationMaskExtraHeight(windowWidthVp, windowHeightVp)
  options.blurEffectiveEndOffsetVp = getHdsTopNavigationBlurEffectiveEndOffset(windowWidthVp, windowHeightVp)
  options.stackBuilder = stackBuilder
  return buildHdsTopNavigationTitleBarOptions(options)
}
