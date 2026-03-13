import { ThemeMode, AppLanguage } from '../../services/PreferencesService'
import { ColorTheme } from '../../models/ThemeColors'
import { bundleManager } from '@kit.AbilityKit'
import { SettingsRouteName } from '../../config/SettingsRouteName'
import { getAppUiState } from '../../state/AppUiState'

class SettingsListItemModel {
  key: string = ''
  icon: Resource = $r('sys.symbol.square_stack_3d')
  title: ResourceStr = ''
  subtitle: ResourceStr = ''
  trailing: ResourceStr = ''
  action: (() => void) | null = null
}

class SettingsGroupModel {
  key: string = ''
  title: Resource = $r('app.string.settings_app_settings')
  items: SettingsListItemModel[] = []
}

@ComponentV2
export struct IndexSettingsPanel {
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  @Param currentThemeMode: ThemeMode = ThemeMode.SYSTEM
  @Event $currentThemeMode: (value: ThemeMode) => void = () => {}
  @Param currentLanguage: AppLanguage = AppLanguage.SYSTEM
  @Event $currentLanguage: (value: AppLanguage) => void = () => {}
  @Param currentColorTheme: ColorTheme = ColorTheme.DEFAULT
  @Event $currentColorTheme: (value: ColorTheme) => void = () => {}
  @Param handAdaptiveEnabled: boolean = false
  @Event $handAdaptiveEnabled: (value: boolean) => void = () => {}
  @Param handAdaptiveNewChat: boolean = false
  @Event $handAdaptiveNewChat: (value: boolean) => void = () => {}
  @Param handAdaptiveUnsupported: boolean = false
  @Event $handAdaptiveUnsupported: (value: boolean) => void = () => {}
  @Param notifyEnabled: boolean = false
  @Event $notifyEnabled: (value: boolean) => void = () => {}
  @Param notifyOnComplete: boolean = false
  @Event $notifyOnComplete: (value: boolean) => void = () => {}
  @Param notifyOnFailed: boolean = false
  @Event $notifyOnFailed: (value: boolean) => void = () => {}
  @Param chatFontSize: number = 15
  @Local themeModeSummary: string = ''
  @Local languageSummary: string = ''
  @Local colorThemeSummary: string = ''
  @Local handAdaptiveSummary: string = ''
  @Local notifySummary: string = ''
  @Local fontSizeSummary: string = ''
  @Local versionName: string = ''

  @Param sidebarMode: boolean = false
  @Param selectedRouteName: string = ''
  @Param highlightSelection: boolean = false
  @Event onOpenModelManage: () => void = () => {}
  @Event onOpenDefaultModel: () => void = () => {}
  @Event onOpenToolsCenter: () => void = () => {}
  @Event onOpenSystemPrompt: () => void = () => {}
  @Event onOpenHandAdaptive: () => void = () => {}
  @Event onOpenTheme: () => void = () => {}
  @Event onOpenColorTheme: () => void = () => {}
  @Event onOpenLanguage: () => void = () => {}
  @Event onOpenNotification: () => void = () => {}
  @Event onOpenFontSize: () => void = () => {}
  @Event onOpenExportData: () => void = () => {}
  @Event onOpenImportData: () => void = () => {}
  @Event onOpenAbout: () => void = () => {}
  @Event onOpenSupportDevelopment: () => void = () => {}
  @Event onOpenPrivacy: () => void = () => {}

  aboutToAppear(): void {
    this.refreshSummaryStates()
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      this.versionName = info.versionName
    } catch (err) {
      console.error('IndexSettingsPanel', `Get version failed: ${JSON.stringify(err)}`)
      this.versionName = '1.0.8'
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
    this.fontSizeSummary = this.resourceToString(this.getFontSizeSummaryText(this.chatFontSize))
  }

  @Monitor('currentThemeMode', 'currentLanguage', 'currentColorTheme', 'handAdaptiveEnabled', 'handAdaptiveNewChat', 'handAdaptiveUnsupported', 'notifyEnabled', 'notifyOnComplete', 'notifyOnFailed', 'chatFontSize')
  onSummaryLinkChanged(): void {
    this.refreshSummaryStates()
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

  private getFontSizeSummaryText(fontSize: number): Resource {
    if (fontSize <= 13) {
      return $r('app.string.font_size_small')
    }
    if (fontSize <= 15) {
      return $r('app.string.font_size_default')
    }
    if (fontSize <= 17) {
      return $r('app.string.font_size_large')
    }
    return $r('app.string.font_size_extra_large')
  }

  private isSelectedItem(item: SettingsListItemModel): boolean {
    if (!this.highlightSelection || item.key === '') {
      return false
    }
    return item.key === this.selectedRouteName
  }

  private buildGroups(): SettingsGroupModel[] {
    return [
      {
        key: 'model',
        title: $r('app.string.settings_model_config'),
        items: [
          {
            key: SettingsRouteName.MODEL_MANAGE,
            icon: $r('sys.symbol.square_stack_3d'),
            title: $r('app.string.settings_model_manage'),
            subtitle: $r('app.string.settings_model_manage_desc'),
            action: (): void => { this.onOpenModelManage() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.DEFAULT_MODEL,
            icon: $r('sys.symbol.wand_and_stars'),
            title: $r('app.string.settings_default_model'),
            subtitle: $r('app.string.settings_default_model_desc'),
            action: (): void => { this.onOpenDefaultModel() }
          } as SettingsListItemModel
        ]
      } as SettingsGroupModel,
      {
        key: 'app',
        title: $r('app.string.settings_app_settings'),
        items: [
          {
            key: SettingsRouteName.THEME_MODE,
            icon: $r('sys.symbol.moon_and_message_fill'),
            title: $r('app.string.settings_appearance'),
            subtitle: $r('app.string.settings_appearance_desc'),
            action: (): void => { this.onOpenTheme() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.TOOLS_CENTER,
            icon: $r('sys.symbol.puzzle'),
            title: $r('app.string.settings_tools_center'),
            subtitle: $r('app.string.settings_tools_center_desc'),
            action: (): void => { this.onOpenToolsCenter() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.SYSTEM_PROMPT,
            icon: $r('sys.symbol.message'),
            title: $r('app.string.settings_system_prompt'),
            subtitle: $r('app.string.settings_system_prompt_desc'),
            action: (): void => { this.onOpenSystemPrompt() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.HAND_ADAPTIVE,
            icon: $r('sys.symbol.person'),
            title: $r('app.string.settings_hand_adaptive'),
            trailing: this.handAdaptiveSummary,
            action: (): void => { this.onOpenHandAdaptive() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.LANGUAGE,
            icon: $r('sys.symbol.globe_badge_message'),
            title: $r('app.string.settings_language'),
            trailing: this.languageSummary,
            action: (): void => { this.onOpenLanguage() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.NOTIFICATION,
            icon: $r('sys.symbol.bell_badge_gearshape'),
            title: $r('app.string.settings_notifications'),
            trailing: this.notifySummary,
            action: (): void => { this.onOpenNotification() }
          } as SettingsListItemModel
        ]
      } as SettingsGroupModel,
      {
        key: 'data',
        title: $r('app.string.settings_data_management'),
        items: [
          {
            key: SettingsRouteName.EXPORT_DATA,
            icon: $r('sys.symbol.arrow_up_and_rectangle_on_rectangle'),
            title: $r('app.string.settings_export_data'),
            subtitle: $r('app.string.settings_export_data_desc'),
            action: (): void => { this.onOpenExportData() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.IMPORT_DATA,
            icon: $r('sys.symbol.arrow_down_and_rectangle_on_rectangle'),
            title: $r('app.string.settings_import_data'),
            subtitle: $r('app.string.settings_import_data_desc'),
            action: (): void => { this.onOpenImportData() }
          } as SettingsListItemModel
        ]
      } as SettingsGroupModel,
      {
        key: 'about',
        title: $r('app.string.settings_about'),
        items: [
          {
            key: SettingsRouteName.ABOUT,
            icon: $r('sys.symbol.exclamationmark_message'),
            title: $r('app.string.settings_about_chatcube'),
            subtitle: `v${this.versionName}`,
            action: (): void => { this.onOpenAbout() }
          } as SettingsListItemModel,
          {
            key: 'privacy',
            icon: $r('sys.symbol.doc_text'),
            title: $r('app.string.settings_privacy_policy'),
            action: null
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.SUPPORT_DEVELOPMENT,
            icon: $r('sys.symbol.heart_fill'),
            title: $r('app.string.settings_support_development'),
            subtitle: $r('app.string.settings_support_development_desc'),
            action: (): void => { this.onOpenSupportDevelopment() }
          } as SettingsListItemModel
        ]
      } as SettingsGroupModel
    ]
  }

  @Builder
  private SectionTitle(title: Resource) {
    Text(title)
      .fontSize(this.sidebarMode ? 11 : 12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: this.sidebarMode ? 6 : 4, bottom: this.sidebarMode ? 8 : 6 })
      .width('100%')
  }

  @Builder
  private PrefixIcon(icon: Resource) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(this.sidebarMode ? 18 : 17)
        .fontColor([this.themePrimary])
    }
    .width(this.sidebarMode ? 32 : 30)
    .height(this.sidebarMode ? 32 : 30)
    .borderRadius(this.sidebarMode ? 11 : 10)
    .backgroundColor(this.themePrimaryLight)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ChevronSuffix() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(16)
      .fontColor([$r('app.color.text_tertiary')])
  }

  @Builder
  private ItemText(item: SettingsListItemModel) {
    if (item.subtitle !== '') {
      Column() {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.subtitle)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    } else {
      Text(item.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  private SettingsItemRow(item: SettingsListItemModel, isLast: boolean) {
    Column() {
      Row({ space: 12 }) {
        this.PrefixIcon(item.icon)
        this.ItemText(item)
        if (item.trailing !== '') {
          Text(item.trailing)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (item.action !== null) {
          this.ChevronSuffix()
        }
      }
      .width('100%')
      .padding({
        left: this.sidebarMode ? 18 : 16,
        right: 12,
        top: item.subtitle === '' ? (this.sidebarMode ? 15 : 16) : (this.sidebarMode ? 13 : 14),
        bottom: item.subtitle === '' ? (this.sidebarMode ? 15 : 16) : (this.sidebarMode ? 13 : 14)
      })
      .backgroundColor(this.isSelectedItem(item) ? this.themePrimaryLight : Color.Transparent)
      .borderRadius(this.sidebarMode ? 16 : 14)
      .onClick(() => {
        if (item.action !== null) {
          item.action()
        }
      })

      if (!isLast) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: this.sidebarMode ? 62 : 58, right: 12 })
      }
    }
  }

  @Builder
  private SettingsGroupCard(group: SettingsGroupModel) {
    Column() {
      ForEach(group.items, (item: SettingsListItemModel) => {
        this.SettingsItemRow(item, item.key === group.items[group.items.length - 1].key)
      }, (item: SettingsListItemModel) => item.key)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(this.sidebarMode ? 20 : 22)
    .clip(true)
    .border({
      width: 1,
      color: $r('app.color.divider')
    })
  }

  build() {
    Column({ space: this.sidebarMode ? 12 : 14 }) {
      ForEach(this.buildGroups(), (group: SettingsGroupModel) => {
        Column() {
          this.SectionTitle(group.title)
          this.SettingsGroupCard(group)
        }
        .width('100%')
      }, (group: SettingsGroupModel) => group.key)
    }
    .width('100%')
    .padding({
      left: this.sidebarMode ? 16 : 12,
      right: this.sidebarMode ? 16 : 12,
      top: this.sidebarMode ? 8 : 0,
      bottom: 28
    })
    .backgroundColor($r('app.color.background'))
  }
}

