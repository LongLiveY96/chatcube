@Component
export struct IndexEmptyStateCard {
  @Prop icon: Resource = $r('sys.symbol.circle')
  @Prop title: Resource = $r('app.string.no_sessions')
  @Prop description: Resource = $r('app.string.start_new_chat')
  @Prop showButton: boolean = false
  @Prop buttonText: Resource = $r('app.string.new_chat')
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  onButtonClick: () => void = () => {}

  build() {
    Column() {
      SymbolGlyph(this.icon)
        .fontSize(64)
        .fontColor([$r('app.color.text_tertiary')])

      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16 })

      Text(this.description)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })

      if (this.showButton) {
        Button(this.buttonText)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(this.themePrimary)
          .borderRadius(24)
          .height(48)
          .padding({ left: 32, right: 32 })
          .margin({ top: 24 })
          .shadow({
            radius: 16,
            color: this.themePrimary + '4D',
            offsetX: 0,
            offsetY: 4
          })
          .onClick(() => {
            this.onButtonClick()
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}
