/**
 * 分享服务
 * 提供消息分享功能：图片分享、Markdown分享、纯文本分享
 */
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { fileUri } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { ChatMessage, MessageRole } from '../models/ChatModels'

// 分享模式枚举
export enum ShareMode {
  IMAGE = 'image',      // 图片分享（卡片风格）
  MARKDOWN = 'markdown', // Markdown 格式
  TEXT = 'text'         // 纯文本格式
}

// 分享结果
export interface ShareResult {
  success: boolean
  errorMessage: string
}

export class ShareService {
  private context: common.UIAbilityContext | null = null

  // 初始化服务
  init(context: common.UIAbilityContext): void {
    this.context = context
  }

  // 将消息列表转换为 Markdown 格式
  convertToMarkdown(messages: ChatMessage[]): string {
    const lines: string[] = []
    lines.push('# 对话记录\n')
    lines.push(`> 导出时间: ${this.formatDateTime(Date.now())}\n`)
    lines.push('---\n')

    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i]
      const roleLabel = msg.role === MessageRole.USER ? '👤 **用户**' : '🤖 **AI**'
      const time = this.formatTime(msg.timestamp)

      lines.push(`### ${roleLabel} · ${time}\n`)

      // 添加消息内容
      if (msg.content.length > 0) {
        lines.push(msg.content)
        lines.push('')
      }

      // 如果有推理内容，添加折叠块
      if (msg.reasoningContent.length > 0) {
        lines.push('<details>')
        lines.push('<summary>💭 思考过程</summary>\n')
        lines.push(msg.reasoningContent)
        lines.push('</details>\n')
      }

      lines.push('---\n')
    }

    return lines.join('\n')
  }

  // 将消息列表转换为纯文本格式
  convertToPlainText(messages: ChatMessage[]): string {
    const lines: string[] = []
    lines.push('=== 对话记录 ===')
    lines.push(`导出时间: ${this.formatDateTime(Date.now())}`)
    lines.push('')

    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i]
      const roleLabel = msg.role === MessageRole.USER ? '[用户]' : '[AI]'
      const time = this.formatTime(msg.timestamp)

      lines.push(`${roleLabel} ${time}`)
      lines.push(msg.content)

      // 如果有推理内容
      if (msg.reasoningContent.length > 0) {
        lines.push('')
        lines.push('[思考过程]')
        lines.push(msg.reasoningContent)
      }

      lines.push('')
      lines.push('---')
      lines.push('')
    }

    return lines.join('\n')
  }

  // 分享文本内容
  async shareText(content: string, title: string = '分享对话'): Promise<ShareResult> {
    if (this.context === null) {
      console.error('ShareService', '[shareText] 服务未初始化')
      return { success: false, errorMessage: '服务未初始化' }
    }

    try {
      console.info('ShareService', `[shareText] 开始分享文本，内容长度: ${content.length}`)
      const shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: content,
        title: title
      })

      const controller = new systemShare.ShareController(shareData)
      console.info('ShareService', '[shareText] 打开分享面板')
      await controller.show(this.context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      })

      console.info('ShareService', '[shareText] 分享面板已关闭')
      return { success: true, errorMessage: '' }
    } catch (error) {
      console.error('ShareService', `[shareText] 分享文本失败: ${JSON.stringify(error)}`)
      return { success: false, errorMessage: `分享失败: ${error}` }
    }
  }

  // 分享图片
  async shareImage(imagePath: string, title: string = '分享对话'): Promise<ShareResult> {
    if (this.context === null) {
      console.error('ShareService', '[shareImage] 服务未初始化')
      return { success: false, errorMessage: '服务未初始化' }
    }

    try {
      console.info('ShareService', `[shareImage] 开始分享图片: ${imagePath}`)
      const uri = fileUri.getUriFromPath(imagePath)
      console.info('ShareService', `[shareImage] 文件URI: ${uri}`)

      const shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.PNG,
        uri: uri,
        title: title
      })

      const controller = new systemShare.ShareController(shareData)
      console.info('ShareService', '[shareImage] 打开分享面板')
      await controller.show(this.context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      })

      console.info('ShareService', '[shareImage] 分享面板已关闭')
      return { success: true, errorMessage: '' }
    } catch (error) {
      console.error('ShareService', `[shareImage] 分享图片失败: ${JSON.stringify(error)}`)
      return { success: false, errorMessage: `分享失败: ${error}` }
    }
  }

  // 截取组件为图片并保存
  async captureComponentAsImage(componentId: string, uiContext: UIContext): Promise<string> {
    try {
      // 使用 componentSnapshot 截取组件
      const snapshot = uiContext.getComponentSnapshot()
      const pixelMap = await snapshot.get(componentId, { scale: 2 })

      // 创建图片打包器
      const packer = image.createImagePacker()

      // 打包为 PNG
      const packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100
      }
      const arrayBuffer = await packer.packToData(pixelMap, packOpts)

      // 保存到临时目录
      const fileName = `share_${Date.now()}.png`
      const tempDir = this.context?.tempDir ?? ''
      const filePath = `${tempDir}/${fileName}`

      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
      fs.writeSync(file.fd, arrayBuffer)
      fs.closeSync(file)

      // 释放资源
      packer.release()
      pixelMap.release()

      return filePath
    } catch (e) {
      const errorMsg = `截图失败: ${JSON.stringify(e)}`
      console.error('ShareService', errorMsg)
      throw new Error(errorMsg)
    }
  }

  // 格式化时间
  private formatTime(timestamp: number): string {
    const date = new Date(timestamp)
    const hours = date.getHours()
    const minutes = date.getMinutes().toString().padStart(2, '0')
    const period = hours >= 12 ? 'PM' : 'AM'
    const displayHours = hours % 12 || 12
    return `${displayHours}:${minutes} ${period}`
  }

  // 格式化日期时间
  private formatDateTime(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${year}-${month}-${day} ${hours}:${minutes}`
  }
}

// 单例实例
let shareServiceInstance: ShareService | null = null

export function getShareService(): ShareService {
  if (shareServiceInstance === null) {
    shareServiceInstance = new ShareService()
  }
  return shareServiceInstance
}
