import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { bundleManager } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { showToast } from '../utils/ToastUtil'

const TAG = 'AboutPage'
const GITHUB_URL = 'https://github.com/LongLiveY96/chatcube'

@Entry
@Component
struct AboutPage {
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_primary_light') themePrimaryLight: string = '#E6F2FF'
  @State showQrSheet: boolean = false
  @State isSaving: boolean = false
  @State versionName: string = ''

  aboutToAppear(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      this.versionName = info.versionName
    } catch (err) {
      hilog.error(0x0000, TAG, 'Get version failed: %{public}s', JSON.stringify(err))
      this.versionName = '1.0.0'
    }
  }

  private pageToast(message: string | Resource): void {
    showToast(this.getUIContext(), message, 2000)
  }

  build() {
    Column() {
      HdsNavigation() {
        Scroll() {
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

            // Contact section title
            Text($r('app.string.about_contact_section'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 16, bottom: 6 })
              .width('100%')

            // Contact cards
            Column() {
              // QQ Group card
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
                this.showQrSheet = true
              })

              Divider().color($r('app.color.divider')).margin({ left: 64 })

              // GitHub card
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

            // Footer
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
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background'))
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
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .bindSheet($$this.showQrSheet, this.QrCodeSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      showClose: true,
      dragBar: true,
      backgroundColor: $r('app.color.background')
    })
  }

  @Builder
  QrCodeSheetBuilder() {
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

      Button($r('app.string.about_save_qrcode'))
        .width('70%')
        .height(44)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .type(ButtonType.Capsule)
        .backgroundColor(this.themePrimary)
        .fontColor(Color.White)
        .enabled(!this.isSaving)
        .onClick(() => {
          this.saveQrCode()
        })
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

  private async saveQrCode(): Promise<void> {
    if (this.isSaving) {
      return
    }
    this.isSaving = true
    try {
      const hostContext = this.getUIContext().getHostContext()
      if (!hostContext) {
        throw new Error('UI context unavailable')
      }
      const context = hostContext as common.UIAbilityContext

      // Copy rawfile to cache temp file
      const rawFileData = context.resourceManager.getRawFileContentSync('qq_group_qrcode.jpg')
      const tempPath = `${context.cacheDir}/temp_qrcode_${Date.now()}.jpg`
      const tempFile = fileIo.openSync(tempPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
      fileIo.writeSync(tempFile.fd, rawFileData.buffer)
      fileIo.closeSync(tempFile)

      // Use photoAccessHelper to save
      const tempUriStr = fileUri.getUriFromPath(tempPath)
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: `ChatCube_QQ_Group_${Date.now()}`,
        fileNameExtension: 'jpg',
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context)
      const desFileUris = await phAccessHelper.showAssetsCreationDialog([tempUriStr], [config])
      if (desFileUris.length === 0) {
        throw new Error('User cancelled save')
      }

      const srcFile = fileIo.openSync(tempUriStr, fileIo.OpenMode.READ_ONLY)
      const desFile = fileIo.openSync(desFileUris[0], fileIo.OpenMode.WRITE_ONLY)
      fileIo.copyFileSync(srcFile.fd, desFile.fd)
      fileIo.closeSync(srcFile)
      fileIo.closeSync(desFile)

      this.pageToast($r('app.string.about_qrcode_saved'))

      // Cleanup
      try {
        fileIo.unlinkSync(tempPath)
      } catch (_) {
        // ignore cleanup error
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      hilog.error(0x0000, TAG, 'Save QR code failed: %{public}s', msg)
      if (!msg.includes('cancelled') && !msg.includes('cancel')) {
        this.pageToast($r('app.string.about_qrcode_save_failed'))
      }
    } finally {
      this.isSaving = false
    }
  }
}
