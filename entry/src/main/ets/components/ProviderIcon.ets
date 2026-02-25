/**
 * 供应商图标组件
 * 统一处理供应商和模型图标的显示
 * 支持三种图标类型：SVG、文字、自定义图片
 */

import { buildIconResourcePath } from '../utils/ProviderIconUtils'
import { TRANSPARENT_BG_COLOR } from '../utils/IconGeneratorUtils'

@Component
export struct ProviderIcon {
  @Prop iconPath: string = ''
  @Prop iconSize: number = 40
  @Prop bgColor: ResourceColor = Color.Transparent
  @Prop radius: number = 12
  @Prop fallbackSymbol: Resource = $r('sys.symbol.message')
  @Prop fallbackColor: ResourceColor = Color.White
  // 新增：图标类型相关参数
  @Prop iconType: string = 'svg'
  @Prop textIcon: string = ''
  @Prop textIconBgColor: string = ''
  @Prop customImagePath: string = ''
  // 新增：品牌色参数（用于 SVG 图标的边框）
  @Prop brandColor: ResourceColor = ''
  @StorageProp('isDarkMode') isDarkMode: boolean = false

  // 判断是否显示品牌色边框
  private shouldShowBrandBorder(): boolean {
    return this.iconType === 'svg' && this.brandColor !== ''
  }

  // 判断是否为透明背景
  private isTransparentBg(): boolean {
    return this.textIconBgColor === TRANSPARENT_BG_COLOR || this.textIconBgColor === ''
  }

  // 获取背景色
  private getBackgroundColor(): ResourceColor {
    if (this.iconType === 'text') {
      if (this.isTransparentBg()) {
        return Color.Transparent
      }
      return this.textIconBgColor
    }
    return this.bgColor
  }

  // 获取文字颜色（透明背景时使用深色文字）
  private getTextColor(): ResourceColor {
    if (this.isTransparentBg()) {
      return $r('app.color.text_primary')
    }
    return Color.White
  }

  build() {
    Column() {
      // SVG 图标
      if (this.iconType === 'svg' && this.iconPath !== '') {
        Image($rawfile(buildIconResourcePath(this.iconPath)))
          .width(this.iconSize * 0.6)
          .height(this.iconSize * 0.6)
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.High)
      }
      // 文字图标
      else if (this.iconType === 'text' && this.textIcon !== '') {
        Text(this.textIcon)
          .fontSize(this.isTransparentBg() ? this.iconSize * 0.7 : this.iconSize * 0.45)
          .fontColor(this.getTextColor())
          .fontWeight(FontWeight.Bold)
      }
      // 自定义图片
      else if (this.iconType === 'image' && this.customImagePath !== '') {
        Image('file://' + this.customImagePath)
          .width(this.iconSize * 0.6)
          .height(this.iconSize * 0.6)
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.High)
          .borderRadius(this.radius * 0.5)
      }
      // 默认 fallback（显示云图标）
      else {
        SymbolGlyph(this.fallbackSymbol)
          .fontSize(this.iconSize * 0.55)
          .fontColor([this.fallbackColor])
      }
    }
    .width(this.iconSize)
    .height(this.iconSize)
    .borderRadius(this.radius)
    .backgroundColor(this.getBackgroundColor())
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .border(this.shouldShowBrandBorder() ? {
      width: 2,
      color: this.brandColor
    } : undefined)
  }
}

@Component
export struct ProviderIconSmall {
  @Prop iconPath: string = ''
  @Prop iconSize: number = 24
  // 新增：图标类型相关参数
  @Prop iconType: string = 'svg'
  @Prop textIcon: string = ''
  @Prop textIconBgColor: string = ''
  @Prop customImagePath: string = ''
  // 新增：品牌色参数（用于 SVG 图标的边框）
  @Prop brandColor: ResourceColor = ''
  @StorageProp('isDarkMode') isDarkMode: boolean = false

  // 判断是否显示品牌色边框
  private shouldShowBrandBorder(): boolean {
    return this.iconType === 'svg' && this.brandColor !== ''
  }

  // 判断是否为透明背景
  private isTransparentBg(): boolean {
    return this.textIconBgColor === TRANSPARENT_BG_COLOR || this.textIconBgColor === ''
  }

  build() {
    // SVG 图标
    if (this.iconType === 'svg' && this.iconPath !== '') {
      Image($rawfile(buildIconResourcePath(this.iconPath)))
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.High)
        .border(this.shouldShowBrandBorder() ? {
          width: 1.5,
          color: this.brandColor
        } : undefined)
        .borderRadius(this.iconSize * 0.2)
    }
    // 文字图标
    else if (this.iconType === 'text' && this.textIcon !== '') {
      if (this.isTransparentBg()) {
        // 透明背景：直接显示文字/emoji
        Text(this.textIcon)
          .fontSize(this.iconSize * 0.85)
          .fontWeight(FontWeight.Bold)
      } else {
        // 有背景色：显示彩色背景 + 白色文字
        Column() {
          Text(this.textIcon)
            .fontSize(this.iconSize * 0.45)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
        }
        .width(this.iconSize)
        .height(this.iconSize)
        .borderRadius(this.iconSize * 0.3)
        .backgroundColor(this.textIconBgColor)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    // 自定义图片
    else if (this.iconType === 'image' && this.customImagePath !== '') {
      Image('file://' + this.customImagePath)
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Cover)
        .interpolation(ImageInterpolation.High)
        .borderRadius(this.iconSize * 0.3)
    }
    // 默认 fallback
    else {
      SymbolGlyph($r('sys.symbol.message'))
        .fontSize(this.iconSize)
        .fontColor([$r('app.color.text_tertiary')])
    }
  }
}
