import { ModelInfo } from '../models/ChatModels'
import {
  ModelRowGroupPosition,
  ModelRowRadius,
  ModelPickerBuildResult,
  ModelPickerGroupHeaderRow,
  ModelPickerModelRow,
  ModelPickerRow,
  ModelPickerRowType,
  buildModelPickerRows
} from '../config/ModelListProjection'
import { buildModelIconRenderData, ModelIconRenderData } from '../utils/ModelIconRenderUtils'
import { getAppUiState } from '../state/AppUiState'

@ComponentV2
export struct ModelPickerSheet {
  @Param availableModels: string[] = []
  @Param existingModels: ModelInfo[] = []
  @Param providerId: string = ''
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  @Local searchKeywords: string = ''
  @Local selectedIds: Set<string> = new Set<string>()

  @Event onConfirm: (selectedIds: string[]) => void = () => {}
  @Event onCancel: () => void = () => {}

  @Local private rows: ModelPickerRow[] = []
  private existingModelIdSet: Set<string> = new Set<string>()
  private filteredModelIds: string[] = []
  private groupExpansionState: Map<string, boolean> = new Map<string, boolean>()
  private iconRenderCache: Map<string, ModelIconRenderData> = new Map<string, ModelIconRenderData>()

  aboutToAppear(): void {
    this.initializeSelection()
    this.rebuildRows()
  }

  private initializeSelection(): void {
    const selected = new Set<string>()
    const existingModelIdSet = new Set<string>()
    const availableModelSet = new Set<string>(this.availableModels)
    for (let i = 0; i < this.existingModels.length; i++) {
      const modelId = this.existingModels[i].id
      existingModelIdSet.add(modelId)
      if (availableModelSet.has(modelId)) {
        selected.add(modelId)
      }
    }
    this.existingModelIdSet = existingModelIdSet
    this.selectedIds = selected
  }

  private rebuildRows(): void {
    const startAt = Date.now()
    const result: ModelPickerBuildResult = buildModelPickerRows(
      this.availableModels,
      this.existingModelIdSet,
      this.searchKeywords,
      this.groupExpansionState
    )
    this.filteredModelIds = result.filteredModelIds
    this.rows = result.rows
    console.info(
      'ModelPickerSheet',
      `[rebuildRows] available=${this.availableModels.length}, rows=${result.rows.length}, filtered=${this.filteredModelIds.length}, cost=${Date.now() - startAt}ms`
    )
  }

  private toggleModel(modelId: string): void {
    const newSet = new Set<string>(this.selectedIds)
    if (newSet.has(modelId)) {
      newSet.delete(modelId)
    } else {
      newSet.add(modelId)
    }
    this.selectedIds = newSet
  }

  private isSelected(modelId: string): boolean {
    return this.selectedIds.has(modelId)
  }

  private isAllSelected(): boolean {
    if (this.filteredModelIds.length === 0) {
      return false
    }
    for (let i = 0; i < this.filteredModelIds.length; i++) {
      if (!this.selectedIds.has(this.filteredModelIds[i])) {
        return false
      }
    }
    return true
  }

  private toggleSelectAll(): void {
    const newSet = new Set<string>(this.selectedIds)
    if (this.isAllSelected()) {
      for (let i = 0; i < this.filteredModelIds.length; i++) {
        newSet.delete(this.filteredModelIds[i])
      }
    } else {
      for (let i = 0; i < this.filteredModelIds.length; i++) {
        newSet.add(this.filteredModelIds[i])
      }
    }
    this.selectedIds = newSet
  }

  private toggleGroupExpansion(groupName: string): void {
    const current = this.groupExpansionState.has(groupName) ? (this.groupExpansionState.get(groupName) ?? true) : true
    this.groupExpansionState.set(groupName, !current)
    this.rebuildRows()
  }

  private isGroupAllSelected(modelIds: string[]): boolean {
    if (modelIds.length === 0) {
      return false
    }
    for (let i = 0; i < modelIds.length; i++) {
      if (!this.selectedIds.has(modelIds[i])) {
        return false
      }
    }
    return true
  }

  private getGroupSelectedCount(modelIds: string[]): number {
    let count = 0
    for (let i = 0; i < modelIds.length; i++) {
      if (this.selectedIds.has(modelIds[i])) {
        count++
      }
    }
    return count
  }

  private toggleGroupSelectAll(modelIds: string[]): void {
    const newSet = new Set<string>(this.selectedIds)
    if (this.isGroupAllSelected(modelIds)) {
      for (let i = 0; i < modelIds.length; i++) {
        newSet.delete(modelIds[i])
      }
    } else {
      for (let i = 0; i < modelIds.length; i++) {
        newSet.add(modelIds[i])
      }
    }
    this.selectedIds = newSet
  }

  private getModelIconRenderData(modelId: string): ModelIconRenderData {
    const cached = this.iconRenderCache.get(modelId)
    if (cached !== undefined) {
      return cached
    }
    const renderData = buildModelIconRenderData(modelId, this.providerId, '')
    this.iconRenderCache.set(modelId, renderData)
    return renderData
  }

  private getRowIconRenderData(row: ModelPickerModelRow): ModelIconRenderData {
    return this.getModelIconRenderData(row.modelId)
  }

  private confirmSelection(): void {
    const selected: string[] = []
    this.selectedIds.forEach((id: string) => {
      selected.push(id)
    })
    this.onConfirm(selected)
  }

  build() {
    Column() {
      this.SheetHeader()
      this.SearchBar()
      this.SelectAllRow()
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
        this.rebuildRows()
      })
  }

  @Builder
  SelectAllRow() {
    Row() {
      Checkbox()
        .select(this.isAllSelected())
        .selectedColor(this.themePrimary)
        .hitTestBehavior(HitTestMode.None)

      Text(this.isAllSelected() ? $r('app.string.model_picker_deselect_all') : $r('app.string.model_picker_select_all'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ left: 8 })

      Text(`(${this.selectedIds.size}/${this.filteredModelIds.length})`)
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
  GroupHeader(row: ModelPickerGroupHeaderRow) {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: row.isExpanded ? 90 : 0 })
          .animation({ duration: 200 })

        Text(row.groupName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 8 })

        Text(` (${this.getGroupSelectedCount(row.modelIds)}/${row.modelIds.length})`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .onClick(() => {
        this.toggleGroupExpansion(row.groupName)
      })

      Checkbox()
        .select(this.isGroupAllSelected(row.modelIds))
        .selectedColor(this.themePrimary)
        .width(20)
        .height(20)
        .margin({ right: 8 })
        .onClick(() => {
          this.toggleGroupSelectAll(row.modelIds)
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 8 })
  }

  @Builder
  ModelList() {
    List() {
      Repeat<ModelPickerRow>(this.rows)
        .each((ri: RepeatItem<ModelPickerRow>) => {
          ListItem() {
            if (ri.item.type === ModelPickerRowType.GROUP_HEADER) {
              this.GroupHeader(ri.item as ModelPickerGroupHeaderRow)
            } else {
              this.ModelRow(ri.item as ModelPickerModelRow)
            }
          }
        })
        .key((row: ModelPickerRow) => row.key)
        .virtualScroll({ totalCount: this.rows.length })
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16, bottom: 40 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .cachedCount(10)
  }

  @Builder
  ModelRow(row: ModelPickerModelRow) {
    Column() {
      Row() {
        Checkbox()
          .select(this.isSelected(row.modelId))
          .selectedColor(this.themePrimary)
          .hitTestBehavior(HitTestMode.None)

        Column() {
          if (this.getRowIconRenderData(row).hasIcon()) {
            if (this.getRowIconRenderData(row).isRawfile()) {
              Image($rawfile(this.getRowIconRenderData(row).resourcePath))
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
            } else {
              Image(this.getRowIconRenderData(row).resourcePath)
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

        Column() {
          Text(row.modelId)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (row.isExisting) {
            Text($r('app.string.model_picker_added'))
              .fontSize(11)
              .fontColor(this.themePrimary)
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10 })
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(this.buildRowRadius(row.groupPosition))
      .onClick(() => {
        this.toggleModel(row.modelId)
      })

      if (this.shouldShowDivider(row.groupPosition)) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 54, right: 12 })
      }
    }
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

  private shouldShowDivider(groupPosition: ModelRowGroupPosition): boolean {
    return groupPosition === ModelRowGroupPosition.FIRST || groupPosition === ModelRowGroupPosition.MIDDLE
  }
}

