import { getAppUiState } from '../../state/AppUiState'

@ComponentV2
export struct IndexBottomTabItem {
  @Param active: boolean = false
  @Param activeIcon: Resource = $r('sys.symbol.circle')
  @Param inactiveIcon: Resource = $r('sys.symbol.circle')
  @Param label: Resource = $r('app.string.tab_chat')
  @Param badgeCount: number = 0
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  build() {
    Column({ space: 2 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.active ? this.activeIcon : this.inactiveIcon)
          .fontSize(22)
          .fontColor(this.active ? [this.themePrimary] : [$r('app.color.text_secondary')])

        if (this.badgeCount > 0) {
          Row() {
            Text(this.badgeCount > 99 ? '99+' : this.badgeCount.toString())
              .fontSize(9)
              .fontColor($r('sys.color.comp_background_list_card'))
              .fontWeight(FontWeight.Medium)
          }
          .height(14)
          .padding({ left: 4, right: 4 })
          .borderRadius(7)
          .backgroundColor($r('app.color.status_error'))
          .position({ x: 16, y: -8 })
        }
      }
      .width(28)
      .height(24)

      Text(this.label)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.active ? this.themePrimary : $r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

