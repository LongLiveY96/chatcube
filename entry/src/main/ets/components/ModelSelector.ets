import { ModelProvider, ModelInfo } from '../models/ChatModels'
import {
  ModelRowGroupPosition,
  ModelRowRadius,
  ModelSelectorBuildResult,
  ModelSelectorModelRow,
  ModelSelectorRow,
  ModelSelectorRowType,
  buildModelSelectorRows
} from '../config/ModelListProjection'
import { FavoriteModelsService, getFavoriteModelsService } from '../services/FavoriteModelsService'
import { ProviderIcon } from './ProviderIcon'
import { buildModelIconRenderData, ModelIconRenderData } from '../utils/ModelIconRenderUtils'
import { getAppUiState } from '../state/AppUiState'

@ComponentV2
export struct ModelSelectorContent {
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  @Param providers: ModelProvider[] = []
  @Param showEditEntry: boolean = true
  @Param showFavoriteActions: boolean = true
  @Param showFavoriteFilter: boolean = true
  @Param showClearSelectionOption: boolean = false
  @Param clearSelectionText: string | Resource = $r('app.string.default_model_clear_selection')
  @Param searchPlaceholder: string | Resource = $r('app.string.filter_models_placeholder')
  @Param includeModelIdInSearch: boolean = false
  @Param emptyStateMode: string = 'chat'
  @Local searchKeywords: string = ''
  @Local showFavoritesOnly: boolean = false
  @Local hasEnabledModels: boolean = false
  @Local hasFavoriteModels: boolean = false
  @Local hasFilteredModels: boolean = false
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get favoriteAccentColor(): Resource {
    return $r('app.color.status_error')
  }
  private get favoriteFilterActiveBackground(): string {
    return this.isDarkMode ? 'rgba(239, 68, 68, 0.20)' : 'rgba(239, 68, 68, 0.10)'
  }
  @Event onSelectModel: (providerId: string, modelId: string, modelName: string) => void =
    (_providerId: string, _modelId: string, _modelName: string): void => {}
  @Event onLongPressModel: (model: ModelInfo, provider: ModelProvider) => void =
    (_model: ModelInfo, _provider: ModelProvider): void => {}
  @Event onClearSelection: () => void = (): void => {}

  private favoriteService: FavoriteModelsService = getFavoriteModelsService()
  @Local private rows: ModelSelectorRow[] = []
  @Local private favoriteKeySet: Set<string> = new Set<string>()
  private iconRenderCache: Map<string, ModelIconRenderData> = new Map<string, ModelIconRenderData>()
  private favoriteLoadRequestId: number = 0
  private favoriteMutationVersion: number = 0

  private isModelFavorite(providerId: string, modelId: string): boolean {
    return this.favoriteKeySet.has(`${providerId}::${modelId}`)
  }

  aboutToAppear(): void {
    if (!this.showFavoriteFilter) {
      this.showFavoritesOnly = false
    }
    this.rebuildRows()
    if (this.showFavoriteActions || this.showFavoriteFilter) {
      this.loadFavorites()
    }
  }

  @Monitor('providers')
  onProvidersChanged(): void {
    this.iconRenderCache.clear()
    this.rebuildRows()
  }

  private async loadFavorites(): Promise<void> {
    const requestId = this.favoriteLoadRequestId + 1
    this.favoriteLoadRequestId = requestId
    const mutationVersionAtStart = this.favoriteMutationVersion
    await this.favoriteService.load()
    if (requestId !== this.favoriteLoadRequestId) {
      return
    }
    if (mutationVersionAtStart !== this.favoriteMutationVersion) {
      return
    }
    this.syncFavoriteKeysFromService()
  }

  private async toggleFavorite(model: ModelInfo, provider: ModelProvider): Promise<void> {
    this.favoriteMutationVersion = this.favoriteMutationVersion + 1
    const key = this.favoriteService.getFavoriteKey(provider.id, model.id)
    const previousSet = this.favoriteKeySet
    const nextSet = new Set<string>(this.favoriteKeySet)
    const willFavorite = !nextSet.has(key)
    if (willFavorite) {
      nextSet.add(key)
    } else {
      nextSet.delete(key)
    }
    this.favoriteKeySet = nextSet
    this.rebuildRows()

    try {
      if (willFavorite) {
        await this.favoriteService.addFavorite(model.id, provider.id, model.name, provider.name)
      } else {
        await this.favoriteService.removeFavorite(model.id, provider.id)
      }
      this.syncFavoriteKeysFromService()
    } catch (error) {
      console.error('ModelSelectorContent', `[toggleFavorite] failed: ${JSON.stringify(error)}`)
      this.favoriteKeySet = previousSet
      this.rebuildRows()
    }
  }

  private syncFavoriteKeysFromService(): void {
    this.favoriteKeySet = new Set<string>(this.favoriteService.getFavoriteKeys())
    this.rebuildRows()
  }

  private rebuildRows(): void {
    const startAt = Date.now()
    const result: ModelSelectorBuildResult = buildModelSelectorRows(
      this.providers,
      this.searchKeywords,
      this.favoriteKeySet,
      this.showFavoritesOnly,
      this.includeModelIdInSearch
    )
    this.hasEnabledModels = result.hasEnabledModels
    this.hasFavoriteModels = result.hasFavoriteModels
    this.hasFilteredModels = result.hasFilteredModels
    this.rows = result.rows
    console.info(
      'ModelSelectorContent',
      `[rebuildRows] providers=${this.providers.length}, rows=${result.rows.length}, enabled=${result.enabledModelCount}, matched=${result.matchedModelCount}, cost=${Date.now() - startAt}ms`
    )
  }

  private getModelIconRenderData(modelId: string, providerId: string, modelName: string): ModelIconRenderData {
    const cacheKey = `${providerId}::${modelId}::${modelName}`
    const cached = this.iconRenderCache.get(cacheKey)
    if (cached !== undefined) {
      return cached
    }
    const renderData = buildModelIconRenderData(modelId, providerId, modelName)
    this.iconRenderCache.set(cacheKey, renderData)
    return renderData
  }

  private getModelDisplayName(model: ModelInfo): string {
    return model.name !== '' ? model.name : model.id
  }

  private buildRowRadius(groupPosition: ModelRowGroupPosition): ModelRowRadius {
    if (groupPosition === ModelRowGroupPosition.SINGLE) {
      return { topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 16 }
    }
    if (groupPosition === ModelRowGroupPosition.FIRST) {
      return { topLeft: 16, topRight: 16, bottomLeft: 0, bottomRight: 0 }
    }
    if (groupPosition === ModelRowGroupPosition.LAST) {
      return { topLeft: 0, topRight: 0, bottomLeft: 16, bottomRight: 16 }
    }
    return { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 }
  }

  private isSelectedModel(row: ModelSelectorModelRow): boolean {
    if (row.model.id !== this.currentModelId) {
      return false
    }
    return this.currentProviderId === '' || row.provider.id === this.currentProviderId
  }

  private getRowModelDisplayName(row: ModelSelectorModelRow): string {
    return this.getModelDisplayName(row.model)
  }

  private getRowModelIconRenderData(row: ModelSelectorModelRow): ModelIconRenderData {
    return this.getModelIconRenderData(row.model.id, row.provider.id, row.model.name)
  }

  build() {
    Column() {
      this.SearchBar()
      this.ModelList()
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  SearchBar() {
    Row() {
      Search({ value: this.searchKeywords, placeholder: this.searchPlaceholder })
        .layoutWeight(1)
        .height(40)
        .backgroundColor($r('app.color.background'))
        .onChange((value: string) => {
          this.searchKeywords = value
          this.rebuildRows()
        })

      if (this.showFavoriteFilter) {
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph(this.showFavoritesOnly ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(14)
              .fontColor([this.showFavoritesOnly ? this.favoriteAccentColor : $r('app.color.text_secondary')])

            Text($r('app.string.menu_favorite'))
              .fontSize(12)
              .fontColor(this.showFavoritesOnly ? this.favoriteAccentColor : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
        }
        .height(32)
        .padding({ left: 10, right: 10 })
        .margin({ left: 8 })
        .backgroundColor(this.showFavoritesOnly ? this.favoriteFilterActiveBackground : $r('app.color.surface'))
        .border({
          width: this.showFavoritesOnly ? 1 : 0.5,
          color: this.showFavoritesOnly ? this.favoriteAccentColor : $r('app.color.divider')
        })
        .onClick(() => {
          this.showFavoritesOnly = !this.showFavoritesOnly
          this.rebuildRows()
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
  }

  @Builder
  ModelList() {
    if (this.providers.length === 0 || !this.hasEnabledModels) {
      this.EmptyState()
    } else if (this.showFavoritesOnly && !this.hasFavoriteModels) {
      this.NoFavoriteState()
    } else if (!this.hasFilteredModels) {
      this.NoResultState()
    } else {
      List() {
        if (this.showClearSelectionOption) {
          ListItem() {
            Row() {
              Text(this.clearSelectionText)
                .fontSize(16)
                .fontColor($r('app.color.status_error'))

              Blank()
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(12)
            .onClick(() => {
              this.onClearSelection()
            })
          }
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        }

        Repeat<ModelSelectorRow>(this.rows)
          .each((ri: RepeatItem<ModelSelectorRow>) => {
            ListItem() {
              if (ri.item.type === ModelSelectorRowType.PROVIDER_HEADER) {
                this.ProviderHeader(ri.item.provider)
              } else {
                this.ModelRow(ri.item as ModelSelectorModelRow)
              }
            }
          })
          .key((row: ModelSelectorRow) => row.key)

        ListItem() {
          Column().height(20)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .padding({ bottom: 12 })
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
    }
  }

  @Builder
  ProviderHeader(provider: ModelProvider) {
    Row() {
      ProviderIcon({
        iconType: provider.iconType,
        iconPath: provider.iconPath,
        textIcon: provider.textIcon,
        textIconBgColor: provider.textIconBgColor,
        customImagePath: provider.customImagePath,
        iconSize: 28,
        radius: 8,
        bgColor: provider.brandColor,
        brandColor: provider.brandColor,
        fallbackSymbol: $r('sys.symbol.message'),
        fallbackColor: Color.White
      })

      Text(provider.name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 6 })
  }

  @Builder
  ModelRow(row: ModelSelectorModelRow) {
    Column() {
      Row() {
        Row() {
          Column() {
            if (this.getRowModelIconRenderData(row).hasIcon()) {
              if (this.getRowModelIconRenderData(row).isRawfile()) {
                Image($rawfile(this.getRowModelIconRenderData(row).resourcePath))
                  .width(20)
                  .height(20)
                  .objectFit(ImageFit.Contain)
              } else {
                Image(this.getRowModelIconRenderData(row).resourcePath)
                  .width(20)
                  .height(20)
                  .objectFit(ImageFit.Contain)
              }
            } else {
              ProviderIcon({
                iconType: row.provider.iconType,
                iconPath: row.provider.iconPath,
                textIcon: row.provider.textIcon,
                textIconBgColor: row.provider.textIconBgColor,
                customImagePath: row.provider.customImagePath,
                iconSize: 20,
                radius: 6,
                bgColor: row.provider.brandColor,
                brandColor: row.provider.brandColor,
                fallbackSymbol: $r('sys.symbol.ai_edit'),
                fallbackColor: $r('app.color.text_tertiary')
              })
            }
          }
          .width(32)
          .height(32)
          .borderRadius(8)
          .backgroundColor($r('app.color.model_icon_bg'))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          Column() {
            Text(this.getRowModelDisplayName(row))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))

            Row() {
              if (row.model.capabilities.supportsReasoning) {
                this.CapabilityIcon('sys.symbol.AI_deep_thinking')
              }
              if (row.model.capabilities.supportsVision) {
                this.CapabilityIcon('sys.symbol.ohos_photo')
              }
              if (row.model.capabilities.supportsTools) {
                this.CapabilityIcon('sys.symbol.wrench_and_screwdriver')
              }
              if (row.model.capabilities.supportsWebSearch) {
                this.CapabilityIcon('sys.symbol.ohos_wifi')
              }
            }
            .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 10 })
          .layoutWeight(1)
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onSelectModel(row.provider.id, row.model.id, this.getRowModelDisplayName(row))
        })
        .gesture(LongPressGesture({ duration: 500 })
          .onAction(() => {
            if (this.showEditEntry) {
              this.onLongPressModel(row.model, row.provider)
            }
          }))

        if (this.showEditEntry) {
          Button() {
            SymbolGlyph($r('sys.symbol.square_and_pencil'))
              .fontSize(17)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .type(ButtonType.Circle)
          .width(32)
          .height(32)
          .stateEffect(false)
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.onLongPressModel(row.model, row.provider)
          })
        }

        if (this.showFavoriteActions) {
          Button() {
            SymbolGlyph(this.isModelFavorite(row.provider.id, row.model.id) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(18)
              .fontColor([this.isModelFavorite(row.provider.id, row.model.id) ? $r('app.color.status_error') : $r('app.color.text_tertiary')])
          }
          .type(ButtonType.Circle)
          .width(32)
          .height(32)
          .stateEffect(false)
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.toggleFavorite(row.model, row.provider)
          })
        }

        if (this.isSelectedModel(row)) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(18)
            .fontColor([this.themePrimary])
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(this.isSelectedModel(row) ? this.themePrimaryLight : $r('app.color.surface'))
      .borderRadius(this.buildRowRadius(row.groupPosition))

      if (row.groupPosition === ModelRowGroupPosition.FIRST || row.groupPosition === ModelRowGroupPosition.MIDDLE) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 60, right: 12 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  EmptyState() {
    Column() {
      SymbolGlyph(this.emptyStateMode === 'default' ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.message'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])

      Text(this.emptyStateMode === 'default' ? $r('app.string.default_model_no_provider') : '暂无可用模型')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 16 })

      Text(this.emptyStateMode === 'default' ? $r('app.string.default_model_no_provider_hint') : '请先添加或启用AI服务商')
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 4 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  NoResultState() {
    Column() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])

      Text('未找到匹配的模型')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 16 })

      Text('请尝试其他关键词')
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 4 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  NoFavoriteState() {
    Column() {
      SymbolGlyph($r('sys.symbol.heart'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])

      Text($r('app.string.favorite_models_empty_title'))
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 16 })

      Text($r('app.string.favorite_models_empty_desc'))
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 4 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  CapabilityIcon(icon: string) {
    SymbolGlyph($r(icon))
      .fontSize(12)
      .fontColor([$r('app.color.text_tertiary')])
      .margin({ right: 6 })
  }
}

