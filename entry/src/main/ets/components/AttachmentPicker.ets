/**
 * 附件选择器组件
 * 点击输入栏的 + 按钮后弹出，支持拍照、选择照片、上传文件
 */

import { picker } from '@kit.CoreFileKit'
import { camera, cameraPicker } from '@kit.CameraKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { MessageAttachment, AttachmentType } from '../models/ChatModels'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { getAttachmentStorageService, AttachmentStorageService } from '../services/AttachmentStorageService'

// 附件选项
interface AttachmentOption {
  icon: Resource
  label: string
  action: () => void
}

@Component
export struct AttachmentPicker {
  @State isLoading: boolean = false
  onSelectAttachments: (attachments: MessageAttachment[]) => void = () => {
  }
  onClose: () => void = () => {
  }

  build() {
    Column() {
      // 拖动条
      Column()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('app.color.divider'))
        .margin({ top: 8, bottom: 16 })

      // 主要选项：拍照、照片、上传文件
      Row() {
        this.OptionButton($r('sys.symbol.camera'), '拍照', () => {
          this.openCamera()
        })

        this.OptionButton($r('sys.symbol.shutter_photo'), '照片', () => {
          this.openPhotoPicker()
        })

        this.OptionButton($r('sys.symbol.paperclip'), '上传文件', () => {
          this.openFilePicker()
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  @Builder
  OptionButton(icon: Resource, label: string, action: () => void) {
    Column() {
      Column() {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(64)
      .height(64)
      .borderRadius(16)
      .backgroundColor($r('app.color.background'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
    }
    .onClick(() => {
      action()
    })
  }

  // 打开相机拍照
  private async openCamera(): Promise<void> {
    try {
      // 使用 cameraPicker 拍照
      const pickerProfile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      }
      const context = this.getUIContext().getHostContext()
      if (context === undefined) {
        console.error('AttachmentPicker', 'Failed to get context')
        return
      }
      const pickerResult: cameraPicker.PickerResult = await cameraPicker.pick(
        context,
        [cameraPicker.PickerMediaType.PHOTO],
        pickerProfile
      )

      if (pickerResult.resultCode === 0 && pickerResult.resultUri !== '') {
        const attachment = await this.createAttachmentFromUri(pickerResult.resultUri, 'camera_photo.jpg')
        if (attachment !== null) {
          this.onSelectAttachments([attachment])
          this.onClose()
        }
      }
    } catch (error) {
      console.error('AttachmentPicker', `Failed to open camera: ${JSON.stringify(error)}`)
    }
  }

  // 打开照片选择器
  private async openPhotoPicker(): Promise<void> {
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      photoSelectOptions.maxSelectNumber = 5 // 最多选择5张图片

      const photoPicker = new photoAccessHelper.PhotoViewPicker()
      const photoSelectResult = await photoPicker.select(photoSelectOptions)

      if (photoSelectResult.photoUris.length > 0) {
        const attachments: MessageAttachment[] = []
        for (let i = 0; i < photoSelectResult.photoUris.length; i++) {
          const uri = photoSelectResult.photoUris[i]
          const fileName = `image_${i + 1}.jpg`
          const attachment = await this.createAttachmentFromUri(uri, fileName)
          if (attachment !== null) {
            attachments.push(attachment)
          }
        }
        if (attachments.length > 0) {
          this.onSelectAttachments(attachments)
          this.onClose()
        }
      }
    } catch (error) {
      console.error('AttachmentPicker', `Failed to open photo picker: ${JSON.stringify(error)}`)
    }
  }

  // 打开文件选择器
  private async openFilePicker(): Promise<void> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.maxSelectNumber = 3
      documentSelectOptions.fileSuffixFilters = ['.pdf', '.doc', '.docx', '.txt', '.md']

      const context = this.getUIContext().getHostContext()
      if (context === undefined) {
        console.error('AttachmentPicker', 'Failed to get context')
        return
      }
      const documentPicker = new picker.DocumentViewPicker(context)
      const documentSelectResult = await documentPicker.select(documentSelectOptions)

      if (documentSelectResult.length > 0) {
        const attachments: MessageAttachment[] = []
        for (let i = 0; i < documentSelectResult.length; i++) {
          const uri = documentSelectResult[i]
          const fileName = this.getFileNameFromUri(uri)
          const attachment = await this.createFileAttachment(uri, fileName)
          if (attachment !== null) {
            attachments.push(attachment)
          }
        }
        if (attachments.length > 0) {
          this.onSelectAttachments(attachments)
          this.onClose()
        }
      }
    } catch (error) {
      console.error('AttachmentPicker', `Failed to open file picker: ${JSON.stringify(error)}`)
    }
  }

  // 从 URI 创建图片附件（保存到应用目录）
  private async createAttachmentFromUri(uri: string, fileName: string): Promise<MessageAttachment | null> {
    try {
      console.info('AttachmentPicker', `Creating attachment from URI: ${uri}`)
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      fileIo.closeSync(file)
      console.info('AttachmentPicker', `Read file size: ${stat.size}`)

      // 转换为 Base64（用于发送 API 和保存文件）
      const base64Helper = new util.Base64Helper()
      const uint8Array = new Uint8Array(buffer)
      const base64Data = base64Helper.encodeToStringSync(uint8Array)
      console.info('AttachmentPicker', `Base64 data length: ${base64Data.length}`)

      // 创建附件对象
      const attachmentId = `img_${Date.now()}`
      const attachment = new MessageAttachment(
        attachmentId,
        AttachmentType.IMAGE,
        fileName,
        '', // filePath 稍后由存储服务设置
        'image/jpeg',
        stat.size
      )
      attachment.base64Data = base64Data

      // 保存到应用目录
      const storageService = getAttachmentStorageService()
      const filePath = await storageService.saveAttachment(attachment)
      console.info('AttachmentPicker', `Saved attachment to: ${filePath}`)
      attachment.filePath = filePath

      return attachment
    } catch (error) {
      console.error('AttachmentPicker', `Failed to create attachment: ${JSON.stringify(error)}`)
      return null
    }
  }

  // 从 URI 创建文件附件（保存到应用目录）
  private async createFileAttachment(uri: string, fileName: string): Promise<MessageAttachment | null> {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      fileIo.closeSync(file)

      // 转换为 Base64
      const base64Helper = new util.Base64Helper()
      const uint8Array = new Uint8Array(buffer)
      const base64Data = base64Helper.encodeToStringSync(uint8Array)

      const mimeType = this.getMimeType(fileName)
      const attachmentId = `file_${Date.now()}`
      const attachment = new MessageAttachment(
        attachmentId,
        AttachmentType.FILE,
        fileName,
        '', // filePath 稍后由存储服务设置
        mimeType,
        stat.size
      )
      attachment.base64Data = base64Data

      // 保存到应用目录
      const storageService = getAttachmentStorageService()
      const filePath = await storageService.saveAttachment(attachment)
      attachment.filePath = filePath

      return attachment
    } catch (error) {
      console.error('AttachmentPicker', `Failed to create file attachment: ${JSON.stringify(error)}`)
      return null
    }
  }

  // 从 URI 获取文件名
  private getFileNameFromUri(uri: string): string {
    const parts = uri.split('/')
    const encodedName = parts[parts.length - 1] || 'file'
    // 解码 URL 编码的中文文件名
    try {
      return decodeURIComponent(encodedName)
    } catch (e) {
      return encodedName
    }
  }

  // 根据文件扩展名获取 MIME 类型
  private getMimeType(fileName: string): string {
    const ext = fileName.split('.').pop()?.toLowerCase() || ''
    const mimeTypes: Record<string, string> = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt': 'text/plain',
      'md': 'text/markdown',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp'
    }
    return mimeTypes[ext] || 'application/octet-stream'
  }
}
