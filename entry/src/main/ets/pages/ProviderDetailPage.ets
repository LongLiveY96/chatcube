import { SymbolGlyphModifier } from '@kit.ArkUI'
import { ModelProvider, ModelInfo, ProviderType } from '../models/ChatModels'
import { ModelEditSheet } from '../components/ModelEditSheet'
import { ModelItemCard } from '../components/ProviderDetailSheet'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { buildIconResourcePath, getModelIconPath, isNetworkIconPath, isSandboxIconPath } from '../utils/ProviderIconUtils'
import { showToast } from '../utils/ToastUtil'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { ModelCapabilityMatcher } from '../services/ModelCapabilityMatcher'
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationMenuItemOptions } from '@kit.UIDesignKit'
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
  getGroupEnabledCount as countGroupEnabled
} from '../config/ProviderModelActions'

@Entry
@Component
struct ProviderDetailPage {
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
  // 动效触发器
  @State toggleAllEffectTrigger: number = 0
  // Tab 切换索引
  @State currentTabIndex: number = 0
  // Tab 图标动效触发器
  @State configTabEffectTrigger: number = 0
  @State modelsTabEffectTrigger: number = 0
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_primary_light') themePrimaryLight: string = '#E6F2FF'
  @StorageProp('isDarkMode') isDarkMode: boolean = false

  private providerId: string = ''
  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()

  // API 风格选项（仅用于自定义服务商）
  private apiStyleOptions: ApiStyleOption[] = getDefaultApiStyleOptions()

  aboutToAppear(): void {
    // 从路由参数获取 providerId
    const routerObj = this.getUIContext().getRouter()
    const params = routerObj.getParams() as Record<string, string>
    if (params !== null && params !== undefined && params['providerId'] !== undefined) {
      this.providerId = params['providerId']
    }
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

  private getProviderIconPathForRender(): string {
    if (this.provider === null || this.provider.iconPath === '') {
      return ''
    }
    return this.provider.iconPath
  }

  private getProviderIconResourcePath(): string {
    const iconPath = this.getProviderIconPathForRender()
    if (iconPath === '') {
      return ''
    }
    return buildIconResourcePath(iconPath)
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
        console.error('ProviderDetailPage', `[testConnection] failed: ${result.errorMessage}`)
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
        console.error('ProviderDetailPage', `[fetchModels] failed: ${result.errorMessage}`)
        this.showProviderToast($r('app.string.provider_fetch_models_failed'), 3000)
        return
      }

      if (result.models.length === 0) {
        this.showProviderToast($r('app.string.provider_no_models'), 2000)
        return
      }

      // 更新模型列表
      const models: ModelInfo[] = []
      for (let i = 0; i < result.models.length; i++) {
        const modelId = result.models[i]
        const modelInfo = new ModelInfo(modelId, modelId, 4096, true, false)
        models.push(modelInfo)
      }

      // 自动匹配模型能力（失败时静默降级）
      await ModelCapabilityMatcher.getInstance().applyCapabilitiesBatch(models)

      this.provider.models = models

      await this.saveCurrentProvider()
      this.refreshModelGroups()
      this.showProviderToast($r('app.string.provider_models_refreshed'), 2000)
    } finally {
      this.isFetchingModels = false
    }
  }

  // 保存配置
  async saveConfig(): Promise<void> {
    if (this.provider === null || this.isSaving) {
      return
    }

    this.isSaving = true
    try {
      await this.saveCurrentProvider()
      this.showProviderToast($r('app.string.config_saved'), 2000)
    } finally {
      this.isSaving = false
    }
  }

  // 保存配置并返回上一级
  async saveConfigAndBack(): Promise<void> {
    if (this.provider === null || this.isSaving) {
      return
    }

    this.isSaving = true
    try {
      await this.saveCurrentProvider()
      this.showProviderToast($r('app.string.config_saved'), 1500)
      this.getUIContext().getRouter().back()
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
          this.showProviderToast($r('app.string.provider_deleted'))
          this.getUIContext().getRouter().back()
        }
      }
    })
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
    this.showEditSheet = true
  }

  // 保存模型编辑
  private async saveModelEdit(): Promise<void> {
    if (this.provider !== null) {
      await this.saveCurrentProvider()
      this.showProviderToast($r('app.string.provider_model_saved'))
    }
    this.showEditSheet = false
    this.editingModel = null
    this.refreshModelGroups()
  }

  // 取消模型编辑
  private cancelModelEdit(): void {
    this.showEditSheet = false
  }

  // 清理编辑状态
  private clearEditState(): void {
    this.editingModel = null
  }

  build() {
    Column() {
      HdsNavigation() {
        Column() {
        if (this.isLoading) {
          this.LoadingView()
        } else if (this.provider === null) {
          this.ErrorView()
        } else {
          // 供应商头部卡片（始终可见）
          this.ProviderHeaderCard()

          // Tab 分区：配置 | 模型（原生悬浮 Tab 栏）
          Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
            TabContent() {
              Scroll() {
                Column() {
                  this.ApiConfigCard()

                  Column().height(100)
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
              Scroll() {
                Column() {
                  this.ModelsCard()
                  Column().height(100)
                }
                .width('100%')
              }
              .width('100%')
              .height('100%')
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .align(Alignment.Top)
            }
            .tabBar(this.ModelsTabBuilder())
          }
          .layoutWeight(1)
          .barOverlap(true)
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
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background'))
      .titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: true,
        content: {
          title: {
            mainTitle: $r('app.string.provider_detail_title')
          },
          menu: {
            value: this.getTitleMenus()
          }
        }
      })
      .bindSheet($$this.showEditSheet, this.ModelEditSheetBuilder(), {
        height: SheetSize.LARGE,
        showClose: false,
        dragBar: true,
        blurStyle: BlurStyle.Regular,
        onDisappear: () => {
          this.clearEditState()
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  private getTitleMenus(): Array<HdsNavigationMenuItemOptions> {
    const menus: Array<HdsNavigationMenuItemOptions> = []

    // 删除按钮（非预置服务商）
    if (this.provider !== null && !this.provider.isPreset) {
      const deleteIcon = new SymbolGlyphModifier($r('sys.symbol.clean'))
      deleteIcon.fontSize(20)
      deleteIcon.fontColor([$r('app.color.status_error')])
      menus.push({
        content: {
          label: $r('app.string.delete_provider_title'),
          icon: deleteIcon,
          action: () => {
            this.showDeleteConfirmDialog()
          }
        }
      })
    }

    // 保存按钮
    const saveIcon = new SymbolGlyphModifier($r('sys.symbol.save'))
    saveIcon.fontSize(20)
    saveIcon.fontColor([$r('app.color.text_primary')])
    menus.push({
      content: {
        label: $r('app.string.save'),
        icon: saveIcon,
        action: () => {
          this.saveConfigAndBack()
        }
      }
    })

    return menus
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
        Text($r('app.string.action_back'))
          .fontSize(14)
          .fontColor(this.themePrimary)
      }
        .fontSize(14)
        .backgroundColor(this.themePrimaryLight)
        .borderRadius(20)
        .height(40)
        .padding({ left: 24, right: 24 })
        .margin({ top: 24 })
        .onClick(() => {
          this.getUIContext().getRouter().back()
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
        // 供应商图标
        if (this.getProviderIconResourcePath() !== '') {
          Image(this.getProviderIconResourcePath())
            .width(40)
            .height(40)
            .objectFit(ImageFit.Contain)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.cloud'))
              .fontSize(24)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(40)
          .height(40)
          .borderRadius(8)
          .backgroundColor($r('app.color.divider'))
          .justifyContent(FlexAlign.Center)
        }

        Column() {
          if (this.provider !== null && !this.provider.isPreset) {
            TextInput({ text: this.provider?.name ?? '', placeholder: $r('app.string.provider_name_placeholder') })
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor(Color.Transparent)
              .padding(0)
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
          }

          Text(this.provider?.baseUrl ?? '')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)

        // 启用开关
        Toggle({ type: ToggleType.Switch, isOn: this.provider?.isConnected ?? false })
          .selectedColor(this.themePrimary)
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
    .margin({ left: 16, right: 16, top: 16 })
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
                Radio({ value: option.style, group: 'apiStyleEdit' })
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
                    .fontColor($r('app.color.text_tertiary'))
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
          .fontColor($r('app.color.text_tertiary'))

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
                    .fontColor($r('app.color.text_tertiary'))
                }
                .layoutWeight(1)
                .onClick(() => {
                  this.toggleGroupExpansion(groupIndex)
                })

                // 分组一键开关按钮
                Button() {
                  SymbolGlyph(this.isGroupAllEnabled(groupIndex) ? $r('sys.symbol.xmark_circle') : $r('sys.symbol.checkmark_circle'))
                    .fontSize(16)
                    .fontColor([this.isGroupAllEnabled(groupIndex) ? $r('app.color.text_tertiary') : this.themePrimary])
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
                ForEach(group.models, (model: ModelInfo, modelIndex: number) => {
                  ModelItemCard({
                    model: model,
                    showDivider: modelIndex < group.models.length - 1,
                    providerId: this.provider?.id ?? '',
                    onToggle: () => {
                      if (this.provider !== null) {
                        this.providerViewModel.saveProvider(this.provider)
                      }
                    },
                    onEdit: () => {
                      this.openModelEditSheet(model)
                    }
                  })
                }, (model: ModelInfo) => model.id)
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
            .fontColor($r('app.color.text_tertiary'))
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
  ModelEditSheetBuilder() {
    if (this.editingModel !== null) {
      ModelEditSheet({
        model: this.editingModel,
        onSave: async (): Promise<void> => {
          await this.saveModelEdit()
        },
        onCancel: () => {
          this.cancelModelEdit()
        }
      })
    }
  }
}
