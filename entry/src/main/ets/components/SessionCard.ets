import { ChatSession } from '../models/ChatModels'
import { curves } from '@kit.ArkUI'
import { hdsEffect } from '@kit.UIDesignKit'
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in'
import {
  getSessionDisplayPreviewText,
  getSessionPreviewBodyText,
  hasSessionDraftContent,
  SESSION_DRAFT_TAG_TEXT
} from '../utils/ChatSessionDisplayHelper'
import { getAppUiState } from '../state/AppUiState'

@ComponentV2
export struct SessionCard {
  @Param session: ChatSession = new ChatSession('', '', '')
  @Param unreadCount: number = 0
  @Param enableAnimation: boolean = true
  @Param enableContextMenu: boolean = true
  @Param themeRenderKey: string = ''
  @Local scaleValue: number = 1
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  @Param uiVisualEnhanced: boolean = false
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private titleMarkdownController: MarkdownController | null = null
  @Event onTap: () => void = () => {}
  @Event onDelete: () => void = () => {}
  @Event onMultiSelect: () => void = () => {}
  @Event onShare: () => void = () => {}
  @Event onToggleFavorite: () => void = () => {}

  aboutToAppear(): void {
    if (this.titleContainsLatex()) {
      this.configureTitleMarkdownStyles()
    }
  }

  @Monitor('themeRenderKey')
  onThemeRenderKeyChange(): void {
    this.configureTitleMarkdownStyles()
  }

  aboutToDisappear(): void {
  }

  private configureTitleMarkdownStyles(): void {
    if (this.titleMarkdownController === null) {
      return
    }
    const textColor = $r('app.color.text_primary')
    const latexTextColor = this.isDarkMode ? 0xFFE0E0E0 : 0xFF333333

    this.titleMarkdownController
      .setTitleColor(textColor)
      .setTextColor(textColor)
      .setTextSize(13)
      .setTextLineHeight(18)
      .setLatexMathTextColor(latexTextColor)
      .setLatexMathTextSize(14)
  }

  private getTitleMarkdownController(): MarkdownController {
    if (this.titleMarkdownController === null) {
      this.titleMarkdownController = new MarkdownController()
      this.configureTitleMarkdownStyles()
    }
    return this.titleMarkdownController
  }

  private titleContainsLatex(): boolean {
    return /\$.+?\$/.test(this.session.title) ||
      this.session.title.includes('\\(') ||
      this.session.title.includes('\\[')
  }

  private normalizeLatexInTitle(title: string): string {
    let result = title
    result = result.replace(/\\\[([\s\S]*?)\\\]/g, (_match: string, p1: string): string => `$$${p1}$$`)
    result = result.replace(/\\\(([\s\S]*?)\\\)/g, (_match: string, p1: string): string => `$${p1}$`)
    return result
  }

  private getFavoriteMenuText(): Resource {
    if (this.session.isFavorite) {
      return $r('app.string.menu_unfavorite')
    }
    return $r('app.string.menu_favorite')
  }

  private getPreviewText(): string {
    return getSessionDisplayPreviewText(this.session)
  }

  private getPreviewBodyText(): string {
    return getSessionPreviewBodyText(this.session)
  }

  private hasDraftPreview(): boolean {
    return hasSessionDraftContent(this.session)
  }

  @Builder
  private PreviewTextContent() {
    if (this.hasDraftPreview()) {
      Row({ space: 6 }) {
        Text(SESSION_DRAFT_TAG_TEXT)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .backgroundColor(this.themePrimaryLight)
          .borderRadius(6)

        Text(this.getPreviewBodyText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
    } else {
      Text(this.getPreviewText())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  SessionContextMenu() {
    Menu() {
      MenuItem({ startIcon: $r('sys.symbol.checkmark_circle'), content: $r('app.string.menu_multi_select') })
        .onClick(() => {
          this.onMultiSelect()
        })
      MenuItem({ startIcon: $r('sys.symbol.share'), content: $r('app.string.menu_share') })
        .onClick(() => {
          this.onShare()
        })
      MenuItem({ startIcon: $r('sys.symbol.heart'), content: this.getFavoriteMenuText() })
        .onClick(() => {
          this.onToggleFavorite()
        })
      MenuItem({ startIcon: $r('sys.symbol.trash'), content: $r('app.string.delete') })
        .contentFontColor('#FF3B30')
        .onClick(() => {
          this.onDelete()
        })
    }
  }

  @Builder
  SessionPreview() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.ellipsis_message_fill'))
          .fontSize(18)
          .fontColor([this.themePrimary])
      }
      .width(36)
      .height(36)
      .borderRadius(9)
      .backgroundColor(this.themePrimaryLight)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column() {
        if (this.titleContainsLatex()) {
          Markdown({
            controller: this.getTitleMarkdownController(),
            text: this.normalizeLatexInTitle(this.session.title)
          })
            .constraintSize({ maxHeight: 22 })
            .clip(true)
            .backgroundColor(Color.Transparent)
        } else {
          Text(this.session.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        if (this.getPreviewText() !== '') {
          Row() {
            this.PreviewTextContent()
          }
          .width('100%')
            .margin({ top: 2 })
        } else {
          Text($r('app.string.session_no_preview'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
      .layoutWeight(1)
    }
    .width(290)
    .padding(12)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
  }

  @Builder
  private PrefixContent() {
    Column() {
      SymbolGlyph($r('sys.symbol.ellipsis_message_fill'))
        .fontSize(18)
        .fontColor([this.themePrimary])
    }
    .width(36)
    .height(36)
    .borderRadius(9)
    .backgroundColor(this.themePrimaryLight)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private MiddleContent() {
    Column() {
      Row() {
        if (this.titleContainsLatex()) {
          Markdown({
            controller: this.getTitleMarkdownController(),
            text: this.normalizeLatexInTitle(this.session.title)
          })
            .layoutWeight(1)
            .constraintSize({ maxHeight: 22 })
            .clip(true)
            .backgroundColor(Color.Transparent)
        } else {
          Text(this.session.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }

        if (this.unreadCount > 0) {
          Text(this.getUnreadCountText())
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.status_error'))
            .borderRadius(8)
            .margin({ right: 6 })
        }

        this.RelativeTimeText(this.session.updatedAt)
      }
      .width('100%')

      Row() {
        if (this.getPreviewText() !== '') {
          Row() {
            this.PreviewTextContent()
          }
          .width('100%')
            .layoutWeight(1)
        } else {
          Text($r('app.string.session_no_preview'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }

        Row() {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(10)
            .fontColor([$r('app.color.text_tertiary')])
          Text(this.session.messageCount.toString())
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 2 })

          if (this.session.isFavorite) {
            SymbolGlyph($r('sys.symbol.heart_fill'))
              .fontSize(10)
              .fontColor([$r('app.color.status_error')])
              .margin({ left: 6 })
          }
        }
        .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SuffixContent() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(14)
      .fontColor([$r('app.color.text_tertiary')])
      .margin({ left: 8 })
  }

  private buildCardPointLightEffect() {
    return new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.uiVisualEnhanced ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect()
  }

  build() {
    Row() {
      this.PrefixContent()

      Column() {
        this.MiddleContent()
      }
      .layoutWeight(1)
      .margin({ left: 10 })

      this.SuffixContent()
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .visualEffect(this.buildCardPointLightEffect())
    .onClick(() => {
      this.onTap()
    })
    .bindContextMenu(this.enableContextMenu ? this.SessionContextMenu : undefined, ResponseType.LongPress, {
      preview: this.SessionPreview
    })
  }

  @Builder
  RelativeTimeText(timestamp: number) {
    Row({ space: 0 }) {
      if (this.isJustNow(timestamp)) {
        Text($r('app.string.time_just_now'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.isMinutesAgo(timestamp)) {
        Text(this.getMinutesAgoValue(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text($r('app.string.time_minutes_ago_suffix'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.isHoursAgo(timestamp)) {
        Text(this.getHoursAgoValue(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text($r('app.string.time_hours_ago_suffix'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.isDaysAgo(timestamp)) {
        Text(this.getDaysAgoValue(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text($r('app.string.time_days_ago_suffix'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else {
        Text(this.formatDateMMDD(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .margin({ left: 8 })
  }

  private formatDateMMDD(timestamp: number): string {
    const date = new Date(timestamp)
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const dayNum = date.getDate().toString().padStart(2, '0')
    return `${month}-${dayNum}`
  }

  private getRelativeDiff(timestamp: number): number {
    const now = Date.now()
    return now > timestamp ? now - timestamp : 0
  }

  private isJustNow(timestamp: number): boolean {
    return this.getRelativeDiff(timestamp) < 60 * 1000
  }

  private isMinutesAgo(timestamp: number): boolean {
    const diff = this.getRelativeDiff(timestamp)
    return diff >= 60 * 1000 && diff < 60 * 60 * 1000
  }

  private isHoursAgo(timestamp: number): boolean {
    const diff = this.getRelativeDiff(timestamp)
    return diff >= 60 * 60 * 1000 && diff < 24 * 60 * 60 * 1000
  }

  private isDaysAgo(timestamp: number): boolean {
    const diff = this.getRelativeDiff(timestamp)
    return diff >= 24 * 60 * 60 * 1000 && diff < 7 * 24 * 60 * 60 * 1000
  }

  private getMinutesAgoValue(timestamp: number): string {
    return `${Math.floor(this.getRelativeDiff(timestamp) / (60 * 1000))}`
  }

  private getHoursAgoValue(timestamp: number): string {
    return `${Math.floor(this.getRelativeDiff(timestamp) / (60 * 60 * 1000))}`
  }

  private getDaysAgoValue(timestamp: number): string {
    return `${Math.floor(this.getRelativeDiff(timestamp) / (24 * 60 * 60 * 1000))}`
  }

  private getUnreadCountText(): string {
    if (this.unreadCount > 99) {
      return '99+'
    }
    return this.unreadCount.toString()
  }
}

