let storage = new LocalStorage();

@Entry(storage)
@Component
struct NewChatCard {
  @LocalStorageProp('title') title: string = '新对话';
  @LocalStorageProp('subtitle') subtitle: string = '点击开始聊天';
  @LocalStorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @LocalStorageProp('textPrimary') textPrimary: string = '#191919';
  @LocalStorageProp('textColor') textColor: string = '';
  @LocalStorageProp('glassBgColor') glassBgColor: string = 'rgba(255,255,255,0.55)';
  @LocalStorageProp('shadowColor') shadowColor: string = 'rgba(0,0,0,0.1)';
  @LocalStorageProp('borderColor') glassBorderColor: string = 'rgba(0,0,0,0.06)';

  private getEffectiveTextColor(): string {
    return this.textColor || this.textPrimary;
  }

  build() {
    Row() {
      Row() {
        Text('开始对话')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getEffectiveTextColor())
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

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
    .clip(true)
    .backgroundBlurStyle(BlurStyle.Regular)
    .backgroundColor(this.glassBgColor)
    .borderRadius(16)
    .border({ width: 0.75, color: this.glassBorderColor })
    .shadow({
      radius: 14,
      color: this.shadowColor,
      offsetX: 0,
      offsetY: 3
    })
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
