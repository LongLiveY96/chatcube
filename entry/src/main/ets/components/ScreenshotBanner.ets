import { MessageAttachment, AttachmentType } from '../models/ChatModels'
import { BaseItemInfo, PhotoSource, RecentPhotoComponent, RecentPhotoOptions, photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { getAttachmentStorageService } from '../services/AttachmentStorageService'
import { AppStorageKeys } from '../config/AppStorageKeys'

@Component
export struct ScreenshotBanner {
  @Link attachments: MessageAttachment[]
  @Prop hasRecentPhoto: boolean = false
  @State dismissed: boolean = false
  @State bannerHeight: number = 0
  private recentPhotoOptions: RecentPhotoOptions = new RecentPhotoOptions()

  aboutToAppear(): void {
    this.recentPhotoOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
    this.recentPhotoOptions.period = 300
    this.recentPhotoOptions.photoSource = PhotoSource.SCREENSHOT

    // 检查是否在检测周期内已忽略过截图
    const dismissedTs = AppStorage.get<number>(AppStorageKeys.SCREENSHOT_DISMISSED_TS)
    const now = Date.now()
    if (dismissedTs !== undefined && (now - dismissedTs) < 300 * 1000) {
      this.dismissed = true
    }
  }

  build() {
    if (this.hasRecentPhoto && !this.dismissed) {
      Column() {
        Row() {
          Text($r('app.string.screenshot_banner_title'))
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
          Blank()
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(9)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(20)
          .height(20)
          .backgroundColor($r('app.color.divider'))
          .onClick(() => {
            this.dismiss()
          })
        }
        .width('100%')

        RecentPhotoComponent({
          recentPhotoOptions: this.recentPhotoOptions,
          onRecentPhotoClick: (info: BaseItemInfo): boolean => {
            if (info && info.uri) {
              this.addScreenshotByUri(info.uri)
            }
            return true
          },
          onRecentPhotoCheckResult: (_exists: boolean): void => {}
        })
          .width(48)
          .height(48)
          .borderRadius(8)
          .margin({ top: 8 })

        Text($r('app.string.screenshot_banner_subtitle'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 6 })
      }
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .width(140)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.12)', offsetX: 0, offsetY: 6 })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        let h = newArea.height
        if (typeof h === 'number') {
          this.bannerHeight = h
        }
      })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.85, y: 0.85 }))
          .animation({ duration: 250, curve: Curve.EaseOut }),
        TransitionEffect.OPACITY.animation({ duration: 150 })
      ))
    }
  }

  private dismiss(): void {
    this.dismissed = true
    AppStorage.setOrCreate<number>(AppStorageKeys.SCREENSHOT_DISMISSED_TS, Date.now())
  }

  private async addScreenshotByUri(uri: string): Promise<void> {
    if (!uri) {
      return
    }
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      fileIo.closeSync(file)

      const base64Helper = new util.Base64Helper()
      const uint8Array = new Uint8Array(buffer)
      const base64Data = base64Helper.encodeToStringSync(uint8Array)

      const attachmentId = `img_${Date.now()}`
      const attachment = new MessageAttachment(
        attachmentId,
        AttachmentType.IMAGE,
        `screenshot_${Date.now()}.jpg`,
        '',
        'image/jpeg',
        stat.size
      )
      attachment.base64Data = base64Data

      const storageService = getAttachmentStorageService()
      const filePath = await storageService.saveAttachment(attachment)
      attachment.filePath = filePath

      this.attachments.push(attachment)
      this.attachments = [...this.attachments]
      this.dismiss()
    } catch (error) {
      console.error('ScreenshotBanner', `Failed to add screenshot: ${JSON.stringify(error)}`)
    }
  }
}
