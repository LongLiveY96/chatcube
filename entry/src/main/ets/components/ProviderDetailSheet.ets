import { ModelProvider, ModelInfo, ProviderType, ProviderIconType } from '../models/ChatModels'
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
  getGroupEnabledCount as countGroupEnabled,
  removeModelById,
  buildSelectedModelsWithPreservedConfig
} from '../config/ProviderModelActions'

@Component
export struct ProviderDetailSheet {
  @Prop providerId: string = ''
  onClose: () => void = () => {}
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('isDarkMode') isDarkMode: boolean = false

  @State provider: ModelProvider | null = null
  @State isLoading: boolean = true
  @State isTesting: boolean = false
  @State isFetchingModels: boolean = false
  @State isSaving: boolean = false
  @State showApiKey: boolean = false
  @State searchKeywords: string = ''
  @State modelGroups: ProviderModelGroup[] = []
  // 模型编辑相关状态
  @State showEditSheet: boolean = false
  @State editingModel: ModelInfo | null = null
  // 模型选择器相关状态
  @State fetchedModels: string[] = []
  // 统一的弹窗控制：'none' | 'edit' | 'picker' | 'icon'
  @State activeSheet: string = 'none'
  @State showSheet: boolean = false
  // 动效触发器
  @State toggleAllEffectTrigger: number = 0
  // 图标编辑相关状态
  @State showTextIconEditor: boolean = false
  @State showColorPicker: boolean = false
  @State tempTextIcon: string = ''
  @State tempTextIconBgColor: string = ''

  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()

  // API 风格选项（仅用于自定义服务商）
  private apiStyleOptions: ApiStyleOption[] = getDefaultApiStyleOptions()

  aboutToAppear(): void {
    this.loadProviderData()
  }

  async loadProviderData(): Promise<void> {
    this.isLoading = true
    // 强制从数据库重新加载（不使用缓存）
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
      return
    }
    const models = filterProviderModelsByKeyword(this.provider.models, this.searchKeywords)
    this.modelGroups = buildProviderModelGroups(models)
  }

  private showProviderToast(message: string | Resource, duration: number = 2000): void {
    showToast(this.getUIContext(), message, duration)
  }

  private async saveCurrentProvider(): Promise<void> {
    if (this.provider === null) {
      return
    }
    await this.providerViewModel.saveProvider(this.provider)
  }

  private refreshModelGroups(): void {
    this.modelGroups = []
    this.buildModelGroups()
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
        this.showProviderToast($r('app.string.connection_failed'), 3000)
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
        this.showProviderToast($r('app.string.provider_fetch_models_failed'), 3000)
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
    } finally {
      this.isFetchingModels = false
    }
  }

  // 保存选中的模型
  async saveSelectedModels(selectedIds: string[]): Promise<void> {
    if (this.provider === null) {
      return
    }

    const newModels = buildSelectedModelsWithPreservedConfig(this.provider.models, selectedIds)

    // 自动匹配模型能力（失败时静默降级）
    await ModelCapabilityMatcher.getInstance().applyCapabilitiesBatch(newModels)

    this.provider.models = newModels

    await this.saveCurrentProvider()

    this.refreshModelGroups()

    // 先关闭内部弹窗
    this.showSheet = false
    this.activeSheet = 'none'

    // 显示提示
    this.showProviderToast($r('app.string.provider_models_selected'), 2000)

    // 延迟通知父页面关闭并刷新数据（等待内部弹窗关闭动画完成）
    setTimeout(() => {
      this.onClose()
    }, 200)
  }

  // 删除单个模型
  async deleteModel(model: ModelInfo): Promise<void> {
    if (this.provider === null) {
      return
    }

    this.provider.models = removeModelById(this.provider.models, model.id)

    await this.saveCurrentProvider()
    this.refreshModelGroups()

    console.info('ProviderDetailSheet', `[deleteModel] deleted model: ${model.name}`)
    this.showProviderToast($r('app.string.provider_model_deleted'))
  }

  // 保存配置并关闭
  async saveConfigAndClose(): Promise<void> {
    if (this.provider === null || this.isSaving) {
      return
    }

    this.isSaving = true
    try {
      await this.saveCurrentProvider()
      this.showProviderToast($r('app.string.config_saved'), 1500)
      this.onClose()
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

  // 获取分组内启用的模型数量（用于 ForEach key）
  private getGroupEnabledCount(group: ProviderModelGroup): number {
    return countGroupEnabled(group)
  }

  // 打开模型编辑弹窗
  private openModelEditSheet(model: ModelInfo): void {
    this.editingModel = model
    this.activeSheet = 'edit'
    this.showSheet = true
  }

  // 保存模型编辑
  private async saveModelEdit(): Promise<void> {
    if (this.provider !== null) {
      await this.saveCurrentProvider()
      this.showProviderToast($r('app.string.provider_model_saved'))
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.showSheet = false
      this.activeSheet = 'none'
    })
    this.editingModel = null
    this.refreshModelGroups()
  }

  // 取消模型编辑
  private cancelModelEdit(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.showSheet = false
      this.activeSheet = 'none'
    })
  }

  // 清理编辑状态
  private clearEditState(): void {
    this.editingModel = null
    this.activeSheet = 'none'
    this.fetchedModels = []
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
        Scroll() {
          Column() {
            // 供应商头部卡片
            this.ProviderHeaderCard()

            // API 配置卡片
            this.ApiConfigCard()

            // 模型管理卡片
            this.ModelsCard()

            // 底部间距
            Column().height(40)
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showSheet, this.UnifiedSheetBuilder(), {
      height: SheetSize.LARGE,
      showClose: false,
      dragBar: true,
      blurStyle: BlurStyle.Regular,
      onDisappear: () => {
        this.clearEditState()
      }
    })
  }

  @Builder
  SheetHeader() {
    Row() {
      // 关闭按钮
      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
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
      Text(this.provider?.name ?? $r('app.string.provider_detail_title'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      // 保存按钮
      Button() {
        SymbolGlyph($r('sys.symbol.checkmark'))
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
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  LoadingView() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color($r('app.color.primary'))

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
        Text($r('app.string.action_close'))
          .fontSize(14)
          .fontColor($r('app.color.primary'))
      }
        .backgroundColor($r('app.color.primary_light'))
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

        Column() {
          Text(this.provider?.name ?? '')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text(this.provider?.baseUrl ?? '')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)

        // 启用开关
        Toggle({ type: ToggleType.Switch, isOn: this.provider?.isConnected ?? false })
          .selectedColor($r('app.color.primary'))
          .onChange((isOn: boolean) => {
            // 只有当状态真正改变时才处理（避免重复触发）
            if (this.provider !== null && this.provider.isConnected !== isOn) {
              this.toggleEnabled()
            }
          })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .margin({ left: 16, right: 16, top: 8 })
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

      // API 风格选择（仅自定义类型服务商显示）
      if (this.provider !== null && this.provider.type === ProviderType.CUSTOM) {
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

      // API Key
      Column() {
        Row() {
          Text($r('app.string.api_key'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text(' *')
            .fontSize(13)
            .fontColor(Color.Red)
        }
        .width('100%')

        Row() {
          TextInput({ text: this.provider?.apiKey ?? '', placeholder: $r('app.string.provider_api_key_placeholder') })
            .type(InputType.Password)
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
                .color($r('app.color.primary'))
            } else {
              Text($r('app.string.test_connection'))
                .fontSize(13)
                .fontColor($r('app.color.primary'))
            }
          }
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.primary_light'))
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
    .margin({ left: 16, right: 16, top: 16 })
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
                .fontColor([this.isAllModelsEnabled() ? $r('app.color.text_tertiary') : $r('app.color.primary')])
                .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), this.toggleAllEffectTrigger)
              Text(this.isAllModelsEnabled() ? $r('app.string.provider_disable_all') : $r('app.string.provider_enable_all'))
                .fontSize(13)
                .fontColor(this.isAllModelsEnabled() ? $r('app.color.text_tertiary') : $r('app.color.primary'))
                .margin({ left: 4 })
            }
          }
          .height(32)
          .padding({ left: 10, right: 10 })
          .backgroundColor(this.isAllModelsEnabled() ? $r('app.color.background') : $r('app.color.primary_light'))
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

        // 获取模型按钮
        Button() {
          Row() {
            if (this.isFetchingModels) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color($r('app.color.primary'))
            } else {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(14)
                .fontColor([$r('app.color.primary')])
            }
            Text(this.isFetchingModels ? $r('app.string.provider_fetching') : $r('app.string.provider_fetch_models'))
              .fontSize(13)
              .fontColor($r('app.color.primary'))
              .margin({ left: 4 })
          }
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.primary_light'))
        .borderRadius(16)
        .enabled(!this.isFetchingModels)
        .onClick(() => {
          this.fetchModels()
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })

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

      // 模型分组列表
      if (this.modelGroups.length > 0) {
        Column() {
          ForEach(this.modelGroups, (group: ProviderModelGroup, groupIndex: number) => {
            Column() {
              // 分组标题
              Row() {
                Row() {
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('app.color.text_tertiary')])
                    .rotate({ angle: group.isExpanded ? 90 : 0 })
                    .animation({ duration: 200 })

                  Text(group.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ left: 8 })

                  Text(` (${group.models.length})`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                .layoutWeight(1)
                .onClick(() => {
                  this.toggleGroupExpansion(groupIndex)
                })

                // 分组一键开关按钮
                Button() {
                  SymbolGlyph(this.isGroupAllEnabled(groupIndex) ? $r('sys.symbol.xmark_circle') : $r('sys.symbol.checkmark_circle'))
                    .fontSize(16)
                    .fontColor([this.isGroupAllEnabled(groupIndex) ? $r('app.color.text_tertiary') : $r('app.color.primary')])
                }
                .type(ButtonType.Circle)
                .width(32)
                .height(32)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  if (this.isGroupAllEnabled(groupIndex)) {
                    this.disableGroupModels(groupIndex)
                  } else {
                    this.enableGroupModels(groupIndex)
                  }
                })
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 8 })

              // 分组内模型列表
              if (group.isExpanded) {
                List() {
                  ForEach(group.models, (model: ModelInfo, modelIndex: number) => {
                    ListItem() {
                      this.ModelItem(model, modelIndex < group.models.length - 1)
                    }
                    .swipeAction({
                      end: {
                        builder: () => {
                          this.DeleteButton(model)
                        }
                      }
                    })
                  }, (model: ModelInfo) => `${model.id}_${model.isEnabled}_${model.capabilities.supportsTools}_${model.capabilities.supportsReasoning}_${model.capabilities.supportsVision}_${model.capabilities.supportsWebSearch}`)
                }
                .width('100%')
                .scrollBar(BarState.Off)
                .nestedScroll({
                  scrollForward: NestedScrollMode.PARENT_FIRST,
                  scrollBackward: NestedScrollMode.SELF_FIRST
                })
              }
            }
          }, (group: ProviderModelGroup, index: number) => `${group.name}_${index}_${group.isExpanded}_${this.getGroupEnabledCount(group)}`)
        }
        .width('100%')
        .margin({ top: 12 })
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

      Column().height(16)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .margin({ left: 16, right: 16, top: 16 })
  }

  @Builder
  ModelItem(model: ModelInfo, showDivider: boolean) {
    Column() {
      Row() {
        // 模型图标（与 ModelSelector 一致）
        Column() {
          if (this.hasModelIcon(model.id)) {
            if (this.isRawfileModelIcon(model.id)) {
              Image($rawfile(this.getModelIconResourcePath(model.id)))
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
            } else {
              Image(this.getModelIconResourcePath(model.id))
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

        // 模型信息（与 ModelSelector 一致）
        Column() {
          Text(model.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(model.isEnabled ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 模型能力图标（与 ModelSelector 一致）
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
        .layoutWeight(1)
        .margin({ left: 10 })

        // 启用开关
        Toggle({ type: ToggleType.Switch, isOn: model.isEnabled })
          .selectedColor($r('app.color.primary'))
          .width(44)
          .height(24)
          .onChange(async (isOn: boolean) => {
            model.isEnabled = isOn
            if (this.provider !== null) {
              await this.providerViewModel.saveProvider(this.provider)
            }
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
          this.openModelEditSheet(model)
        })
      }
      .width('100%')
      .padding(14)
      .borderRadius(12)

      if (showDivider) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 56, right: 16 })
      }
    }
  }

  @Builder
  CapabilityIcon(icon: string) {
    SymbolGlyph($r(icon))
      .fontSize(12)
      .fontColor([$r('app.color.text_tertiary')])
      .margin({ right: 6 })
  }

  @Builder
  UnifiedSheetBuilder() {
    if (this.activeSheet === 'edit' && this.editingModel !== null) {
      ModelEditSheet({
        model: this.editingModel,
        onSave: async (): Promise<void> => {
          await this.saveModelEdit()
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
      showColorPicker: $showColorPicker,
      tempTextIcon: $tempTextIcon,
      tempTextIconBgColor: $tempTextIconBgColor,
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
