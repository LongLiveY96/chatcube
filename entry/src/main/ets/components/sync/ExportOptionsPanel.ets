/**
 * 共享导出选项面板
 * 在 ExportDataPage / WebDAVSyncPage 之间复用,
 * 仅承载 includeAttachments / includeProviders / includePreferences 三个开关。
 */

import { getAppUiState } from '../../state/AppUiState'

@ComponentV2
export struct ExportOptionsPanel {
  @Param includeAttachments: boolean = true
  @Param includeProviders: boolean = true
  @Param includePreferences: boolean = true
  @Event onIncludeAttachmentsChange: (value: boolean) => void = () => {}
  @Event onIncludeProvidersChange: (value: boolean) => void = () => {}
  @Event onIncludePreferencesChange: (value: boolean) => void = () => {}

  build() {
    Column() {
      this.OptionRow(
        $r('app.string.export_include_attachments'),
        this.includeAttachments,
        (value: boolean) => { this.onIncludeAttachmentsChange(value) }
      )
      Divider().color($r('app.color.divider'))
      this.OptionRow(
        $r('app.string.export_include_providers'),
        this.includeProviders,
        (value: boolean) => { this.onIncludeProvidersChange(value) }
      )
      Divider().color($r('app.color.divider'))
      this.OptionRow(
        $r('app.string.export_include_preferences'),
        this.includePreferences,
        (value: boolean) => { this.onIncludePreferencesChange(value) }
      )
    }
    .width('100%')
    .backgroundColor(getAppUiState().themeSurface)
    .borderRadius(16)
  }

  @Builder
  OptionRow(
    title: Resource,
    checked: boolean,
    onChange: (value: boolean) => void
  ) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .onChange(onChange)
    }
    .width('100%')
    .padding(16)
  }
}
