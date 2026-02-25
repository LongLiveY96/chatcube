import { ModelProvider, ModelInfo } from '../models/ChatModels'
import { getModelIconPath, buildIconResourcePath, isNetworkIconPath, isSandboxIconPath } from '../utils/ProviderIconUtils'
import { FavoriteModelsService, getFavoriteModelsService } from '../services/FavoriteModelsService'
import { ProviderIcon } from './ProviderIcon'

// 模型选择器内容组件（用于 bindSheet）
@Component
export struct ModelSelectorContent {
  @Prop currentModelId: string = ''
  @Prop providers: ModelProvider[] = []
  @Prop showEditEntry: boolean = true
  @Prop showFavoriteActions: boolean = true
  @Prop showFavoriteFilter: boolean = true
  @Prop showClearSelectionOption: boolean = false
  @Prop clearSelectionText: string | Resource = $r('app.string.default_model_clear_selection')
  @Prop searchPlaceholder: string | Resource = $r('app.string.filter_models_placeholder')
  @Prop includeModelIdInSearch: boolean = false
  @Prop emptyStateMode: string = 'chat'
  @State searchKeywords: string = ''
  @State favoriteKeys: string[] = []
  @State showFavoritesOnly: boolean = false
  @State isLoadingFavorites: boolean = true
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_primary_light') themePrimaryLight: string = '#E6F2FF'
  @StorageProp('isDarkMode') isDarkMode: boolean = false
  onSelectModel: (providerId: string, modelId: string, modelName: string) => void =
    (providerId: string, modelId: string, modelName: string): void => {}
  onLongPressModel: (model: ModelInfo, provider: ModelProvider) => void =
    (model: ModelInfo, provider: ModelProvider): void => {}
  onClearSelection: () => void = () => {}

  private favoriteService: FavoriteModelsService = getFavoriteModelsService()

  aboutToAppear(): void {
    if (!this.showFavoriteFilter) {
      this.showFavoritesOnly = false
    }
    if (this.showFavoriteActions || this.showFavoriteFilter) {
      this.loadFavorites()
    } else {
      this.isLoadingFavorites = false
    }
  }

  private async loadFavorites(): Promise<void> {
    this.isLoadingFavorites = true
    await this.favoriteService.load()
    this.favoriteKeys = this.favoriteService.getFavoriteKeys()
    this.isLoadingFavorites = false
  }

  private async toggleFavorite(model: ModelInfo, provider: ModelProvider): Promise<void> {
    const isFavorite = await this.favoriteService.toggleFavorite(
      model.id,
      provider.id,
      model.name,
      provider.name
    )
    // 更新本地状态（使用复合键）
    const key = this.favoriteService.getFavoriteKey(provider.id, model.id)
    if (isFavorite) {
      this.favoriteKeys = [...this.favoriteKeys, key]
    } else {
      this.favoriteKeys = this.favoriteKeys.filter(k => k !== key)
    }
  }

  private isFavorite(modelId: string, providerId: string): boolean {
    const key = this.favoriteService.getFavoriteKey(providerId, modelId)
    return this.favoriteKeys.includes(key)
  }

  private getModelIconPathForRender(modelId: string, providerId: string, modelName: string): string {
    if (modelId !== '') {
      const iconById = getModelIconPath(modelId, providerId, '')
      if (iconById !== '') {
        return iconById
      }
    }
    if (modelName !== '') {
      return getModelIconPath(modelName, providerId, '')
    }
    return ''
  }

  private getModelIconResourcePath(modelId: string, providerId: string, modelName: string): string {
    const iconPath = this.getModelIconPathForRender(modelId, providerId, modelName)
    if (iconPath === '') {
      return ''
    }
    return buildIconResourcePath(iconPath)
  }

  private hasModelIcon(modelId: string, providerId: string, modelName: string): boolean {
    return this.getModelIconResourcePath(modelId, providerId, modelName) !== ''
  }

  private isRawfileIcon(modelId: string, providerId: string, modelName: string): boolean {
    const resourcePath = this.getModelIconResourcePath(modelId, providerId, modelName)
    return resourcePath !== '' && !isNetworkIconPath(resourcePath) && !isSandboxIconPath(resourcePath)
  }

  // 获取过滤后的模型
  private getFilteredModels(provider: ModelProvider): ModelInfo[] {
    if (this.searchKeywords === '' && !this.showFavoritesOnly) {
      return provider.models.filter(m => m.isEnabled)
    }
    const keyword = this.searchKeywords.toLowerCase()
    return provider.models.filter(m => {
      if (!m.isEnabled) {
        return false
      }
      if (this.searchKeywords !== '') {
        const modelName = m.name.toLowerCase()
        let searchMatched = modelName.includes(keyword)
        if (!searchMatched && this.includeModelIdInSearch) {
          searchMatched = m.id.toLowerCase().includes(keyword)
        }
        if (!searchMatched) {
          return false
        }
      }
      if (this.showFavoritesOnly && !this.isFavorite(m.id, provider.id)) {
        return false
      }
      return true
    })
  }

  // 检查过滤后是否有模型
  private hasFilteredModels(provider: ModelProvider): boolean {
    return this.getFilteredModels(provider).length > 0
  }

  // 检查是否有任何匹配的模型
  private hasAnyFilteredModels(): boolean {
    for (let i = 0; i < this.providers.length; i++) {
      if (this.hasFilteredModels(this.providers[i])) {
        return true
      }
    }
    return false
  }

  private hasAnyEnabledModels(): boolean {
    for (let i = 0; i < this.providers.length; i++) {
      const provider = this.providers[i]
      for (let j = 0; j < provider.models.length; j++) {
        const model = provider.models[j]
        if (model.isEnabled) {
          return true
        }
      }
    }
    return false
  }

  private hasAnyFavoriteModels(): boolean {
    for (let i = 0; i < this.providers.length; i++) {
      const provider = this.providers[i]
      for (let j = 0; j < provider.models.length; j++) {
        const model = provider.models[j]
        if (model.isEnabled && this.isFavorite(model.id, provider.id)) {
          return true
        }
      }
    }
    return false
  }

  build() {
    Column() {
      this.SearchBar()
      this.ModelList()
    }
    .width('100%')
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
        })

      if (this.showFavoriteFilter) {
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph(this.showFavoritesOnly ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(14)
              .fontColor([this.showFavoritesOnly ? this.themePrimary : $r('app.color.text_secondary')])

            Text($r('app.string.menu_favorite'))
              .fontSize(12)
              .fontColor(this.showFavoritesOnly ? this.themePrimary : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
        }
        .height(32)
        .padding({ left: 10, right: 10 })
        .margin({ left: 8 })
        .backgroundColor(this.showFavoritesOnly ? this.themePrimaryLight : $r('app.color.surface'))
        .border({
          width: this.showFavoritesOnly ? 1 : 0.5,
          color: this.showFavoritesOnly ? this.themePrimary : $r('app.color.divider')
        })
        .onClick(() => {
          this.showFavoritesOnly = !this.showFavoritesOnly
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
  }

  @Builder
  ModelList() {
    if (this.providers.length === 0 || !this.hasAnyEnabledModels()) {
      this.EmptyState()
    } else if (this.showFavoritesOnly && !this.hasAnyFavoriteModels()) {
      this.NoFavoriteState()
    } else if (!this.hasAnyFilteredModels()) {
      this.NoResultState()
    } else {
      Scroll() {
        Column() {
          if (this.showClearSelectionOption) {
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
            .margin({ bottom: 12 })
          }

          ForEach(this.providers, (provider: ModelProvider) => {
            if (this.hasFilteredModels(provider)) {
              this.ProviderSection(provider)
            }
          })

          Column().height(20)
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          bottom: 12
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .nestedScroll({
        scrollForward: NestedScrollMode.PARENT_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
    }
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
  ProviderSection(provider: ModelProvider) {
    Column() {
      Row() {
        // 使用 ProviderIcon 组件显示供应商图标
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
      .padding({ top: 10, bottom: 6, left: 4 })

      Column() {
        ForEach(this.getFilteredModels(provider), (model: ModelInfo) => {
          Row() {
            // 模型图标
            Column() {
              if (this.hasModelIcon(model.id, provider.id, model.name)) {
                if (this.isRawfileIcon(model.id, provider.id, model.name)) {
                  Image($rawfile(this.getModelIconResourcePath(model.id, provider.id, model.name)))
                    .width(20)
                    .height(20)
                    .objectFit(ImageFit.Contain)
                } else {
                  Image(this.getModelIconResourcePath(model.id, provider.id, model.name))
                    .width(20)
                    .height(20)
                    .objectFit(ImageFit.Contain)
                }
              } else {
                ProviderIcon({
                  iconType: provider.iconType,
                  iconPath: provider.iconPath,
                  textIcon: provider.textIcon,
                  textIconBgColor: provider.textIconBgColor,
                  customImagePath: provider.customImagePath,
                  iconSize: 20,
                  radius: 6,
                  bgColor: provider.brandColor,
                  brandColor: provider.brandColor,
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
              Text(model.name !== '' ? model.name : model.id)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))

              // 模型能力图标
              Row() {
                if (model.capabilities.supportsReasoning) {
                  this.CapabilityIcon('sys.symbol.AI_deep_thinking')
                }
                if (model.capabilities.supportsVision) {
                  this.CapabilityIcon('sys.symbol.ohos_photo')
                }
                if (model.capabilities.supportsTools) {
                  this.CapabilityIcon('sys.symbol.wrench_and_screwdriver')
                }
                if (model.capabilities.supportsWebSearch) {
                  this.CapabilityIcon('sys.symbol.ohos_wifi')
                }
              }
              .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 10 })
            .layoutWeight(1)

            if (this.showEditEntry) {
              // 编辑按钮
              Button() {
                SymbolGlyph($r('sys.symbol.square_and_pencil'))
                  .fontSize(17)
                  .fontColor([$r('app.color.text_tertiary')])
              }
              .type(ButtonType.Circle)
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.onLongPressModel(model, provider)
              })
            }

            if (this.showFavoriteActions) {
              // 收藏按钮
              Button() {
                SymbolGlyph(this.isFavorite(model.id, provider.id) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                  .fontSize(18)
                  .fontColor([this.isFavorite(model.id, provider.id) ? $r('app.color.status_error') : $r('app.color.text_tertiary')])
              }
              .type(ButtonType.Circle)
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.toggleFavorite(model, provider)
              })
            }

            // 选中状态
            if (model.id === this.currentModelId) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(18)
                .fontColor([this.themePrimary])
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(model.id === this.currentModelId ? this.themePrimaryLight : Color.Transparent)
          .borderRadius(12)
          .onClick(() => {
            const modelName = model.name !== '' ? model.name : model.id
            this.onSelectModel(provider.id, model.id, modelName)
          })
          .gesture(LongPressGesture({ duration: 500 })
            .onAction(() => {
              if (this.showEditEntry) {
                this.onLongPressModel(model, provider)
              }
            }))
        }, (model: ModelInfo): string =>
          `${provider.id}_${model.id}_${model.isEnabled}_${model.capabilities.supportsTools}_` +
          `${model.capabilities.supportsReasoning}_${model.capabilities.supportsVision}_` +
          `${model.capabilities.supportsWebSearch}`)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(16)
      .border({
        width: 1,
        color: $r('app.color.divider')
      })
    }
    .width('100%')
  }

  @Builder
  CapabilityIcon(icon: string) {
    SymbolGlyph($r(icon))
      .fontSize(12)
      .fontColor([$r('app.color.text_tertiary')])
      .margin({ right: 6 })
  }
}
