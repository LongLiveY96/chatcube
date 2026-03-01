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
    // Sheet 关闭由 onClose 回调处理，这里处理从其他页面返回的情况
    if (this.hasLoaded && !this.showProviderSheet) {
      this.refreshFromDatabase()
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

  // 静默刷新数据（从 ViewModel 缓存同步，不访问数据库）
  // 就地更新现有对象属性，保持 @ObjectLink 绑定不断裂
  private refreshFromCache(): void {
    const cachedProviders = this.providerViewModel.getCachedProviders()
    if (cachedProviders.length === 0) {
      return
    }

    // 构建缓存数据的 ID 查找表
    const cacheMap = new Map<string, ModelProvider>()
    for (let i = 0; i < cachedProviders.length; i++) {
      cacheMap.set(cachedProviders[i].id, cachedProviders[i])
    }

    // 就地更新现有对象的所有属性（@Observed 会自动通知 @ObjectLink 子组件）
    for (let i = 0; i < this.allProviders.length; i++) {
      const existing = this.allProviders[i]
      const updated = cacheMap.get(existing.id)
      if (updated !== undefined && updated !== existing) {
        this.providerViewModel.syncProviderProperties(existing, updated)
      }
    }

    // 如果服务商数量或顺序变化（如新增、删除），需要重建数组
    let needsRebuild = cachedProviders.length !== this.allProviders.length
    if (!needsRebuild) {
      for (let i = 0; i < cachedProviders.length; i++) {
        if (cachedProviders[i].id !== this.allProviders[i].id) {
          needsRebuild = true
          break
        }
      }
    }
    if (needsRebuild) {
      this.allProviders = cachedProviders
    }
  }

  // 从数据库完整刷新（仅在从其他页面返回时使用）
  private async refreshFromDatabase(): Promise<void> {
    const savedProviders = await this.providerViewModel.loadAllProviders()
    if (savedProviders.length === 0) {
      return
    }

    const newMap = new Map<string, ModelProvider>()
    for (let i = 0; i < savedProviders.length; i++) {
      newMap.set(savedProviders[i].id, savedProviders[i])
    }

    for (let i = 0; i < this.allProviders.length; i++) {
      const existing = this.allProviders[i]
      const updated = newMap.get(existing.id)
      if (updated !== undefined) {
        this.providerViewModel.syncProviderProperties(existing, updated)
      }
    }

    let needsRebuild = savedProviders.length !== this.allProviders.length
    if (!needsRebuild) {
      for (let i = 0; i < savedProviders.length; i++) {
        if (savedProviders[i].id !== this.allProviders[i].id) {
          needsRebuild = true
          break
        }
      }
    }
    if (needsRebuild) {
      this.allProviders = savedProviders
    }
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

  // 保存排序到数据库
  private async saveOrder(): Promise<void> {
    const providerIds: string[] = []
    for (let i = 0; i < this.allProviders.length; i++) {
      providerIds.push(this.allProviders[i].id)
    }
    await this.providerViewModel.saveProvidersOrder(providerIds)
  }

  // 获取过滤后的所有供应商
  private getFilteredProviders(): ModelProvider[] {
    if (this.searchKeywords.trim() === '') {
      return this.allProviders
    }
    const result: ModelProvider[] = []
    for (let i = 0; i < this.allProviders.length; i++) {
      if (this.matchesSearch(this.allProviders[i])) {
        result.push(this.allProviders[i])
      }
    }
    return result
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
            Repeat<ModelProvider>(this.allProviders)
              .each((obj: RepeatItem<ModelProvider>) => {
                ListItem() {
                  ProviderCardItem({
                    provider: obj.item,
                    searchKeywords: this.searchKeywords,
                    onCardClick: () => {
                      this.selectedProviderId = obj.item.id
                      this.showProviderSheet = true
                    },
                    onToggleEnabled: () => {
                      this.toggleProviderEnabled(obj.item)
                    }
                  })
                }
                .margin({ left: 16, right: 16 })
                .borderRadius(16)
                .clip(true)
                .transition({ type: TransitionType.All, opacity: 0 })
                .visibility(this.matchesSearch(obj.item) ? Visibility.Visible : Visibility.None)
              })
              .key((item: ModelProvider) => {
                return item.id
              })
              .onMove((from: number, to: number) => {
                let temp = this.allProviders.splice(from, 1)
                this.allProviders.splice(to, 0, temp[0])
                this.saveOrder()
              })

            // 搜索无结果提示
            if (this.searchKeywords.trim() !== '' && this.getFilteredProviders().length === 0) {
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
              Column() {
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
                .onClick(() => {
                  this.selectedProviderId = ''
                  this.showProviderSheet = true
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8 })
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
          // Sheet 关闭后从缓存同步（无 DB 开销，即时生效）
          this.refreshFromCache()
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  ProviderDetailSheetBuilder() {
    ProviderDetailSheet({
      providerId: this.selectedProviderId,
      isCreateMode: this.selectedProviderId === '',
      onClose: () => {
        // 立即从缓存同步数据到列表（不等关闭动画）
        this.refreshFromCache()
        this.showProviderSheet = false
      }
    })
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
            this.selectedProviderId = ''
            this.showProviderSheet = true
          }
        }
      }
    ]
    return menus
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
    provider.isConnected = newStatus

    // 异步持久化到数据库
    await this.providerViewModel.updateProviderEnabled(provider.id, newStatus)

    this.showManageToast(newStatus ? $r('app.string.provider_enabled') : $r('app.string.provider_disabled'))
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

@Component
struct ProviderCardItem {
  @ObjectLink provider: ModelProvider
  @Prop searchKeywords: string = ''
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  onCardClick: () => void = () => {}
  onToggleEnabled: () => void = () => {}

  private getEnabledCount(): string {
    const enabled = this.provider.models.filter(m => m.isEnabled).length
    return `${enabled}/${this.provider.models.length}`
  }

  build() {
    Column() {
      Row() {
        // ① 拖拽手柄 — 不消费长按，长按可穿透到 ListItem 触发拖拽
        if (this.searchKeywords.trim() === '') {
          Column() {
            SymbolGlyph($r('sys.symbol.line_3_horizontal'))
              .fontSize(16)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .width(28)
          .height(28)
          .justifyContent(FlexAlign.Center)
          .margin({ right: 4 })
        }

        // ② 内容区域 — 消费长按事件，阻止拖拽穿透
        Row() {
          ProviderIcon({
            iconType: this.provider.iconType,
            iconPath: this.provider.iconPath,
            textIcon: this.provider.textIcon,
            textIconBgColor: this.provider.textIconBgColor,
            customImagePath: this.provider.customImagePath,
            iconSize: 24,
            radius: 6,
            bgColor: $r('app.color.divider'),
            brandColor: this.provider.brandColor,
            fallbackSymbol: $r('sys.symbol.cloud'),
            fallbackColor: $r('app.color.text_tertiary')
          })
            .margin({ right: 8 })
            .opacity(this.provider.isConnected ? 1.0 : 0.5)

          Text(this.provider.name.toUpperCase())
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.provider.isConnected ? $r('app.color.text_secondary') : $r('app.color.text_tertiary'))
            .letterSpacing(1)

          Text(` (${this.getEnabledCount()})`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_tertiary'))

          // 系统服务标签
          if (this.provider.id === 'siliconflow') {
            Text($r('app.string.system_service'))
              .fontSize(11)
              .fontColor($r('app.color.primary'))
              .backgroundColor($r('app.color.primary_light'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .margin({ left: 8 })
          }

          Blank()

          // Toggle 开关（siliconflow 不显示）
          if (this.provider.id !== 'siliconflow') {
            Toggle({ type: ToggleType.Switch, isOn: this.provider.isConnected })
              .selectedColor(this.themePrimary)
              .onChange((isOn: boolean) => {
                if (this.provider.isConnected !== isOn) {
                  this.onToggleEnabled()
                }
              })
          }

          // 状态圆点：绿色=启用，灰色=停用
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.provider.isConnected ? '#4CAF50' : '#BDBDBD')
            .margin({ left: 12 })

          // 跳转箭头
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ left: 4 })
        }
        .layoutWeight(1)
        .gesture(LongPressGesture().onAction(() => {
          // 空实现：仅消费长按事件，阻止穿透到 ListItem 触发拖拽
        }))
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 16, bottom: 16 })
      .onClick(() => {
        this.onCardClick()
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }
}
