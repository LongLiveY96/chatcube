/**
 * 分享消息卡片组件
 * 用于渲染分享图片的卡片样式
 */
import { ChatMessage, MessageRole, MessageAttachment, AttachmentType } from '../models/ChatModels'
import { getModelIconPath, buildIconResourcePath } from '../utils/ProviderIconUtils'
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in'

@Component
export struct ShareMessageCard {
  messages: ChatMessage[] = []
  appName: string = 'ChatCube'
  currentModelId: string = ''
  // 为每条消息创建独立的 MarkdownController
  private markdownControllers: Map<string, MarkdownController> = new Map()
  // 暗黑模式适配
  @StorageProp('isDarkMode') isDarkMode: boolean = false
  // 主题色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_user_bubble') themeUserBubble: string = '#0A59F7'
  @StorageProp('theme_user_bubble_text') themeUserBubbleText: string = '#FFFFFF'
  @StorageProp('theme_ai_bubble') themeAiBubble: string = '#FFFFFF'

  // 配置 Markdown 样式（与聊天页面保持一致，避免深色模式下不可读）
  private configureMarkdownController(controller: MarkdownController): void {
    const titleColor = $r('app.color.markdown_title')
    const textColor = $r('app.color.markdown_text')
    const quoteBgColor = $r('app.color.markdown_quote_bg')
    const linkColor = $r('app.color.markdown_link')
    const linkBgColor = $r('app.color.markdown_link_bg')
    const inlineCodeBgColor = $r('app.color.markdown_code_bg')
    const inlineCodeTextColor = $r('app.color.markdown_code_text')
    const tableBgColor = $r('app.color.markdown_table_bg')
    const tableHeaderBgColor = $r('app.color.markdown_table_header_bg')
    const tableAltBgColor = $r('app.color.markdown_table_alt_bg')
    const tableBorderColor = $r('app.color.markdown_table_border')
    const codeTheme = this.isDarkMode ? 'dark' : 'light'

    // 数学公式颜色接口需要 number（ARGB），不能直接传 ResourceColor
    const latexTextColor = this.isDarkMode ? 0xFFE0E0E0 : 0xFF333333

    controller
      .setTitleColor(titleColor)
      .setTextColor(textColor)
      .setTextSize(12)
      .setTextLineHeight(18)
      .setTitleSize([18, 16, 14, 13, 12, 12])
      .setQuoteBackgroundColor(quoteBgColor)
      .setQuoteBorderColor(linkColor)
      .setHyperlinkTextColor(linkColor)
      .setHyperlinkBackgroundColor(linkBgColor)
      .setInlineCodeColor(inlineCodeTextColor)
      .setInlineCodeBackgroundColor(inlineCodeBgColor)
      .setCodeBlockTheme(codeTheme)
      .setLatexMathTextColor(latexTextColor)
      .setTableBackgroundColor(tableBgColor)
      .setTableTitleBackgroundColor(tableHeaderBgColor)
      .setTableInterleaveBackgroundColor(tableAltBgColor)
      .setTableOuterBorderColor(tableBorderColor)
      .setTableInnerBorderColor(tableBorderColor)
      .setUlPointColor(textColor)
      .setLineColor(tableBorderColor)
      .setFootnoteTextColor(linkColor)
  }

  // 获取或创建 MarkdownController
  private getMarkdownController(messageId: string): MarkdownController {
    let controller = this.markdownControllers.get(messageId)
    if (controller === undefined) {
      controller = new MarkdownController()
      this.configureMarkdownController(controller)
      this.markdownControllers.set(messageId, controller)
    }
    return controller
  }

  // 获取卡片背景色
  private getCardBackground(): ResourceColor {
    return $r('app.color.surface')
  }

  // 获取主文字颜色
  private getPrimaryTextColor(): ResourceColor {
    return $r('app.color.text_primary')
  }

  // 获取次要文字颜色
  private getSecondaryTextColor(): ResourceColor {
    return $r('app.color.text_secondary')
  }

  // 获取分割线颜色
  private getDividerColor(): ResourceColor {
    return $r('app.color.divider')
  }

  // 获取AI头像背景色
  private getAiAvatarBgColor(): ResourceColor {
    return $r('app.color.chat_ai_bubble')
  }

  // 获取 AI 内容容器背景色
  private getAiContentBgColor(): ResourceColor {
    return $r('app.color.chat_ai_bubble')
  }

  // 获取用户消息气泡背景色（使用主题色）
  private getUserBubbleBgColor(): string {
    return this.themeUserBubble
  }

  // 获取用户消息文字颜色
  private getUserBubbleTextColor(): string {
    return this.themeUserBubbleText
  }

  // 获取消息模型图标文件名（空字符串表示无可用图标）
  private getMessageModelIconPath(message: ChatMessage): string {
    // 优先用 modelId → 回退到当前会话模型 ID → 最后回退到 modelName
    let id = message.modelId
    if (id === '' || id === undefined) {
      id = this.currentModelId
    }
    if (id === '' || id === undefined) {
      id = message.modelName
    }
    if (id === '' || id === undefined) {
      return ''
    }
    return getModelIconPath(id, '', '')
  }

  // 获取消息模型图标资源路径（空字符串表示无可用图标）
  private getMessageModelIconResourcePath(message: ChatMessage): string {
    const iconPath = this.getMessageModelIconPath(message)
    if (iconPath === '') {
      return ''
    }
    return buildIconResourcePath(iconPath)
  }

  build() {
    // 外层底板容器：带圆角和裁剪，确保截图时圆角生效
    Column() {
      // 内层卡片内容
      Column() {
        // 卡片头部：应用名称和时间
        Row() {
          // 应用图标
          Image($r('app.media.app_icon'))
            .width(24)
            .height(24)
            .borderRadius(6)

          Text(this.appName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getPrimaryTextColor())
            .margin({ left: 8 })

          Blank()

          Text(this.formatDateTime(Date.now()))
            .fontSize(12)
            .fontColor(this.getSecondaryTextColor())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        Divider()
          .color(this.getDividerColor())
          .margin({ left: 16, right: 16 })

        // 消息列表
        Column() {
          ForEach(this.messages, (message: ChatMessage, index: number) => {
            this.MessageItem(message, index)
          }, (message: ChatMessage) => message.id)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .width('100%')
      .backgroundColor(this.getCardBackground())
    }
    .width('100%')
    // 底板背景色：使用轻微的灰色作为分享图片的背景
    .backgroundColor(this.isDarkMode ? '#1A1A1A' : '#F5F5F5')
    .borderRadius(16)
    .clip(true) // 关键：启用裁剪确保圆角生效
    .shadow({
      radius: 20,
      color: this.isDarkMode ? 'rgba(0, 0, 0, 0.3)' : 'rgba(0, 0, 0, 0.1)',
      offsetX: 0,
      offsetY: 4
    })
  }

  @Builder
  MessageItem(message: ChatMessage, index: number) {
    Column() {
      if (message.role === MessageRole.USER) {
        // 用户消息
        Row() {
          Blank()

          Column() {
            // 附件展示
            if (message.hasAttachments()) {
              this.ShareAttachments(message, true)
            }

            // 文本内容
            if (message.content.length > 0) {
              Text(message.content)
                .fontSize(13)
                .fontColor(this.getUserBubbleTextColor())
                .lineHeight(18)
                .padding(message.hasAttachments() ? { left: 8, right: 8 } : { left: 0, right: 0 })
            }
          }
          .padding(message.hasAttachments() ? { left: 4, right: 4, top: 4, bottom: 8 } : { left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(this.getUserBubbleBgColor())
          .borderRadius({
            topLeft: 16,
            topRight: 16,
            bottomLeft: 16,
            bottomRight: 4
          })
          .constraintSize({ maxWidth: '75%' })
        }
        .width('100%')
        .margin({ bottom: 12 })
      } else {
        // AI 消息
        Row() {
          // 模型图标
          Column() {
            if (this.getMessageModelIconResourcePath(message) !== '') {
              Image(this.getMessageModelIconResourcePath(message))
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
            } else {
              SymbolGlyph($r('sys.symbol.ai_edit'))
                .fontSize(16)
                .fontColor([this.themePrimary])
            }
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor($r('app.color.model_icon_bg'))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .flexShrink(0)

          Column() {
            Column() {
              // 模型名称
              Text(message.modelName || 'AI')
                .fontSize(11)
                .fontColor(this.getSecondaryTextColor())
                .margin({ bottom: 4 })

              // 附件展示（AI 生成的图片等）
              if (message.hasAttachments()) {
                this.ShareAttachments(message, false)
              }

              // 消息内容 - 使用 Markdown 渲染（紧凑样式）
              if (message.content.length > 0) {
                Markdown({
                  controller: this.getMarkdownController(message.id),
                  text: message.content
                })
                  .width('100%')
                  .backgroundColor(Color.Transparent)
              }
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor(this.getAiContentBgColor())
            .borderRadius(12)
            .border({ width: 0.5, color: this.getDividerColor() })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 10 })
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ bottom: 12 })
      }
    }
    .width('100%')
  }

  // 分享卡片中的附件展示（无交互手势，纯静态展示）
  @Builder
  ShareAttachments(message: ChatMessage, isUserMessage: boolean) {
    Column() {
      ForEach(message.attachments, (attachment: MessageAttachment) => {
        if (attachment.type === AttachmentType.IMAGE) {
          // 图片附件：直接显示图片
          if (attachment.filePath !== '') {
            Image('file://' + attachment.filePath)
              .constraintSize({
                maxWidth: isUserMessage ? 160 : 240,
                maxHeight: isUserMessage ? 160 : 240
              })
              .objectFit(ImageFit.Contain)
              .borderRadius(isUserMessage ? 12 : 8)
              .margin({ bottom: 4 })
          } else if (attachment.base64Data !== '') {
            Image(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
              .constraintSize({
                maxWidth: isUserMessage ? 160 : 240,
                maxHeight: isUserMessage ? 160 : 240
              })
              .objectFit(ImageFit.Contain)
              .borderRadius(isUserMessage ? 12 : 8)
              .margin({ bottom: 4 })
          }
        } else {
          // 文件附件：图标+文件名
          Row() {
            SymbolGlyph($r('sys.symbol.doc'))
              .fontSize(14)
              .fontColor([isUserMessage ? 'rgba(255,255,255,0.8)' : this.getSecondaryTextColor()])

            Text(attachment.name)
              .fontSize(11)
              .fontColor(isUserMessage ? 'rgba(255,255,255,0.9)' : this.getSecondaryTextColor())
              .margin({ left: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .padding(6)
          .backgroundColor(isUserMessage ? 'rgba(255,255,255,0.15)' : this.getDividerColor())
          .borderRadius(6)
          .margin({ bottom: 4 })
        }
      }, (attachment: MessageAttachment) => attachment.id || attachment.filePath)
    }
    .alignItems(isUserMessage ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  // 格式化日期时间
  private formatDateTime(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${year}/${month}/${day} ${hours}:${minutes}`
  }
}

// 用于截图的 Builder
@Builder
export function ShareMessageCardBuilder(messages: ChatMessage[], appName: string) {
  ShareMessageCard({
    messages: messages,
    appName: appName
  })
}
