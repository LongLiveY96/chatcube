/**
 * 附件存储服务
 * 将附件文件保存到应用沙箱目录，便于未来 WebDAV 同步
 */

import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { Context } from '@kit.AbilityKit'
import { MessageAttachment, AttachmentType } from '../models/ChatModels'

// 附件存储目录名
const ATTACHMENTS_DIR = 'attachments'
const IMAGES_DIR = 'images'
const FILES_DIR = 'files'

export class AttachmentStorageService {
  private static instance: AttachmentStorageService | null = null
  private context: Context | null = null
  private baseDir: string = ''
  private isInitialized: boolean = false

  private constructor() {}

  static getInstance(): AttachmentStorageService {
    if (AttachmentStorageService.instance === null) {
      AttachmentStorageService.instance = new AttachmentStorageService()
    }
    return AttachmentStorageService.instance
  }

  // 初始化服务
  async initialize(context: Context): Promise<void> {
    if (this.isInitialized) {
      return
    }
    this.context = context
    this.baseDir = context.filesDir
    await this.ensureDirectories()
    this.isInitialized = true
    console.info('AttachmentStorageService', `Initialized with baseDir: ${this.baseDir}`)
  }

  // 检查是否已初始化
  isReady(): boolean {
    return this.isInitialized && this.baseDir !== ''
  }

  // 确保存储目录存在
  private async ensureDirectories(): Promise<void> {
    const attachmentsPath = `${this.baseDir}/${ATTACHMENTS_DIR}`
    const imagesPath = `${attachmentsPath}/${IMAGES_DIR}`
    const filesPath = `${attachmentsPath}/${FILES_DIR}`

    try {
      fileIo.mkdirSync(attachmentsPath)
    } catch (e) {
      // 目录创建失败或已存在，忽略异常
    }

    try {
      fileIo.mkdirSync(imagesPath)
    } catch (e) {
      // 目录创建失败或已存在，忽略异常
    }

    try {
      fileIo.mkdirSync(filesPath)
    } catch (e) {
      // 目录创建失败或已存在，忽略异常
    }
  }

  // 保存附件到文件系统
  async saveAttachment(attachment: MessageAttachment): Promise<string> {
    if (!this.isInitialized || this.baseDir === '') {
      console.error('AttachmentStorageService', 'Service not initialized, baseDir is empty')
      return ''
    }

    try {
      const subDir = attachment.type === AttachmentType.IMAGE ? IMAGES_DIR : FILES_DIR
      const ext = this.getExtension(attachment.name, attachment.mimeType)
      const fileName = `${attachment.id}${ext}`
      const filePath = `${this.baseDir}/${ATTACHMENTS_DIR}/${subDir}/${fileName}`
      console.info('AttachmentStorageService', `Saving to path: ${filePath}`)

      // 如果有 base64 数据，从 base64 写入
      if (attachment.base64Data !== '') {
        const base64Helper = new util.Base64Helper()
        const data = base64Helper.decodeSync(attachment.base64Data)
        console.info('AttachmentStorageService', `Decoded data size: ${data.byteLength}`)
        const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
        fileIo.writeSync(file.fd, data.buffer)
        fileIo.closeSync(file)
        console.info('AttachmentStorageService', `File saved successfully: ${filePath}`)
      } else {
        console.warn('AttachmentStorageService', 'No base64 data to save')
      }

      return filePath
    } catch (error) {
      console.error('AttachmentStorageService', `Failed to save attachment: ${JSON.stringify(error)}`)
      return ''
    }
  }

  // 从文件路径读取 base64 数据（用于发送 API）
  async readAsBase64(filePath: string): Promise<string> {
    try {
      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      fileIo.closeSync(file)

      const base64Helper = new util.Base64Helper()
      const uint8Array = new Uint8Array(buffer)
      return base64Helper.encodeToStringSync(uint8Array)
    } catch (error) {
      console.error('AttachmentStorageService', `Failed to read file as base64: ${JSON.stringify(error)}`)
      return ''
    }
  }

  // 删除附件文件
  async deleteAttachment(filePath: string): Promise<void> {
    try {
      if (filePath !== '' && fileIo.accessSync(filePath)) {
        fileIo.unlinkSync(filePath)
      }
    } catch (error) {
      console.error('AttachmentStorageService', `Failed to delete attachment: ${JSON.stringify(error)}`)
    }
  }

  // 检查文件是否存在
  fileExists(filePath: string): boolean {
    try {
      return fileIo.accessSync(filePath)
    } catch (e) {
      return false
    }
  }

  // 获取附件目录路径（用于 WebDAV 同步）
  getAttachmentsDir(): string {
    return `${this.baseDir}/${ATTACHMENTS_DIR}`
  }

  // 复制文件
  private async copyFile(srcUri: string, destPath: string): Promise<void> {
    try {
      const srcFile = fileIo.openSync(srcUri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(srcFile.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(srcFile.fd, buffer)
      fileIo.closeSync(srcFile)

      const destFile = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
      fileIo.writeSync(destFile.fd, buffer)
      fileIo.closeSync(destFile)
    } catch (error) {
      console.error('AttachmentStorageService', `Failed to copy file: ${JSON.stringify(error)}`)
      throw new Error('Failed to copy file')
    }
  }

  // 获取文件扩展名
  private getExtension(fileName: string, mimeType: string): string {
    // 优先从文件名获取
    const dotIndex = fileName.lastIndexOf('.')
    if (dotIndex > 0) {
      return fileName.substring(dotIndex)
    }

    // 从 MIME 类型推断
    const mimeToExt: Record<string, string> = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'application/pdf': '.pdf',
      'text/plain': '.txt',
      'text/markdown': '.md'
    }
    return mimeToExt[mimeType] || ''
  }
}

// 导出单例获取方法
export function getAttachmentStorageService(): AttachmentStorageService {
  return AttachmentStorageService.getInstance()
}
