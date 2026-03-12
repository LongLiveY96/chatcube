import { Want, common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { bundleManager } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { showToast } from '../utils/ToastUtil'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import { saveRawfileImageToAlbum } from '../utils/RawfileImageSaveUtil'

const TAG = 'AboutPage'
const GITHUB_URL = 'https://github.com/LongLiveY96/chatcube'
const QQ_GROUP_NUMBER = '752237762'
const QQ_GROUP_DEEP_LINK = `mqqapi://card/show_pslcard?card_type=group&uin=${QQ_GROUP_NUMBER}`
const QQ_GROUP_INVITE_URL = 'https://qm.qq.com/q/LtqdPMezoQ'

@Entry
@ComponentV2
struct AboutPage {
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
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
  @Local showQqGroupSheet: boolean = false
  @Local isSaving: boolean = false
  @Local isOpeningGroup: boolean = false
  @Local versionName: string = ''

  aboutToAppear(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      this.versionName = info.versionName
    } catch (err) {
      hilog.error(0x0000, TAG, 'Get version failed: %{public}s', JSON.stringify(err))
      this.versionName = '1.0.7'
    }
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

  @Builder
  private PageContent() {
    Scroll() {
      Row() {
        Column() {
          // Header: App icon + name + version + slogan
          Column({ space: 8 }) {
            Image($r('app.media.app_icon'))
              .width(80)
              .height(80)
              .borderRadius(20)
              .shadow({ radius: 12, color: 'rgba(0,0,0,0.1)', offsetY: 4 })

            Text('ChatCube')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            Text(`v${this.versionName}`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))

            Text($r('app.string.about_page_slogan'))
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .padding({ top: 24, bottom: 28 })
          .alignItems(HorizontalAlign.Center)

          Text($r('app.string.about_contact_section'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, bottom: 6 })
            .width('100%')

          Column() {
            Row() {
              Column() {
                SymbolGlyph($r('sys.symbol.person_2'))
                  .fontSize(20)
                  .fontColor([this.themePrimary])
              }
              .width(36)
              .height(36)
              .borderRadius(9)
              .backgroundColor(this.themePrimaryLight)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Column({ space: 2 }) {
                Text($r('app.string.about_qq_group'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text($r('app.string.about_qq_group_number'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(18)
                .fontColor([$r('app.color.text_tertiary')])
            }
            .width('100%')
            .height(64)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.showQqGroupSheet = true
            })

            Divider().color($r('app.color.divider')).margin({ left: 64 })

            Row() {
              Column() {
                SymbolGlyph($r('sys.symbol.link'))
                  .fontSize(20)
                  .fontColor([this.themePrimary])
              }
              .width(36)
              .height(36)
              .borderRadius(9)
              .backgroundColor(this.themePrimaryLight)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Column({ space: 2 }) {
                Text($r('app.string.about_github'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text($r('app.string.about_github_repo'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(18)
                .fontColor([$r('app.color.text_tertiary')])
            }
            .width('100%')
            .height(64)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.copyGitHubLink()
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius(16)

          Column({ space: 4 }) {
            Text($r('app.string.about_open_source'))
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
            Text($r('app.string.about_copyright'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .padding({ top: 32, bottom: 40 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_about'))
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
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.background'))
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .titleBar({
          avoidLayoutSafeArea: true,
          enableComponentSafeArea: true,
          content: {
            title: {
              mainTitle: $r('app.string.settings_about')
            }
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .bindSheet($$this.showQqGroupSheet, this.QqGroupSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      showClose: true,
      dragBar: true,
      backgroundColor: $r('app.color.background')
    })
  }

  @Builder
  QqGroupSheetBuilder() {
    Column({ space: 16 }) {
      Text($r('app.string.about_qq_group'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text($r('app.string.about_qq_group_number'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))

      Image($rawfile('qq_group_qrcode.jpg'))
        .width('70%')
        .objectFit(ImageFit.Contain)
        .borderRadius(12)

      Row({ space: 12 }) {
        Button($r('app.string.about_join_qq_group'))
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .type(ButtonType.Capsule)
          .backgroundColor(this.themePrimary)
          .fontColor(Color.White)
          .enabled(!this.isOpeningGroup && !this.isSaving)
          .onClick(() => {
            this.openQqGroup()
          })

        Button($r('app.string.about_save_qrcode'))
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .type(ButtonType.Capsule)
          .backgroundColor(this.themePrimaryLight)
          .fontColor(this.themePrimary)
          .enabled(!this.isSaving && !this.isOpeningGroup)
          .onClick(() => {
            this.saveQqGroupQrCode()
          })
      }
      .width('70%')
    }
    .width('100%')
    .padding({ top: 16, bottom: 32, left: 24, right: 24 })
    .alignItems(HorizontalAlign.Center)
  }

  private copyGitHubLink(): void {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, GITHUB_URL)
      const systemPasteboard = pasteboard.getSystemPasteboard()
      systemPasteboard.setDataSync(pasteData)
      this.pageToast($r('app.string.about_link_copied'))
    } catch (err) {
      hilog.error(0x0000, TAG, 'Copy link failed: %{public}s', JSON.stringify(err))
    }
  }

  private async saveQqGroupQrCode(): Promise<void> {
    await this.saveRawfileImage(
      $r('app.string.about_qrcode_saved'),
      $r('app.string.about_qrcode_save_failed')
    )
  }

  private async saveRawfileImage(successMessage: string | Resource, failMessage: string | Resource): Promise<void> {
    if (this.isSaving) {
      return
    }
    this.isSaving = true
    try {
      const hostContext = this.getUIContext().getHostContext()
      if (!hostContext) {
        throw new Error('UI context unavailable')
      }
      await saveRawfileImageToAlbum(hostContext as common.UIAbilityContext, 'qq_group_qrcode.jpg', 'ChatCube_QQ_Group')
      this.pageToast(successMessage)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      hilog.error(0x0000, TAG, 'Save QR code failed: %{public}s', msg)
      if (!msg.includes('cancelled') && !msg.includes('cancel')) {
        this.pageToast(failMessage)
      }
    } finally {
      this.isSaving = false
    }
  }

  private async openQqGroup(): Promise<void> {
    if (this.isOpeningGroup) {
      return
    }
    this.isOpeningGroup = true
    try {
      const hostContext = this.getUIContext().getHostContext()
      if (!hostContext) {
        throw new Error('UI context unavailable')
      }
      const context = hostContext as common.UIAbilityContext

      let canOpen = false
      try {
        canOpen = bundleManager.canOpenLink(QQ_GROUP_DEEP_LINK)
      } catch (err) {
        hilog.error(0x0000, TAG, 'Check QQ deep link failed: %{public}s', JSON.stringify(err))
      }

      if (canOpen) {
        await context.openLink(QQ_GROUP_DEEP_LINK)
        return
      }
      await this.startBrowsableAbility(context, QQ_GROUP_INVITE_URL)
    } catch (err) {
      hilog.error(0x0000, TAG, 'Open QQ group failed: %{public}s', JSON.stringify(err))
      this.pageToast($r('app.string.about_open_qq_group_failed'))
    } finally {
      this.isOpeningGroup = false
    }
  }

  private async startBrowsableAbility(context: common.UIAbilityContext, url: string): Promise<void> {
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    }
    await context.startAbility(want)
  }
}

@Builder
export function AboutPageBuilder(name: string, param: Object) {
  NavDestination() {
    AboutPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
}

