import {
  HdsNavigation,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsFloatingStyle
} from '@kit.UIDesignKit'
import { ALL_THEMES, ColorTheme, getThemeColors, ThemeColorConfig, ThemeInfo } from '../models/ThemeColors'
import { ThemeMode } from '../services/PreferencesService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { getSettingsPageContentMaxWidth, getSettingsPageCompactTabsTotalInset } from '../utils/SettingsPageLayoutHelper'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptions,
  getHdsTopNavigationBlurEffectiveEndOffset,
  getHdsTopNavigationMaskExtraHeight,
  HdsTopNavigationBlurOptions
} from '../utils/HdsVisualEffectUtil'
import {
  buildCompactTabsFloatingStyle,
  CompactTabsFloatingStyleOptions
} from '../utils/HdsTabsFloatingStyleHelper'
import { IndexBottomTabItem } from '../components/index/IndexBottomTabItem'

let themeModeSettingsPathStack: NavPathStack | null = null

const TAB_INDEX_THEME = 0
const TAB_INDEX_FONT = 1
const TAB_INDEX_MATERIAL = 2

const PREVIEW_TAB_INDEX_ASSISTANTS = 0
const PREVIEW_TAB_INDEX_CHAT = 1
const PREVIEW_TAB_INDEX_SETTINGS = 2

@ComponentV2
export struct ThemeAppearanceSettingsView {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get bottomAvoidHeight(): number {
    return getAppUiState().bottomAvoidHeight
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }
  private get themeDivider(): string {
    return getAppUiState().themeDivider
  }
  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }
  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }
  private get themeUserBubbleText(): string {
    return getAppUiState().themeUserBubbleText
  }
  private get themeTextPrimary(): string {
    return getAppUiState().themeTextPrimary
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  @Param compactTitle: string | Resource = $r('app.string.settings_appearance')
  @Event onCompactBack: () => void = () => {}

  @Local currentThemeMode: ThemeMode = ThemeMode.SYSTEM
  @Local currentColorTheme: ColorTheme = ColorTheme.DEFAULT
  @Local chatFontSize: number = 15
  @Local materialType: number = 100
  @Local materialLevel: number = 10
  @Local lightColorMode: string = 'default'

  @Local currentTabIndex: number = TAB_INDEX_THEME
  @Local previewTabIndex: number = PREVIEW_TAB_INDEX_CHAT

  private settingsManager = ServiceRegistry.settings()
  private themeScroller: Scroller = new Scroller()
  private fontScroller: Scroller = new Scroller()
  private materialScroller: Scroller = new Scroller()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.currentThemeMode = this.settingsManager.getThemeMode()
    this.currentColorTheme = this.settingsManager.getColorTheme()
    this.chatFontSize = this.settingsManager.getChatFontSize()
    this.materialType = this.settingsManager.getMaterialType()
    this.materialLevel = this.settingsManager.getMaterialLevel()
    this.lightColorMode = this.settingsManager.getLightColorMode()
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private getScrollBottomPadding(): number {
    return 24 + getSettingsPageCompactTabsTotalInset(this.px2vp(this.bottomAvoidHeight),
      this.settingsDetailPresentationMode)
  }

  private getCompactTitleBarMaskExtraHeight(): number {
    return getHdsTopNavigationMaskExtraHeight(this.windowWidthVp, this.windowHeightVp)
  }

  private getCompactContentTopPadding(): number {
    return this.px2vp(this.topAvoidHeight) + 56 + this.getCompactTitleBarMaskExtraHeight()
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    const options = new HdsTopNavigationBlurOptions()
    options.materialType = this.materialType
    options.materialLevel = this.materialLevel
    options.windowWidthVp = this.windowWidthVp
    options.windowHeightVp = this.windowHeightVp
    options.maskExtraHeightVp = this.getCompactTitleBarMaskExtraHeight()
    options.blurEffectiveEndOffsetVp = getHdsTopNavigationBlurEffectiveEndOffset(this.windowWidthVp,
      this.windowHeightVp)
    options.stackBuilder = (): void => this.CompactTitleStackBuilder()
    return buildHdsTopNavigationTitleBarOptions(options)
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
    if (themeId === ColorTheme.NOTION) {
      return $r('app.string.theme_color_notion')
    }
    return $r('app.string.theme_color_default')
  }

  private getThemeDescription(themeId: ColorTheme): Resource {
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
    if (themeId === ColorTheme.NOTION) {
      return $r('app.string.theme_color_notion_desc')
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

  private async handleMaterialTypeSelected(type: number): Promise<void> {
    const previous = this.materialType
    this.materialType = type
    try {
      await this.settingsManager.setMaterialType(type)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView', `Failed to set material type: ${JSON.stringify(error)}`)
      this.materialType = previous
    }
  }

  private async handleMaterialLevelSelected(level: number): Promise<void> {
    const previous = this.materialLevel
    this.materialLevel = level
    try {
      await this.settingsManager.setMaterialLevel(level)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView', `Failed to set material level: ${JSON.stringify(error)}`)
      this.materialLevel = previous
    }
  }

  private async handleLightColorModeSelected(mode: string): Promise<void> {
    const previous = this.lightColorMode
    this.lightColorMode = mode
    try {
      await this.settingsManager.setLightColorMode(mode)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView', `Failed to set light color mode: ${JSON.stringify(error)}`)
      this.lightColorMode = previous
    }
  }

  private buildPreviewFloatingStyle(): HdsTabsFloatingStyle {
    const opts = new CompactTabsFloatingStyleOptions()
    opts.materialType = this.materialType
    opts.materialLevel = this.materialLevel
    opts.lightColorMode = this.lightColorMode
    opts.themePrimary = this.themePrimary
    opts.barSideMargin = 10
    opts.barBottomMargin = 8
    opts.barWidth = { smallWidth: 200, mediumWidth: 220, largeWidth: 240 }
    return buildCompactTabsFloatingStyle(opts)
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
    .backgroundColor(this.themeSurface)
    .borderRadius(24)
    .border({ width: 1, color: $r('app.color.divider') })
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  private MaterialTypeRadioRow(type: number, title: Resource) {
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

      Radio({ value: `${type}`, group: 'materialType' })
        .checked(this.materialType === type)
        .radioStyle({
          checkedBackgroundColor: this.themePrimary,
          indicatorColor: Color.White
        })
        .onChange((isChecked: boolean) => {
          if (isChecked && this.materialType !== type) {
            this.handleMaterialTypeSelected(type)
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (this.materialType !== type) {
        this.handleMaterialTypeSelected(type)
      }
    })
  }

  @Builder
  private MaterialLevelRadioRow(level: number, title: Resource) {
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

      Radio({ value: `${level}`, group: 'materialLevel' })
        .checked(this.materialLevel === level)
        .radioStyle({
          checkedBackgroundColor: this.themePrimary,
          indicatorColor: Color.White
        })
        .onChange((isChecked: boolean) => {
          if (isChecked && this.materialLevel !== level) {
            this.handleMaterialLevelSelected(level)
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (this.materialLevel !== level) {
        this.handleMaterialLevelSelected(level)
      }
    })
  }

  @Builder
  private LightColorModeRadioRow(mode: string, title: Resource) {
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

      Radio({ value: mode, group: 'lightColorMode' })
        .checked(this.lightColorMode === mode)
        .radioStyle({
          checkedBackgroundColor: this.themePrimary,
          indicatorColor: Color.White
        })
        .onChange((isChecked: boolean) => {
          if (isChecked && this.lightColorMode !== mode) {
            this.handleLightColorModeSelected(mode)
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (this.lightColorMode !== mode) {
        this.handleLightColorModeSelected(mode)
      }
    })
  }

  @Builder
  private ThemeCard(theme: ThemeInfo) {
    Column() {
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
      .width('100%')
      .padding(10)
      .backgroundColor(this.themeSurface)
      .borderRadius(20)
    }
    .padding(2)
    .backgroundColor(this.currentColorTheme === theme.id ? this.themePrimary : this.themeSurface)
    .borderRadius(22)
    .border({ width: 1, color: $r('app.color.divider') })
    .clip(true)
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
  private MiniTabBarAssistants() {
    IndexBottomTabItem({
      active: this.previewTabIndex === PREVIEW_TAB_INDEX_ASSISTANTS,
      activeIcon: $r('sys.symbol.person_fill'),
      inactiveIcon: $r('sys.symbol.person'),
      label: $r('app.string.tab_assistants')
    })
  }

  @Builder
  private MiniTabBarChat() {
    IndexBottomTabItem({
      active: this.previewTabIndex === PREVIEW_TAB_INDEX_CHAT,
      activeIcon: $r('sys.symbol.ellipsis_message_fill'),
      inactiveIcon: $r('sys.symbol.ellipsis_message'),
      label: $r('app.string.tab_chat')
    })
  }

  @Builder
  private MiniTabBarSettings() {
    IndexBottomTabItem({
      active: this.previewTabIndex === PREVIEW_TAB_INDEX_SETTINGS,
      activeIcon: $r('sys.symbol.gearshape_fill'),
      inactiveIcon: $r('sys.symbol.gearshape'),
      label: $r('app.string.tab_settings')
    })
  }

  @Builder
  private MiniHdsTabs() {
    Column() {
      HdsTabs({ barPosition: BarPosition.End, index: this.previewTabIndex }) {
        TabContent() {
          Column().width('100%').height('100%').backgroundColor(this.themeBackground)
        }
        .tabBar(this.MiniTabBarAssistants())

        TabContent() {
          Column().width('100%').height('100%').backgroundColor(this.themeBackground)
        }
        .tabBar(this.MiniTabBarChat())

        TabContent() {
          Column().width('100%').height('100%').backgroundColor(this.themeBackground)
        }
        .tabBar(this.MiniTabBarSettings())
      }
      .barOverlap(true)
      .barBackgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .barBackgroundColor(Color.Transparent)
      .barMode(BarMode.Fixed)
      .barFloatingStyle(this.buildPreviewFloatingStyle())
      .scrollable(false)
      .onChange((idx: number) => {
        if (this.previewTabIndex !== idx) {
          this.previewTabIndex = idx
        }
      })
    }
    .width('100%')
    .height(105)
    .borderRadius(18)
    .clip(true)
    .backgroundColor(this.themeBackground)
    .border({ width: 1, color: this.themeDivider })
  }

  @Builder
  private DualBubblePreview() {
    Column({ space: 12 }) {
      Row() {
        Column() {
          Text($r('app.string.font_preview_ai_message'))
            .fontSize(this.getAiPreviewFontSize())
            .lineHeight(this.getAiPreviewFontSize() + 7)
            .fontColor(this.themeTextPrimary)
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.themeAiBubble)
        .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 6, bottomRight: 18 })
        .border({ width: 1, color: this.themeDivider })
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
            .fontColor(this.themeUserBubbleText)
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.themeUserBubble)
        .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 6 })
        .constraintSize({ maxWidth: '76%' })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private LivePreviewSection() {
    Column({ space: 14 }) {
      this.SectionHeader($r('app.string.appearance_live_preview_title'),
        $r('app.string.appearance_live_preview_desc'))

      Column({ space: 10 }) {
        this.DualBubblePreview()
        this.MiniHdsTabs()
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.themeSurface)
      .borderRadius(24)
      .border({ width: 1, color: $r('app.color.divider') })
    }
    .width('100%')
  }

  @Builder
  private TopTabBarBuilder(label: Resource, index: number) {
    Column() {
      Text(label)
        .fontSize(15)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentTabIndex === index ? this.themePrimary : $r('app.color.text_secondary'))

      Column()
        .width(20)
        .height(2)
        .margin({ top: 6 })
        .borderRadius(1)
        .backgroundColor(this.currentTabIndex === index ? this.themePrimary : Color.Transparent)
    }
    .height(44)
    .padding({ left: 14, right: 14 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ThemeTabContent() {
    Scroll(this.themeScroller) {
      Row() {
        Column({ space: 22 }) {
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
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, top: 16, bottom: this.getScrollBottomPadding() })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private FontTabContent() {
    Scroll(this.fontScroller) {
      Row() {
        Column({ space: 22 }) {
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
          .backgroundColor(this.themeSurface)
          .borderRadius(24)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, top: 16, bottom: this.getScrollBottomPadding() })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private MaterialTabContent() {
    Scroll(this.materialScroller) {
      Row() {
        Column({ space: 22 }) {
          this.SectionHeader($r('app.string.material_effect_title'),
            $r('app.string.material_effect_desc'))

          Column() {
            this.MaterialTypeRadioRow(0, $r('app.string.material_type_none'))
            Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
            this.MaterialTypeRadioRow(100, $r('app.string.material_type_adaptive'))
            Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
            this.MaterialTypeRadioRow(101, $r('app.string.material_type_immersive'))
          }
          .width('100%')
          .backgroundColor(this.themeSurface)
          .borderRadius(24)
          .border({ width: 1, color: $r('app.color.divider') })
          .padding({ top: 6, bottom: 6 })

          this.SectionHeader($r('app.string.material_level_title'),
            $r('app.string.material_level_desc'))

          Column() {
            this.MaterialLevelRadioRow(0, $r('app.string.material_level_exquisite'))
            Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
            this.MaterialLevelRadioRow(1, $r('app.string.material_level_gentle'))
            Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
            this.MaterialLevelRadioRow(2, $r('app.string.material_level_smooth'))
            Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
            this.MaterialLevelRadioRow(10, $r('app.string.material_level_adaptive'))
          }
          .width('100%')
          .backgroundColor(this.themeSurface)
          .borderRadius(24)
          .border({ width: 1, color: $r('app.color.divider') })
          .padding({ top: 6, bottom: 6 })

          this.SectionHeader($r('app.string.light_color_mode_title'),
            $r('app.string.light_color_mode_desc'))

          Column() {
            this.LightColorModeRadioRow('default', $r('app.string.light_color_mode_default'))
            Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
            this.LightColorModeRadioRow('theme', $r('app.string.light_color_mode_theme'))
          }
          .width('100%')
          .backgroundColor(this.themeSurface)
          .borderRadius(24)
          .border({ width: 1, color: $r('app.color.divider') })
          .padding({ top: 6, bottom: 6 })
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, top: 16, bottom: this.getScrollBottomPadding() })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private PageBody() {
    Column({ space: 12 }) {
      Row() {
        Column() {
          this.LivePreviewSection()
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, top: 8 })

      HdsTabs({ barPosition: BarPosition.Start, index: this.currentTabIndex }) {
        TabContent() {
          this.ThemeTabContent()
        }
        .tabBar(this.TopTabBarBuilder($r('app.string.appearance_tab_theme'), TAB_INDEX_THEME))

        TabContent() {
          this.FontTabContent()
        }
        .tabBar(this.TopTabBarBuilder($r('app.string.appearance_tab_font'), TAB_INDEX_FONT))

        TabContent() {
          this.MaterialTabContent()
        }
        .tabBar(this.TopTabBarBuilder($r('app.string.appearance_tab_material'), TAB_INDEX_MATERIAL))
      }
      .barMode(BarMode.Fixed)
      .barHeight(48)
      .scrollable(true)
      .layoutWeight(1)
      .animationDuration(280)
      .onChange((idx: number) => {
        if (this.currentTabIndex !== idx) {
          animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
            this.currentTabIndex = idx
          })
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private CompactBody() {
    Column() {
      Blank()
        .width('100%')
        .height(this.getCompactContentTopPadding())

      this.PageBody()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: this.compactTitle,
      onBack: this.onCompactBack
    })
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
    .backgroundColor(this.themeBackground)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        Column() {
          this.DetailPaneHeader()
          this.PageBody()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsNavigation() {
          this.CompactBody()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .titleMode(HdsNavigationTitleMode.MINI)
        .hideBackButton(true)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }
}

@Entry
@ComponentV2
struct ThemeModeSettingsPage {
  private handleBack(): void {
    if (themeModeSettingsPathStack !== null && themeModeSettingsPathStack.size() > 0) {
      themeModeSettingsPathStack.pop()
    }
  }

  build() {
    Column() {
      ThemeAppearanceSettingsView({
        compactTitle: $r('app.string.settings_appearance'),
        onCompactBack: () => {
          this.handleBack()
        }
      })
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
  .onReady((context: NavDestinationContext) => {
    themeModeSettingsPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (themeModeSettingsPathStack !== null && themeModeSettingsPathStack.size() > 0) {
      themeModeSettingsPathStack.pop()
    }
    return true
  })
}
