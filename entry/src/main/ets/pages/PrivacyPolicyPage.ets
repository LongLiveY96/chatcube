import { webview } from '@kit.ArkWeb'
import { SettingsCompactPageHeader } from '../components/settings/SettingsCompactPageHeader'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageCompactTabsTotalInset } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'

const PRIVACY_POLICY_URL = 'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1906111586003597632'

let privacyPolicyPagePathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct PrivacyPolicyPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get bottomAvoidHeight(): number {
    return getAppUiState().bottomAvoidHeight
  }
  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }
  @Computed
  get appIsDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private privacyPolicyWebController: webview.WebviewController = new webview.WebviewController()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private getContentBottomPadding(): number {
    return 24 + getSettingsPageCompactTabsTotalInset(this.px2vp(this.bottomAvoidHeight),
      this.settingsDetailPresentationMode)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private handleBack(): void {
    if (privacyPolicyPagePathStack !== null && privacyPolicyPagePathStack.size() > 0) {
      privacyPolicyPagePathStack.pop()
    }
  }

  @Builder
  private PageContent() {
    Column() {
      Web({ src: PRIVACY_POLICY_URL, controller: this.privacyPolicyWebController })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .darkMode(this.appIsDarkMode ? WebDarkMode.On : WebDarkMode.Off)
        .forceDarkAccess(this.appIsDarkMode)
        .backgroundColor($r('app.color.background'))
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.background'))
    .padding({ bottom: this.getContentBottomPadding() })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_privacy_policy'))
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
    .backgroundColor($r('app.color.background'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
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
        Column() {
          SettingsCompactPageHeader({
            title: $r('app.string.settings_privacy_policy'),
            topAvoidHeight: this.topAvoidHeight,
            onBack: () => {
              this.handleBack()
            }
          })
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.background'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

@Builder
export function PrivacyPolicyPageBuilder(name: string, param: Object) {
  NavDestination() {
    PrivacyPolicyPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    privacyPolicyPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (privacyPolicyPagePathStack !== null && privacyPolicyPagePathStack.size() > 0) {
      privacyPolicyPagePathStack.pop()
    }
    return true
  })
}
