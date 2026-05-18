import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { showToast } from '../utils/ToastUtil'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import { saveRawfileImageToAlbum } from '../utils/RawfileImageSaveUtil'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'

const TAG = 'SupportDevelopmentPage'

let supportDevelopmentPathStack: NavPathStack | null = null

interface PerkItem {
  icon: Resource
  title: Resource
  desc: Resource
}

@Entry
@ComponentV2
struct SupportDevelopmentPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }

  @Local isSaving: boolean = false
  private compactScroller: Scroller = new Scroller()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private pageToast(message: string | Resource): void {
    showToast(this.getUIContext(), message, 2000)
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private handleBack(): void {
    if (supportDevelopmentPathStack !== null && supportDevelopmentPathStack.size() > 0) {
      supportDevelopmentPathStack.pop()
    }
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp,
      this.windowHeightVp, (): void => this.CompactTitleStackBuilder())
  }

  private getPerkItems(): PerkItem[] {
    return [
      {
        icon: $r('sys.symbol.paperplane_right_fill'),
        title: $r('app.string.sponsor_perk_priority_title'),
        desc: $r('app.string.sponsor_perk_priority_desc')
      } as PerkItem,
      {
        icon: $r('sys.symbol.message_fill'),
        title: $r('app.string.sponsor_perk_channel_title'),
        desc: $r('app.string.sponsor_perk_channel_desc')
      } as PerkItem,
      {
        icon: $r('sys.symbol.wand_and_stars'),
        title: $r('app.string.sponsor_perk_resource_title'),
        desc: $r('app.string.sponsor_perk_resource_desc')
      } as PerkItem
    ]
  }

  private getUsageItems(): Resource[] {
    return [
      $r('app.string.sponsor_usage_1'),
      $r('app.string.sponsor_usage_2'),
      $r('app.string.sponsor_usage_3')
    ]
  }

  @Builder
  private SectionTitle(title: Resource) {
    Text(title)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 16, bottom: 6 })
      .width('100%')
  }

  @Builder
  private HeroBlock() {
    Column({ space: 10 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.heart_fill'))
          .fontSize(36)
          .fontColor([Color.White])
      }
      .width(76)
      .height(76)
      .borderRadius(24)
      .linearGradient({
        direction: GradientDirection.RightBottom,
        colors: [[this.themePrimary, 0], ['#FF6F91', 1]]
      })
      .shadow({ radius: 18, color: 'rgba(99,102,241,0.28)', offsetY: 8 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text($r('app.string.settings_support_development'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text($r('app.string.sponsor_page_subtitle'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 12, right: 12 })

      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(13)
          .fontColor([this.themePrimary])
        Text($r('app.string.sponsor_disclaimer'))
          .fontSize(12)
          .fontColor(this.themePrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.themePrimaryLight)
      .borderRadius(12)
      .margin({ top: 6 })
    }
    .width('100%')
    .padding({ top: 24, bottom: 16 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private WechatCard() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.qrcode'))
            .fontSize(20)
            .fontColor([this.themePrimary])
        }
        .width(40)
        .height(40)
        .borderRadius(12)
        .backgroundColor(this.themePrimaryLight)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 2 }) {
          Text($r('app.string.sponsor_wechat_title'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.sponsor_wechat_desc'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Image($rawfile('wechat-pay.png'))
        .width('64%')
        .objectFit(ImageFit.Contain)
        .borderRadius(14)

      Button($r('app.string.sponsor_wechat_save'))
        .width('64%')
        .height(40)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .type(ButtonType.Capsule)
        .backgroundColor(this.themePrimaryLight)
        .fontColor(this.themePrimary)
        .enabled(!this.isSaving)
        .onClick(() => {
          this.saveWechatPayCode()
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 18 })
    .backgroundColor(this.themeSurface)
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.divider') })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private UsageCard() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
            .fontSize(18)
            .fontColor([this.themePrimary])
        }
        .width(34)
        .height(34)
        .borderRadius(11)
        .backgroundColor(this.themePrimaryLight)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Text($r('app.string.sponsor_usage_title'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })

      Column({ space: 8 }) {
        ForEach(this.getUsageItems(), (item: Resource) => {
          Row({ space: 10 }) {
            Text('•')
              .fontSize(14)
              .fontColor(this.themePrimary)
            Text(item)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .backgroundColor(this.themeSurface)
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private PerkRow(perk: PerkItem, isLast: boolean) {
    Column() {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph(perk.icon)
            .fontSize(18)
            .fontColor([this.themePrimary])
        }
        .width(36)
        .height(36)
        .borderRadius(11)
        .backgroundColor(this.themePrimaryLight)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 3 }) {
          Text(perk.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(perk.desc)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)

      if (!isLast) {
        Divider().color($r('app.color.divider')).margin({ left: 64, right: 12 })
      }
    }
    .width('100%')
  }

  @Builder
  private PerksCard() {
    Column() {
      ForEach(this.getPerkItems(), (perk: PerkItem, idx: number) => {
        this.PerkRow(perk, idx === this.getPerkItems().length - 1)
      }, (perk: PerkItem) => `${perk.title}`)
    }
    .width('100%')
    .backgroundColor(this.themeSurface)
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.divider') })
    .clip(true)
  }

  @Builder
  private QqHintBanner() {
    Row({ space: 8 }) {
      Text($r('app.string.sponsor_qq_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.themePrimaryLight)
    .borderRadius(14)
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private PageContent() {
    Scroll(this.compactScroller) {
      Row() {
        Column({ space: 14 }) {
          if (!this.isDetailPaneMode()) {
            Blank()
              .width('100%')
              .height(this.getCompactContentTopPadding())
          }

          this.HeroBlock()
          this.WechatCard()
          this.UsageCard()

          this.SectionTitle($r('app.string.sponsor_perks_title'))
          this.PerksCard()

          this.QqHintBanner()

          Blank().height(20)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_support_development'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(getAppUiState().themeBackground)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.settings_support_development'),
      onBack: () => {
        this.handleBack()
      }
    })
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        Column() {
          this.DetailPaneHeader()
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(getAppUiState().themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .bindToScrollable([this.compactScroller])
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(true)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  private async saveWechatPayCode(): Promise<void> {
    if (this.isSaving) {
      return
    }
    this.isSaving = true
    try {
      const hostContext = this.getUIContext().getHostContext()
      if (!hostContext) {
        throw new Error('UI context unavailable')
      }
      await saveRawfileImageToAlbum(hostContext as common.UIAbilityContext, 'wechat-pay.png', 'ChatCube_WeChat_Pay')
      this.pageToast($r('app.string.sponsor_wechat_saved'))
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      hilog.error(0x0000, TAG, 'Save payment code failed: %{public}s', message)
      if (!message.includes('cancelled') && !message.includes('cancel')) {
        this.pageToast($r('app.string.sponsor_wechat_save_failed'))
      }
    } finally {
      this.isSaving = false
    }
  }
}

@Builder
export function SupportDevelopmentPageBuilder(name: string, param: Object) {
  NavDestination() {
    SupportDevelopmentPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    supportDevelopmentPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (supportDevelopmentPathStack !== null && supportDevelopmentPathStack.size() > 0) {
      supportDevelopmentPathStack.pop()
    }
    return true
  })
}
