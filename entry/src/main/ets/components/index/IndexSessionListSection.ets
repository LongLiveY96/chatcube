import { ChatSession } from '../../models/ChatModels'
import { SessionListGroupViewModel, SessionListItemData } from '../../pages/index/IndexSessionListDataSource'
import { IndexSessionListItem } from './IndexSessionListItem'
import { getAppUiState } from '../../state/AppUiState'

@ComponentV2
export struct IndexSessionListSection {
  @Param sessionGroups: SessionListGroupViewModel[] = []
  @Param isMultiSelectMode: boolean = false
  @Param bottomSpacerHeight: number = 100
  @Param themeRenderKey: string = ''
  @Event onGetGroupTitle: (groupKey: string) => Resource = (_groupKey: string): Resource => $r('app.string.group_older')
  @Event onToggleSelection: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onOpenSession: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onDeleteSession: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onEnterMultiSelect: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onShareSession: (session: ChatSession) => void = (_session: ChatSession): void => {}
  @Event onToggleFavorite: (session: ChatSession) => void = (_session: ChatSession): void => {}

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
    .padding({ left: 8, right: 8, top: 6, bottom: 2 })
  }

  @Builder
  private FavoriteSwipeButton(session: ChatSession) {
    Button() {
      Column() {
        SymbolGlyph(session.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(18)
          .fontColor([Color.White])

        Text(session.isFavorite ? $r('app.string.menu_unfavorite') : $r('app.string.menu_favorite'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ top: 2 })
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(72)
    .height('100%')
    .borderRadius({ topLeft: 12, bottomLeft: 12 })
    .backgroundColor(session.isFavorite ? $r('app.color.status_error') : getAppUiState().themePrimary)
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
    .width(64)
    .height('100%')
    .backgroundColor($r('app.color.status_error'))
    .borderRadius({ topRight: 12, bottomRight: 12 })
    .onClick(() => {
      this.sessionListScroller.closeAllSwipeActions()
      this.onDeleteSession(sessionId)
    })
  }

  @Builder
  private SessionGroup(group: SessionListGroupViewModel) {
    ListItemGroup({
      header: this.SessionGroupHeader(group.key, group.count)
    }) {
      LazyForEach(group.dataSource, (item: SessionListItemData, index: number) => {
        ListItem({ style: ListItemStyle.NONE }) {
          IndexSessionListItem({
            item: item,
            isMultiSelectMode: this.isMultiSelectMode,
            themeRenderKey: this.themeRenderKey,
            onToggleSelection: (sessionId: string): void => {
              this.onToggleSelection(sessionId)
            },
            onOpenSession: (sessionId: string): void => {
              this.onOpenSession(sessionId)
            },
            onDeleteSession: (sessionId: string): void => {
              this.onDeleteSession(sessionId)
            },
            onEnterMultiSelect: (sessionId: string): void => {
              this.onEnterMultiSelect(sessionId)
            },
            onShareSession: (session: ChatSession): void => {
              this.onShareSession(session)
            },
            onToggleFavorite: (session: ChatSession): void => {
              this.onToggleFavorite(session)
            }
          })
        }
        .margin({ left: 8, right: 8, top: index === 0 ? 4 : 0, bottom: 6 })
        .swipeAction(this.isMultiSelectMode ? undefined : {
          start: this.FavoriteSwipeButton(item.session),
          end: this.DeleteSwipePanel(item.session.id)
        })
        .borderRadius(12)
        .clip(true)
      }, (item: SessionListItemData): string => item.key)
    }
    .divider(null)
  }

  build() {
    List({ scroller: this.sessionListScroller }) {
      ForEach(this.sessionGroups, (group: SessionListGroupViewModel) => {
        this.SessionGroup(group)
      }, (group: SessionListGroupViewModel): string => group.key)

      ListItem() {
        Column()
          .height(this.bottomSpacerHeight)
      }
      .focusable(false)
      .selectable(false)
    }
    .sticky(StickyStyle.None)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .cachedCount(4)
  }
}
