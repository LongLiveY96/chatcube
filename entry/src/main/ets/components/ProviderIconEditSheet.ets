import { ModelProvider } from '../models/ChatModels'
import { ProviderIcon } from './ProviderIcon'
import { generateSoftColor, getAllSoftColors, TRANSPARENT_BG_COLOR } from '../utils/IconGeneratorUtils'

@Component
export struct ProviderIconEditSheet {
  @Link showColorPicker: boolean
  @Link tempTextIcon: string
  @Link tempTextIconBgColor: string
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'

  @Prop provider: ModelProvider | null = null
  onSave: () => void = () => {}
  onResetToPreset: () => void = () => {}
  onClose: () => void = () => {}

  build() {
    Column({ space: 16 }) {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Circle)
        .width(32)
        .height(32)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.onClose()
        })

        Blank()

        Text($r('app.string.icon_edit_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([Color.White])
        }
        .type(ButtonType.Circle)
        .width(32)
        .height(32)
        .backgroundColor(this.themePrimary)
        .onClick(() => {
          this.onSave()
          this.onClose()
        })
      }
      .width('100%')

      if (this.provider !== null) {
        ProviderIcon({
          iconType: 'text',
          iconPath: '',
          textIcon: this.tempTextIcon,
          textIconBgColor: this.tempTextIconBgColor,
          customImagePath: '',
          iconSize: 80,
          radius: 20,
          bgColor: $r('app.color.surface'),
          fallbackSymbol: $r('sys.symbol.message'),
          fallbackColor: $r('app.color.text_tertiary')
        })
          .alignSelf(ItemAlign.Center)
          .bindSheet($$this.showColorPicker, this.ColorPickerSheet(), {
            height: 400,
            showClose: true,
            onDisappear: () => {
              this.showColorPicker = false
            }
          })
      }

      Column({ space: 8 }) {
        Text($r('app.string.icon_text_input_label'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        TextInput({ text: this.tempTextIcon })
          .maxLength(2)
          .fontSize(16)
          .onChange((value: string) => {
            this.tempTextIcon = value
          })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Column({ space: 8 }) {
        Row() {
          Text($r('app.string.icon_background_color'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          Button($r('app.string.icon_random_generate'))
            .fontSize(12)
            .type(ButtonType.Normal)
            .borderRadius(6)
            .backgroundColor($r('app.color.surface'))
            .fontColor($r('app.color.text_primary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.tempTextIconBgColor = generateSoftColor()
            })
        }
        .width('100%')

        Row({ space: 12 }) {
          if (this.tempTextIconBgColor === TRANSPARENT_BG_COLOR) {
            Column() {
              Text($r('app.string.icon_none'))
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width(40)
            .height(40)
            .borderRadius(8)
            .border({ width: 1, color: $r('app.color.divider') })
            .justifyContent(FlexAlign.Center)
          } else {
            Column()
              .width(40)
              .height(40)
              .backgroundColor(this.tempTextIconBgColor)
              .borderRadius(8)
              .border({ width: 1, color: $r('app.color.divider') })
          }

          Text(this.tempTextIconBgColor === TRANSPARENT_BG_COLOR ? $r('app.string.icon_transparent_hint') : this.tempTextIconBgColor)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)

          Button($r('app.string.icon_select_color'))
            .fontSize(12)
            .type(ButtonType.Normal)
            .borderRadius(6)
            .backgroundColor($r('app.color.surface'))
            .fontColor($r('app.color.text_primary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.showColorPicker = true
            })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      if (this.provider !== null && this.provider.isPreset && this.provider.iconPath !== '') {
        Row() {
          Button($r('app.string.icon_reset_button'))
            .fontSize(14)
            .type(ButtonType.Normal)
            .borderRadius(8)
            .backgroundColor($r('app.color.surface'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.onResetToPreset()
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  ColorPickerSheet() {
    Column({ space: 16 }) {
      Text($r('app.string.icon_color_picker_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .width('100%')

      Row() {
        Column() {
          Text($r('app.string.icon_none'))
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width(50)
        .height(50)
        .borderRadius(8)
        .border({
          width: this.tempTextIconBgColor === TRANSPARENT_BG_COLOR ? 3 : 1,
          color: this.tempTextIconBgColor === TRANSPARENT_BG_COLOR ? $r('app.color.primary') : $r('app.color.divider')
        })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.tempTextIconBgColor = TRANSPARENT_BG_COLOR
          this.showColorPicker = false
        })

        Text($r('app.string.icon_transparent_hint'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ bottom: 8 })

      Divider().color($r('app.color.divider'))

      Scroll() {
        Grid() {
          ForEach(getAllSoftColors(), (color: string) => {
            GridItem() {
              Column()
                .width(50)
                .height(50)
                .backgroundColor(color)
                .borderRadius(8)
                .border({
                  width: this.tempTextIconBgColor === color ? 3 : 1,
                  color: this.tempTextIconBgColor === color ? $r('app.color.primary') : $r('app.color.divider')
                })
                .onClick(() => {
                  this.tempTextIconBgColor = color
                  this.showColorPicker = false
                })
            }
          })
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(12)
        .columnsGap(12)
        .width('100%')
      }
      .width('100%')
      .height(250)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.background'))
  }
}
