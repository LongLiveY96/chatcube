/**
 * 分享预览弹窗组件
 * 支持三种分享模式：图片、Markdown、纯文本
 */
import { ChatMessage, MessageRole } from '../models/ChatModels'
import { ShareService, ShareMode, getShareService } from '../services/ShareService'
import { ShareMessageCard } from './ShareMessageCard'
import { showToast } from '../utils/ToastUtil'
import { common } from '@kit.AbilityKit'
import { image } from '@kit.ImageKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { fileUri } from '@kit.CoreFileKit'

@Component
export struct SharePreviewSheet {
  messages: ChatMessage[] = []
  currentModelId: string = ''
  @State selectedMode: ShareMode = ShareMode.IMAGE
  @State isSharing: boolean = false
  @State previewText: string = ''
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_primary_light') themePrimaryLight: string = '#E6F2FF'
  onClose: () => void = () => {}

  private shareService: ShareService = getShareService()

  private showShareToast(message: string | Resource, duration: number = 2000): void {
    showToast(this.getUIContext(), message, duration)
  }

  aboutToAppear(): void {
    console.info('SharePreviewSheet', `[aboutToAppear] 消息数量: ${this.messages.length}, 分享模式: ${this.selectedMode}`)
    // 初始化预览文本
    this.updatePreviewText()
  }

  // 更新预览文本
  private updatePreviewText(): void {
    if (this.selectedMode === ShareMode.MARKDOWN) {
      this.previewText = this.shareService.convertToMarkdown(this.messages)
    } else if (this.selectedMode === ShareMode.TEXT) {
      this.previewText = this.shareService.convertToPlainText(this.messages)
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text($r('app.string.share_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Blank()

        // 关闭按钮
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

      // 分享模式选择
      Row() {
        this.ModeButton($r('app.string.share_mode_image'), ShareMode.IMAGE, $r('sys.symbol.picture'))
        this.ModeButton($r('app.string.share_mode_markdown'), ShareMode.MARKDOWN, $r('sys.symbol.doc_text'))
        this.ModeButton($r('app.string.share_mode_text'), ShareMode.TEXT, $r('sys.symbol.text_alignleft'))
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .justifyContent(FlexAlign.SpaceBetween)

      // 预览区域
      Column() {
        if (this.messages.length === 0) {
          // 空状态提示
          Column() {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(48)
              .fontColor([$r('app.color.text_tertiary')])
              .margin({ bottom: 12 })
            Text($r('app.string.share_no_content'))
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.selectedMode === ShareMode.IMAGE) {
          // 图片预览
          Scroll() {
            ShareMessageCard({
              messages: this.messages,
              appName: 'ChatCube',
              currentModelId: this.currentModelId
            })
              .margin(16)
              .id('share_card_preview')
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        } else {
          // 文本预览
          Scroll() {
            Text(this.previewText)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .lineHeight(20)
              .width('100%')
              .textAlign(TextAlign.Start)
          }
          .width('100%')
          .layoutWeight(1)
          .padding(16)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .margin({ left: 20, right: 20, top: 12 })
        }
      }
      .width('100%')
      .layoutWeight(1)

      // 分享按钮
      Button(this.isSharing ? $r('app.string.sharing') : $r('app.string.share_button'))
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.themePrimary)
        .borderRadius(24)
        .margin({ left: 20, right: 20, top: 12, bottom: 20 })
        .enabled(!this.isSharing && this.messages.length > 0)
        .opacity(this.messages.length > 0 ? 1 : 0.5)
        .onClick(() => {
          this.handleShare()
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  ModeButton(label: string | Resource, mode: ShareMode, icon: Resource) {
    Column() {
      Row() {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([this.selectedMode === mode ? this.themePrimary : $r('app.color.text_secondary')])
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor(this.selectedMode === mode ? this.themePrimaryLight : $r('app.color.surface'))
      .justifyContent(FlexAlign.Center)

      Text(label)
        .fontSize(12)
        .fontColor(this.selectedMode === mode ? this.themePrimary : $r('app.color.text_secondary'))
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (this.selectedMode !== mode) {
        this.selectedMode = mode
        this.updatePreviewText()
      }
    })
  }

  // 处理分享
  private async handleShare(): Promise<void> {
    if (this.messages.length === 0) {
      console.warn('SharePreviewSheet', '[handleShare] no message to share')
      this.showShareToast($r('app.string.share_no_content'))
      return
    }

    this.isSharing = true
    console.info('SharePreviewSheet', `[handleShare] 开始分享，模式: ${this.selectedMode}, 消息数: ${this.messages.length}`)

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!context) {
        console.error('SharePreviewSheet', '[handleShare] app context unavailable')
        this.showShareToast($r('app.string.share_context_unavailable'))
        this.isSharing = false
        return
      }
      this.shareService.init(context)

      if (this.selectedMode === ShareMode.IMAGE) {
        // 图片分享：截取卡片组件
        await this.shareAsImage(context)
      } else if (this.selectedMode === ShareMode.MARKDOWN) {
        // Markdown 分享
        const content = this.shareService.convertToMarkdown(this.messages)
        const result = await this.shareService.shareText(content, 'conversation.md')
        if (!result.success) {
          if (result.errorMessage !== '') {
            this.showShareToast(result.errorMessage)
          } else {
            this.showShareToast($r('app.string.share_failed'))
          }
        }
      } else {
        // 纯文本分享
        const content = this.shareService.convertToPlainText(this.messages)
        const result = await this.shareService.shareText(content, 'conversation')
        if (!result.success) {
          if (result.errorMessage !== '') {
            this.showShareToast(result.errorMessage)
          } else {
            this.showShareToast($r('app.string.share_failed'))
          }
        }
      }
    } catch (e) {
      console.error('SharePreviewSheet', `分享失败: ${JSON.stringify(e)}`)
      this.showShareToast($r('app.string.share_failed'))
    } finally {
      this.isSharing = false
    }
  }

  // 图片分享
  private async shareAsImage(context: common.UIAbilityContext): Promise<void> {
    try {
      console.info('SharePreviewSheet', '[shareAsImage] start snapshot sharing flow')

      // 等待组件完全渲染（Sheet 动画完成 + 足够时间让 Scroll 内容渲染）
      await new Promise<void>((resolve) => {
        setTimeout(() => {
          resolve()
        }, 800)
      })

      // 使用 componentSnapshot 截取预览卡片
      const snapshot = this.getUIContext().getComponentSnapshot()
      console.info('SharePreviewSheet', '[shareAsImage] snapshot start, componentId=share_card_preview')

      // 检查组件是否存在
      let pixelMap: image.PixelMap
      try {
        pixelMap = await snapshot.get('share_card_preview', { scale: 2 })
        const imageInfo = pixelMap.getImageInfoSync()
        console.info('SharePreviewSheet', `[shareAsImage] 截图成功，尺寸: ${imageInfo.size.width}x${imageInfo.size.height}`)
      } catch (snapshotError) {
        console.error('SharePreviewSheet', `[shareAsImage] 截图失败: ${JSON.stringify(snapshotError)}`)
        this.showShareToast($r('app.string.share_snapshot_failed'))
        return
      }

      // 创建图片打包器
      const packer = image.createImagePacker()
      const packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100
      }
      const arrayBuffer = await packer.packToData(pixelMap, packOpts)
      console.info('SharePreviewSheet', `[shareAsImage] 图片打包完成，大小: ${arrayBuffer.byteLength} 字节`)

      // 保存到缓存目录
      const fileName = `share_${Date.now()}.png`
      const cacheDir = context.cacheDir
      const filePath = `${cacheDir}/${fileName}`
      console.info('SharePreviewSheet', `[shareAsImage] 保存图片到: ${filePath}`)

      // 确保目录存在
      try {
        fs.accessSync(cacheDir)
      } catch (e) {
        fs.mkdirSync(cacheDir, true)
      }

      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
      fs.writeSync(file.fd, arrayBuffer)
      fs.closeSync(file)
      console.info('SharePreviewSheet', '[shareAsImage] image saved')

      // 释放资源
      packer.release()
      pixelMap.release()

      // 分享图片
      console.info('SharePreviewSheet', '[shareAsImage] start share image')
      const result = await this.shareService.shareImage(filePath, 'conversation')

      if (!result.success) {
        console.error('SharePreviewSheet', `[shareAsImage] 分享失败: ${result.errorMessage}`)
        if (result.errorMessage !== '') {
          this.showShareToast(result.errorMessage)
        } else {
          this.showShareToast($r('app.string.share_failed'))
        }
      } else {
        console.info('SharePreviewSheet', '[shareAsImage] shared')
      }
    } catch (e) {
      console.error('SharePreviewSheet', `[shareAsImage] 图片分享失败: ${JSON.stringify(e)}`)
      this.showShareToast($r('app.string.share_failed'))
    }
  }
}
