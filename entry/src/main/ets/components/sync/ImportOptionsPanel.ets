/**
 * 共享导入选项面板
 * 在 ImportDataPage / WebDAVSyncPage 之间复用,
 * 承载 importProviders / importPreferences 开关与 conflictStrategy 单选。
 * 冲突策略仅在父级提供 hasConflicts=true 时显示。
 */

import { getAppUiState } from '../../state/AppUiState'

export type ImportConflictStrategy = 'skip' | 'overwrite' | 'ask'

@ComponentV2
export struct ImportOptionsPanel {
  @Param importProviders: boolean = true
  @Param importPreferences: boolean = true
  @Param conflictStrategy: ImportConflictStrategy = 'skip'
  @Param hasConflicts: boolean = false
  // 父组件用于隔离不同实例的 Radio 分组,默认即可
  @Param radioGroup: string = 'conflictStrategy'
  @Event onImportProvidersChange: (value: boolean) => void = () => {}
  @Event onImportPreferencesChange: (value: boolean) => void = () => {}
  @Event onConflictStrategyChange: (value: ImportConflictStrategy) => void = () => {}

  build() {
    Column() {
      if (this.hasConflicts) {
        this.SectionTitle($r('app.string.import_conflict_strategy'))
        Column() {
          this.RadioRow(
            $r('app.string.import_strategy_skip'),
            'skip',
            this.conflictStrategy === 'skip',
            () => { this.onConflictStrategyChange('skip') }
          )
          Divider().color($r('app.color.divider'))
          this.RadioRow(
            $r('app.string.import_strategy_overwrite'),
            'overwrite',
            this.conflictStrategy === 'overwrite',
            () => { this.onConflictStrategyChange('overwrite') }
          )
          Divider().color($r('app.color.divider'))
          this.RadioRow(
            $r('app.string.import_strategy_ask'),
            'ask',
            this.conflictStrategy === 'ask',
            () => { this.onConflictStrategyChange('ask') }
          )
        }
        .width('100%')
        .backgroundColor(getAppUiState().themeSurface)
        .borderRadius(16)
        .margin({ bottom: 24 })
      }

      this.SectionTitle($r('app.string.import_options'))
      Column() {
        this.OptionRow(
          $r('app.string.import_providers'),
          this.importProviders,
          (value: boolean) => { this.onImportProvidersChange(value) }
        )
        Divider().color($r('app.color.divider'))
        this.OptionRow(
          $r('app.string.import_preferences'),
          this.importPreferences,
          (value: boolean) => { this.onImportPreferencesChange(value) }
        )
      }
      .width('100%')
      .backgroundColor(getAppUiState().themeSurface)
      .borderRadius(16)
    }
    .width('100%')
  }

  @Builder
  SectionTitle(title: Resource) {
    Text(title)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .fontWeight(FontWeight.Medium)
      .margin({ top: 24, bottom: 12, left: 4 })
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

  @Builder
  RadioRow(
    title: Resource,
    value: string,
    checked: boolean,
    onChange: () => void
  ) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Radio({ value: value, group: this.radioGroup })
        .checked(checked)
        .onChange(onChange)
    }
    .width('100%')
    .padding(16)
    .onClick(onChange)
  }
}
