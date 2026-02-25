import { ModelInfo } from '../models/ChatModels'
import { ModelPickerSheet } from './ModelPickerSheet'

@Component
export struct ModelPickerSheetHost {
  @Prop availableModels: string[] = []
  @Prop existingModels: ModelInfo[] = []
  @Prop providerId: string = ''
  onConfirm: (selectedIds: string[]) => void = (_selectedIds: string[]): void => {}
  onCancel: () => void = (): void => {}

  build() {
    if (this.availableModels.length > 0) {
      ModelPickerSheet({
        availableModels: this.availableModels,
        existingModels: this.existingModels,
        providerId: this.providerId,
        onConfirm: (selectedIds: string[]) => {
          this.onConfirm(selectedIds)
        },
        onCancel: () => {
          this.onCancel()
        }
      })
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
    }
  }
}
