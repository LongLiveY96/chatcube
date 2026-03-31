import { bundleManager } from '@kit.AbilityKit'
import { SettingsRouteName } from '../../config/SettingsRouteName'
import { getAppUiState } from '../../state/AppUiState'

class SettingsListItemModel {
  key: string = ''
  icon: Resource = $r('sys.symbol.square_stack_3d')
  title: ResourceStr = ''
  subtitle: ResourceStr = ''
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
  @Event onOpenLanguage: () => void = () => {}
  @Event onOpenNotification: () => void = () => {}
  @Event onOpenExportData: () => void = () => {}
  @Event onOpenImportData: () => void = () => {}
  @Event onOpenAbout: () => void = () => {}
  @Event onOpenSupportDevelopment: () => void = () => {}
  @Event onOpenPrivacy: () => void = () => {}

  aboutToAppear(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      this.versionName = info.versionName
    } catch (err) {
      console.error('IndexSettingsPanel', `Get version failed: ${JSON.stringify(err)}`)
      this.versionName = '1.0.11'
    }
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
            action: (): void => { this.onOpenHandAdaptive() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.LANGUAGE,
            icon: $r('sys.symbol.globe_badge_message'),
            title: $r('app.string.settings_language'),
            action: (): void => { this.onOpenLanguage() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.NOTIFICATION,
            icon: $r('sys.symbol.bell_badge_gearshape'),
            title: $r('app.string.settings_notifications'),
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
            key: SettingsRouteName.PRIVACY_POLICY,
            icon: $r('sys.symbol.doc_text'),
            title: $r('app.string.settings_privacy_policy'),
            action: (): void => { this.onOpenPrivacy() }
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
    if (this.hasSubtitle(item)) {
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

  private hasSubtitle(item: SettingsListItemModel): boolean {
    return item.subtitle !== undefined && item.subtitle !== ''
  }

  private hasRowAction(item: SettingsListItemModel): boolean {
    return item.action !== null && item.action !== undefined
  }

  @Builder
  private SettingsItemRow(item: SettingsListItemModel, isLast: boolean) {
    Column() {
      Row({ space: 12 }) {
        this.PrefixIcon(item.icon)
        this.ItemText(item)
        if (this.hasRowAction(item)) {
          this.ChevronSuffix()
        }
      }
      .width('100%')
      .padding({
        left: this.sidebarMode ? 18 : 16,
        right: 12,
        top: this.hasSubtitle(item) ? (this.sidebarMode ? 13 : 14) : (this.sidebarMode ? 15 : 16),
        bottom: this.hasSubtitle(item) ? (this.sidebarMode ? 13 : 14) : (this.sidebarMode ? 15 : 16)
      })
      .backgroundColor(this.isSelectedItem(item) ? this.themePrimaryLight : Color.Transparent)
      .borderRadius(this.sidebarMode ? 16 : 14)
      .onClick(() => {
        const rowAction = item.action
        if (rowAction !== null && rowAction !== undefined) {
          rowAction()
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

