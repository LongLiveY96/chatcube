import { KeyboardAvoidMode } from '@kit.ArkUI'
import { ModelProvider, ModelInfo, ModelInfoExtendedJson, ProviderType, ProviderIconType, ApiStyle } from '../models/ChatModels'
import { ModelEditSheet } from '../components/ModelEditSheet'
import { ModelPickerSheetHost } from '../components/ModelPickerSheetHost'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { buildIconResourcePath, getModelIconPath, isNetworkIconPath, isSandboxIconPath } from '../utils/ProviderIconUtils'
import { showToast } from '../utils/ToastUtil'
import { ProviderIcon } from './ProviderIcon'
import { generateDefaultTextIcon } from '../utils/IconGeneratorUtils'
import { getPresetProviderById } from '../config/PresetProviders'
import { ProviderIconEditSheet } from './ProviderIconEditSheet'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { ModelCapabilityMatcher } from '../services/ModelCapabilityMatcher'
import { buildModelIconRenderData, ModelIconRenderData } from '../utils/ModelIconRenderUtils'
import {
  ApiStyleOption,
  ProviderModelGroup,
  getDefaultApiStyleOptions,
  buildProviderModelGroups,
  filterProviderModelsByKeyword
} from '../config/ProviderDetailShared'
import {
  setAllModelsEnabled as applyAllModelsEnabled,
  setGroupModelsEnabled as applyGroupModelsEnabled,
  isAllModelsEnabled as areAllModelsEnabled,
  isGroupAllEnabled as areGroupAllEnabled,
  removeModelById,
  buildSelectedModelsWithPreservedConfig
} from '../config/ProviderModelActions'
import { getAppUiState } from '../state/AppUiState'
import { applyModelDraft } from '../utils/ModelDraftUtils'

export enum ProviderDetailPresentationMode {
  SHEET = 'sheet',
  PAGE = 'page',
  DETAIL_PANE = 'detailPane'
}

enum ProviderModelRenderRowType {
  GROUP_HEADER = 0,
  MODEL = 1
}

interface ProviderModelRenderRow {
  type: ProviderModelRenderRowType
  key: string
  groupIndex: number
  groupName: string
  groupCount: number
  model: ModelInfo | null
  showDivider: boolean
}

let providerDetailInternalBackHandler: (() => boolean) | null = null

@ComponentV2
export struct ProviderDetailPanel {
  @Param providerId: string = ''
  @Param isCreateMode: boolean = false
  @Param closeOnSave: boolean = true
  @Param closeOnModelsSelected: boolean = false
  @Param presentationMode: ProviderDetailPresentationMode = ProviderDetailPresentationMode.SHEET
  @Event onClose: () => void = () => {}
  @Event onProviderChanged: (providerId: string, isCreateMode: boolean) => void = (_providerId: string, _isCreateMode: boolean) => {}
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }

  @Local provider: ModelProvider | null = null
  @Local isLoading: boolean = true
  @Local isTesting: boolean = false
  @Local isFetchingModels: boolean = false
  @Local isSaving: boolean = false
  @Local showApiKey: boolean = false
  @Local searchKeywords: string = ''
  @Local modelGroups: ProviderModelGroup[] = []
  @Local modelRenderRows: ProviderModelRenderRow[] = []
  // 模型编辑相关状态
  @Local showEditSheet: boolean = false
  @Local editingModel: ModelInfo | null = null
  // 模型选择器相关状态
  @Local fetchedModels: string[] = []
  // 统一的弹窗控制：'none' | 'edit' | 'picker' | 'icon'
  @Local activeSheet: string = 'none'
  @Local showSheet: boolean = false
  // 动效触发器
  @Local toggleAllEffectTrigger: number = 0
  // Tab 切换索引
  @Local currentTabIndex: number = 0
  // Tab 图标动效触发器
  @Local configTabEffectTrigger: number = 0
  @Local modelsTabEffectTrigger: number = 0
  // 图标编辑相关状态
  @Local showTextIconEditor: boolean = false
  @Local showColorPicker: boolean = false
  @Local tempTextIcon: string = ''
  @Local tempTextIconBgColor: string = ''
  // 手动添加模型相关状态
  @Local showAddModelInput: boolean = false
  @Local addModelIdText: string = ''

  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()

  // API 风格选项（仅用于自定义服务商）
  private apiStyleOptions: ApiStyleOption[] = getDefaultApiStyleOptions()

  aboutToAppear(): void {
    providerDetailInternalBackHandler = (): boolean => {
      return this.handleInternalBackPressed()
    }
    if (this.isStandalonePagePresentation()) {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    }
    this.loadProviderData()
  }

  aboutToDisappear(): void {
    providerDetailInternalBackHandler = null
    if (this.isStandalonePagePresentation()) {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
    }
  }

  @Monitor('providerId', 'isCreateMode')
  onProviderInputChanged(): void {
    this.searchKeywords = ''
    this.modelGroups = []
    this.provider = null
    this.showEditSheet = false
    this.editingModel = null
    this.showSheet = false
    this.activeSheet = 'none'
    this.fetchedModels = []
    this.showAddModelInput = false
    this.addModelIdText = ''
    this.loadProviderData()
  }

  async loadProviderData(): Promise<void> {
    this.isLoading = true

    if (this.isCreateMode) {
      // 新建模式：创建空白 Provider
      const providerId = `custom_${Date.now()}`
      const provider = new ModelProvider(
        providerId,
        '',
        ProviderType.CUSTOM,
        'message',
        $r('app.color.brand_custom'),
        '',
        ApiStyle.OPENAI
      )
      provider.isConnected = true
      provider.isPreset = false
      // 生成默认文字图标
      const iconConfig = generateDefaultTextIcon('')
      provider.iconType = 'text' as ProviderIconType
      provider.textIcon = iconConfig.text
      provider.textIconBgColor = iconConfig.bgColor
      this.provider = provider
      this.isLoading = false
      return
    }

    // 编辑模式：从数据库加载
    await this.providerViewModel.loadAllProviders()
    const provider = this.providerViewModel.getProviderById(this.providerId)
    if (provider !== null) {
      this.provider = provider
      this.buildModelGroups()
    }
    this.isLoading = false
  }

  // 构建模型分组
  private buildModelGroups(): void {
    if (this.provider === null) {
      this.modelRenderRows = []
      return
    }
    const models = filterProviderModelsByKeyword(this.provider.models, this.searchKeywords)
    this.modelGroups = buildProviderModelGroups(models)
    this.rebuildModelRenderRows()
  }

  private showProviderToast(message: string | Resource, duration: number = 2000): void {
    showToast(this.getUIContext(), message, duration)
  }

  private async saveCurrentProvider(): Promise<void> {
    if (this.provider === null) {
      return
    }
    await this.providerViewModel.saveProvider(this.provider, this.isCreateMode)
  }

  private notifyProviderChanged(): void {
    if (this.provider === null) {
      return
    }
    this.onProviderChanged(this.provider.id, this.isCreateMode)
  }

  private refreshModelGroups(): void {
    this.modelRenderRows = []
    this.modelGroups = []
    this.buildModelGroups()
  }

  private rebuildModelRenderRows(): void {
    const rows: ProviderModelRenderRow[] = []
    for (let groupIndex = 0; groupIndex < this.modelGroups.length; groupIndex++) {
      const group = this.modelGroups[groupIndex]
      rows.push({
        type: ProviderModelRenderRowType.GROUP_HEADER,
        key: `group_${groupIndex}_${group.name}`,
        groupIndex: groupIndex,
        groupName: group.name,
        groupCount: group.models.length,
        model: null,
        showDivider: false
      })
      if (!group.isExpanded) {
        continue
      }
      for (let modelIndex = 0; modelIndex < group.models.length; modelIndex++) {
        rows.push({
          type: ProviderModelRenderRowType.MODEL,
          key: `model_${groupIndex}_${group.models[modelIndex].id}`,
          groupIndex: groupIndex,
          groupName: group.name,
          groupCount: group.models.length,
          model: group.models[modelIndex],
          showDivider: modelIndex < group.models.length - 1
        })
      }
    }
    this.modelRenderRows = rows
  }

  private getModelListCachedCount(): number {
    if (this.modelRenderRows.length >= 120) {
      return 2
    }
    if (this.modelRenderRows.length >= 40) {
      return 3
    }
    return 4
  }

  private getModelIconPathForRender(modelId: string): string {
    return getModelIconPath(modelId, this.provider?.id ?? '', '')
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

  // 测试连接
  async testConnection(): Promise<void> {
    if (this.provider === null || this.isTesting) {
      return
    }

    this.isTesting = true
    this.showProviderToast($r('app.string.provider_testing_connection'), 1500)

    try {
      const result = await this.providerViewModel.testConnection(this.provider)
      if (result.success) {
        this.showProviderToast($r('app.string.connection_success'), 2000)
      } else {
        console.error('ProviderDetailSheet', `[testConnection] failed: ${result.errorMessage}`)
        this.showProviderToast(result.errorMessage !== '' ? result.errorMessage : $r('app.string.connection_failed'), 3000)
      }
    } finally {
      this.isTesting = false
    }
  }

  // 获取模型列表
  async fetchModels(): Promise<void> {
    if (this.provider === null || this.isFetchingModels) {
      return
    }

    this.isFetchingModels = true
    this.showProviderToast($r('app.string.provider_fetching_models'), 1500)

    try {
      const result = await this.providerViewModel.refreshModels(this.provider)
      if (!result.success) {
        console.error('ProviderDetailSheet', `[fetchModels] failed: ${result.errorMessage}`)
        this.showProviderToast(result.errorMessage !== '' ? result.errorMessage : $r('app.string.provider_fetch_models_failed'), 3000)
        return
      }

      if (result.models.length === 0) {
        this.showProviderToast($r('app.string.provider_no_models'), 2000)
        return
      }

      // 打开选择器让用户选择需要保留的模型
      this.fetchedModels = result.models
      this.activeSheet = 'picker'
      this.showSheet = true
      this.showProviderToast($r('app.string.provider_models_refreshed'), 2000)
    } catch (err) {
      console.error('ProviderDetailSheet', `fetchModels error: ${JSON.stringify(err)}`)
      this.showProviderToast($r('app.string.provider_fetch_models_failed'), 3000)
    } finally {
      this.isFetchingModels = false
    }
  }

  // 保存选中的模型
  async saveSelectedModels(selectedIds: string[]): Promise<void> {
    if (this.provider === null) {
      return
    }

    const providerId = this.provider.id
    const existingModelIds = new Set<string>()
    for (let i = 0; i < this.provider.models.length; i++) {
      existingModelIds.add(this.provider.models[i].id)
    }
    const newModels = buildSelectedModelsWithPreservedConfig(this.provider.models, selectedIds)
    const newlyAddedModelIds: string[] = []
    for (let i = 0; i < selectedIds.length; i++) {
      if (!existingModelIds.has(selectedIds[i])) {
        newlyAddedModelIds.push(selectedIds[i])
      }
    }

    // 保留不在 API 列表中的已有模型（如手动添加的模型）
    const fetchedSet = new Set<string>(this.fetchedModels)
    const newModelIdSet = new Set<string>()
    for (let i = 0; i < newModels.length; i++) {
      newModelIdSet.add(newModels[i].id)
    }
    for (let i = 0; i < this.provider.models.length; i++) {
      const model = this.provider.models[i]
      if (!fetchedSet.has(model.id) && !newModelIdSet.has(model.id)) {
        newModels.push(model)
      }
    }

    this.provider.models = newModels

    await this.saveCurrentProvider()

    this.refreshModelGroups()

    // 先关闭内部弹窗
    this.showSheet = false
    this.activeSheet = 'none'

    // 显示提示
    this.showProviderToast($r('app.string.provider_models_selected'), 2000)

    this.notifyProviderChanged()

    if (this.closeOnModelsSelected) {
      // 延迟通知父页面关闭并刷新数据（等待内部弹窗关闭动画完成）
      setTimeout(() => {
        this.onClose()
      }, 200)
    }

    if (newlyAddedModelIds.length > 0) {
      this.applySelectedModelCapabilitiesAsync(providerId, newlyAddedModelIds)
    }
  }

  // 手动添加模型
  async addManualModel(): Promise<void> {
    if (this.provider === null) {
      return
    }
    const modelId = this.addModelIdText.trim()
    if (modelId.length === 0) {
      this.showProviderToast($r('app.string.provider_add_model_id_required'), 2000)
      return
    }
    // 检查重复
    for (let i = 0; i < this.provider.models.length; i++) {
      if (this.provider.models[i].id === modelId) {
        this.showProviderToast($r('app.string.provider_model_id_duplicate'), 2000)
        return
      }
    }
    const model = new ModelInfo(modelId, modelId, 4096, true, false)
    this.provider.models.push(model)
    await this.saveCurrentProvider()
    this.refreshModelGroups()
    this.showAddModelInput = false
    this.addModelIdText = ''
    this.getUIContext().getFocusController().clearFocus()
    this.notifyProviderChanged()
    // 自动打开编辑面板
    this.editingModel = model
    this.activeSheet = 'edit'
    this.showSheet = true
    // 异步匹配能力
    this.applySelectedModelCapabilitiesAsync(this.provider.id, [modelId])
  }

  private applySelectedModelCapabilitiesAsync(providerId: string, modelIds: string[]): void {
    this.applySelectedModelCapabilities(providerId, modelIds).catch((error: Object) => {
      console.warn('ProviderDetailSheet', `[applySelectedModelCapabilitiesAsync] skipped: ${JSON.stringify(error)}`)
    })
  }

  private async applySelectedModelCapabilities(providerId: string, modelIds: string[]): Promise<void> {
    if (modelIds.length === 0) {
      return
    }
    const provider = await this.providerViewModel.getProviderByIdAsync(providerId)
    if (provider === null) {
      return
    }

    const targetModels: ModelInfo[] = []
    for (let i = 0; i < provider.models.length; i++) {
      if (modelIds.includes(provider.models[i].id)) {
        targetModels.push(provider.models[i])
      }
    }
    if (targetModels.length === 0) {
      return
    }

    const matchedCount = await ModelCapabilityMatcher.getInstance().applyCapabilitiesBatch(targetModels)
    if (matchedCount <= 0) {
      return
    }

    await this.providerViewModel.saveProvider(provider)
    if (this.provider !== null && this.provider.id === providerId) {
      this.provider = provider
      this.refreshModelGroups()
      this.notifyProviderChanged()
    }
  }

  // 删除单个模型
  async deleteModel(model: ModelInfo): Promise<void> {
    if (this.provider === null) {
      return
    }

    this.provider.models = removeModelById(this.provider.models, model.id)

    await this.saveCurrentProvider()
    this.refreshModelGroups()
    this.notifyProviderChanged()

    console.info('ProviderDetailSheet', `[deleteModel] deleted model: ${model.name}`)
    this.showProviderToast($r('app.string.provider_model_deleted'))
  }

  // 保存配置并关闭
  async saveConfigAndClose(): Promise<void> {
    if (this.provider === null || this.isSaving) {
      return
    }

    // 新建模式校验
    if (this.isCreateMode) {
      if (this.provider.name.trim() === '') {
        this.showProviderToast($r('app.string.provider_name_required'), 3000)
        return
      }
      if (this.provider.baseUrl.trim() === '') {
        this.showProviderToast($r('app.string.base_url_required'), 3000)
        return
      }
    }

    this.isSaving = true
    try {
      await this.saveCurrentProvider()
      if (this.isCreateMode) {
        this.showProviderToast($r('app.string.provider_added'), 1500)
      } else {
        this.showProviderToast($r('app.string.config_saved'), 1500)
      }
      this.notifyProviderChanged()
      if (this.closeOnSave) {
        this.onClose()
      }
    } finally {
      this.isSaving = false
    }
  }

  // 切换供应商启用状态
  async toggleEnabled(): Promise<void> {
    if (this.provider === null) {
      return
    }

    this.provider.isConnected = !this.provider.isConnected
    await this.providerViewModel.updateProviderEnabled(this.provider.id, this.provider.isConnected)
    this.notifyProviderChanged()

    this.showProviderToast(
      this.provider.isConnected ? $r('app.string.provider_enabled') : $r('app.string.provider_disabled'),
      2000
    )
  }

  // 切换分组展开状态
  private toggleGroupExpansion(index: number): void {
    if (index >= 0 && index < this.modelGroups.length) {
      // 使用 animateTo 实现平滑动画
      this.getUIContext().animateTo({
        duration: 300,
        curve: Curve.EaseInOut
      }, () => {
        this.modelGroups[index] = {
          name: this.modelGroups[index].name,
          models: this.modelGroups[index].models,
          isExpanded: !this.modelGroups[index].isExpanded
        }
        this.rebuildModelRenderRows()
      })
    }
  }

  // 一键开启所有模型
  private async enableAllModels(): Promise<void> {
    if (this.provider === null) {
      return
    }
    this.provider.models = applyAllModelsEnabled(this.provider.models, true)
    await this.saveCurrentProvider()
    this.refreshModelGroups()
    this.showProviderToast($r('app.string.provider_all_models_enabled'))
  }

  // 一键关闭所有模型
  private async disableAllModels(): Promise<void> {
    if (this.provider === null) {
      return
    }
    this.provider.models = applyAllModelsEnabled(this.provider.models, false)
    await this.saveCurrentProvider()
    this.refreshModelGroups()
    this.showProviderToast($r('app.string.provider_all_models_disabled'))
  }

  // 一键开启分组内所有模型
  private async enableGroupModels(groupIndex: number): Promise<void> {
    if (this.provider === null || groupIndex < 0 || groupIndex >= this.modelGroups.length) {
      return
    }
    const group = this.modelGroups[groupIndex]
    applyGroupModelsEnabled(group, true)
    await this.saveCurrentProvider()
    this.refreshModelGroups()
    this.showProviderToast($r('app.string.provider_group_models_enabled'))
  }

  // 一键关闭分组内所有模型
  private async disableGroupModels(groupIndex: number): Promise<void> {
    if (this.provider === null || groupIndex < 0 || groupIndex >= this.modelGroups.length) {
      return
    }
    const group = this.modelGroups[groupIndex]
    applyGroupModelsEnabled(group, false)
    await this.saveCurrentProvider()
    this.refreshModelGroups()
    this.showProviderToast($r('app.string.provider_group_models_disabled'))
  }

  // 检查是否所有模型都已开启
  private isAllModelsEnabled(): boolean {
    if (this.provider === null) {
      return false
    }
    return areAllModelsEnabled(this.provider.models)
  }

  // 检查分组内是否所有模型都已开启
  private isGroupAllEnabled(groupIndex: number): boolean {
    if (groupIndex < 0 || groupIndex >= this.modelGroups.length) {
      return false
    }
    return areGroupAllEnabled(this.modelGroups[groupIndex])
  }

  private updateModelEnabled(modelId: string, isEnabled: boolean): void {
    this.updateModelEnabledAsync(modelId, isEnabled).catch((error: Object) => {
      console.error('ProviderDetailSheet', `[updateModelEnabled] failed: ${JSON.stringify(error)}`)
      this.showProviderToast($r('app.string.action_failed_retry'))
      this.refreshModelGroups()
    })
  }

  private async updateModelEnabledAsync(modelId: string, isEnabled: boolean): Promise<void> {
    if (this.provider === null) {
      return
    }

    let changed = false
    for (let i = 0; i < this.provider.models.length; i++) {
      const model = this.provider.models[i]
      if (model.id === modelId) {
        if (model.isEnabled !== isEnabled) {
          model.isEnabled = isEnabled
          changed = true
        }
        break
      }
    }

    if (!changed) {
      return
    }

    await this.saveCurrentProvider()
    this.refreshModelGroups()
    this.notifyProviderChanged()
  }

  // 打开模型编辑弹窗
  private openModelEditSheet(model: ModelInfo): void {
    this.editingModel = model
    this.activeSheet = 'edit'
    this.showSheet = true
  }

  // 保存模型编辑
  private async saveModelEdit(draft: ModelInfoExtendedJson): Promise<void> {
    if (this.provider === null || this.editingModel === null) {
      return
    }

    applyModelDraft(this.editingModel, draft)
    await this.saveCurrentProvider()
    this.showProviderToast($r('app.string.provider_model_saved'))
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.showSheet = false
      this.activeSheet = 'none'
    })
    this.editingModel = null
    this.refreshModelGroups()
    this.notifyProviderChanged()
  }

  // 取消模型编辑
  private cancelModelEdit(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.showSheet = false
      this.activeSheet = 'none'
    })
    this.editingModel = null
  }

  // 显示删除确认对话框
  private showDeleteConfirmDialog(): void {
    if (this.provider === null) {
      return
    }
    const providerId = this.provider.id
    this.getUIContext().showAlertDialog({
      title: $r('app.string.delete_provider_title'),
      message: $r('app.string.delete_provider_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
          // 取消操作
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: Color.Red,
        action: async () => {
          await this.providerViewModel.deleteProvider(providerId)
          showToast(this.getUIContext(), $r('app.string.provider_deleted'))
          this.onProviderChanged(providerId, false)
          this.onClose()
        }
      }
    })
  }

  // 清理编辑状态
  private clearEditState(): void {
    this.editingModel = null
    this.activeSheet = 'none'
    this.fetchedModels = []
  }

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private isStandalonePagePresentation(): boolean {
    return this.presentationMode === ProviderDetailPresentationMode.PAGE
  }

  private getCurrentApiStyleName(): string {
    const currentStyle = this.provider?.apiStyle
    for (let i = 0; i < this.apiStyleOptions.length; i++) {
      if (this.apiStyleOptions[i].style === currentStyle) {
        return this.apiStyleOptions[i].name
      }
    }
    return 'OpenAI'
  }

  private headerLeadingSymbol(): Resource {
    if (this.isStandalonePagePresentation()) {
      return $r('sys.symbol.chevron_left')
    }
    return $r('sys.symbol.xmark')
  }

  private headerSaveSymbol(): Resource {
    if (this.isStandalonePagePresentation()) {
      return $r('sys.symbol.save')
    }
    return $r('sys.symbol.checkmark')
  }

  private closeActionLabel(): Resource {
    if (this.isStandalonePagePresentation()) {
      return $r('app.string.action_back')
    }
    return $r('app.string.action_close')
  }

  private handleInternalBackPressed(): boolean {
    if (this.showTextIconEditor) {
      this.showTextIconEditor = false
      this.showColorPicker = false
      return true
    }
    if (this.showSheet) {
      this.showSheet = false
      this.activeSheet = 'none'
      return true
    }
    return false
  }

  build() {
    Column() {
      // 自定义头部
      this.SheetHeader()

      if (this.isLoading) {
        this.LoadingView()
      } else if (this.provider === null) {
        this.ErrorView()
      } else {
        // 供应商头部卡片（始终可见）
        this.ProviderHeaderCard()

        if (this.isStandalonePagePresentation()) {
          this.PageSectionTabs()

          if (this.currentTabIndex === 0) {
            Scroll() {
              Column() {
                this.ApiConfigCard()

                Column().height(12)
              }
              .width('100%')
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .align(Alignment.Top)
          } else {
            Column() {
              this.ModelsCard()
            }
            .width('100%')
            .layoutWeight(1)
          }
        } else {
          // Tab 分区：配置 | 模型（原生悬浮 Tab 栏）
          Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
            TabContent() {
              Scroll() {
                Column() {
                  this.ApiConfigCard()

                  Column().height(20)
                }
                .width('100%')
              }
              .width('100%')
              .height('100%')
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .align(Alignment.Top)
            }
            .tabBar(this.ConfigTabBuilder())

            TabContent() {
              Column() {
                this.ModelsCard()
              }
              .width('100%')
              .height('100%')
            }
            .tabBar(this.ModelsTabBuilder())
          }
          .layoutWeight(1)
          .barOverlap(false)
          .barBackgroundBlurStyle(BlurStyle.Thin)
          .animationDuration(300)
          .onChange((index: number) => {
            this.currentTabIndex = index
            if (index === 0) {
              this.configTabEffectTrigger++
            } else {
              this.modelsTabEffectTrigger++
            }
          })
        }
      }

      // 单独的 Sheet 宿主，避免详情面板内容切换时误触发关闭
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showSheet, this.UnifiedSheetBuilder(), {
          height: SheetSize.LARGE,
          showClose: false,
          dragBar: true,
          blurStyle: BlurStyle.Regular,
          shouldDismiss: (dismissAction: SheetDismiss) => {
            dismissAction.dismiss()
          },
          onDisappear: () => {
            this.clearEditState()
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isStandalonePagePresentation() ? $r('app.color.background') : Color.Transparent)
  }

  @Builder
  ConfigTabBuilder() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(16)
        .fontColor([this.currentTabIndex === 0 ? $r('app.color.text_primary') : $r('app.color.text_tertiary')])
        .symbolEffect(new ScaleSymbolEffect(EffectScope.WHOLE), this.configTabEffectTrigger)
      Text($r('app.string.provider_tab_config'))
        .fontSize(14)
        .fontColor(this.currentTabIndex === 0 ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
        .fontWeight(this.currentTabIndex === 0 ? FontWeight.Bold : FontWeight.Normal)
    }
    .justifyContent(FlexAlign.Center)
    .height('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  ModelsTabBuilder() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.satellite_map'))
        .fontSize(16)
        .fontColor([this.currentTabIndex === 1 ? $r('app.color.text_primary') : $r('app.color.text_tertiary')])
        .symbolEffect(new ScaleSymbolEffect(EffectScope.WHOLE), this.modelsTabEffectTrigger)
      Text($r('app.string.provider_tab_models'))
        .fontSize(14)
        .fontColor(this.currentTabIndex === 1 ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
        .fontWeight(this.currentTabIndex === 1 ? FontWeight.Bold : FontWeight.Normal)
    }
    .justifyContent(FlexAlign.Center)
    .height('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  PageSectionTabs() {
    Row({ space: 20 }) {
      this.PageSectionTabButton(0, $r('app.string.provider_tab_config'))
      this.PageSectionTabButton(1, $r('app.string.provider_tab_models'))
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 2, bottom: 2 })
  }

  @Builder
  PageSectionTabButton(index: number, title: Resource) {
    Button() {
      Column({ space: 6 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(this.currentTabIndex === index ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.currentTabIndex === index ? $r('app.color.text_primary') : $r('app.color.text_secondary'))

        Column()
          .width(this.currentTabIndex === index ? 24 : 14)
          .height(3)
          .borderRadius(2)
          .backgroundColor(this.currentTabIndex === index ? this.themePrimary : Color.Transparent)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .type(ButtonType.Normal)
    .stateEffect(false)
    .padding({ left: 0, right: 0, top: 4, bottom: 4 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (this.currentTabIndex === index) {
        return
      }
      this.currentTabIndex = index
    })
  }

  @Builder
  SheetHeader() {
    if (this.isStandalonePagePresentation()) {
      Column({ space: 6 }) {
        Column()
          .width('100%')
          .height(this.px2vp(this.topAvoidHeight))

        Row({ space: 8 }) {
          Button() {
            SymbolGlyph(this.headerLeadingSymbol())
              .fontSize(18)
              .fontColor([$r('app.color.text_primary')])
          }
          .type(ButtonType.Normal)
          .stateEffect(false)
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onClose()
          })

          Column({ space: 2 }) {
            Text($r('app.string.provider_detail_title'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text(this.currentTabIndex === 0 ? $r('app.string.provider_api_config') : $r('app.string.provider_models_manage'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (!this.isCreateMode && this.provider !== null && !this.provider.isPreset) {
            Button() {
              SymbolGlyph($r('sys.symbol.clean'))
                .fontSize(18)
                .fontColor([$r('app.color.status_error')])
            }
            .type(ButtonType.Circle)
            .width(36)
            .height(36)
            .backgroundColor($r('app.color.divider'))
            .onClick(() => {
              this.showDeleteConfirmDialog()
            })
          }

          Button() {
            SymbolGlyph(this.headerSaveSymbol())
              .fontSize(18)
              .fontColor([Color.White])
          }
          .type(ButtonType.Circle)
          .width(36)
          .height(36)
          .backgroundColor(this.themePrimary)
          .onClick(() => {
            this.saveConfigAndClose()
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 6 })
      .backgroundColor($r('app.color.background'))
    } else {
      Row() {
        // 关闭按钮
        Button() {
          SymbolGlyph(this.headerLeadingSymbol())
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.onClose()
        })

        // 标题
        Text(this.isCreateMode ? $r('app.string.add_custom_provider') :
          (this.provider?.name ?? $r('app.string.provider_detail_title')))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 删除按钮（非创建模式且非预置服务商）
        if (!this.isCreateMode && this.provider !== null && !this.provider.isPreset) {
          Button() {
            SymbolGlyph($r('sys.symbol.clean'))
              .fontSize(18)
              .fontColor([$r('app.color.status_error')])
          }
          .type(ButtonType.Circle)
          .width(36)
          .height(36)
          .backgroundColor($r('app.color.divider'))
          .margin({ right: 8 })
          .onClick(() => {
            this.showDeleteConfirmDialog()
          })
        }

        // 保存按钮
        Button() {
          SymbolGlyph(this.headerSaveSymbol())
            .fontSize(18)
            .fontColor([Color.White])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor(this.themePrimary)
        .onClick(() => {
          this.saveConfigAndClose()
        })
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
    }
  }

  @Builder
  LoadingView() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(this.themePrimary)

      Text($r('app.string.loading'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ErrorView() {
    Column() {
      SymbolGlyph($r('sys.symbol.xmark_circle'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])

      Text($r('app.string.provider_detail_not_found'))
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 16 })

      Button() {
        Text(this.closeActionLabel())
          .fontSize(14)
          .fontColor(this.themePrimary)
      }
        .backgroundColor(this.themePrimaryLight)
        .borderRadius(20)
        .height(40)
        .padding({ left: 24, right: 24 })
        .margin({ top: 24 })
        .onClick(() => {
          this.onClose()
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ProviderHeaderCard() {
    if (this.isStandalonePagePresentation()) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 12 }) {
          Row({ space: 12 }) {
            if (this.provider !== null) {
              ProviderIcon({
                iconType: this.provider.iconType,
                iconPath: this.provider.iconPath,
                textIcon: this.provider.textIcon,
                textIconBgColor: this.provider.textIconBgColor,
                customImagePath: this.provider.customImagePath,
                iconSize: 48,
                radius: 12,
                bgColor: $r('app.color.divider'),
                brandColor: this.provider.brandColor,
                fallbackSymbol: $r('sys.symbol.cloud'),
                fallbackColor: $r('app.color.text_secondary')
              })
                .onClick(() => {
                  this.openIconEditor()
                })
                .bindSheet($$this.showTextIconEditor, this.IconEditSheetBuilder(), {
                  height: 450,
                  showClose: false,
                  onDisappear: () => {
                    this.showTextIconEditor = false
                    this.showColorPicker = false
                  }
                })
            }

            Column({ space: 2 }) {
              if (this.isCreateMode) {
                TextInput({ text: this.provider?.name ?? '', placeholder: $r('app.string.provider_name_placeholder') })
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor(Color.Transparent)
                  .borderRadius(0)
                  .padding({ left: 8, right: 4, top: 0, bottom: 0 })
                  .onChange((value: string) => {
                    if (this.provider !== null) {
                      this.provider.name = value
                      if (this.provider.iconType === 'text') {
                        const config = generateDefaultTextIcon(value)
                        this.provider.textIcon = config.text
                      }
                    }
                  })
              } else if (this.provider !== null && !this.provider.isPreset) {
                TextInput({ text: this.provider?.name ?? '', placeholder: $r('app.string.provider_name_placeholder') })
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor(Color.Transparent)
                  .borderRadius(0)
                  .padding({ left: 8, right: 4, top: 0, bottom: 0 })
                  .onChange((value: string) => {
                    if (this.provider !== null) {
                      this.provider.name = value
                    }
                  })
              } else {
                Text(this.provider?.name ?? '')
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ left: 8 })
                  .maxLines(1)
              }

              Text(this.provider?.baseUrl ?? '')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 8 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            if (this.provider?.id !== 'siliconflow') {
              Toggle({ type: ToggleType.Switch, isOn: this.provider?.isConnected ?? false })
                .selectedColor(this.themePrimary)
                .onChange((isOn: boolean) => {
                  if (this.provider !== null && this.provider.isConnected !== isOn) {
                    this.toggleEnabled()
                  }
                })
            }
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')

          Row({ space: 8 }) {
            Row({ space: 6 }) {
              SymbolGlyph((this.provider?.isConnected ?? false) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.xmark_circle'))
                .fontSize(12)
                .fontColor([(this.provider?.isConnected ?? false) ? this.themePrimary : $r('app.color.text_secondary')])
              Text((this.provider?.isConnected ?? false) ? $r('app.string.provider_enabled') : $r('app.string.provider_disabled'))
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor((this.provider?.isConnected ?? false) ? this.themePrimary : $r('app.color.text_secondary'))
            }
            .padding({ left: 8, right: 8, top: 5, bottom: 5 })
            .backgroundColor((this.provider?.isConnected ?? false) ? this.themePrimaryLight : $r('app.color.background'))
            .borderRadius(14)

            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.gearshape'))
                .fontSize(12)
                .fontColor([$r('app.color.text_secondary')])
              Text(this.getCurrentApiStyleName())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
            }
            .padding({ left: 8, right: 8, top: 5, bottom: 5 })
            .backgroundColor($r('app.color.background'))
            .borderRadius(14)

            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.satellite_map'))
                .fontSize(12)
                .fontColor([$r('app.color.text_secondary')])
              Text(`${this.provider?.models.length ?? 0}`)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
            }
            .padding({ left: 8, right: 8, top: 5, bottom: 5 })
            .backgroundColor($r('app.color.background'))
            .borderRadius(14)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 14 })
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(20)
      .clip(true)
      .margin({ left: 16, right: 16, top: 2, bottom: 4 })
    } else {
      Column() {
        Row() {
          // 供应商图标（使用 ProviderIcon 组件支持所有图标类型）
          if (this.provider !== null) {
            ProviderIcon({
              iconType: this.provider.iconType,
              iconPath: this.provider.iconPath,
              textIcon: this.provider.textIcon,
              textIconBgColor: this.provider.textIconBgColor,
              customImagePath: this.provider.customImagePath,
              iconSize: 44,
              radius: 11,
              bgColor: $r('app.color.divider'),
              brandColor: this.provider.brandColor,
              fallbackSymbol: $r('sys.symbol.cloud'),
              fallbackColor: $r('app.color.text_secondary')
            })
              .onClick(() => {
                this.openIconEditor()
              })
              .bindSheet($$this.showTextIconEditor, this.IconEditSheetBuilder(), {
                height: 450,
                showClose: false,
                onDisappear: () => {
                  this.showTextIconEditor = false
                  this.showColorPicker = false
                }
              })
          }

          Column() {
            if (this.isCreateMode) {
              TextInput({ text: this.provider?.name ?? '', placeholder: $r('app.string.provider_name_placeholder') })
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor(Color.Transparent)
                .borderRadius(0)
                .padding({ left: 8, right: 4, top: 0, bottom: 0 })
                .onChange((value: string) => {
                  if (this.provider !== null) {
                    this.provider.name = value
                    // 自动更新文字图标
                    if (this.provider.iconType === 'text') {
                      const config = generateDefaultTextIcon(value)
                      this.provider.textIcon = config.text
                    }
                  }
                })
            } else if (this.provider !== null && !this.provider.isPreset) {
              TextInput({ text: this.provider?.name ?? '', placeholder: $r('app.string.provider_name_placeholder') })
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor(Color.Transparent)
                .borderRadius(0)
                .padding({ left: 8, right: 4, top: 0, bottom: 0 })
                .onChange((value: string) => {
                  if (this.provider !== null) {
                    this.provider.name = value
                  }
                })
            } else {
              Text(this.provider?.name ?? '')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .margin({ left: 8 })
            }

            Text(this.provider?.baseUrl ?? '')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 8, top: 2 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 10 })
          .layoutWeight(1)

          // 启用开关（系统服务不可禁用）
          if (this.provider?.id !== 'siliconflow') {
            Toggle({ type: ToggleType.Switch, isOn: this.provider?.isConnected ?? false })
              .selectedColor(this.themePrimary)
              .onChange((isOn: boolean) => {
                // 只有当状态真正改变时才处理（避免重复触发）
                if (this.provider !== null && this.provider.isConnected !== isOn) {
                  this.toggleEnabled()
                }
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(16)
      .margin({ left: 16, right: 16, top: 4 })
    }
  }

  @Builder
  PageMetaBadge(symbol: Resource, label: string | Resource, accent: boolean = false) {
    Row({ space: 6 }) {
      SymbolGlyph(symbol)
        .fontSize(12)
        .fontColor([accent ? this.themePrimary : $r('app.color.text_secondary')])
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(accent ? this.themePrimary : $r('app.color.text_secondary'))
    }
    .padding({ left: 8, right: 8, top: 5, bottom: 5 })
    .backgroundColor(accent ? this.themePrimaryLight : $r('app.color.background'))
    .borderRadius(14)
  }

  @Builder
  ApiConfigCard() {
    Column() {
      // 标题
      Text($r('app.string.provider_api_config'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 12 })

      // API 风格选择
      if (this.provider !== null) {
        Column() {
          Text($r('app.string.api_style'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')

          Column() {
            ForEach(this.apiStyleOptions, (option: ApiStyleOption, index: number) => {
              Row() {
                Radio({ value: option.style, group: 'apiStyleSheet' })
                  .checked(this.provider?.apiStyle === option.style)
                  .onChange((isChecked: boolean) => {
                    if (isChecked && this.provider !== null) {
                      this.provider.apiStyle = option.style
                    }
                  })

                Column() {
                  Text(option.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))

                  Text(option.description)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 8 })
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 10, bottom: 10 })
              .onClick(() => {
                if (this.provider !== null) {
                  this.provider.apiStyle = option.style
                }
              })

              if (index < this.apiStyleOptions.length - 1) {
                Divider().color($r('app.color.divider')).margin({ left: 40 })
              }
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.background'))
          .borderRadius(8)
          .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 16, right: 16, top: 16, bottom: 16 })
      }

      if (this.provider !== null && !this.provider.isPreset) {
        Column() {
          Row() {
            Column() {
              Text($r('app.string.provider_requires_api_key'))
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))

              Text($r('app.string.provider_requires_api_key_desc'))
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.provider.requiresApiKey })
              .selectedColor(this.themePrimary)
              .onChange((isOn: boolean) => {
                if (this.provider !== null) {
                  this.provider.requiresApiKey = isOn
                }
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 16, right: 16, top: 16, bottom: 16 })
      }

      // API Key
      Column() {
        Row() {
          Text($r('app.string.api_key'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          if (this.provider?.requiresApiKey ?? true) {
            Text(' *')
              .fontSize(13)
              .fontColor(Color.Red)
          }
        }
        .width('100%')

        Row() {
          TextInput({ text: this.provider?.apiKey ?? '', placeholder: $r('app.string.provider_api_key_placeholder') })
            .type(InputType.Password)
            .enableAutoFill(false)
            .showPasswordIcon(true)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onChange((value: string) => {
              if (this.provider !== null) {
                this.provider.apiKey = value
              }
            })

          // 测试按钮
          Button() {
            if (this.isTesting) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(this.themePrimary)
            } else {
              Text($r('app.string.test_connection'))
                .fontSize(13)
                .fontColor(this.themePrimary)
            }
          }
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.themePrimaryLight)
          .borderRadius(16)
          .margin({ left: 8 })
          .enabled(!this.isTesting)
          .onClick(() => {
            this.testConnection()
          })
        }
        .width('100%')
        .height(48)
        .backgroundColor($r('app.color.background'))
        .borderRadius(8)
        .padding({ left: 12, right: 8 })
        .margin({ top: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Divider()
        .color($r('app.color.divider'))
        .margin({ left: 16, right: 16, top: 16, bottom: 16 })

      // API Base URL
      Column() {
        Row() {
          Text($r('app.string.base_url'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text(' *')
            .fontSize(13)
            .fontColor(Color.Red)
        }
        .width('100%')

        TextInput({ text: this.provider?.baseUrl ?? '', placeholder: $r('app.string.provider_base_url_placeholder') })
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.background'))
          .borderRadius(8)
          .height(48)
          .width('100%')
          .padding({ left: 12, right: 12 })
          .margin({ top: 8 })
          .onChange((value: string) => {
            if (this.provider !== null) {
              this.provider.baseUrl = value
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Divider()
        .color($r('app.color.divider'))
        .margin({ left: 16, right: 16, top: 16, bottom: 16 })

      // API 路径（可选）
      Column() {
        Text($r('app.string.api_path_optional'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        TextInput({ text: this.provider?.apiPath ?? '', placeholder: $r('app.string.provider_api_path_placeholder') })
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.background'))
          .borderRadius(8)
          .height(48)
          .width('100%')
          .padding({ left: 12, right: 12 })
          .margin({ top: 8 })
          .onChange((value: string) => {
            if (this.provider !== null) {
              this.provider.apiPath = value
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
  }
  .width('100%')
  .backgroundColor($r('app.color.surface'))
  .borderRadius(16)
  .margin({ left: 16, right: 16, top: 8 })
}

@Builder
ModelsCard() {
    Column() {
      // 标题行
      Row() {
        Text($r('app.string.provider_models_manage'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Text(` (${this.provider?.models.length ?? 0})`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))

        Blank()

        // 一键开关按钮
        if (this.provider !== null && this.provider.models.length > 0) {
          Button() {
            Row() {
              SymbolGlyph(this.isAllModelsEnabled() ? $r('sys.symbol.xmark_circle') : $r('sys.symbol.checkmark_circle'))
                .fontSize(14)
                .fontColor([this.isAllModelsEnabled() ? $r('app.color.text_tertiary') : this.themePrimary])
                .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), this.toggleAllEffectTrigger)
              Text(this.isAllModelsEnabled() ? $r('app.string.provider_disable_all') : $r('app.string.provider_enable_all'))
                .fontSize(13)
                .fontColor(this.isAllModelsEnabled() ? $r('app.color.text_tertiary') : this.themePrimary)
                .margin({ left: 4 })
            }
          }
          .height(32)
          .padding({ left: 10, right: 10 })
          .backgroundColor(this.isAllModelsEnabled() ? $r('app.color.background') : this.themePrimaryLight)
          .borderRadius(16)
          .margin({ right: 8 })
          .onClick(() => {
            // 触发切换动效
            this.toggleAllEffectTrigger++
            if (this.isAllModelsEnabled()) {
              this.disableAllModels()
            } else {
              this.enableAllModels()
            }
          })
        }

        // 手动添加模型按钮
        Button() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(14)
            .fontColor([this.themePrimary])
        }
        .type(ButtonType.Circle)
        .width(32)
        .height(32)
        .backgroundColor(this.themePrimaryLight)
        .margin({ right: 8 })
        .onClick(() => {
          this.showAddModelInput = !this.showAddModelInput
          if (!this.showAddModelInput) {
            this.addModelIdText = ''
          }
        })

        // 获取模型按钮
        Button() {
          Row() {
            if (this.isFetchingModels) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(this.themePrimary)
            } else {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(14)
                .fontColor([this.themePrimary])
            }
            Text(this.isFetchingModels ? $r('app.string.provider_fetching') : $r('app.string.provider_fetch_models'))
              .fontSize(13)
              .fontColor(this.themePrimary)
              .margin({ left: 4 })
          }
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.themePrimaryLight)
        .borderRadius(16)
        .enabled(!this.isFetchingModels)
        .onClick(() => {
          this.fetchModels()
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 搜索框
      Search({ value: this.searchKeywords, placeholder: $r('app.string.filter_models_placeholder') })
        .width('100%')
        .height(40)
        .backgroundColor($r('app.color.background'))
        .margin({ left: 16, right: 16 })
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.searchKeywords = value
          this.buildModelGroups()
        })

      // 手动添加模型输入行
      if (this.showAddModelInput) {
        Row({ space: 8 }) {
          TextInput({ text: this.addModelIdText, placeholder: $r('app.string.provider_add_model_placeholder') })
            .layoutWeight(1)
            .height(36)
            .fontSize(14)
            .backgroundColor($r('app.color.background'))
            .borderRadius(8)
            .onChange((value: string) => {
              this.addModelIdText = value
            })
            .onSubmit(() => {
              this.addManualModel()
            })

          Button() {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(16)
              .fontColor([this.themePrimary])
          }
          .type(ButtonType.Circle)
          .width(36)
          .height(36)
          .backgroundColor(this.themePrimaryLight)
          .onClick(() => {
            this.addManualModel()
          })

          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .type(ButtonType.Circle)
          .width(36)
          .height(36)
          .backgroundColor($r('app.color.background'))
          .onClick(() => {
            this.showAddModelInput = false
            this.addModelIdText = ''
            this.getUIContext().getFocusController().clearFocus()
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }

      // 模型分组列表
      if (this.modelRenderRows.length > 0) {
        List() {
          Repeat<ProviderModelRenderRow>(this.modelRenderRows)
            .each((ri: RepeatItem<ProviderModelRenderRow>) => {
              if (ri.item.type === ProviderModelRenderRowType.GROUP_HEADER) {
                ListItem() {
                  Row() {
                    Row() {
                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(14)
                        .fontColor([$r('app.color.text_tertiary')])
                        .rotate({ angle: (ri.item.groupIndex < this.modelGroups.length &&
                          this.modelGroups[ri.item.groupIndex].isExpanded) ? 90 : 0 })
                        .animation({ duration: 200 })

                      Text(ri.item.groupName)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ left: 8 })

                      Text(` (${ri.item.groupCount})`)
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                    }
                    .layoutWeight(1)
                    .onClick(() => {
                      this.toggleGroupExpansion(ri.item.groupIndex)
                    })

                    Button() {
                      SymbolGlyph(this.isGroupAllEnabled(ri.item.groupIndex)
                        ? $r('sys.symbol.xmark_circle')
                        : $r('sys.symbol.checkmark_circle'))
                        .fontSize(16)
                        .fontColor([this.isGroupAllEnabled(ri.item.groupIndex)
                          ? $r('app.color.text_tertiary')
                          : this.themePrimary])
                    }
                    .type(ButtonType.Circle)
                    .width(32)
                    .height(32)
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                      if (this.isGroupAllEnabled(ri.item.groupIndex)) {
                        this.disableGroupModels(ri.item.groupIndex)
                      } else {
                        this.enableGroupModels(ri.item.groupIndex)
                      }
                    })
                  }
                  .width('100%')
                  .height(44)
                  .padding({ left: 16, right: 8 })
                }
              } else if (ri.item.model !== null) {
                ListItem() {
                  ModelItemCard({
                    model: ri.item.model,
                    showDivider: ri.item.showDivider,
                    providerId: this.provider?.id ?? '',
                    onToggle: (modelId: string, isOn: boolean) => {
                      this.updateModelEnabled(modelId, isOn)
                    },
                    onEdit: () => {
                      this.openModelEditSheet(ri.item.model!)
                    }
                  })
                }
                .swipeAction({
                  end: {
                    builder: () => {
                      this.DeleteButton(ri.item.model!)
                    }
                  }
                })
              }
            })
            .key((row: ProviderModelRenderRow) => row.key)
            .virtualScroll({ totalCount: this.modelRenderRows.length })

          ListItem() {
            Column().height(16)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 8 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(this.getModelListCachedCount())
      } else if (this.provider !== null && this.provider.models.length === 0) {
        // 无模型提示
        Column() {
          SymbolGlyph($r('sys.symbol.square_stack_3d'))
            .fontSize(40)
            .fontColor([$r('app.color.text_tertiary')])

          Text($r('app.string.provider_no_models'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })

          Text($r('app.string.provider_no_models_hint'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ top: 40, bottom: 40 })
      } else {
        // 搜索无结果
        Column() {
          Text($r('app.string.provider_models_not_found'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 40, bottom: 40 })
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .margin({ left: 16, right: 16, top: 8 })
  }


  @Builder
  UnifiedSheetBuilder() {
    if (this.activeSheet === 'edit' && this.editingModel !== null) {
      ModelEditSheet({
        model: this.editingModel,
        onSave: async (draft: ModelInfoExtendedJson): Promise<void> => {
          await this.saveModelEdit(draft)
        },
        onCancel: () => {
          this.cancelModelEdit()
        }
      })
    } else if (this.activeSheet === 'picker' && this.provider !== null) {
      ModelPickerSheetHost({
        availableModels: this.fetchedModels,
        existingModels: this.provider.models,
        providerId: this.provider.id,
        onConfirm: (selectedIds: string[]) => {
          this.saveSelectedModels(selectedIds)
        },
        onCancel: () => {
          this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
            this.showSheet = false
            this.activeSheet = 'none'
          })
        }
      })
    } else {
      // 默认分支：提供背景色占位，避免关闭动画时黑屏
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
    }
  }

  @Builder
  DeleteButton(model: ModelInfo) {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([Color.White])
      }
      .width(56)
      .height(48)
      .backgroundColor($r('app.color.status_error'))
      .borderRadius(12)
      .onClick(() => {
        this.deleteModel(model)
      })
    }
    .padding({ left: 8, right: 8 })
    .height(56)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  IconEditSheetBuilder() {
    ProviderIconEditSheet({
      tempTextIcon: this.tempTextIcon!!,
      tempTextIconBgColor: this.tempTextIconBgColor!!,
      provider: this.provider,
      onSave: () => {
        this.saveIconConfig()
      },
      onResetToPreset: () => {
        this.resetToPresetIcon()
      },
      onClose: () => {
        this.showTextIconEditor = false
      }
    })
  }

  // ========== 图标编辑相关方法 ==========

  // 打开图标编辑器
  private openIconEditor(): void {
    if (this.provider === null) {
      return
    }
    // 初始化临时变量
    if (this.provider.iconType === 'text') {
      this.tempTextIcon = this.provider.textIcon
      this.tempTextIconBgColor = this.provider.textIconBgColor
      this.showTextIconEditor = true
    } else {
      // 对于其他类型，先切换到文字图标模式
      const config = generateDefaultTextIcon(this.provider.name)
      this.tempTextIcon = config.text
      this.tempTextIconBgColor = config.bgColor
      this.showTextIconEditor = true
    }
  }

  // 保存图标配置
  private async saveIconConfig(): Promise<void> {
    if (this.provider === null) {
      return
    }
    this.provider.iconType = 'text' as ProviderIconType
    this.provider.textIcon = this.tempTextIcon
    this.provider.textIconBgColor = this.tempTextIconBgColor
    await this.saveCurrentProvider()
    this.showProviderToast($r('app.string.provider_icon_updated'))
  }

  // 重置为预设图标
  private async resetToPresetIcon(): Promise<void> {
    if (this.provider === null) {
      return
    }
    this.provider.iconType = 'text' as ProviderIconType
    this.provider.iconPath = ''
    this.provider.customImagePath = ''
    // 恢复预设文字图标
    const preset = getPresetProviderById(this.provider.id)
    if (preset !== null) {
      this.provider.textIcon = preset.textIcon
      this.provider.textIconBgColor = preset.textIconBgColor
    } else {
      const config = generateDefaultTextIcon(this.provider.name)
      this.provider.textIcon = config.text
      this.provider.textIconBgColor = config.bgColor
    }
    await this.saveCurrentProvider()
    this.showProviderToast($r('app.string.provider_default_icon_reset'))
    this.showTextIconEditor = false
  }
}

@ComponentV2
export struct ProviderDetailSheet {
  @Param providerId: string = ''
  @Param isCreateMode: boolean = false
  @Param closeOnSave: boolean = true
  @Param closeOnModelsSelected: boolean = false
  @Event onClose: () => void = () => {}
  @Event onProviderChanged: (providerId: string, isCreateMode: boolean) => void = (_providerId: string, _isCreateMode: boolean) => {}

  build() {
    Column() {
      ProviderDetailPanel({
        providerId: this.providerId,
        isCreateMode: this.isCreateMode,
        closeOnSave: this.closeOnSave,
        closeOnModelsSelected: this.closeOnModelsSelected,
        presentationMode: ProviderDetailPresentationMode.SHEET,
        onClose: () => {
          this.onClose()
        },
        onProviderChanged: (providerId: string, isCreateMode: boolean) => {
          this.onProviderChanged(providerId, isCreateMode)
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}

export function tryHandleProviderDetailInternalBack(): boolean {
  if (providerDetailInternalBackHandler === null) {
    return false
  }
  return providerDetailInternalBackHandler()
}

@ComponentV2
export struct ModelItemCard {
  @Param model: ModelInfo = new ModelInfo('', '')
  @Param showDivider: boolean = false
  @Param providerId: string = ''
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  @Event onToggle: (modelId: string, isEnabled: boolean) => void = (_modelId: string, _isEnabled: boolean): void => {}
  @Event onEdit: () => void = () => {}

  private getModelIconRenderData(): ModelIconRenderData {
    return buildModelIconRenderData(this.model.id, this.providerId, this.model.name)
  }

  @Builder
  CapabilityIcon(icon: string) {
    SymbolGlyph($r(icon))
      .fontSize(12)
      .fontColor([$r('app.color.text_tertiary')])
      .margin({ right: 6 })
  }

  private iconRenderData(): ModelIconRenderData {
    return this.getModelIconRenderData()
  }

  build() {
    Column() {
      Row() {
        // 模型图标
        Column() {
          if (this.iconRenderData().hasIcon()) {
            if (this.iconRenderData().isRawfile()) {
              Image($rawfile(this.iconRenderData().resourcePath))
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
            } else {
              Image(this.iconRenderData().resourcePath)
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

        // 模型信息
        Column() {
          Text(this.model.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.model.isEnabled ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 模型能力图标
          Row() {
            if (this.model.capabilities.supportsReasoning) {
              this.CapabilityIcon('sys.symbol.AI_deep_thinking')
            }
            if (this.model.capabilities.supportsVision) {
              this.CapabilityIcon('sys.symbol.ohos_photo')
            }
            if (this.model.capabilities.supportsTools) {
              this.CapabilityIcon('sys.symbol.wrench_and_screwdriver')
            }
            if (this.model.capabilities.supportsWebSearch) {
              this.CapabilityIcon('sys.symbol.ohos_wifi')
            }
          }
          .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10 })

        // 启用开关
        Toggle({ type: ToggleType.Switch, isOn: this.model.isEnabled })
          .selectedColor(this.themePrimary)
          .width(44)
          .height(24)
          .onChange((isOn: boolean) => {
            this.onToggle(this.model.id, isOn)
          })

        // 设置按钮
        Button() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(16)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .type(ButtonType.Circle)
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .margin({ left: 8 })
        .onClick(() => {
          this.onEdit()
        })
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding(14)
      .borderRadius(12)

      if (this.showDivider) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 56, right: 16 })
      }
    }
  }
}

