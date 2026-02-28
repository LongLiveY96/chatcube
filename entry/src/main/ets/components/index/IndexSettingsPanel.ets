import { ThemeMode, AppLanguage } from '../../services/PreferencesService'
import { ColorTheme } from '../../models/ThemeColors'
import { HdsListItemCard, PrefixCustomBuilder, SuffixCustomBuilder } from '@kit.UIDesignKit'
import { bundleManager } from '@kit.AbilityKit'

class SettingsRowParams {
  icon: Resource = $r('app.string.settings_version')
  title: ResourceStr = ''
  subtitle: ResourceStr = ''
  action: () => void = () => {}
}

class SettingsRowNoSubtitleParams {
  icon: Resource = $r('app.string.settings_version')
  title: ResourceStr = ''
  action: () => void = () => {}
}

@Component
export struct IndexSettingsPanel {
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_primary_light') themePrimaryLight: string = '#E6F2FF'
  @Link @Watch('onSummaryLinkChanged') currentThemeMode: ThemeMode
  @Link @Watch('onSummaryLinkChanged') currentLanguage: AppLanguage
  @Link @Watch('onSummaryLinkChanged') currentColorTheme: ColorTheme
  @Link @Watch('onSummaryLinkChanged') handAdaptiveEnabled: boolean
  @Link @Watch('onSummaryLinkChanged') handAdaptiveNewChat: boolean
  @Link @Watch('onSummaryLinkChanged') handAdaptiveUnsupported: boolean
  @Link @Watch('onSummaryLinkChanged') notifyEnabled: boolean
  @Link @Watch('onSummaryLinkChanged') notifyOnComplete: boolean
  @Link @Watch('onSummaryLinkChanged') notifyOnFailed: boolean
  @State themeModeSummary: string = ''
  @State languageSummary: string = ''
  @State colorThemeSummary: string = ''
  @State handAdaptiveSummary: string = ''
  @State notifySummary: string = ''
  @State versionName: string = ''
  onOpenModelManage: () => void = () => {}
  onOpenDefaultModel: () => void = () => {}
  onOpenToolsCenter: () => void = () => {}
  onOpenSystemPrompt: () => void = () => {}
  onOpenHandAdaptive: () => void = () => {}
  onOpenTheme: () => void = () => {}
  onOpenColorTheme: () => void = () => {}
  onOpenLanguage: () => void = () => {}
  onOpenNotification: () => void = () => {}
  onOpenExportData: () => void = () => {}
  onOpenImportData: () => void = () => {}
  onOpenAbout: () => void = () => {}
  onOpenPrivacy: () => void = () => {}

  aboutToAppear(): void {
    this.refreshSummaryStates()
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      this.versionName = info.versionName
    } catch (err) {
      console.error('IndexSettingsPanel', `Get version failed: ${JSON.stringify(err)}`)
      this.versionName = '1.0.0'
    }
  }

  private resourceToString(resource: Resource): string {
    const hostContext = this.getUIContext().getHostContext()
    if (hostContext === undefined || hostContext === null) {
      return ''
    }
    try {
      return hostContext.resourceManager.getStringSync(resource.id)
    } catch (error) {
      console.error('IndexSettingsPanel', `Failed to resolve resource string: ${JSON.stringify(error)}`)
      return ''
    }
  }

  private refreshSummaryStates(): void {
    this.themeModeSummary = this.resourceToString(this.getThemeModeText(this.currentThemeMode))
    this.languageSummary = this.resourceToString(this.getLanguageText(this.currentLanguage))
    this.colorThemeSummary = this.resourceToString(this.getColorThemeText(this.currentColorTheme))
    this.handAdaptiveSummary = this.resourceToString(this.getHandAdaptiveSummaryText(this.handAdaptiveEnabled,
      this.handAdaptiveUnsupported, this.handAdaptiveNewChat))
    this.notifySummary = this.resourceToString(
      this.getNotificationSummaryText(this.notifyEnabled, this.notifyOnComplete, this.notifyOnFailed))
    console.info('IndexSettingsPanel', `Summary text states: theme=${this.themeModeSummary},` +
      ` language=${this.languageSummary}, color=${this.colorThemeSummary}, hand=${this.handAdaptiveSummary},` +
      ` notify=${this.notifySummary}`)
  }

  private onSummaryLinkChanged(): void {
    this.refreshSummaryStates()
    console.info('IndexSettingsPanel',
      `Summary link changed: theme=${this.currentThemeMode}, language=${this.currentLanguage},` +
      ` colorTheme=${this.currentColorTheme}, hand=${this.handAdaptiveEnabled}/${this.handAdaptiveNewChat}/` +
      `${this.handAdaptiveUnsupported}, notify=${this.notifyEnabled}/${this.notifyOnComplete}/${this.notifyOnFailed}`)
  }

  @Builder
  private SettingsSectionTitle(title: Resource) {
    Text(title)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 16, top: 16, bottom: 6 })
      .width('100%')
  }

  @Builder
  private PrefixIcon(icon: Resource) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([this.themePrimary])
    }
    .width(36)
    .height(36)
    .borderRadius(9)
    .backgroundColor(this.themePrimaryLight)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private SettingsRowText(title: ResourceStr, subtitle: ResourceStr) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(subtitle)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
    }.alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SettingsRowTitleOnly(title: ResourceStr) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private ChevronSuffix() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(18)
      .fontColor([$r('app.color.text_tertiary')])
  }

  @Builder
  private SettingsRow(params: SettingsRowParams) {
    HdsListItemCard({
      prefixItem: new PrefixCustomBuilder((): void => { this.PrefixIcon(params.icon) }),
      textItem: {
        customBuilder: (): void => { this.SettingsRowText(params.title, params.subtitle) }
      },
      suffixItem: new SuffixCustomBuilder((): void => { this.ChevronSuffix() }),
      cardBackgroundColor: $r('app.color.surface'),
      cardBorderRadius: 12,
      onClick: (): void => { params.action() }
    })
  }

  @Builder
  private SettingsRowNoSubtitle(params: SettingsRowNoSubtitleParams) {
    HdsListItemCard({
      prefixItem: new PrefixCustomBuilder((): void => { this.PrefixIcon(params.icon) }),
      textItem: {
        customBuilder: (): void => { this.SettingsRowTitleOnly(params.title) }
      },
      suffixItem: new SuffixCustomBuilder((): void => { this.ChevronSuffix() }),
      cardBackgroundColor: $r('app.color.surface'),
      cardBorderRadius: 12,
      onClick: (): void => { params.action() }
    })
  }

  private getThemeModeText(mode: ThemeMode): Resource {
    if (mode === ThemeMode.LIGHT) {
      return $r('app.string.theme_light')
    }
    if (mode === ThemeMode.DARK) {
      return $r('app.string.theme_dark')
    }
    return $r('app.string.theme_system')
  }

  private getLanguageText(language: AppLanguage): Resource {
    if (language === AppLanguage.ZH_CN) {
      return $r('app.string.language_zh_cn')
    }
    if (language === AppLanguage.EN_US) {
      return $r('app.string.language_en_us')
    }
    return $r('app.string.language_system')
  }

  private getColorThemeText(theme: ColorTheme): Resource {
    if (theme === ColorTheme.YUANBAO) {
      return $r('app.string.theme_color_yuanbao')
    }
    if (theme === ColorTheme.CLAUDE) {
      return $r('app.string.theme_color_claude')
    }
    if (theme === ColorTheme.CHATGPT) {
      return $r('app.string.theme_color_chatgpt')
    }
    if (theme === ColorTheme.VIOLET) {
      return $r('app.string.theme_color_violet')
    }
    if (theme === ColorTheme.MINT) {
      return $r('app.string.theme_color_mint')
    }
    if (theme === ColorTheme.SUNSET) {
      return $r('app.string.theme_color_sunset')
    }
    return $r('app.string.theme_color_default')
  }

  private getHandAdaptiveSummaryText(enabled: boolean, unsupported: boolean, newChat: boolean): Resource {
    if (!enabled) {
      return $r('app.string.hand_adaptive_disabled')
    }
    if (unsupported) {
      return $r('app.string.hand_adaptive_unsupported')
    }
    if (newChat) {
      return $r('app.string.hand_adaptive_summary_new_chat')
    }
    return $r('app.string.hand_adaptive_summary_none')
  }

  private getNotificationSummaryText(enabled: boolean, onComplete: boolean, onFailed: boolean): Resource {
    if (!enabled) {
      return $r('app.string.notification_disabled')
    }
    if (onComplete && onFailed) {
      return $r('app.string.notification_summary_all')
    }
    if (onComplete) {
      return $r('app.string.notification_summary_complete')
    }
    if (onFailed) {
      return $r('app.string.notification_summary_failed')
    }
    return $r('app.string.notification_summary_none')
  }

  @Builder
  private HandAdaptiveText() {
    Column() {
      Text($r('app.string.settings_hand_adaptive'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.handAdaptiveSummary)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
    }.alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ThemeModeText() {
    Row() {
      Text($r('app.string.settings_dark_mode'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.themeModeSummary)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ right: 4 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%')
  }

  @Builder
  private ColorThemeText() {
    Row() {
      Text($r('app.string.settings_color_theme'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.colorThemeSummary)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ right: 4 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%')
  }

  @Builder
  private LanguageText() {
    Row() {
      Text($r('app.string.settings_language'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.languageSummary)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ right: 4 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%')
  }

  @Builder
  private NotificationText() {
    Column() {
      Text($r('app.string.settings_notifications'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.notifySummary)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
    }.alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column() {
        this.SettingsSectionTitle($r('app.string.settings_model_config'))

        Column() {
          this.SettingsRow({
            icon: $r('sys.symbol.square_stack_3d'),
            title: $r('app.string.settings_model_manage'),
            subtitle: $r('app.string.settings_model_manage_desc'),
            action: () => { this.onOpenModelManage() }
          } as SettingsRowParams)
          Divider().color($r('app.color.divider')).margin({ left: 60 })
          this.SettingsRow({
            icon: $r('sys.symbol.wand_and_stars'),
            title: $r('app.string.settings_default_model'),
            subtitle: $r('app.string.settings_default_model_desc'),
            action: () => { this.onOpenDefaultModel() }
          } as SettingsRowParams)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)

        this.SettingsSectionTitle($r('app.string.settings_app_settings'))

        Column() {
          this.SettingsRow({
            icon: $r('sys.symbol.puzzle'),
            title: $r('app.string.settings_tools_center'),
            subtitle: $r('app.string.settings_tools_center_desc'),
            action: () => { this.onOpenToolsCenter() }
          } as SettingsRowParams)

          Divider().color($r('app.color.divider')).margin({ left: 60 })

          this.SettingsRow({
            icon: $r('sys.symbol.message'),
            title: $r('app.string.settings_system_prompt'),
            subtitle: $r('app.string.settings_system_prompt_desc'),
            action: () => { this.onOpenSystemPrompt() }
          } as SettingsRowParams)

          Divider().color($r('app.color.divider')).margin({ left: 60 })

          // 智感握姿 - HdsListItemCard（动态摘要）
          HdsListItemCard({
            prefixItem: new PrefixCustomBuilder((): void => { this.PrefixIcon($r('sys.symbol.person')) }),
            textItem: {
              customBuilder: (): void => { this.HandAdaptiveText() }
            },
            suffixItem: new SuffixCustomBuilder((): void => { this.ChevronSuffix() }),
            cardBackgroundColor: $r('app.color.surface'),
            cardBorderRadius: 12,
            onClick: (): void => { this.onOpenHandAdaptive() }
          })

          Divider().color($r('app.color.divider')).margin({ left: 60 })

          // 主题 - HdsListItemCard（动态摘要）
          HdsListItemCard({
            prefixItem: new PrefixCustomBuilder((): void => { this.PrefixIcon($r('sys.symbol.moon_and_message_fill')) }),
            textItem: {
              customBuilder: (): void => { this.ThemeModeText() }
            },
            suffixItem: new SuffixCustomBuilder((): void => { this.ChevronSuffix() }),
            cardBackgroundColor: $r('app.color.surface'),
            cardBorderRadius: 12,
            onClick: (): void => { this.onOpenTheme() }
          })

          Divider().color($r('app.color.divider')).margin({ left: 60 })

          // 主题配色 - HdsListItemCard（动态摘要）
          HdsListItemCard({
            prefixItem: new PrefixCustomBuilder((): void => { this.PrefixIcon($r('sys.symbol.paintpalette')) }),
            textItem: {
              customBuilder: (): void => { this.ColorThemeText() }
            },
            suffixItem: new SuffixCustomBuilder((): void => { this.ChevronSuffix() }),
            cardBackgroundColor: $r('app.color.surface'),
            cardBorderRadius: 12,
            onClick: (): void => { this.onOpenColorTheme() }
          })

          Divider().color($r('app.color.divider')).margin({ left: 60 })

          // 语言 - HdsListItemCard（动态摘要）
          HdsListItemCard({
            prefixItem: new PrefixCustomBuilder((): void => { this.PrefixIcon($r('sys.symbol.globe_badge_message')) }),
            textItem: {
              customBuilder: (): void => { this.LanguageText() }
            },
            suffixItem: new SuffixCustomBuilder((): void => { this.ChevronSuffix() }),
            cardBackgroundColor: $r('app.color.surface'),
            cardBorderRadius: 12,
            onClick: (): void => { this.onOpenLanguage() }
          })

          Divider().color($r('app.color.divider')).margin({ left: 60 })

          // 通知 - HdsListItemCard（动态摘要）
          HdsListItemCard({
            prefixItem: new PrefixCustomBuilder((): void => { this.PrefixIcon($r('sys.symbol.bell_badge_gearshape')) }),
            textItem: {
              customBuilder: (): void => { this.NotificationText() }
            },
            suffixItem: new SuffixCustomBuilder((): void => { this.ChevronSuffix() }),
            cardBackgroundColor: $r('app.color.surface'),
            cardBorderRadius: 12,
            onClick: (): void => { this.onOpenNotification() }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)

        this.SettingsSectionTitle($r('app.string.settings_data_management'))

        Column() {
          this.SettingsRow({
            icon: $r('sys.symbol.arrow_up_and_rectangle_on_rectangle'),
            title: $r('app.string.settings_export_data'),
            subtitle: $r('app.string.settings_export_data_desc'),
            action: () => { this.onOpenExportData() }
          } as SettingsRowParams)
          Divider().color($r('app.color.divider')).margin({ left: 60 })
          this.SettingsRow({
            icon: $r('sys.symbol.arrow_down_and_rectangle_on_rectangle'),
            title: $r('app.string.settings_import_data'),
            subtitle: $r('app.string.settings_import_data_desc'),
            action: () => { this.onOpenImportData() }
          } as SettingsRowParams)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)

        this.SettingsSectionTitle($r('app.string.settings_about'))

        Column() {
          this.SettingsRow({
            icon: $r('sys.symbol.exclamationmark_message'),
            title: $r('app.string.settings_about_chatcube'),
            subtitle: `v${this.versionName}`,
            action: () => { this.onOpenAbout() }
          } as SettingsRowParams)
          Divider().color($r('app.color.divider')).margin({ left: 60 })
          this.SettingsRowNoSubtitle({
            icon: $r('sys.symbol.doc_text'),
            title: $r('app.string.settings_privacy_policy'),
            action: () => { this.onOpenPrivacy() }
          } as SettingsRowNoSubtitleParams)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 40 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }
}
