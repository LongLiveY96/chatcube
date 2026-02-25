import { SymbolGlyphModifier } from '@kit.ArkUI'
import { ModelProvider, ModelInfo } from '../models/ChatModels'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { showToast } from '../utils/ToastUtil'
import { ProviderDetailSheet } from '../components/ProviderDetailSheet'
import { ProviderIcon } from '../components/ProviderIcon'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { ModelCapabilityMatcher } from '../services/ModelCapabilityMatcher'
import { IconDownloadCache } from '../services/IconDownloadCache'
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationMenuItemOptions } from '@kit.UIDesignKit'

@Entry
@Component
struct ModelManagePage {
  @State allProviders: ModelProvider[] = []
  @State isLoading: boolean = false
  @State searchKeywords: string = ''
  // 半模态弹窗相关状态
  @State showProviderSheet: boolean = false
  @State selectedProviderId: string = ''
  @State isMatchingIcons: boolean = false
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  private hasLoaded: boolean = false
  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()

  private showManageToast(message: string | Resource, duration: number = 2000): void {
    showToast(this.getUIContext(), message, duration)
  }

  aboutToAppear(): void {
    this.loadData()
  }

  onPageShow(): void {
    // 只在已加载过且不是从 Sheet 返回时静默刷新
    // Sheet 关闭由 onClose 回调处理，这里主要处理从 AddProviderPage 返回的情况
    if (this.hasLoaded && !this.showProviderSheet) {
      this.refreshDataSilently()
    }
  }

  async loadData(): Promise<void> {
    if (this.isLoading) {
      return
    }
    this.isLoading = true

    // 首次加载时初始化所有预置服务商（如果数据库为空）
    await this.providerViewModel.initializeAllPresetProviders()

    // 从数据库加载已保存的服务商（已按 sort_order 排序，包括禁用的）
    const savedProviders = await this.providerViewModel.loadAllProviders()

    if (savedProviders.length > 0) {
      this.allProviders = savedProviders
      // 调试日志：打印每个供应商的模型数量
      for (let i = 0; i < savedProviders.length; i++) {
        const p = savedProviders[i]
        const enabledCount = p.models.filter(m => m.isEnabled).length
        console.info('ModelManagePage', `Loaded provider ${p.name}: ${enabledCount}/${p.models.length}`)
      }
    } else {
      // 使用默认服务商
      this.allProviders = this.providerViewModel.getDefaultProviders()
    }

    this.isLoading = false
    this.hasLoaded = true
  }

  // 静默刷新数据（不显示加载状态，实现无感更新）
  private async refreshDataSilently(): Promise<void> {
    const savedProviders = await this.providerViewModel.loadAllProviders()
    if (savedProviders.length > 0) {
      this.allProviders = savedProviders
    }
  }

  // 获取启用的供应商
  private getEnabledProviders(): ModelProvider[] {
    const result: ModelProvider[] = []
    for (let i = 0; i < this.allProviders.length; i++) {
      if (this.allProviders[i].isConnected) {
        result.push(this.allProviders[i])
      }
    }
    return result
  }

  // 获取停用的供应商
  private getDisabledProviders(): ModelProvider[] {
    const result: ModelProvider[] = []
    for (let i = 0; i < this.allProviders.length; i++) {
      if (!this.allProviders[i].isConnected) {
        result.push(this.allProviders[i])
      }
    }
    return result
  }

  // 获取过滤后的启用供应商（用于搜索）
  private getFilteredEnabledProviders(): ModelProvider[] {
    const enabled = this.getEnabledProviders()
    if (this.searchKeywords === '') {
      return enabled
    }
    const result: ModelProvider[] = []
    for (let i = 0; i < enabled.length; i++) {
      if (this.getFilteredModels(enabled[i].models).length > 0) {
        result.push(enabled[i])
      }
    }
    return result
  }

  // 获取过滤后的停用供应商（用于搜索）
  private getFilteredDisabledProviders(): ModelProvider[] {
    const disabled = this.getDisabledProviders()
    if (this.searchKeywords === '') {
      return disabled
    }
    const result: ModelProvider[] = []
    for (let i = 0; i < disabled.length; i++) {
      if (this.getFilteredModels(disabled[i].models).length > 0) {
        result.push(disabled[i])
      }
    }
    return result
  }

  // 查找供应商在 allProviders 中的索引
  private findProviderIndex(providerId: string): number {
    for (let i = 0; i < this.allProviders.length; i++) {
      if (this.allProviders[i].id === providerId) {
        return i
      }
    }
    return -1
  }

  // 判断供应商是否可以上移
  private canMoveUp(providerId: string): boolean {
    const index = this.findProviderIndex(providerId)
    return index > 0
  }

  // 判断供应商是否可以下移
  private canMoveDown(providerId: string): boolean {
    const index = this.findProviderIndex(providerId)
    return index >= 0 && index < this.allProviders.length - 1
  }

  // 上移供应商
  private moveProviderUp(providerId: string): void {
    const index = this.findProviderIndex(providerId)
    if (index > 0) {
      this.moveProvider(index, index - 1)
      this.showManageToast($r('app.string.provider_moved_up'))
    }
  }

  // 下移供应商
  private moveProviderDown(providerId: string): void {
    const index = this.findProviderIndex(providerId)
    if (index >= 0 && index < this.allProviders.length - 1) {
      this.moveProvider(index, index + 1)
      this.showManageToast($r('app.string.provider_moved_down'))
    }
  }

  // 移动供应商位置
  private moveProvider(fromIndex: number, toIndex: number): void {
    if (fromIndex < 0 || toIndex < 0 || fromIndex >= this.allProviders.length || toIndex >= this.allProviders.length) {
      return
    }
    if (fromIndex === toIndex) {
      return
    }
    const item = this.allProviders[fromIndex]
    this.allProviders.splice(fromIndex, 1)
    this.allProviders.splice(toIndex, 0, item)
    // 触发 UI 更新
    this.allProviders = [...this.allProviders]
    // 保存排序
    this.saveOrder()
  }

  // 处理供应商拖拽移动（使用 onMove API）
  // from 和 to 是 allProviders 数组的索引
  private handleProviderMove(from: number, to: number): void {
    if (from < 0 || to < 0 || from >= this.allProviders.length || to >= this.allProviders.length) {
      return
    }
    if (from === to) {
      return
    }

    const fromProvider = this.allProviders[from]
    const toProvider = this.allProviders[to]

    // 不允许跨分组拖拽（启用/停用分组）
    if (fromProvider.isConnected !== toProvider.isConnected) {
      return
    }

    // 交换位置
    const item = this.allProviders[from]
    this.allProviders.splice(from, 1)
    this.allProviders.splice(to, 0, item)
    // 触发 UI 更新
    this.allProviders = [...this.allProviders]
    // 保存排序
    this.saveOrder()
  }

  // 保存排序到数据库
  private async saveOrder(): Promise<void> {
    const providerIds: string[] = []
    for (let i = 0; i < this.allProviders.length; i++) {
      providerIds.push(this.allProviders[i].id)
    }
    await this.providerViewModel.saveProvidersOrder(providerIds)
  }

  build() {
    Column() {
      HdsNavigation() {
        Column() {
        // Search Bar
        Row() {
          Search({ value: this.searchKeywords, placeholder: $r('app.string.filter_models_placeholder') })
            .width('100%')
            .height(40)
            .backgroundColor($r('app.color.surface'))
            .onChange((value: string) => {
              this.searchKeywords = value
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        if (this.isLoading) {
          this.LoadingView()
        } else {
          List({ space: 8 }) {
            // ========== 启用的供应商分组 ==========
            if (this.getFilteredEnabledProviders().length > 0) {
              ListItem() {
                this.GroupHeader($r('app.string.enabled_services'), this.getFilteredEnabledProviders().length, true)
              }

              ForEach(this.allProviders, (provider: ModelProvider, index: number) => {
                if (provider.isConnected && this.matchesSearch(provider)) {
                  ListItem() {
                    this.ProviderCard(provider, false, index)
                  }
                  .margin({ left: 16, right: 16 })
                  .borderRadius(16)
                  .clip(true)
                  .transition({ type: TransitionType.All, opacity: 0 })
                }
              }, (provider: ModelProvider) => `provider_${provider.id}_${provider.isConnected}_${provider.iconType}_${provider.textIcon}_${provider.textIconBgColor}_${provider.customImagePath}_${this.getEnabledModelCount(provider)}`)
              .onMove((from: number, to: number) => {
                this.handleProviderMove(from, to)
              })
            }

            // ========== 停用的供应商分组 ==========
            if (this.getFilteredDisabledProviders().length > 0) {
              ListItem() {
                this.GroupHeader($r('app.string.disabled_services'), this.getFilteredDisabledProviders().length, false)
              }

              ForEach(this.allProviders, (provider: ModelProvider, index: number) => {
                if (!provider.isConnected && this.matchesSearch(provider)) {
                  ListItem() {
                    this.ProviderCard(provider, true, index)
                  }
                  .margin({ left: 16, right: 16 })
                  .borderRadius(16)
                  .clip(true)
                  .transition({ type: TransitionType.All, opacity: 0 })
                }
              }, (provider: ModelProvider) => `provider_${provider.id}_${provider.isConnected}_${provider.iconType}_${provider.textIcon}_${provider.textIconBgColor}_${provider.customImagePath}_${this.getEnabledModelCount(provider)}`)
              .onMove((from: number, to: number) => {
                this.handleProviderMove(from, to)
              })
            }

            // 搜索无结果提示
            if (this.searchKeywords.trim() !== '' &&
                this.getFilteredEnabledProviders().length === 0 &&
                this.getFilteredDisabledProviders().length === 0) {
              ListItem() {
                Column() {
                  SymbolGlyph($r('sys.symbol.magnifyingglass'))
                    .fontSize(48)
                    .fontColor([$r('app.color.text_tertiary')])

                  Text($r('app.string.provider_models_not_found'))
                    .fontSize(16)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 16 })

                  Text($r('app.string.search_try_other_keywords'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_tertiary'))
                    .margin({ top: 4 })
                }
                .width('100%')
                .padding({ top: 60, bottom: 60 })
                .justifyContent(FlexAlign.Center)
              }
            }

            // Add Provider Button
            ListItem() {
              Button() {
                Row() {
                  SymbolGlyph($r('sys.symbol.plus_circle'))
                    .fontSize(22)
                    .fontColor([this.themePrimary])

                  Text($r('app.string.add_custom_provider'))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.themePrimary)
                    .margin({ left: 8 })
                }
              }
              .width('100%')
              .height(56)
              .backgroundColor($r('app.color.surface'))
              .borderRadius(24)
              .margin({ left: 16, right: 16, top: 8 })
              .onClick(() => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/AddProviderPage' })
              })
            }

            // Bottom Spacer
            ListItem() {
              Column().height(100)
            }
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
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
            mainTitle: $r('app.string.model_manage_title')
          },
          menu: {
            value: this.getManageMenus()
          }
        }
      })
      .bindSheet($$this.showProviderSheet, this.ProviderDetailSheetBuilder(), {
        height: SheetSize.LARGE,
        showClose: false,
        dragBar: true,
        blurStyle: BlurStyle.Regular,
        onDisappear: () => {
          this.selectedProviderId = ''
          // Sheet 完全关闭后静默刷新数据
          this.refreshDataSilently()
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  ProviderDetailSheetBuilder() {
    if (this.selectedProviderId !== '') {
      ProviderDetailSheet({
        providerId: this.selectedProviderId,
        onClose: () => {
          this.showProviderSheet = false
          // 数据刷新由 onDisappear 回调处理，确保 Sheet 完全关闭后再刷新
        }
      })
    }
  }

  private getManageMenus(): Array<HdsNavigationMenuItemOptions> {
    const addIcon = new SymbolGlyphModifier($r('sys.symbol.plus_circle'))
    addIcon.fontSize(20)
    addIcon.fontColor([$r('app.color.text_primary')])

    const matchIconsIcon = new SymbolGlyphModifier($r('sys.symbol.wand_and_stars'))
    matchIconsIcon.fontSize(20)
    matchIconsIcon.fontColor([$r('app.color.text_primary')])

    const menus: Array<HdsNavigationMenuItemOptions> = [
      {
        content: {
          label: $r('app.string.match_icons'),
          icon: matchIconsIcon,
          isEnabled: !this.isMatchingIcons,
          action: () => {
            this.matchAllIcons()
          }
        }
      },
      {
        content: {
          label: $r('app.string.add_custom_provider'),
          icon: addIcon,
          action: () => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/AddProviderPage' })
          }
        }
      }
    ]
    return menus
  }

  @Builder
  GroupHeader(title: string | Resource, count: number, isEnabled: boolean) {
    Row() {
      // 状态图标
      Column() {
        SymbolGlyph(isEnabled ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.xmark_circle_fill'))
          .fontSize(16)
          .fontColor([isEnabled ? $r('app.color.primary') : $r('app.color.text_tertiary')])
      }
      .width(28)
      .height(28)
      .borderRadius(14)
      .backgroundColor(isEnabled ? $r('app.color.primary_light') : $r('app.color.divider'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(isEnabled ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
        .margin({ left: 10 })

      Text(`(${count})`)
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 6 })
    }
    .width('100%')
    .padding({ left: 20, right: 16, top: 20, bottom: 8 })
  }

  @Builder
  ProviderCard(provider: ModelProvider, isDisabled: boolean, index: number) {
    Column() {
      // 供应商标题行
      Row() {
        // 拖拽手柄（视觉指示器）
        Column() {
          SymbolGlyph($r('sys.symbol.line_3_horizontal'))
            .fontSize(16)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .width(28)
        .height(28)
        .justifyContent(FlexAlign.Center)
        .margin({ right: 4 })

        // 供应商图标（使用 ProviderIcon 组件支持所有图标类型）
        ProviderIcon({
          iconType: provider.iconType,
          iconPath: provider.iconPath,
          textIcon: provider.textIcon,
          textIconBgColor: provider.textIconBgColor,
          customImagePath: provider.customImagePath,
          iconSize: 24,
          radius: 6,
          bgColor: $r('app.color.divider'),
          brandColor: provider.brandColor,
          fallbackSymbol: $r('sys.symbol.cloud'),
          fallbackColor: $r('app.color.text_tertiary')
        })
          .margin({ right: 8 })

        Text(provider.name.toUpperCase())
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(isDisabled ? $r('app.color.text_tertiary') : $r('app.color.text_secondary'))
          .letterSpacing(1)

        Text(` (${this.getEnabledCount(provider)})`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_tertiary'))

        // 系统服务标签
        if (provider.id === 'siliconflow') {
          Text($r('app.string.system_service'))
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.primary_light'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .margin({ left: 8 })
        }

        // 停用标签
        if (isDisabled) {
          Text($r('app.string.provider_disabled_badge'))
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .backgroundColor($r('app.color.divider'))
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .margin({ left: 8 })
        }

        Blank()

        // 更多操作菜单按钮
        Button() {
          SymbolGlyph($r('sys.symbol.more'))
            .fontSize(16)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .type(ButtonType.Circle)
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .bindMenu(this.ProviderMenuBuilder(provider))

        // 跳转箭头
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])
          .margin({ left: 4 })
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 16, bottom: 16 })
      .onClick(() => {
        // 打开供应商详情半模态弹窗
        this.selectedProviderId = provider.id
        this.showProviderSheet = true
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private ProviderMenuBuilder(provider: ModelProvider) {
    Menu() {
      // 只有多个供应商时才显示排序选项
      if (this.allProviders.length > 1 && this.canMoveUp(provider.id)) {
        MenuItem({
          content: $r('app.string.provider_menu_move_up')
        })
          .onClick(() => {
            this.moveProviderUp(provider.id)
          })
      }

      if (this.allProviders.length > 1 && this.canMoveDown(provider.id)) {
        MenuItem({
          content: $r('app.string.provider_menu_move_down')
        })
          .onClick(() => {
            this.moveProviderDown(provider.id)
          })
      }

      // 启用/停用选项（硅基流动服务商不允许操作）
      if (provider.id !== 'siliconflow') {
        MenuItem({
          content: !provider.isConnected ? $r('app.string.provider_menu_enable') : $r('app.string.provider_menu_disable')
        })
          .onClick(() => {
            this.toggleProviderEnabled(provider)
          })
      }

      // 删除选项（预设供应商不可删除）
      if (!provider.isPreset) {
        MenuItem({
          content: $r('app.string.delete')
        })
          .contentFontColor($r('app.color.status_error'))
          .onClick(() => {
            this.showDeleteConfirmDialog(provider)
          })
      }
    }
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

  private getEnabledCount(provider: ModelProvider): string {
    const enabled = provider.models.filter(m => m.isEnabled).length
    return `${enabled}/${provider.models.length}`
  }

  // 获取启用的模型数量（用于 ForEach key）
  private getEnabledModelCount(provider: ModelProvider): number {
    return provider.models.filter(m => m.isEnabled).length
  }

  private getFilteredModels(models: ModelInfo[]): ModelInfo[] {
    if (!this.searchKeywords) {
      return models
    }
    return models.filter(m => m.name.toLowerCase().includes(this.searchKeywords.toLowerCase()))
  }

  // 检查供应商是否匹配搜索关键词
  private matchesSearch(provider: ModelProvider): boolean {
    if (this.searchKeywords.trim() === '') {
      return true
    }
    // 检查供应商名称或模型名称是否匹配
    if (provider.name.toLowerCase().includes(this.searchKeywords.toLowerCase())) {
      return true
    }
    return this.getFilteredModels(provider.models).length > 0
  }

  // 切换供应商启用/停用状态
  private async toggleProviderEnabled(provider: ModelProvider): Promise<void> {
    const newStatus = !provider.isConnected

    // 保存到数据库
    await this.providerViewModel.updateProviderEnabled(provider.id, newStatus)

    // 重新从数据库加载，确保获取全新的对象引用
    const freshProviders = await this.providerViewModel.loadAllProviders()

    // 使用全新数组替换，触发 @State 刷新
    this.allProviders = []  // 先清空
    this.allProviders = freshProviders  // 再赋值新数组

    this.showManageToast(newStatus ? $r('app.string.provider_enabled') : $r('app.string.provider_disabled'))
  }

  // 显示删除确认对话框
  private showDeleteConfirmDialog(provider: ModelProvider): void {
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
        action: () => {
          this.deleteProvider(provider)
        }
      }
    })
  }

  // 执行删除供应商
  private async deleteProvider(provider: ModelProvider): Promise<void> {
    await this.providerViewModel.deleteProvider(provider.id)

    // 从列表中移除
    const index = this.allProviders.findIndex(p => p.id === provider.id)
    if (index >= 0) {
      this.allProviders.splice(index, 1)
      // 强制触发 UI 更新
      this.allProviders = [...this.allProviders]
    }

    // 重新保存排序
    await this.saveOrder()

    this.showManageToast($r('app.string.provider_deleted'))
  }

  // 一键匹配所有模型图标
  private async matchAllIcons(): Promise<void> {
    if (this.isMatchingIcons) {
      return
    }
    this.isMatchingIcons = true
    this.showManageToast($r('app.string.matching_icons'))

    const matcher = ModelCapabilityMatcher.getInstance()
    const loaded = await matcher.loadCache()
    if (!loaded) {
      this.showManageToast($r('app.string.match_icons_failed'))
      this.isMatchingIcons = false
      return
    }

    const iconCache = IconDownloadCache.getInstance()
    let matchedCount = 0
    let totalModels = 0
    // 去重：同一 logoUrl 只下载一次
    const downloadedUrls = new Set<string>()

    for (let i = 0; i < this.allProviders.length; i++) {
      const provider = this.allProviders[i]
      for (let j = 0; j < provider.models.length; j++) {
        totalModels++
        const logoUrl = matcher.getLogoUrl(provider.models[j].id)
        if (logoUrl !== '') {
          matchedCount++
          matcher.recordModelLogo(provider.models[j].id, logoUrl)
          if (!downloadedUrls.has(logoUrl)) {
            downloadedUrls.add(logoUrl)
            const cached = iconCache.getCachedIconUri(logoUrl)
            if (cached === '') {
              await iconCache.downloadAndCache(logoUrl)
            }
          }
        }
      }
    }

    // 显式保存，确保冷启动后可直接恢复
    await matcher.savePersistedLogoIndex()

    // 触发 UI 刷新
    this.allProviders = [...this.allProviders]
    this.showManageToast(`已匹配 ${matchedCount}/${totalModels} 个模型图标`)
    this.isMatchingIcons = false
  }
}
