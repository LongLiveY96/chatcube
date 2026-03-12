import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { showToast } from '../utils/ToastUtil'
import { SettingsCompactPageHeader } from '../components/settings/SettingsCompactPageHeader'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import { saveRawfileImageToAlbum } from '../utils/RawfileImageSaveUtil'

const TAG = 'SupportDevelopmentPage'
let supportDevelopmentPathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct SupportDevelopmentPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
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

  @Local isSaving: boolean = false

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

  @Builder
  private PageContent() {
    Scroll() {
      Row() {
        Column({ space: 16 }) {
          Column({ space: 8 }) {
            Text($r('app.string.about_wechat_support'))
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            Text($r('app.string.about_wechat_pay_note'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({ top: 24, bottom: 8 })
          .alignItems(HorizontalAlign.Center)

          Image($rawfile('wechat-pay.png'))
            .width('72%')
            .objectFit(ImageFit.Contain)
            .borderRadius(16)

          Button($r('app.string.about_save_payment_code'))
            .width('72%')
            .height(44)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .type(ButtonType.Capsule)
            .backgroundColor(this.themePrimary)
            .fontColor(Color.White)
            .enabled(!this.isSaving)
            .onClick(() => {
              this.saveWechatPayCode()
            })
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
            title: $r('app.string.settings_support_development'),
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
      this.pageToast($r('app.string.about_payment_code_saved'))
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      hilog.error(0x0000, TAG, 'Save payment code failed: %{public}s', message)
      if (!message.includes('cancelled') && !message.includes('cancel')) {
        this.pageToast($r('app.string.about_payment_code_save_failed'))
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
