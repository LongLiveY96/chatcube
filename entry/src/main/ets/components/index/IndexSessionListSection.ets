import { ChatSession } from '../../models/ChatModels'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { HdsListItemCard, PrefixCustomBuilder, SuffixCustomBuilder } from '@kit.UIDesignKit'
import { SessionGroupData } from '../../pages/index/IndexPageTypes'

@Component
export struct IndexSessionListSection {
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_primary_light') themePrimaryLight: string = '#E6F2FF'
  @Prop sessionGroups: SessionGroupData[] = []
  @Prop isMultiSelectMode: boolean = false
  @Prop selectedSessionIds: Array<string> = []
  onGetUnreadCount: (sessionId: string) => number = (_sessionId: string): number => 0
  onGetGroupTitle: (groupKey: string) => Resource = (_groupKey: string): Resource => $r('app.string.group_older')
  onGetGroupRenderKey: (group: SessionGroupData) => string = (group: SessionGroupData): string => group.key
  onToggleSelection: (sessionId: string) => void = (_sessionId: string): void => {}
  onOpenSession: (sessionId: string) => void = (_sessionId: string): void => {}
  onDeleteSession: (sessionId: string) => void = (_sessionId: string): void => {}
  onEnterMultiSelect: (sessionId: string) => void = (_sessionId: string): void => {}
  onShareSession: (session: ChatSession) => void = (_session: ChatSession): void => {}
  onToggleFavorite: (session: ChatSession) => void = (_session: ChatSession): void => {}

  private sessionListScroller: ListScroller = new ListScroller()

  @Builder
  private SessionGroupHeader(groupKey: string, count: number) {
    Row() {
      Text(this.onGetGroupTitle(groupKey))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))

      Text(count.toString())
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 2 })
  }

  // --- SessionCard inlined builders ---

  @Builder
  private SessionPrefix() {
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
  private SessionMiddle(session: ChatSession, unreadCount: number) {
    Column() {
      Row() {
        Text(session.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (unreadCount > 0) {
          Text(unreadCount > 99 ? '99+' : unreadCount.toString())
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.status_error'))
            .borderRadius(8)
            .margin({ right: 6 })
        }

        this.RelativeTimeText(session.updatedAt)
      }
      .width('100%')

      Row() {
        if (session.lastMessagePreview !== '') {
          Text(session.lastMessagePreview)
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
          Text(session.messageCount.toString())
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 2 })

          if (session.isFavorite) {
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
  private SessionSuffix() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(14)
      .fontColor([$r('app.color.text_tertiary')])
      .margin({ left: 8 })
  }

  // --- Context menu & preview ---

  private getFavoriteMenuText(session: ChatSession): Resource {
    if (session.isFavorite) {
      return $r('app.string.menu_unfavorite')
    }
    return $r('app.string.menu_favorite')
  }

  @Builder
  private SessionContextMenu(session: ChatSession) {
    Menu() {
      MenuItem({ startIcon: $r('sys.symbol.checkmark_circle'), content: $r('app.string.menu_multi_select') })
        .onClick(() => {
          this.onEnterMultiSelect(session.id)
        })
      MenuItem({ startIcon: $r('sys.symbol.share'), content: $r('app.string.menu_share') })
        .onClick(() => {
          this.onShareSession(session)
        })
      MenuItem({ startIcon: $r('sys.symbol.heart'), content: this.getFavoriteMenuText(session) })
        .onClick(() => {
          this.onToggleFavorite(session)
        })
      MenuItem({ startIcon: $r('sys.symbol.trash'), content: $r('app.string.delete') })
        .contentFontColor('#FF3B30')
        .onClick(() => {
          this.onDeleteSession(session.id)
        })
    }
  }

  @Builder
  private SessionPreview(session: ChatSession) {
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
        Text(session.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (session.lastMessagePreview !== '') {
          Text(session.lastMessagePreview)
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

  // --- Relative time helpers ---

  @Builder
  private RelativeTimeText(timestamp: number) {
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

  // --- Swipe action builders ---

  @Builder
  private FavoriteSwipeButton(session: ChatSession) {
    Button() {
      Column() {
        SymbolGlyph(session.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(16)
          .fontColor([Color.White])

        Text(session.isFavorite ? $r('app.string.menu_unfavorite') : $r('app.string.menu_favorite'))
          .fontSize(10)
          .fontColor(Color.White)
          .margin({ top: 2 })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(84)
    .height('100%')
    .borderRadius({ topRight: 12, bottomRight: 12 })
    .backgroundColor(session.isFavorite ? $r('app.color.status_error') : this.themePrimary + 'B3')
    .onClick(() => {
      this.sessionListScroller.closeAllSwipeActions()
      this.onToggleFavorite(session)
    })
  }

  @Builder
  private DeleteSwipePanel(sessionId: string) {
    Button() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(24)
        .fontColor([Color.White])
    }
    .width(80)
    .height('100%')
    .backgroundColor($r('app.color.status_error'))
    .borderRadius({ topRight: 12, bottomRight: 12 })
    .onClick(() => {
      this.sessionListScroller.closeAllSwipeActions()
      this.onDeleteSession(sessionId)
    })
  }

  build() {
    List({ scroller: this.sessionListScroller }) {
      ForEach(this.sessionGroups, (group: SessionGroupData) => {
        ListItem() {
          this.SessionGroupHeader(group.key, group.sessions.length)
        }
        .margin({ top: 4 })

        ForEach(group.sessions, (session: ChatSession, index: number) => {
          ListItem() {
            HdsListItemCard({
              prefixItem: new PrefixCustomBuilder((): void => { this.SessionPrefix() }),
              textItem: {
                customBuilder: (): void => {
                  this.SessionMiddle(session, this.onGetUnreadCount(session.id))
                }
              },
              suffixItem: new SuffixCustomBuilder((): void => { this.SessionSuffix() }),
              cardBackgroundColor: $r('app.color.surface'),
              cardBorderRadius: 12,
              onClick: (): void => {
                if (this.isMultiSelectMode) {
                  this.onToggleSelection(session.id)
                } else {
                  this.onOpenSession(session.id)
                }
              }
            })
          }
          .swipeAction(this.isMultiSelectMode ? undefined : {
            start: this.FavoriteSwipeButton(session),
            end: this.DeleteSwipePanel(session.id)
          })
          .margin({ left: 16, right: 16, top: index === 0 ? 4 : 0, bottom: 6 })
          .borderRadius(12)
          .clip(true)
          .border(this.isMultiSelectMode && this.selectedSessionIds.includes(session.id)
            ? { width: 1.5, color: this.themePrimary }
            : { width: 0, color: Color.Transparent })
          .animation({ duration: 200 })
          .bindContextMenu(this.isMultiSelectMode ? undefined :
            (): void => { this.SessionContextMenu(session) }, ResponseType.LongPress, {
            preview: (): void => { this.SessionPreview(session) }
          })
        }, (session: ChatSession) => `${session.id}_${session.isFavorite ? '1' : '0'}`)
      }, (group: SessionGroupData) => this.onGetGroupRenderKey(group))

      ListItem() {
        Column().height(100)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}