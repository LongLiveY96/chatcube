import { ChatSession } from '../models/ChatModels'
import { curves } from '@kit.ArkUI'
import { HdsListItemCard, PrefixCustomBuilder, SuffixCustomBuilder, hdsEffect } from '@kit.UIDesignKit'

@Component
export struct SessionCard {
  @Prop session: ChatSession = new ChatSession('', '', '')
  @Prop unreadCount: number = 0
  @Prop enableAnimation: boolean = true
  @Prop enableContextMenu: boolean = true
  @State scaleValue: number = 1
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_primary_light') themePrimaryLight: string = '#E6F2FF'
  @StorageProp('ui_visual_enhanced') uiVisualEnhanced: boolean = false
  onTap: () => void = () => {}
  onDelete: () => void = () => {}
  onMultiSelect: () => void = () => {}
  onShare: () => void = () => {}
  onToggleFavorite: () => void = () => {}

  private getFavoriteMenuText(): Resource {
    if (this.session.isFavorite) {
      return $r('app.string.menu_unfavorite')
    }
    return $r('app.string.menu_favorite')
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
        Text(this.session.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.session.lastMessagePreview !== '') {
          Text(this.session.lastMessagePreview)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
        Text(this.session.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

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
        if (this.session.lastMessagePreview !== '') {
          Text(this.session.lastMessagePreview)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
    // TODO: 排查横滑冲突，临时禁用 onTouch 按压缩放
    // .scale(this.enableAnimation ? { x: this.scaleValue, y: this.scaleValue } : { x: 1, y: 1 })
    // .onTouch(this.enableAnimation ? (event: TouchEvent) => {
    //   if (event.type === TouchType.Down) {
    //     this.getUIContext().animateTo({
    //       curve: curves.interpolatingSpring(0, 1, 350, 35)
    //     }, () => {
    //       this.scaleValue = 0.96
    //     })
    //   } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
    //     this.getUIContext().animateTo({
    //       curve: curves.interpolatingSpring(0, 1, 350, 35)
    //     }, () => {
    //       this.scaleValue = 1
    //     })
    //   }
    // } : undefined)
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
