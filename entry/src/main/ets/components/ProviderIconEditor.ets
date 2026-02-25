/**
 * 供应商图标编辑器组件
 * 支持两种图标类型：SVG、文字
 */

import { ProviderIcon } from './ProviderIcon'
import { generateSoftColor, getAllSoftColors, TRANSPARENT_BG_COLOR } from '../utils/IconGeneratorUtils'
import { showToast } from '../utils/ToastUtil'

@Component
export struct ProviderIconEditor {
  // 双向绑定的图标配置
  @Link iconType: string
  @Link iconPath: string
  @Link textIcon: string
  @Link textIconBgColor: string
  // 供应商信息
  @Prop providerName: string = ''
  @Prop isPreset: boolean = false
  // 内部状态
  @State showTextIconEditor: boolean = false
  @State showColorPicker: boolean = false
  @State tempTextIcon: string = ''
  @State tempTextIconBgColor: string = ''
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'

  private showIconToast(message: string | Resource, duration: number = 2000): void {
    showToast(this.getUIContext(), message, duration)
  }

  build() {
    Column({ space: 12 }) {
      // 图标预览
      Row({ space: 12 }) {
        // 图标显示
        ProviderIcon({
          iconType: this.iconType,
          iconPath: this.iconPath,
          textIcon: this.textIcon,
          textIconBgColor: this.textIconBgColor,
          customImagePath: '',
          iconSize: 56,
          radius: 16,
          bgColor: $r('app.color.surface'),
          fallbackSymbol: $r('sys.symbol.message'),
          fallbackColor: $r('app.color.text_tertiary')
        })
          .onClick(() => {
            this.onIconClick()
          })
          .bindSheet($$this.showTextIconEditor, this.TextIconEditorSheet(), {
            height: 450,
            showClose: false,
            onDisappear: () => {
              this.showTextIconEditor = false
            }
          })

        Column({ space: 4 }) {
          Text($r('app.string.icon_click_edit'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Text(this.getIconTypeText())
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(12)

      // 图标类型选择
      Row({ space: 8 }) {
        // 文字图标按钮
        Button($r('app.string.icon_text_button'))
          .fontSize(14)
          .type(ButtonType.Normal)
          .borderRadius(8)
          .backgroundColor(this.iconType === 'text' ? $r('app.color.primary') : $r('app.color.surface'))
          .fontColor(this.iconType === 'text' ? Color.White : $r('app.color.text_primary'))
          .layoutWeight(1)
          .onClick(() => {
            this.switchToTextIcon()
          })

        // 重置按钮（仅预设供应商显示）
        if (this.isPreset && this.iconPath !== '') {
          Button($r('app.string.icon_reset_button'))
            .fontSize(14)
            .type(ButtonType.Normal)
            .borderRadius(8)
            .backgroundColor($r('app.color.surface'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.resetToPresetIcon()
            })
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  // 获取图标类型文本
  private getIconTypeText(): string | Resource {
    if (this.iconType === 'svg') {
      return $r('app.string.icon_type_preset')
    } else if (this.iconType === 'text') {
      return this.textIcon !== '' ? this.textIcon : $r('app.string.icon_type_text')
    }
    return $r('app.string.icon_type_unset')
  }

  // 点击图标
  private onIconClick(): void {
    if (this.iconType === 'text') {
      this.tempTextIcon = this.textIcon
      this.tempTextIconBgColor = this.textIconBgColor
      this.showTextIconEditor = true
    }
  }

  // 切换到文字图标
  private switchToTextIcon(): void {
    // 检查之前是否就是文字图标类型
    const wasTextIcon = this.iconType === 'text'

    this.iconType = 'text'

    if (!wasTextIcon || this.textIcon === '') {
      // 从其他类型切换过来，或者文字图标为空时，自动生成首字母
      this.textIcon = this.extractInitials(this.providerName)
    }
    if (this.textIconBgColor === '') {
      this.textIconBgColor = generateSoftColor()
    }
    this.tempTextIcon = this.textIcon
    this.tempTextIconBgColor = this.textIconBgColor
    this.showTextIconEditor = true
  }

  // 重置为预设图标
  private resetToPresetIcon(): void {
    this.iconType = 'svg'
    this.textIcon = ''
    this.textIconBgColor = ''
    this.showIconToast($r('app.string.provider_default_icon_reset'))
  }

  // 提取首字母（简化版）
  private extractInitials(text: string): string {
    if (text === '' || text.length === 0) {
      return 'AI'
    }
    const words = text.trim().split(/[\s\-_]+/)
    const initials: string[] = []
    for (let i = 0; i < words.length && initials.length < 2; i++) {
      const word = words[i]
      if (word.length > 0) {
        initials.push(word.charAt(0).toUpperCase())
      }
    }
    return initials.length > 0 ? initials.join('') : 'AI'
  }

  // 文字图标编辑器 Sheet
  @Builder
  TextIconEditorSheet() {
    Column({ space: 16 }) {
      // 标题行
      Row() {
        // 关闭按钮
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
          this.showTextIconEditor = false
        })

        // 标题
        Text($r('app.string.icon_edit_text_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 保存按钮
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
          this.textIcon = this.tempTextIcon
          this.textIconBgColor = this.tempTextIconBgColor
          this.showTextIconEditor = false
        })
      }
      .width('100%')

      // 图标预览
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

      // 文字输入
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

      // 背景颜色
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
          // 颜色预览
          if (this.tempTextIconBgColor === TRANSPARENT_BG_COLOR) {
            // 透明背景：显示棋盘格图案
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

          // 颜色值
          Text(this.tempTextIconBgColor === TRANSPARENT_BG_COLOR ? $r('app.string.icon_transparent_hint') : this.tempTextIconBgColor)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)

          // 选择颜色按钮
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

    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.background'))
  }

  // 颜色选择器 Sheet
  @Builder
  ColorPickerSheet() {
    Column({ space: 16 }) {
      // 标题
      Text($r('app.string.icon_color_picker_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .width('100%')

      // 透明选项
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

      // 颜色网格
      Scroll() {
        Grid() {
          ForEach(getAllSoftColors(), (color: string, index: number) => {
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
