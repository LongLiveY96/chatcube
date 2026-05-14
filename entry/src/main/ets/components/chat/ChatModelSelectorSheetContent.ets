import { ModelProvider, ModelInfo, ModelInfoExtendedJson } from '../../models/ChatModels'
import { ModelSelectorContent } from '../ModelSelector'
import { ModelEditSheet } from '../ModelEditSheet'
import { getAppUiState } from '../../state/AppUiState'

@ComponentV2
export struct ChatModelSelectorSheetContent {
  @Param providers: ModelProvider[] = []
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  @Param activePanel: string = 'selector'
  @Param editingModel: ModelInfo | null = null
  @Event $editingModel: (value: ModelInfo | null) => void = (_value: ModelInfo | null) => {}
  @Event onSelectModel: (providerId: string, modelId: string, modelName: string) => void =
    (_providerId: string, _modelId: string, _modelName: string): void => {}
  @Event onStartEdit: (model: ModelInfo, provider: ModelProvider) => void =
    (_model: ModelInfo, _provider: ModelProvider): void => {}
  @Event onSaveEdit: (draft: ModelInfoExtendedJson) => Promise<void> =
    async (_draft: ModelInfoExtendedJson): Promise<void> => {}
  @Event onCancelEdit: () => void = (): void => {}

  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }

  private get themeTextPrimary(): string {
    return getAppUiState().themeTextPrimary
  }

  @Builder
  private ModelEditSheetBuilder() {
    if (this.editingModel !== null) {
      ModelEditSheet({
        model: this.editingModel,
        onSave: (draft: ModelInfoExtendedJson) => {
          return this.onSaveEdit(draft)
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
            .fontColor(this.themeTextPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.themeBackground)

        ModelSelectorContent({
          providers: this.providers,
          currentModelId: this.currentModelId,
          currentProviderId: this.currentProviderId,
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
    .backgroundColor(this.themeBackground)
  }
}
