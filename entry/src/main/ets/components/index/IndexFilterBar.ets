import { SessionFilterType } from '../../pages/index/IndexPageTypes'

@ComponentV2
export struct IndexFilterBar {
  @Param currentFilter: SessionFilterType = SessionFilterType.ALL
  @Param countText: string = '0'
  @Param themePrimary: string = '#0A59F7'
  @Param themePrimaryLight: string = '#E6F2FF'
  @Event onFilterChange: (filterType: SessionFilterType) => void = (_filterType: SessionFilterType): void => {}

  @Builder
  private FilterChip(filterType: SessionFilterType, title: Resource) {
    if (this.currentFilter === filterType) {
      Row() {
        Text(title)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
      }
      .height(28)
      .padding({ left: 12, right: 12 })
      .margin({ right: 8 })
      .borderRadius(14)
      .backgroundColor(this.themePrimaryLight)
      .border({ width: 1, color: this.themePrimary })
      .onClick(() => {
        this.onFilterChange(filterType)
      })
    } else {
      Row() {
        Text(title)
          .fontSize(12)
          .fontWeight(FontWeight.Regular)
          .fontColor($r('app.color.text_secondary'))
      }
      .height(28)
      .padding({ left: 12, right: 12 })
      .margin({ right: 8 })
      .borderRadius(14)
      .backgroundColor($r('app.color.surface'))
      .onClick(() => {
        this.onFilterChange(filterType)
      })
    }
  }

  build() {
    Row() {
      this.FilterChip(SessionFilterType.ALL, $r('app.string.filter_all'))
      this.FilterChip(SessionFilterType.FAVORITE, $r('app.string.filter_favorite'))
      Blank()
      Text(this.countText)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .height(36)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }
}
