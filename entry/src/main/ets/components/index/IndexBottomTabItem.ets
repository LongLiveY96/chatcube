@Component
export struct IndexBottomTabItem {
  @Prop active: boolean = false
  @Prop activeIcon: Resource = $r('sys.symbol.circle')
  @Prop inactiveIcon: Resource = $r('sys.symbol.circle')
  @Prop label: Resource = $r('app.string.tab_chat')
  @Prop badgeCount: number = 0
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'

  build() {
    Column() {
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
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }
}
