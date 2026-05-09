/**
 * 分享消息卡片组件
 * 用于渲染分享图片的卡片样式
 */
import { ChatMessage, MessageRole, MessageAttachment, AttachmentType } from '../models/ChatModels'
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in'
import { getAppUiState } from '../state/AppUiState'
import { AssistantAvatarView } from './AssistantAvatar'
import {
  getMarkdownBlockSpacing,
  getMarkdownQuotePadding,
  getMarkdownTextLineHeight,
  getMarkdownTitleLineHeights,
  getMarkdownTitleSizes
} from '../utils/MarkdownTypographyUtils'

@ComponentV2
export struct ShareMessageCard {
  @Param messages: ChatMessage[] = []
  @Param appName: string = 'ChatCube'
  @Param currentModelId: string = ''
  @Param iconRenderVersion: number = 0
  @Param assistantAvatarValue: string = 'AI'
  @Param assistantAvatarColor: string = '#4E6F9E'
  @Param assistantAvatarCacheKey: number = 0
  private markdownControllers: Map<string, MarkdownController> = new Map()
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }
  private get themeUserBubbleText(): string {
    return getAppUiState().themeUserBubbleText
  }
  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

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
    const textSize = 14
    const titleSizes = getMarkdownTitleSizes(textSize)

    // 数学公式颜色接口需要 number（ARGB），不能直接传 ResourceColor
    const latexTextColor = this.isDarkMode ? 0xFFE0E0E0 : 0xFF333333

    controller
      .setTitleColor(titleColor)
      .setTextColor(textColor)
      .setTextSize(textSize)
      .setTextLineHeight(getMarkdownTextLineHeight(textSize))
      .setTitleSize(titleSizes)
      .setTitleLineHeight(getMarkdownTitleLineHeights(titleSizes))
      .setQuoteBackgroundColor(quoteBgColor)
      .setQuoteBorderColor(linkColor)
      .setQuotePadding(getMarkdownQuotePadding(textSize))
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
    controller.setBlockSpacing(getMarkdownBlockSpacing(textSize))
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

  private hasFencedCodeBlock(content: string): boolean {
    return /```[\s\S]*?```/.test(content)
  }

  private hasMarkdownTable(content: string): boolean {
    const lines = content.split('\n')
    for (let i = 0; i < lines.length - 1; i++) {
      const header = lines[i].trim()
      const separator = lines[i + 1].trim()
      if (header.indexOf('|') < 0 || separator.indexOf('|') < 0) {
        continue
      }
      if (/^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$/.test(separator)) {
        return true
      }
    }
    return false
  }

  private needsWideAiLayout(message: ChatMessage): boolean {
    const content = message.content
    if (content.trim().length === 0) {
      return false
    }
    return this.hasMarkdownTable(content) || this.hasFencedCodeBlock(content)
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

  // 获取 AI 内容容器背景色
  private getAiContentBgColor(): ResourceColor {
    return this.themeAiBubble
  }

  // 获取用户消息气泡背景色（使用主题色）
  private getUserBubbleBgColor(): string {
    return this.themeUserBubble
  }

  // 获取用户消息文字颜色
  private getUserBubbleTextColor(): string {
    return this.themeUserBubbleText
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
            .syncLoad(true)

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
          ForEach(this.messages, (message: ChatMessage) => {
            this.MessageItem(message)
          }, (message: ChatMessage) => message.id)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })

        // AI 生成合规标识（分享图片底部）
        Divider()
          .color(this.getDividerColor())
          .margin({ left: 16, right: 16 })

        Row() {
          Text($r('app.string.ai_generated_label'))
            .fontSize(11)
            .fontColor(this.getSecondaryTextColor())
            .opacity(0.8)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: 16, right: 16, top: 10, bottom: 14 })
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
  MessageItem(message: ChatMessage) {
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
                .fontSize(15)
                .fontColor(this.getUserBubbleTextColor())
                .lineHeight(21)
                .padding(message.hasAttachments() ? { left: 8, right: 8 } : { left: 0, right: 0 })
            }
          }
          .padding(message.hasAttachments() ? { left: 8, right: 8, top: 8, bottom: 8 } : { left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(this.getUserBubbleBgColor())
          .borderRadius({
            topLeft: 20,
            topRight: 20,
            bottomLeft: 20,
            bottomRight: 6
          })
          .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.15)' })
          .constraintSize({ maxWidth: '75%' })
        }
        .width('100%')
        .margin({ bottom: 12 })
      } else {
        // AI 消息
        Row() {
          // 助手头像 (与聊天页 MessageBubble 保持一致)
          Column() {
            AssistantAvatarView({
              value: this.assistantAvatarValue,
              color: this.assistantAvatarColor,
              avatarSize: 30,
              radius: 8,
              fontSize: 14,
              cacheKey: this.assistantAvatarCacheKey,
              modelId: message.modelId !== '' ? message.modelId : this.currentModelId,
              modelName: message.modelName
            })
          }
          .width(30)
          .height(30)
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .flexShrink(0)

          Column() {
            Column() {
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
            .padding(this.needsWideAiLayout(message)
              ? { left: 6, right: 6, top: 10, bottom: 10 }
              : { left: 14, right: 14, top: 12, bottom: 10 })
            .backgroundColor(this.getAiContentBgColor())
            .borderRadius(16)
            .border({ width: 0.5, color: $r('app.color.bubble_border') })
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
                maxWidth: 180,
                maxHeight: 180
              })
              .objectFit(ImageFit.Contain)
              .borderRadius(8)
              .margin({ bottom: 4 })
              .syncLoad(true)
          } else if (attachment.base64Data !== '') {
            Image(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
              .constraintSize({
                maxWidth: 180,
                maxHeight: 180
              })
              .objectFit(ImageFit.Contain)
              .borderRadius(8)
              .margin({ bottom: 4 })
              .syncLoad(true)
          }
        } else {
          // 文件附件：图标+文件名
          Row() {
            SymbolGlyph($r('sys.symbol.doc'))
              .fontSize(18)
              .fontColor([isUserMessage ? 'rgba(255,255,255,0.8)' : $r('app.color.text_tertiary')])

            Text(attachment.name)
              .fontSize(12)
              .fontColor(isUserMessage ? 'rgba(255,255,255,0.9)' : $r('app.color.text_secondary'))
              .margin({ left: 6 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .padding(8)
          .backgroundColor(isUserMessage ? 'rgba(255,255,255,0.15)' : $r('app.color.divider'))
          .borderRadius(8)
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
