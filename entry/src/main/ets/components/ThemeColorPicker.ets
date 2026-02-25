import { ColorTheme, ThemeInfo, ALL_THEMES } from '../models/ThemeColors'
import { getThemeService } from '../services/ThemeService'

@Component
export struct ThemeColorPicker {
  @State currentTheme: ColorTheme = ColorTheme.DEFAULT
  @StorageProp('isDarkMode') isDarkMode: boolean = false
  onThemeSelected: (theme: ColorTheme) => void = () => {}

  aboutToAppear(): void {
    this.currentTheme = getThemeService().getColorTheme()
  }

  build() {
    Column() {
      // 主题网格（每行2个）
      Grid() {
        ForEach(ALL_THEMES, (theme: ThemeInfo) => {
          GridItem() {
            this.ThemeCard(theme)
          }
        }, (theme: ThemeInfo) => theme.id)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 32 })
    }
    .width('100%')
  }

  @Builder
  ThemeCard(theme: ThemeInfo) {
    Column() {
      // 预览色块区域
      Row() {
        // 背景色预览
        Column()
          .width(24)
          .height(24)
          .borderRadius(12)
          .backgroundColor(this.isDarkMode ? theme.dark.background : theme.light.background)
          .border({
            width: 1,
            color: this.isDarkMode ? theme.dark.divider : theme.light.divider
          })

        // 主色调预览
        Column()
          .width(24)
          .height(24)
          .borderRadius(12)
          .backgroundColor(this.isDarkMode ? theme.dark.primary : theme.light.primary)
          .margin({ left: 8 })

        // 气泡色预览
        Column()
          .width(24)
          .height(24)
          .borderRadius(12)
          .backgroundColor(this.isDarkMode ? theme.dark.userBubble : theme.light.userBubble)
          .margin({ left: 8 })

        Blank()

        // 选中标记
        if (this.currentTheme === theme.id) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(20)
            .fontColor([this.isDarkMode ? theme.dark.primary : theme.light.primary])
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12 })

      // 主题名称
      Text(this.getThemeName(theme.id))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
        .alignSelf(ItemAlign.Start)
        .padding({ left: 12 })

      // 主题描述
      Text(this.getThemeDescription(theme.id))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 2, bottom: 12 })
        .alignSelf(ItemAlign.Start)
        .padding({ left: 12 })
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .border({
      width: this.currentTheme === theme.id ? 2 : 1,
      color: this.currentTheme === theme.id ?
        (this.isDarkMode ? theme.dark.primary : theme.light.primary) :
        $r('app.color.divider')
    })
    .onClick(() => {
      this.currentTheme = theme.id
      this.onThemeSelected(theme.id)
    })
  }

  private getThemeName(themeId: ColorTheme): Resource {
    if (themeId === ColorTheme.DEFAULT) {
      return $r('app.string.theme_color_default')
    } else if (themeId === ColorTheme.YUANBAO) {
      return $r('app.string.theme_color_yuanbao')
    } else if (themeId === ColorTheme.CLAUDE) {
      return $r('app.string.theme_color_claude')
    } else if (themeId === ColorTheme.CHATGPT) {
      return $r('app.string.theme_color_chatgpt')
    } else if (themeId === ColorTheme.VIOLET) {
      return $r('app.string.theme_color_violet')
    } else if (themeId === ColorTheme.MINT) {
      return $r('app.string.theme_color_mint')
    } else if (themeId === ColorTheme.SUNSET) {
      return $r('app.string.theme_color_sunset')
    } else {
      return $r('app.string.theme_color_default')
    }
  }

  private getThemeDescription(themeId: ColorTheme): Resource {
    if (themeId === ColorTheme.DEFAULT) {
      return $r('app.string.theme_color_default_desc')
    } else if (themeId === ColorTheme.YUANBAO) {
      return $r('app.string.theme_color_yuanbao_desc')
    } else if (themeId === ColorTheme.CLAUDE) {
      return $r('app.string.theme_color_claude_desc')
    } else if (themeId === ColorTheme.CHATGPT) {
      return $r('app.string.theme_color_chatgpt_desc')
    } else if (themeId === ColorTheme.VIOLET) {
      return $r('app.string.theme_color_violet_desc')
    } else if (themeId === ColorTheme.MINT) {
      return $r('app.string.theme_color_mint_desc')
    } else if (themeId === ColorTheme.SUNSET) {
      return $r('app.string.theme_color_sunset_desc')
    } else {
      return $r('app.string.theme_color_default_desc')
    }
  }
}
