import { ModelProvider, ModelInfo } from '../../models/ChatModels'
import { ModelSelectorContent } from '../ModelSelector'
import { ModelEditSheet } from '../ModelEditSheet'

@ComponentV2
export struct ChatModelSelectorSheetContent {
  @Param providers: ModelProvider[] = []
  @Param currentModelId: string = ''
  @Param activePanel: string = 'selector'
  @Param editingModel: ModelInfo | null = null
  @Event $editingModel: (value: ModelInfo | null) => void = (_value: ModelInfo | null) => {}
  @Event onSelectModel: (providerId: string, modelId: string, modelName: string) => void =
    (_providerId: string, _modelId: string, _modelName: string): void => {}
  @Event onStartEdit: (model: ModelInfo, provider: ModelProvider) => void =
    (_model: ModelInfo, _provider: ModelProvider): void => {}
  @Event onSaveEdit: () => Promise<void> = async (): Promise<void> => {}
  @Event onCancelEdit: () => void = (): void => {}

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
        // 自定义标题栏
        Row() {
          Blank()
            .layoutWeight(1)

          Text($r('app.string.select_model'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })

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
