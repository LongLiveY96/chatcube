import { ModelProvider, ModelInfo } from '../../models/ChatModels'
import { ModelSelectorContent } from '../ModelSelector'
import { ModelEditSheet } from '../ModelEditSheet'

@Component
export struct ChatModelSelectorSheetContent {
  @Prop providers: ModelProvider[] = []
  @Prop currentModelId: string = ''
  @Prop activePanel: string = 'selector'
  @Link editingModel: ModelInfo | null
  onSelectModel: (providerId: string, modelId: string, modelName: string) => void =
    (_providerId: string, _modelId: string, _modelName: string): void => {}
  onStartEdit: (model: ModelInfo, provider: ModelProvider) => void =
    (_model: ModelInfo, _provider: ModelProvider): void => {}
  onSaveEdit: () => Promise<void> = async (): Promise<void> => {}
  onCancelEdit: () => void = (): void => {}

  @Builder
  private ModelEditSheetBuilder() {
    if (this.editingModel !== null) {
      ModelEditSheet({
        model: this.editingModel,
        onSave: () => {
          return this.onSaveEdit()
        },
        onCancel: () => {
          this.onCancelEdit()
        }
      })
    }
  }

  build() {
    Stack() {
      Column() {
        ModelSelectorContent({
          providers: this.providers,
          currentModelId: this.currentModelId,
          onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
            this.onSelectModel(providerId, modelId, modelName)
          },
          onLongPressModel: (model: ModelInfo, provider: ModelProvider): void => {
            this.onStartEdit(model, provider)
          }
        })
      }
      .width('100%')
      .height(this.activePanel === 'selector' ? '100%' : 0)
      .visibility(this.activePanel === 'selector' ? Visibility.Visible : Visibility.Hidden)

      Column() {
        this.ModelEditSheetBuilder()
      }
      .width('100%')
      .height(this.activePanel === 'edit' ? '100%' : 0)
      .visibility(this.activePanel === 'edit' ? Visibility.Visible : Visibility.Hidden)
    }
    .width('100%')
    .height('100%')
  }
}
