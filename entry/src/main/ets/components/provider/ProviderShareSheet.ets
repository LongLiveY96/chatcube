/**
 * 发送方:服务商配置 QR 分享 sheet。
 * 用户输入 4-6 位数字密码,生成加密 QR,可选保存到相册。
 */
import { image } from '@kit.ImageKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo } from '@kit.CoreFileKit'
import { fileUri } from '@kit.CoreFileKit'
import { ModelProvider } from '../../models/ChatModels'
import {
  PASSWORD_MAX_LEN,
  PASSWORD_MIN_LEN,
  ProviderShareCodecError
} from '../../models/ProviderSharePayload'
import { getProviderShareCodec } from '../../services/ProviderShareCodec'
import { getProviderShareGenerator } from '../../services/ProviderShareGenerator'
import { showToast } from '../../utils/ToastUtil'
import { pickLocalizedText } from '../../utils/LocalizedTextUtils'
import { getAppUiState } from '../../state/AppUiState'

const QR_DISPLAY_PX: number = 280

@ComponentV2
export struct ProviderShareSheet {
  @Param provider: ModelProvider | null = null
  @Event onClose: () => void = () => {}

  @Local includeApiKey: boolean = true
  @Local password: string = ''
  @Local qrImage: image.PixelMap | null = null
  @Local isGenerating: boolean = false
  @Local isSaving: boolean = false
  @Local errorMessage: string = ''

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToDisappear(): void {
    this.releaseQrImage()
  }

  private releaseQrImage(): void {
    if (this.qrImage !== null) {
      try {
        this.qrImage.release()
      } catch (err) {
        console.warn('ProviderShareSheet', `release pixelMap failed: ${JSON.stringify(err)}`)
      }
      this.qrImage = null
    }
  }

  private isPasswordValid(): boolean {
    if (this.password.length < PASSWORD_MIN_LEN || this.password.length > PASSWORD_MAX_LEN) {
      return false
    }
    for (let i = 0; i < this.password.length; i++) {
      const code = this.password.charCodeAt(i)
      if (code < 0x30 || code > 0x39) {
        return false
      }
    }
    return true
  }

  private mapCodecErrorMessage(code: ProviderShareCodecError | ''): string {
    switch (code) {
      case 'payload_too_large':
        return pickLocalizedText('配置过长,无法生成二维码', 'Configuration too large for QR')
      case 'crypto_unavailable':
        return pickLocalizedText('加密功能不可用,请检查系统版本', 'Encryption unavailable on this system')
      default:
        return pickLocalizedText('生成失败,请重试', 'Failed to generate, please retry')
    }
  }

  private async onTapGenerate(): Promise<void> {
    if (this.isGenerating || this.provider === null) {
      return
    }
    if (!this.isPasswordValid()) {
      this.errorMessage = pickLocalizedText('请输入 4-6 位数字密码', 'Password must be 4-6 digits')
      return
    }
    this.isGenerating = true
    this.errorMessage = ''
    this.releaseQrImage()
    try {
      const codec = getProviderShareCodec()
      const encodeResult = await codec.encode(this.provider, this.password, this.includeApiKey)
      if (!encodeResult.ok) {
        this.errorMessage = this.mapCodecErrorMessage(encodeResult.error)
        return
      }
      const generator = getProviderShareGenerator()
      this.qrImage = await generator.generateQrPixelMap(encodeResult.payload)
    } catch (err) {
      console.error('ProviderShareSheet', `generate failed: ${JSON.stringify(err)}`)
      this.errorMessage = pickLocalizedText('生成失败,请重试', 'Failed to generate, please retry')
    } finally {
      this.isGenerating = false
    }
  }

  private async onTapSaveToAlbum(): Promise<void> {
    if (this.isSaving || this.qrImage === null) {
      return
    }
    this.isSaving = true
    let tempPath: string = ''
    try {
      const context = this.getUIContext().getHostContext()
      if (context === undefined || context === null) {
        throw new Error('host context unavailable')
      }
      const packer = image.createImagePacker()
      const pngData = await packer.packing(this.qrImage, { format: 'image/png', quality: 100 })
      packer.release()

      tempPath = `${context.tempDir}/provider_qr_${Date.now()}.png`
      const tempFile = fileIo.openSync(tempPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
      fileIo.writeSync(tempFile.fd, pngData)
      fileIo.closeSync(tempFile)

      const config: photoAccessHelper.PhotoCreationConfig = {
        title: `ChatCube_Provider_${Date.now()}`,
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      const srcUri = fileUri.getUriFromPath(tempPath)
      const destUris = await helper.showAssetsCreationDialog([srcUri], [config])
      if (destUris.length > 0) {
        const src = fileIo.openSync(tempPath, fileIo.OpenMode.READ_ONLY)
        const dest = fileIo.openSync(destUris[0], fileIo.OpenMode.WRITE_ONLY)
        fileIo.copyFileSync(src.fd, dest.fd)
        fileIo.closeSync(src)
        fileIo.closeSync(dest)
        showToast(this.getUIContext(), $r('app.string.provider_share_saved_album'))
      }
    } catch (err) {
      console.error('ProviderShareSheet', `save to album failed: ${JSON.stringify(err)}`)
      showToast(this.getUIContext(), $r('app.string.provider_share_save_failed'))
    } finally {
      if (tempPath !== '') {
        try {
          fileIo.unlinkSync(tempPath)
        } catch (err) {
          console.warn('ProviderShareSheet', `cleanup tempfile failed: ${JSON.stringify(err)}`)
        }
      }
      this.isSaving = false
    }
  }

  private maskedApiKey(): string {
    const provider = this.provider
    if (provider === null || provider.apiKey === '') {
      return pickLocalizedText('未填写', 'not set')
    }
    return 'sk-***'
  }

  @Builder
  HeaderRow() {
    Row() {
      Text($r('app.string.provider_share_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Blank()

      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor($r('app.color.divider'))
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.onClose()
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 12 })
  }

  @Builder
  ProviderInfoCard() {
    Column({ space: 6 }) {
      Row() {
        Text($r('app.string.provider_name'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.provider?.name ?? '')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Row() {
        Text('baseUrl')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.provider?.baseUrl ?? '')
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .margin({ left: 12 })
      }
      .width('100%')

      Row() {
        Text('API Key')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.maskedApiKey())
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  IncludeKeyToggle() {
    Row() {
      Column({ space: 2 }) {
        Text($r('app.string.provider_share_include_key'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.provider_share_include_key_desc'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.includeApiKey })
        .selectedColor(this.themePrimary)
        .onChange((on: boolean) => {
          this.includeApiKey = on
          this.releaseQrImage()
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  PasswordRow() {
    Column({ space: 6 }) {
      Text($r('app.string.provider_share_password_label'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ text: this.password, placeholder: $r('app.string.provider_share_password_placeholder') })
        .type(InputType.Number)
        .maxLength(PASSWORD_MAX_LEN)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((value: string) => {
          let digits = ''
          for (let i = 0; i < value.length && digits.length < PASSWORD_MAX_LEN; i++) {
            const code = value.charCodeAt(i)
            if (code >= 0x30 && code <= 0x39) {
              digits += value.charAt(i)
            }
          }
          if (digits !== value) {
            this.password = digits
          } else {
            this.password = value
          }
          this.errorMessage = ''
        })
    }
    .width('100%')
  }

  @Builder
  GenerateButton() {
    Button() {
      Row({ space: 8 }) {
        if (this.isGenerating) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(Color.White)
        }
        Text(this.qrImage !== null
          ? $r('app.string.provider_share_regenerate')
          : $r('app.string.provider_share_generate'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
    }
    .type(ButtonType.Capsule)
    .width('100%')
    .height(44)
    .backgroundColor(this.isPasswordValid() && !this.isGenerating
      ? this.themePrimary
      : $r('app.color.divider'))
    .enabled(this.isPasswordValid() && !this.isGenerating && this.provider !== null)
    .onClick(() => {
      void this.onTapGenerate()
    })
  }

  @Builder
  QrSection() {
    Column({ space: 12 }) {
      if (this.qrImage !== null) {
        Image(this.qrImage)
          .width(QR_DISPLAY_PX)
          .height(QR_DISPLAY_PX)
          .objectFit(ImageFit.Contain)
          .backgroundColor(Color.White)
          .borderRadius(8)
        Text($r('app.string.provider_share_warning'))
          .fontSize(12)
          .fontColor($r('app.color.status_error'))
          .textAlign(TextAlign.Center)
          .width('100%')
        Button() {
          Row({ space: 6 }) {
            if (this.isSaving) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color($r('app.color.text_primary'))
            } else {
              SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
                .fontSize(16)
                .fontColor([$r('app.color.text_primary')])
            }
            Text($r('app.string.provider_share_save_album'))
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
          }
        }
        .type(ButtonType.Capsule)
        .width('100%')
        .height(40)
        .backgroundColor($r('app.color.divider'))
        .enabled(!this.isSaving)
        .onClick(() => {
          void this.onTapSaveToAlbum()
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      this.HeaderRow()
      Scroll() {
        Column({ space: 14 }) {
          this.ProviderInfoCard()
          this.IncludeKeyToggle()
          this.PasswordRow()
          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(12)
              .fontColor($r('app.color.status_error'))
              .width('100%')
          }
          this.GenerateButton()
          this.QrSection()
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }
}
