import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { ALL_THEMES, ColorTheme, getThemeColors, ThemeColorConfig, ThemeInfo } from '../models/ThemeColors'
import { ThemeMode } from '../services/PreferencesService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'

@Component
export struct ThemeAppearanceSettingsView {
  @StorageProp(AppStorageKeys.LAYOUT_SIZE_CLASS) layoutSizeClass: string = LayoutSizeClass.COMPACT
  @StorageProp(AppStorageKeys.WINDOW_WIDTH_VP) windowWidthVp: number = 0
  @StorageProp(AppStorageKeys.WINDOW_HEIGHT_VP) windowHeightVp: number = 0
  @StorageProp(AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE) settingsDetailPresentationMode: string =
    SettingsPagePresentationMode.PAGE
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_primary_light') themePrimaryLight: string = '#E6F2FF'
  @StorageProp('isDarkMode') isDarkMode: boolean = false

  @State currentThemeMode: ThemeMode = ThemeMode.SYSTEM
  @State currentColorTheme: ColorTheme = ColorTheme.DEFAULT
  @State chatFontSize: number = 15

  private settingsManager = ServiceRegistry.settings()

  aboutToAppear(): void {
    this.currentThemeMode = this.settingsManager.getThemeMode()
    this.currentColorTheme = this.settingsManager.getColorTheme()
    this.chatFontSize = this.settingsManager.getChatFontSize()
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private getResolvedDarkMode(mode: ThemeMode = this.currentThemeMode): boolean {
    if (mode === ThemeMode.DARK) {
      return true
    }
    if (mode === ThemeMode.LIGHT) {
      return false
    }
    return this.isDarkMode
  }

  private getPreviewColors(themeId: ColorTheme = this.currentColorTheme, mode: ThemeMode = this.currentThemeMode): ThemeColorConfig {
    return getThemeColors(themeId, this.getResolvedDarkMode(mode))
  }

  private getThemeName(themeId: ColorTheme): Resource {
    if (themeId === ColorTheme.YUANBAO) {
      return $r('app.string.theme_color_yuanbao')
    }
    if (themeId === ColorTheme.CLAUDE) {
      return $r('app.string.theme_color_claude')
    }
    if (themeId === ColorTheme.CHATGPT) {
      return $r('app.string.theme_color_chatgpt')
    }
    if (themeId === ColorTheme.VIOLET) {
      return $r('app.string.theme_color_violet')
    }
    if (themeId === ColorTheme.MINT) {
      return $r('app.string.theme_color_mint')
    }
    if (themeId === ColorTheme.SUNSET) {
      return $r('app.string.theme_color_sunset')
    }
    if (themeId === ColorTheme.BERRY) {
      return $r('app.string.theme_color_berry')
    }
    return $r('app.string.theme_color_default')
  }

  private getThemeDescription(themeId: ColorTheme): Resource {
    if (themeId === ColorTheme.YUANBAO) {
      return $r('app.string.theme_color_yuanbao_desc')
    }
    if (themeId === ColorTheme.CLAUDE) {
      return $r('app.string.theme_color_claude_desc')
    }
    if (themeId === ColorTheme.CHATGPT) {
      return $r('app.string.theme_color_chatgpt_desc')
    }
    if (themeId === ColorTheme.VIOLET) {
      return $r('app.string.theme_color_violet_desc')
    }
    if (themeId === ColorTheme.MINT) {
      return $r('app.string.theme_color_mint_desc')
    }
    if (themeId === ColorTheme.SUNSET) {
      return $r('app.string.theme_color_sunset_desc')
    }
    if (themeId === ColorTheme.BERRY) {
      return $r('app.string.theme_color_berry_desc')
    }
    return $r('app.string.theme_color_default_desc')
  }

  private getThemePreviewSwatch(theme: ThemeInfo, index: number): string {
    if (index >= 0 && index < theme.previewColors.length) {
      return theme.previewColors[index]
    }
    return this.getPreviewColors(theme.id).primary
  }

  private getFontSizeText(size: number): Resource {
    if (size <= 13) {
      return $r('app.string.font_size_small')
    }
    if (size <= 15) {
      return $r('app.string.font_size_default')
    }
    if (size <= 17) {
      return $r('app.string.font_size_large')
    }
    return $r('app.string.font_size_extra_large')
  }

  private getAiPreviewFontSize(): number {
    return this.chatFontSize - 1 < 12 ? 12 : this.chatFontSize - 1
  }

  private async handleThemeModeSelected(mode: ThemeMode): Promise<void> {
    const previousMode = this.currentThemeMode
    this.currentThemeMode = mode
    try {
      await this.settingsManager.setThemeMode(mode)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView', `Failed to set theme mode: ${JSON.stringify(error)}`)
      this.currentThemeMode = previousMode
    }
  }

  private async handleColorThemeSelected(theme: ColorTheme): Promise<void> {
    const previousTheme = this.currentColorTheme
    this.currentColorTheme = theme
    try {
      await this.settingsManager.setColorTheme(theme)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView', `Failed to set color theme: ${JSON.stringify(error)}`)
      this.currentColorTheme = previousTheme
    }
  }

  private handleFontSizeChanged(size: number): void {
    this.chatFontSize = size
    this.settingsManager.setChatFontSize(size).catch((error: Error): void => {
      console.error('ThemeAppearanceSettingsView', `Failed to update chat font size: ${JSON.stringify(error)}`)
    })
  }

  @Builder
  private SectionHeader(title: Resource, subtitle: Resource) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text(subtitle)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(18)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private PreviewLine(color: string, widthValue: string) {
    Column()
      .width(widthValue)
      .height(8)
      .borderRadius(4)
      .backgroundColor(color)
  }

  @Builder
  private ModeRadioRow(mode: ThemeMode, title: Resource) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Regular)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Radio({ value: mode, group: 'appearanceThemeMode' })
        .checked(this.currentThemeMode === mode)
        .radioStyle({
          checkedBackgroundColor: this.themePrimary,
          indicatorColor: Color.White
        })
        .onChange((isChecked: boolean) => {
          if (isChecked && this.currentThemeMode !== mode) {
            this.handleThemeModeSelected(mode)
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (this.currentThemeMode !== mode) {
        this.handleThemeModeSelected(mode)
      }
    })
  }

  @Builder
  private ModeRadioGroup() {
    Column() {
      this.ModeRadioRow(ThemeMode.SYSTEM, $r('app.string.theme_system'))
      Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
      this.ModeRadioRow(ThemeMode.LIGHT, $r('app.string.theme_light'))
      Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
      this.ModeRadioRow(ThemeMode.DARK, $r('app.string.theme_dark'))
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(24)
    .border({ width: 1, color: $r('app.color.divider') })
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  private ThemeCard(theme: ThemeInfo) {
    Column({ space: 12 }) {
      Column({ space: 14 }) {
        Row({ space: 10 }) {
          Column()
            .layoutWeight(1)
            .height(16)
            .borderRadius(8)
            .backgroundColor(this.getThemePreviewSwatch(theme, 0))
            .border({ width: 1, color: this.getPreviewColors(theme.id).divider })

          Column()
            .layoutWeight(1)
            .height(16)
            .borderRadius(8)
            .backgroundColor(this.getThemePreviewSwatch(theme, 1))

          Column()
            .layoutWeight(1)
            .height(16)
            .borderRadius(8)
            .backgroundColor(this.getThemePreviewSwatch(theme, 2))
        }
        .width('100%')

        Row({ space: 12 }) {
          Column({ space: 8 }) {
            this.PreviewLine(this.getPreviewColors(theme.id).primary, '100%')
            this.PreviewLine(this.getPreviewColors(theme.id).primaryLight, '72%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Column()
            .width(30)
            .height(30)
            .borderRadius(15)
            .backgroundColor(this.getPreviewColors(theme.id).userBubble)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
      }
      .width('100%')
      .padding(14)
      .backgroundColor(this.getPreviewColors(theme.id).background)
      .borderRadius(18)
      .border({ width: 1, color: this.getPreviewColors(theme.id).divider })

      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.getThemeName(theme.id))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.getThemeDescription(theme.id))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.currentColorTheme === theme.id) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(18)
            .fontColor([this.themePrimary])
        }
      }
      .width('100%')
    }
    .padding(12)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(22)
    .border({
      width: this.currentColorTheme === theme.id ? 2 : 1,
      color: this.currentColorTheme === theme.id ? this.themePrimary : $r('app.color.divider')
    })
    .onClick(() => {
      this.handleColorThemeSelected(theme.id)
    })
  }

  @Builder
  private FontPresetButton(label: Resource, size: number) {
    Button(label)
      .height(36)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.chatFontSize === size ? Color.White : this.themePrimary)
      .backgroundColor(this.chatFontSize === size ? this.themePrimary : this.themePrimaryLight)
      .borderRadius(18)
      .layoutWeight(1)
      .onClick(() => {
        this.handleFontSizeChanged(size)
      })
  }

  @Builder
  private FontPreviewCard() {
    Column({ space: 14 }) {
      Row() {
        Column() {
          Text($r('app.string.font_preview_ai_message'))
            .fontSize(this.getAiPreviewFontSize())
            .lineHeight(this.getAiPreviewFontSize() + 7)
            .fontColor(this.getPreviewColors().textPrimary)
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.getPreviewColors().aiBubble)
        .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 6, bottomRight: 18 })
        .constraintSize({ maxWidth: '76%' })

        Blank()
      }
      .width('100%')

      Row() {
        Blank()

        Column() {
          Text($r('app.string.font_preview_user_message'))
            .fontSize(this.chatFontSize)
            .lineHeight(this.chatFontSize + 7)
            .fontColor(this.getPreviewColors().userBubbleText)
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.getPreviewColors().userBubble)
        .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 6 })
        .constraintSize({ maxWidth: '76%' })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getPreviewColors().background)
    .borderRadius(20)
    .border({ width: 1, color: this.getPreviewColors().divider })
  }

  @Builder
  private LivePreviewSection() {
    Column({ space: 16 }) {
      this.SectionHeader($r('app.string.appearance_live_preview_title'),
        $r('app.string.appearance_live_preview_desc'))

      Column() {
        this.FontPreviewCard()
      }
      .width('100%')
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(24)
    }
    .width('100%')
  }

  @Builder
  private PageContent() {
    Scroll() {
      Row() {
        Column({ space: 22 }) {
          this.LivePreviewSection()

          this.SectionHeader($r('app.string.appearance_display_mode_title'),
            $r('app.string.appearance_display_mode_desc'))

          this.ModeRadioGroup()

          this.SectionHeader($r('app.string.settings_color_theme'),
            $r('app.string.appearance_color_theme_desc'))

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

          this.SectionHeader($r('app.string.settings_font_size'),
            $r('app.string.settings_font_size_desc'))

          Column({ space: 16 }) {
            Row() {
              Column({ space: 2 }) {
                Text($r('app.string.settings_font_size'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))

                Text(this.getFontSizeText(this.chatFontSize))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)

              Blank()

              Text(`${this.chatFontSize} fp`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
            }
            .width('100%')

            Row({ space: 10 }) {
              Text('A')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))

              Slider({ value: this.chatFontSize, min: 12, max: 22, step: 1, style: SliderStyle.InSet })
                .selectedColor(this.themePrimary)
                .trackThickness(20)
                .layoutWeight(1)
                .onChange((value: number, _mode: SliderChangeMode) => {
                  this.handleFontSizeChanged(Math.round(value))
                })

              Text('A')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Row({ space: 8 }) {
              this.FontPresetButton($r('app.string.font_size_small'), 13)
              this.FontPresetButton($r('app.string.font_size_default'), 15)
              this.FontPresetButton($r('app.string.font_size_large'), 17)
              this.FontPresetButton($r('app.string.font_size_extra_large'), 19)
            }
            .width('100%')
          }
          .width('100%')
          .padding(18)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(24)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_appearance'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor($r('app.color.background'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        Column() {
          this.DetailPaneHeader()
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.background'))
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .titleBar({
          avoidLayoutSafeArea: true,
          enableComponentSafeArea: true,
          content: {
            title: {
              mainTitle: $r('app.string.settings_appearance')
            }
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

@Entry
@Component
struct ThemeModeSettingsPage {
  build() {
    Column() {
      ThemeAppearanceSettingsView()
    }
    .width('100%')
    .height('100%')
  }
}

@Builder
export function ThemeModeSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    ThemeModeSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
}
