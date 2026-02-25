@Entry
@Component
struct NewChatCard {
  @LocalStorageProp('title') title: string = '新对话';
  @LocalStorageProp('subtitle') subtitle: string = '点击开始聊天';
  @LocalStorageProp('themePrimary') themePrimary: string = '#0A59F7';

  build() {
    Column() {
      Row() {
        // 左侧文字区域
        Text('开始对话')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        // 右侧加号图标（参考电话卡片样式：白色图标 + 主题色实心背景）
        Row() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .borderRadius(16)
        .backgroundColor(this.themePrimary)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 12 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.surface'))
    .clip(true)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          action: 'newChat'
        }
      });
    })
  }
}
