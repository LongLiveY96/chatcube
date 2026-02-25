import { ModelProvider } from '../../models/ChatModels'
import { ModelSelectorContent } from '../ModelSelector'

@Component
export struct DefaultModelSelectSheetContent {
  @Prop currentSelectionText: string | Resource = ''
  @Prop isProvidersLoaded: boolean = false
  @Prop providers: ModelProvider[] = []
  @Prop currentModelId: string = ''
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  onSelectModel: (providerId: string, modelId: string, modelName: string) => void =
    (_providerId: string, _modelId: string, _modelName: string): void => {}
  onClearSelection: () => void = (): void => {}

  build() {
    Column() {
      Row() {
        Text($r('app.string.default_model_current_selection'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))

        Text(this.currentSelectionText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(12)
      .margin({ left: 16, right: 16, top: 8 })

      if (!this.isProvidersLoaded) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.themePrimary)
          Text($r('app.string.loading'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        ModelSelectorContent({
          providers: this.providers,
          currentModelId: this.currentModelId,
          showEditEntry: false,
          showFavoriteActions: false,
          showFavoriteFilter: false,
          showClearSelectionOption: true,
          clearSelectionText: $r('app.string.default_model_clear_selection'),
          searchPlaceholder: $r('app.string.filter_models_placeholder'),
          includeModelIdInSearch: true,
          emptyStateMode: 'default',
          onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
            this.onSelectModel(providerId, modelId, modelName)
          },
          onClearSelection: () => {
            this.onClearSelection()
          }
        })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}
