import { ToolConfig, SearchEngine } from '../models/ChatModels'
import { ToolRegistry } from '../services/ToolRegistry'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { registerBuiltinTools } from '../config/BuiltinTools'
import { getPreferencesService, PreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { HdsListItemCard, SuffixCustomBuilder } from '@kit.UIDesignKit'

@Component
export struct ToolsCenterPanel {
  @Prop showHeader: boolean = true
  @State builtinTools: ToolConfig[] = []
  @State searchEngine: SearchEngine = SearchEngine.BING
  @State searchEngineSelectedIndex: number = 0
  @State searchEngineDisplayValue: string = 'Bing(local)'
  @State searchExaApiKey: string = ''
  @State searchExaBaseUrl: string = 'https://api.exa.ai'
  @State searchQueryOptimizationEnabled: boolean = false
  @State isLoading: boolean = false
  @State showSearchConfigSheet: boolean = false

  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'

  private toolRegistry: ToolRegistry = ServiceRegistry.toolRegistry()
  private preferencesService: PreferencesService = getPreferencesService()
  private readonly searchToolId: string = 'web_search'
  private readonly weatherToolId: string = 'weather_query'
  private readonly searchEngineOptions: Array<SelectOption> = [
    { value: 'Bing(local)' },
    { value: 'Exa' }
  ]
  private originalSearchEngine: SearchEngine = SearchEngine.BING
  private originalSearchExaApiKey: string = ''
  private originalSearchExaBaseUrl: string = 'https://api.exa.ai'
  private originalSearchQueryOptimizationEnabled: boolean = false

  private showToolsSnack(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  aboutToAppear(): void {
    this.loadData()
  }

  private async loadData(): Promise<void> {
    this.isLoading = true

    registerBuiltinTools()
    const allTools = this.toolRegistry.getAllToolConfigs()
    const builtin: ToolConfig[] = []
    for (let i = 0; i < allTools.length; i++) {
      builtin.push(allTools[i])
    }
    this.builtinTools = builtin

    await this.loadToolEnabledStates()
    await this.loadSearchSettings()
    this.isLoading = false
  }

  private parseSearchEngine(raw: string): SearchEngine {
    if (raw === SearchEngine.EXA) {
      return SearchEngine.EXA
    }
    return SearchEngine.BING
  }

  private getSearchEngineLabelByIndex(index: number): string {
    if (index === 1) {
      return 'Exa'
    }
    return 'Bing(local)'
  }

  private isSearchTool(tool: ToolConfig): boolean {
    return tool.id === this.searchToolId
  }

  private isBuiltinToolToggleSupported(toolId: string): boolean {
    return toolId === this.searchToolId || toolId === this.weatherToolId
  }

  private applyToolEnabledState(toolId: string, enabled: boolean): void {
    for (let i = 0; i < this.builtinTools.length; i++) {
      if (this.builtinTools[i].id === toolId) {
        this.builtinTools[i].enabled = enabled
      }
    }

    const registeredTool = this.toolRegistry.getTool(toolId)
    if (registeredTool !== undefined) {
      registeredTool.config.enabled = enabled
    }
  }

  private async loadToolEnabledStates(): Promise<void> {
    const webSearchEnabled = await this.preferencesService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    const weatherQueryEnabled = await this.preferencesService.getBoolean(
      PreferenceKeys.WEATHER_QUERY_ENABLED,
      webSearchEnabled
    )
    this.applyToolEnabledState(this.searchToolId, webSearchEnabled)
    this.applyToolEnabledState(this.weatherToolId, weatherQueryEnabled)
  }

  private handleToolEnabledChanged(toolId: string, enabled: boolean): void {
    if (!this.isBuiltinToolToggleSupported(toolId)) {
      return
    }

    this.applyToolEnabledState(toolId, enabled)
    if (toolId === this.searchToolId) {
      this.preferencesService.setBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, enabled)
      return
    }
    if (toolId === this.weatherToolId) {
      this.preferencesService.setBoolean(PreferenceKeys.WEATHER_QUERY_ENABLED, enabled)
    }
  }

  private openToolConfig(tool: ToolConfig): void {
    if (!this.isSearchTool(tool)) {
      return
    }
    this.showSearchConfigSheet = true
  }

  private async loadSearchSettings(): Promise<void> {
    const engineRaw = await this.preferencesService.getString(PreferenceKeys.SEARCH_ENGINE, SearchEngine.BING)
    const exaApiKey = await this.preferencesService.getString(PreferenceKeys.SEARCH_EXA_API_KEY, '')
    const exaBaseUrl = await this.preferencesService.getString(PreferenceKeys.SEARCH_EXA_BASE_URL, 'https://api.exa.ai')
    const optimizationEnabled = await this.preferencesService.getBoolean(
      PreferenceKeys.SEARCH_QUERY_OPTIMIZATION_ENABLED,
      false
    )

    this.searchEngine = this.parseSearchEngine(engineRaw)
    this.searchEngineSelectedIndex = this.searchEngine === SearchEngine.EXA ? 1 : 0
    this.searchEngineDisplayValue = this.getSearchEngineLabelByIndex(this.searchEngineSelectedIndex)
    this.searchExaApiKey = exaApiKey
    this.searchExaBaseUrl = exaBaseUrl.trim() !== '' ? exaBaseUrl.trim() : 'https://api.exa.ai'
    this.searchQueryOptimizationEnabled = optimizationEnabled
    this.syncOriginalSearchSettings()
  }

  private normalizeSearchBaseUrl(raw: string): string {
    const trimmed = raw.trim()
    if (trimmed === '') {
      return 'https://api.exa.ai'
    }
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1)
    }
    return trimmed
  }

  private syncOriginalSearchSettings(): void {
    this.originalSearchEngine = this.searchEngine
    this.originalSearchExaApiKey = this.searchExaApiKey.trim()
    this.originalSearchExaBaseUrl = this.normalizeSearchBaseUrl(this.searchExaBaseUrl)
    this.originalSearchQueryOptimizationEnabled = this.searchQueryOptimizationEnabled
  }

  private hasPendingSearchConfigChanges(): boolean {
    if (this.searchEngine !== this.originalSearchEngine) {
      return true
    }
    if (this.searchExaApiKey.trim() !== this.originalSearchExaApiKey) {
      return true
    }
    if (this.normalizeSearchBaseUrl(this.searchExaBaseUrl) !== this.originalSearchExaBaseUrl) {
      return true
    }
    if (this.searchQueryOptimizationEnabled !== this.originalSearchQueryOptimizationEnabled) {
      return true
    }
    return false
  }

  private performCloseSearchConfigSheet(sheetDismiss?: SheetDismiss): void {
    if (sheetDismiss !== undefined) {
      sheetDismiss.dismiss()
      return
    }
    this.showSearchConfigSheet = false
  }

  private requestCloseSearchConfigSheet(sheetDismiss?: SheetDismiss): void {
    if (!this.hasPendingSearchConfigChanges()) {
      this.performCloseSearchConfigSheet(sheetDismiss)
      return
    }

    this.getUIContext().showAlertDialog({
      title: $r('app.string.search_discard_changes_title'),
      message: $r('app.string.search_discard_changes_message'),
      primaryButton: {
        value: $r('app.string.search_continue_editing'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.search_discard_changes'),
        fontColor: Color.Red,
        action: () => {
          this.performCloseSearchConfigSheet(sheetDismiss)
        }
      }
    })
  }

  private async handleSaveSearchSettings(): Promise<boolean> {
    const exaKey = this.searchExaApiKey.trim()
    if (this.searchEngine === SearchEngine.EXA && exaKey === '') {
      this.showToolsSnack($r('app.string.search_exa_key_required'), 2000, SnackBarTone.ERROR)
      return false
    }

    const baseUrl = this.normalizeSearchBaseUrl(this.searchExaBaseUrl)
    const shouldValidateExaBaseUrl = this.searchEngine === SearchEngine.EXA
    if (shouldValidateExaBaseUrl && !baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      this.showToolsSnack($r('app.string.search_base_url_invalid'), 2000, SnackBarTone.ERROR)
      return false
    }

    await this.preferencesService.setString(PreferenceKeys.SEARCH_ENGINE, this.searchEngine)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_EXA_API_KEY, exaKey)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_EXA_BASE_URL, baseUrl)
    await this.preferencesService.setBoolean(
      PreferenceKeys.SEARCH_QUERY_OPTIMIZATION_ENABLED,
      this.searchQueryOptimizationEnabled
    )
    this.searchExaApiKey = exaKey
    this.searchExaBaseUrl = baseUrl
    this.syncOriginalSearchSettings()

    this.showToolsSnack($r('app.string.search_config_saved'), 2000, SnackBarTone.SUCCESS)
    return true
  }

  private handleSaveAndCloseSearchSettings(): void {
    this.handleSaveSearchSettings().then((saved: boolean) => {
      if (saved) {
        this.showSearchConfigSheet = false
      }
    })
  }

  private handleSearchEngineSelect(index: number, value: string): void {
    this.searchEngineSelectedIndex = index
    const displayValue = value.trim() === '' ? this.getSearchEngineLabelByIndex(index) : value
    this.searchEngineDisplayValue = displayValue
    this.searchEngine = index === 1 ? SearchEngine.EXA : SearchEngine.BING
  }

  @Builder
  SearchConfigSheetBuilder() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.requestCloseSearchConfigSheet()
        })

        Text($r('app.string.search_service_config'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor(this.themePrimary)
        .onClick(() => {
          this.handleSaveAndCloseSearchSettings()
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          Text($r('app.string.search_service_config_desc'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .margin({ bottom: 10 })

          Column() {
            Text($r('app.string.search_engine'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ bottom: 6 })

            Select(this.searchEngineOptions)
              .selected(this.searchEngineSelectedIndex)
              .value(this.searchEngineDisplayValue)
              .onSelect((index: number, value: string) => {
                this.handleSearchEngineSelect(index, value)
              })
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .height(40)
              .backgroundColor($r('app.color.background'))
              .borderRadius(10)
              .padding({ left: 8, right: 8 })

            if (this.searchEngine === SearchEngine.EXA) {
              TextInput({ text: this.searchExaApiKey, placeholder: $r('app.string.search_exa_api_key') })
                .onChange((value: string) => {
                  this.searchExaApiKey = value
                })
                .type(InputType.Password)
                .enableAutoFill(false)
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor($r('app.color.background'))
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })

              TextInput({ text: this.searchExaBaseUrl, placeholder: $r('app.string.search_exa_base_url') })
                .onChange((value: string) => {
                  this.searchExaBaseUrl = value
                })
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor($r('app.color.background'))
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })
            }

            Text($r('app.string.search_engine_runtime_hint'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .margin({ top: 8 })

            Row() {
              Column() {
                Text($r('app.string.search_query_optimization'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')

                Text($r('app.string.search_query_optimization_hint'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                  .margin({ top: 2, right: 8 })
              }
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.searchQueryOptimizationEnabled })
                .onChange((value: boolean) => {
                  this.searchQueryOptimizationEnabled = value
                })
            }
            .width('100%')
            .margin({ top: 10 })

            if (this.searchEngine === SearchEngine.EXA && this.searchQueryOptimizationEnabled) {
              Text($r('app.string.search_query_optimization_exa_hint'))
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .margin({ top: 6 })
            }
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.surface'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  build() {
    Column() {
      if (this.showHeader) {
        Row() {
          Text($r('app.string.tools_center_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Blank()

          Button($r('app.string.tools_center_refresh'))
            .height(30)
            .fontSize(12)
            .backgroundColor(this.themePrimary)
            .fontColor(Color.White)
            .onClick(() => {
              this.loadData()
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
      }

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(42)
            .height(42)
            .color(this.themePrimary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            Text($r('app.string.tools_builtin_section'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ bottom: 10 })

            Text($r('app.string.tools_builtin_section_desc'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .margin({ bottom: 10 })

            ForEach(this.builtinTools, (tool: ToolConfig) => {
              BuiltinToolCardItem({
                tool: tool,
                isSearchTool: this.isSearchTool(tool),
                isToggleSupported: this.isBuiltinToolToggleSupported(tool.id),
                searchEngineDisplayValue: this.searchEngineDisplayValue,
                onToggle: (enabled: boolean) => {
                  this.handleToolEnabledChanged(tool.id, enabled)
                },
                onOpenConfig: () => {
                  this.openToolConfig(tool)
                }
              })
            }, (tool: ToolConfig) => tool.id)
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.background'))
    .bindSheet($$this.showSearchConfigSheet, this.SearchConfigSheetBuilder(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.LARGE],
      showClose: false,
      dragBar: true,
      blurStyle: BlurStyle.Regular,
      onWillAppear: () => {
        this.loadSearchSettings()
      },
      shouldDismiss: (dismissAction: SheetDismiss) => {
        this.requestCloseSearchConfigSheet(dismissAction)
      },
      onDisappear: () => {
        this.showSearchConfigSheet = false
        this.loadSearchSettings()
      }
    })
  }
}

@Component
struct BuiltinToolCardItem {
  @ObjectLink tool: ToolConfig
  @Prop isSearchTool: boolean = false
  @Prop isToggleSupported: boolean = false
  @Prop searchEngineDisplayValue: string = ''
  onToggle: (enabled: boolean) => void = (enabled: boolean) => {}
  onOpenConfig: () => void = () => {}

  @Builder
  ToolCardText() {
    Column() {
      Text(this.tool.name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Text(this.tool.description)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })

      if (this.isSearchTool) {
        Row() {
          Text($r('app.string.search_engine_current'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))

          Text(this.searchEngineDisplayValue)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .margin({ top: 6 })
      } else {
        Text(this.tool.id)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 6 })
      }
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ToolCardSuffix() {
    Row() {
      if (this.isToggleSupported) {
        Toggle({ type: ToggleType.Switch, isOn: this.tool.enabled })
          .onChange((value: boolean) => {
            this.tool.enabled = value
            this.onToggle(value)
          })
      }

      if (this.isSearchTool) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])
          .margin({ left: 10 })
          .onClick(() => {
            this.onOpenConfig()
          })
      }
    }
  }

  build() {
    HdsListItemCard({
      textItem: {
        customBuilder: (): void => { this.ToolCardText() }
      },
      suffixItem: new SuffixCustomBuilder((): void => { this.ToolCardSuffix() }),
      cardBackgroundColor: $r('app.color.surface'),
      cardBorderRadius: 12,
      onClick: this.isSearchTool ? (): void => { this.onOpenConfig() } : undefined
    })
    .margin({ bottom: 8 })
  }
}
