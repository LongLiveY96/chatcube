import { ModelInfo } from '../models/ChatModels'
import { buildIconResourcePath, getModelIconPath, isNetworkIconPath, isSandboxIconPath } from '../utils/ProviderIconUtils'

/**
 * 模型选择器弹窗组件
 * 用于从 API 返回的模型列表中选择需要保留的模型
 */
@Component
export struct ModelPickerSheet {
  @Prop availableModels: string[] = []        // API 返回的所有模型 ID
  @Prop existingModels: ModelInfo[] = []      // 当前已有的模型（默认选中）
  @Prop providerId: string = ''
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('isDarkMode') isDarkMode: boolean = false

  @State searchKeywords: string = ''
  @State selectedIds: Set<string> = new Set()
  @State isInitialized: boolean = false

  onConfirm: (selectedIds: string[]) => void = () => {}
  onCancel: () => void = () => {}

  aboutToAppear(): void {
    this.initializeSelection()
  }

  // 初始化选中状态：已有模型默认选中
  private initializeSelection(): void {
    const selected = new Set<string>()
    for (let i = 0; i < this.existingModels.length; i++) {
      const modelId = this.existingModels[i].id
      // 只选中在可用模型列表中存在的已有模型
      if (this.availableModels.includes(modelId)) {
        selected.add(modelId)
      }
    }
    this.selectedIds = selected
    this.isInitialized = true
  }

  // 获取过滤后的模型列表
  private getFilteredModels(): string[] {
    if (this.searchKeywords.trim() === '') {
      return this.availableModels
    }
    const keyword = this.searchKeywords.toLowerCase()
    const result: string[] = []
    for (let i = 0; i < this.availableModels.length; i++) {
      const modelId = this.availableModels[i]
      if (modelId.toLowerCase().includes(keyword)) {
        result.push(modelId)
      }
    }
    return result
  }

  // 切换模型选中状态
  private toggleModel(modelId: string): void {
    const newSet = new Set<string>()
    // 复制现有选中项
    this.selectedIds.forEach((id: string) => {
      newSet.add(id)
    })
    // 切换状态
    if (newSet.has(modelId)) {
      newSet.delete(modelId)
    } else {
      newSet.add(modelId)
    }
    this.selectedIds = newSet
  }

  // 检查模型是否选中
  private isSelected(modelId: string): boolean {
    return this.selectedIds.has(modelId)
  }

  // 检查是否全选
  private isAllSelected(): boolean {
    const filtered = this.getFilteredModels()
    if (filtered.length === 0) {
      return false
    }
    for (let i = 0; i < filtered.length; i++) {
      if (!this.selectedIds.has(filtered[i])) {
        return false
      }
    }
    return true
  }

  // 全选/取消全选
  private toggleSelectAll(): void {
    const filtered = this.getFilteredModels()
    const newSet = new Set<string>()
    // 复制现有选中项
    this.selectedIds.forEach((id: string) => {
      newSet.add(id)
    })

    if (this.isAllSelected()) {
      // 取消全选（只取消当前过滤结果中的）
      for (let i = 0; i < filtered.length; i++) {
        newSet.delete(filtered[i])
      }
    } else {
      // 全选当前过滤结果
      for (let i = 0; i < filtered.length; i++) {
        newSet.add(filtered[i])
      }
    }
    this.selectedIds = newSet
  }

  // 检查是否是已有模型
  private isExistingModel(modelId: string): boolean {
    for (let i = 0; i < this.existingModels.length; i++) {
      if (this.existingModels[i].id === modelId) {
        return true
      }
    }
    return false
  }

  private getModelIconPathForRender(modelId: string): string {
    return getModelIconPath(modelId, this.providerId, '')
  }

  private getModelIconResourcePath(modelId: string): string {
    const iconPath = this.getModelIconPathForRender(modelId)
    if (iconPath === '') {
      return ''
    }
    return buildIconResourcePath(iconPath)
  }

  private hasModelIcon(modelId: string): boolean {
    return this.getModelIconResourcePath(modelId) !== ''
  }

  private isRawfileModelIcon(modelId: string): boolean {
    const resourcePath = this.getModelIconResourcePath(modelId)
    return resourcePath !== '' && !isNetworkIconPath(resourcePath) && !isSandboxIconPath(resourcePath)
  }

  // 确认选择
  private confirmSelection(): void {
    const selected: string[] = []
    this.selectedIds.forEach((id: string) => {
      selected.push(id)
    })
    this.onConfirm(selected)
  }

  build() {
    Column() {
      // 头部
      this.SheetHeader()

      // 搜索框
      this.SearchBar()

      // 全选行
      this.SelectAllRow()

      // 模型列表
      this.ModelList()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  SheetHeader() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
      }
        .type(ButtonType.Circle)
        .width(32)
        .height(32)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.onCancel()
        })

      // 标题
      Column() {
        Text($r('app.string.select_models'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Text(`${this.selectedIds.size}/${this.availableModels.length}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      // 完成按钮
      Button() {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([Color.White])
      }
        .type(ButtonType.Circle)
        .width(32)
        .height(32)
        .backgroundColor(this.themePrimary)
        .onClick(() => {
          this.confirmSelection()
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  SearchBar() {
    Search({ value: this.searchKeywords, placeholder: $r('app.string.filter_models_placeholder') })
      .width('100%')
      .height(40)
      .backgroundColor($r('app.color.surface'))
      .margin({ left: 16, right: 16 })
      .padding({ left: 16, right: 16 })
      .onChange((value: string) => {
        this.searchKeywords = value
      })
  }

  @Builder
  SelectAllRow() {
    Row() {
      Checkbox()
        .select(this.isAllSelected())
        .selectedColor($r('app.color.primary'))
        .hitTestBehavior(HitTestMode.None) // 让点击穿透到 Row，避免 Checkbox 自身响应点击导致冲突

      Text(this.isAllSelected() ?
        $r('app.string.model_picker_deselect_all') :
        $r('app.string.model_picker_select_all'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ left: 8 })

      Text(`(${this.selectedIds.size}/${this.getFilteredModels().length})`)
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 4 })
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .margin({ top: 8 })
    .onClick(() => {
      this.toggleSelectAll()
    })
  }

  @Builder
  ModelList() {
    List() {
      ForEach(this.getFilteredModels(), (modelId: string, index: number) => {
        ListItem() {
          this.ModelRow(modelId, index < this.getFilteredModels().length - 1)
        }
      }, (modelId: string) => `${modelId}_${this.isSelected(modelId)}`)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16, bottom: 40 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  ModelRow(modelId: string, showDivider: boolean) {
    Column() {
      Row() {
        // 复选框
        Checkbox()
          .select(this.isSelected(modelId))
          .selectedColor($r('app.color.primary'))
          .hitTestBehavior(HitTestMode.None) // 让点击穿透到 Row

        // 模型图标
        Column() {
          if (this.hasModelIcon(modelId)) {
            if (this.isRawfileModelIcon(modelId)) {
              Image($rawfile(this.getModelIconResourcePath(modelId)))
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
            } else {
              Image(this.getModelIconResourcePath(modelId))
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
            }
          } else {
            SymbolGlyph($r('sys.symbol.ai_edit'))
              .fontSize(16)
              .fontColor([$r('app.color.text_tertiary')])
          }
        }
        .width(32)
        .height(32)
        .borderRadius(8)
        .backgroundColor($r('app.color.model_icon_bg'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin({ left: 12 })

        // 模型名称
        Column() {
          Text(modelId)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 已有模型标记
          if (this.isExistingModel(modelId)) {
            Text($r('app.string.model_picker_added'))
              .fontSize(11)
              .fontColor($r('app.color.primary'))
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10 })
      }
      .width('100%')
      .height(56)
      .onClick(() => {
        this.toggleModel(modelId)
      })

      if (showDivider) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 54 })
      }
    }
  }
}
