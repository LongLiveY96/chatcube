import { fileIo, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import {
  ASSISTANT_AVATAR_MODE_IMAGE,
  ASSISTANT_AVATAR_MODE_SYMBOL,
  AssistantAvatarView,
  buildQqAssistantAvatarUrl,
  extractQqFromAssistantAvatar,
  getAssistantAvatarInputMode,
  isQqAssistantAvatar,
  normalizeAssistantAvatarValue,
  sanitizeAssistantQqNumber,
} from './AssistantAvatar'
import { getAppUiState } from '../state/AppUiState'

const ASSISTANT_AVATAR_MODE_QQ: string = 'qq'
const ASSISTANT_AVATAR_MODE_GALLERY: string = 'gallery'
const ASSISTANT_AVATAR_DIR: string = 'assistant_avatars'

@ComponentV2
export struct AssistantAvatarEditorSheet {
  @Param avatarValue: string = 'AI'
  @Event $avatarValue: (value: string) => void = (_value: string) => {}
  @Param avatarColor: ResourceColor = '#0A59F7'
  @Event onClose: () => void = () => {}
  @Local editMode: string = ASSISTANT_AVATAR_MODE_SYMBOL
  @Local textValue: string = 'AI'
  @Local linkValue: string = ''
  @Local qqAvatarValue: string = ''
  @Local qqNumberValue: string = ''
  @Local galleryValue: string = ''
  @Local isPickingImage: boolean = false

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    const normalized = normalizeAssistantAvatarValue(this.avatarValue)
    const normalizedLower = normalized.toLowerCase()
    if (isQqAssistantAvatar(normalized)) {
      this.editMode = ASSISTANT_AVATAR_MODE_QQ
      this.qqAvatarValue = normalized
      this.qqNumberValue = extractQqFromAssistantAvatar(normalized)
      this.textValue = 'AI'
      this.linkValue = ''
      this.galleryValue = ''
    } else if (normalizedLower.startsWith('file://')) {
      this.editMode = ASSISTANT_AVATAR_MODE_GALLERY
      this.galleryValue = normalized
      this.textValue = 'AI'
      this.linkValue = ''
      this.qqAvatarValue = ''
      this.qqNumberValue = ''
    } else if (getAssistantAvatarInputMode(normalized) === ASSISTANT_AVATAR_MODE_IMAGE) {
      this.editMode = ASSISTANT_AVATAR_MODE_IMAGE
      this.linkValue = normalized
      this.textValue = 'AI'
      this.qqAvatarValue = ''
      this.qqNumberValue = ''
      this.galleryValue = ''
    } else {
      this.editMode = ASSISTANT_AVATAR_MODE_SYMBOL
      this.textValue = normalized
      this.linkValue = ''
      this.qqAvatarValue = ''
      this.qqNumberValue = ''
      this.galleryValue = ''
    }
  }

  private getPreviewValue(): string {
    if (this.editMode === ASSISTANT_AVATAR_MODE_IMAGE) {
      return this.linkValue !== '' ? this.linkValue : 'AI'
    }
    if (this.editMode === ASSISTANT_AVATAR_MODE_QQ) {
      return this.qqAvatarValue !== '' ? this.qqAvatarValue : 'AI'
    }
    if (this.editMode === ASSISTANT_AVATAR_MODE_GALLERY) {
      return this.galleryValue !== '' ? this.galleryValue : this.avatarValue
    }
    return this.textValue !== '' ? this.textValue : 'AI'
  }

  private getFileExtension(uri: string): string {
    const cleanUri = uri.split('?')[0].toLowerCase()
    const dotIndex = cleanUri.lastIndexOf('.')
    if (dotIndex >= 0) {
      const ext = cleanUri.substring(dotIndex)
      if (ext === '.jpg' || ext === '.jpeg' || ext === '.png' || ext === '.webp' || ext === '.gif' ||
        ext === '.bmp') {
        return ext
      }
    }
    return '.jpg'
  }

  private ensureAvatarDirectory(baseDir: string): string {
    const dir = `${baseDir}/${ASSISTANT_AVATAR_DIR}`
    try {
      fileIo.mkdirSync(dir, true)
    } catch (error) {
      console.error('AssistantAvatarEditorSheet', `Failed to create avatar dir: ${JSON.stringify(error)}`)
    }
    return dir
  }

  private async copyPickedImageToSandbox(uri: string): Promise<string> {
    const context = this.getUIContext().getHostContext()
    if (context === undefined) {
      return ''
    }
    const dir = this.ensureAvatarDirectory(context.filesDir)
    const targetPath = `${dir}/avatar_${Date.now()}_${Math.random().toString(36).substring(2, 8)}${this.getFileExtension(uri)}`
    try {
      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      try {
        const destFile = fileIo.openSync(targetPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        try {
          await fileIo.copyFile(srcFile.fd, destFile.fd)
        } finally {
          fileIo.closeSync(destFile)
        }
      } finally {
        fileIo.closeSync(srcFile)
      }
      return fileUri.getUriFromPath(targetPath)
    } catch (error) {
      console.error('AssistantAvatarEditorSheet', `Failed to copy picked image: ${JSON.stringify(error)}`)
      return ''
    }
  }

  private async pickGalleryImage(): Promise<void> {
    if (this.isPickingImage) {
      return
    }
    this.isPickingImage = true
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      photoSelectOptions.maxSelectNumber = 1
      const photoPicker = new photoAccessHelper.PhotoViewPicker()
      const photoSelectResult = await photoPicker.select(photoSelectOptions)
      if (photoSelectResult.photoUris.length <= 0) {
        return
      }
      const imageUri = await this.copyPickedImageToSandbox(photoSelectResult.photoUris[0])
      if (imageUri !== '') {
        this.editMode = ASSISTANT_AVATAR_MODE_GALLERY
        this.galleryValue = imageUri
        this.linkValue = ''
        this.qqAvatarValue = ''
        this.qqNumberValue = ''
      }
    } catch (error) {
      console.error('AssistantAvatarEditorSheet', `Failed to pick gallery image: ${JSON.stringify(error)}`)
    } finally {
      this.isPickingImage = false
    }
  }

  private randomQqNumber(): string {
    const length = 5 + Math.floor(Math.random() * 8)
    let result = ''
    for (let i = 0; i < length; i++) {
      if (i === 0) {
        result += (1 + Math.floor(Math.random() * 9)).toString()
      } else {
        result += Math.floor(Math.random() * 10).toString()
      }
    }
    return result
  }

  private useRandomQqAvatar(): void {
    const qqNumber = this.randomQqNumber()
    const link = buildQqAssistantAvatarUrl(qqNumber)
    this.editMode = ASSISTANT_AVATAR_MODE_QQ
    this.qqAvatarValue = link
    this.qqNumberValue = ''
    this.linkValue = ''
    this.galleryValue = ''
  }

  private useCustomQqAvatar(value: string): void {
    const qqNumber = sanitizeAssistantQqNumber(value).substring(0, 12)
    this.qqNumberValue = qqNumber
    this.qqAvatarValue = qqNumber !== '' ? buildQqAssistantAvatarUrl(qqNumber) : ''
    this.linkValue = ''
    this.galleryValue = ''
  }

  build() {
    Column({ space: 18 }) {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Circle)
        .width(34)
        .height(34)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.onClose()
        })

        Text($r('app.string.assistant_avatar_edit_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([Color.White])
        }
        .type(ButtonType.Circle)
        .width(34)
        .height(34)
        .backgroundColor(this.themePrimary)
        .onClick(() => {
          this.$avatarValue(normalizeAssistantAvatarValue(this.getPreviewValue()))
          this.onClose()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      AssistantAvatarView({
        value: this.getPreviewValue(),
        color: this.avatarColor,
        avatarSize: 88,
        radius: 28,
        fontSize: 42
      })
        .alignSelf(ItemAlign.Center)

      Row({ space: 8 }) {
        this.SourceButton(ASSISTANT_AVATAR_MODE_SYMBOL, $r('app.string.assistant_avatar_source_text'))
        this.SourceButton(ASSISTANT_AVATAR_MODE_IMAGE, $r('app.string.assistant_avatar_source_link'))
        this.SourceButton(ASSISTANT_AVATAR_MODE_QQ, $r('app.string.assistant_avatar_type_qq'))
        this.SourceButton(ASSISTANT_AVATAR_MODE_GALLERY, $r('app.string.assistant_avatar_source_gallery'))
      }
      .width('100%')

      if (this.editMode === ASSISTANT_AVATAR_MODE_SYMBOL) {
        Column({ space: 8 }) {
          Text($r('app.string.assistant_avatar_text_label'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          TextInput({ text: this.textValue, placeholder: $r('app.string.assistant_avatar_text_placeholder') })
            .width('100%')
            .height(46)
            .maxLength(8)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor($r('app.color.surface'))
            .borderRadius(16)
            .padding({ left: 14, right: 14 })
            .onChange((text: string) => {
              this.textValue = text
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else if (this.editMode === ASSISTANT_AVATAR_MODE_IMAGE) {
        Column({ space: 10 }) {
          Text($r('app.string.assistant_avatar_link_label'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          TextInput({ text: this.linkValue, placeholder: $r('app.string.assistant_avatar_link_placeholder') })
            .width('100%')
            .height(46)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor($r('app.color.surface'))
            .borderRadius(16)
            .padding({ left: 14, right: 14 })
            .onChange((text: string) => {
              this.linkValue = text
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else if (this.editMode === ASSISTANT_AVATAR_MODE_QQ) {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            TextInput({ text: this.qqNumberValue, placeholder: $r('app.string.assistant_avatar_qq_placeholder') })
              .layoutWeight(1)
              .height(46)
              .maxLength(12)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_tertiary'))
              .backgroundColor($r('app.color.surface'))
              .borderRadius(16)
              .padding({ left: 14, right: 14 })
              .onChange((text: string) => {
                this.useCustomQqAvatar(text)
              })
            Button($r('app.string.assistant_avatar_random_qq'))
              .height(46)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
              .backgroundColor($r('app.color.surface'))
              .borderRadius(16)
              .padding({ left: 14, right: 14 })
              .onClick(() => {
                this.useRandomQqAvatar()
              })
          }
          .width('100%')
        }
        .width('100%')
      } else {
        Column({ space: 10 }) {
          Text($r('app.string.assistant_avatar_gallery_hint'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Button(this.isPickingImage ? $r('app.string.loading') : $r('app.string.assistant_avatar_pick_gallery'))
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(this.themePrimary)
            .borderRadius(18)
            .enabled(!this.isPickingImage)
            .onClick(() => {
              this.pickGalleryImage()
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 28 })
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private SourceButton(mode: string, label: ResourceStr) {
    Button(label)
      .layoutWeight(1)
      .height(38)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.editMode === mode ? Color.White : $r('app.color.text_secondary'))
      .backgroundColor(this.editMode === mode ? this.themePrimary : $r('app.color.surface'))
      .borderRadius(19)
      .border({
        width: this.editMode === mode ? 0 : 1,
        color: $r('app.color.divider')
      })
      .onClick(() => {
        this.editMode = mode
        if (mode === ASSISTANT_AVATAR_MODE_SYMBOL && this.textValue === '') {
          this.textValue = 'AI'
        }
      })
  }
}
