import { SymbolGlyphModifier } from '@kit.ArkUI'
import { ModelProvider, ModelInfo, ProviderType } from '../models/ChatModels'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { showToast } from '../utils/ToastUtil'
import {
  ProviderDetailPanel,
  ProviderDetailPresentationMode,
  tryHandleProviderDetailInternalBack
} from '../components/ProviderDetailSheet'
import { ProviderIcon, resolveProviderTextIconDisplayMode } from '../components/ProviderIcon'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { ModelCapabilityMatcher } from '../services/ModelCapabilityMatcher'
import { IconDownloadCache } from '../services/IconDownloadCache'
import {
  HdsNavigation,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  getHdsTopNavigationMaskExtraHeight,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { isSettingsPageExpandedLayout } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState, observeAppUiState } from '../state/AppUiState'
import { ProviderDetailRouteParams } from './ProviderDetailPage'
import {
  ProviderManageTabKey,
  filterProvidersByTab,
  reorderProvidersWithinTab
} from '../config/ProviderOrderUtils'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

let modelManagePagePathStack: NavPathStack | null = null
let modelManageInternalBackHandler: (() => boolean) | null = null
let modelManageRefreshHandler: (() => void) | null = null

export function notifyModelManageRefresh(): void {
  if (modelManageRefreshHandler !== null) {
    modelManageRefreshHandler()
  }
}

@Entry
@ComponentV2
struct ModelManagePage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  @Local allProviders: ModelProvider[] = []
  @Local isLoading: boolean = false
  @Local searchKeywords: string = ''
  @Local currentTabKey: ProviderManageTabKey = ProviderManageTabKey.ENABLED
  @Local selectedProviderId: string = ''
  @Local detailCreateMode: boolean = false
  @Local isMatchingIcons: boolean = false
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }
  private hasLoaded: boolean = false
  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()
  private layoutObserverDisposer: (() => void) | null = null
  private providerListScroller: ListScroller = new ListScroller()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private showManageToast(message: string | Resource, duration: number = 2000): void {
    showToast(this.getUIContext(), message, duration)
  }

  private handleBackNavigation(): boolean {
    if (modelManagePagePathStack !== null && modelManagePagePathStack.size() > 0) {
      modelManagePagePathStack.pop()
      return true
    }
    return false
  }

  private handleBack(): void {
    this.handlePageBackPressed()
  }

  private handleInternalBackPressed(): boolean {
    if (tryHandleProviderDetailInternalBack()) {
      return true
    }
    if (this.showEmbeddedProviderDetailPage()) {
      this.requestCloseProviderDetail()
      return true
    }
    return false
  }

  private handlePageBackPressed(): boolean {
    if (this.handleInternalBackPressed()) {
      return true
    }
    return this.handleBackNavigation()
  }

  onLayoutSizeClassChanged(): void {
    this.ensureExpandedDetailSelection()
  }

  onBackPress(): boolean {
    return this.handlePageBackPressed()
  }

  private isEmbeddedSettingsDetailPane(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private isExpandedLayout(): boolean {
    return isSettingsPageExpandedLayout(this.layoutSizeClass, this.settingsDetailPresentationMode, this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarMaskExtraHeight(): number {
    return getHdsTopNavigationMaskExtraHeight(this.windowWidthVp, this.windowHeightVp)
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp,
      this.windowHeightVp, (): void => this.CompactTitleStackBuilder())
  }

  private hasExpandedDetailSelection(): boolean {
    return this.detailCreateMode || this.selectedProviderId !== ''
  }

  private ensureExpandedDetailSelection(): void {
    if (!this.isExpandedLayout()) {
      return
    }
    if (this.detailCreateMode || this.selectedProviderId !== '') {
      return
    }
    if (this.allProviders.length > 0) {
      this.selectedProviderId = this.allProviders[0].id
    }
  }

  private ensureVisibleProviderTab(): void {
    const enabledCount = filterProvidersByTab(this.allProviders, ProviderManageTabKey.ENABLED).length
    const disabledCount = filterProvidersByTab(this.allProviders, ProviderManageTabKey.DISABLED).length
    if (this.currentTabKey === ProviderManageTabKey.ENABLED && enabledCount === 0 && disabledCount > 0) {
      this.currentTabKey = ProviderManageTabKey.DISABLED
      return
    }
    if (this.currentTabKey === ProviderManageTabKey.DISABLED && disabledCount === 0 && enabledCount > 0) {
      this.currentTabKey = ProviderManageTabKey.ENABLED
    }
  }

  private openProviderDetail(providerId: string): void {
    if (this.isExpandedLayout()) {
      this.detailCreateMode = false
      this.selectedProviderId = providerId
      return
    }
    if (!this.isEmbeddedSettingsDetailPane()) {
      this.openProviderDetailPage(providerId, false)
      return
    }
    this.detailCreateMode = false
    this.selectedProviderId = providerId
  }

  private openCreateProvider(): void {
    if (this.isExpandedLayout()) {
      this.detailCreateMode = true
      this.selectedProviderId = ''
      return
    }
    if (!this.isEmbeddedSettingsDetailPane()) {
      this.openProviderDetailPage('', true)
      return
    }
    this.detailCreateMode = true
    this.selectedProviderId = ''
  }

  private openProviderDetailPage(providerId: string, isCreateMode: boolean): void {
    if (modelManagePagePathStack === null) {
      return
    }
    const routeParams: ProviderDetailRouteParams = {
      providerId,
      isCreateMode
    }
    modelManagePagePathStack.pushPath({
      name: 'ProviderDetailPage',
      param: routeParams
    })
  }

  private requestCloseProviderDetail(): void {
    this.finalizeProviderDetailClosed()
  }

  private finalizeProviderDetailClosed(): void {
    this.refreshFromCache()
    this.detailCreateMode = false
    this.selectedProviderId = ''
    if (this.isExpandedLayout()) {
      this.ensureExpandedDetailSelection()
    }
  }

  private showEmbeddedProviderDetailPage(): boolean {
    return this.isEmbeddedSettingsDetailPane() && this.hasExpandedDetailSelection()
  }

  aboutToAppear(): void {
    modelManageInternalBackHandler = (): boolean => {
      return this.handleInternalBackPressed()
    }
    modelManageRefreshHandler = (): void => {
      this.refreshFromCache()
    }
    if (this.layoutObserverDisposer === null) {
      this.layoutObserverDisposer = observeAppUiState(['layoutSizeClass', 'windowWidthVp', 'windowHeightVp',
        'settingsDetailPresentationMode'], (): void => {
        this.onLayoutSizeClassChanged()
      })
    }
    this.loadData()
  }

  aboutToDisappear(): void {
    modelManageInternalBackHandler = null
    modelManageRefreshHandler = null
    if (this.layoutObserverDisposer !== null) {
      this.layoutObserverDisposer()
      this.layoutObserverDisposer = null
    }
  }

  onPageShow(): void {
    if (this.hasLoaded) {
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
    this.ensureVisibleProviderTab()
    this.ensureExpandedDetailSelection()
  }

  // 静默刷新数据（从 ViewModel 缓存同步，不访问数据库）
  // 复用现有对象引用以保持子组件 @Param 绑定稳定，但始终重新赋值数组以触发 @Local 响应式刷新——
  // 注意：providerViewModel.getCachedProviders() 返回的是内部缓存数组的同一引用，
  // 而 loadAllProviders/loadProviders 也会把该引用赋给 this.allProviders；
  // 当 saveProvider 通过 unshift 原地新增时，两个变量指向同一被修改的数组，
  // 单纯的 length / 顺序比较都会得出“无需重建”的错误结论，导致新建服务商后列表不刷新。
  private refreshFromCache(): void {
    const cachedProviders = this.providerViewModel.getCachedProviders()
    if (cachedProviders.length === 0) {
      return
    }

    // 构建当前列表的实例查找表，便于复用同 id 的现有实例
    const existingMap = new Map<string, ModelProvider>()
    for (let i = 0; i < this.allProviders.length; i++) {
      existingMap.set(this.allProviders[i].id, this.allProviders[i])
    }

    // 按缓存顺序构建新数组：能复用的就地同步属性（保持子组件绑定），新增项直接采用缓存实例
    const next: ModelProvider[] = []
    for (let i = 0; i < cachedProviders.length; i++) {
      const cached = cachedProviders[i]
      const existing = existingMap.get(cached.id)
      if (existing !== undefined && existing !== cached) {
        this.providerViewModel.syncProviderProperties(existing, cached)
        next.push(existing)
      } else {
        next.push(cached)
      }
    }

    // 始终重新赋值新数组，确保 @Local 检测到引用变化并触发列表刷新
    this.allProviders = next
    this.ensureVisibleProviderTab()
  }

  // 从数据库完整刷新（仅在从其他页面返回时使用）
  private async refreshFromDatabase(): Promise<void> {
    const savedProviders = await this.providerViewModel.loadAllProviders()
    if (savedProviders.length === 0) {
      return
    }

    const existingMap = new Map<string, ModelProvider>()
    for (let i = 0; i < this.allProviders.length; i++) {
      existingMap.set(this.allProviders[i].id, this.allProviders[i])
    }

    const next: ModelProvider[] = []
    for (let i = 0; i < savedProviders.length; i++) {
      const saved = savedProviders[i]
      const existing = existingMap.get(saved.id)
      if (existing !== undefined && existing !== saved) {
        this.providerViewModel.syncProviderProperties(existing, saved)
        next.push(existing)
      } else {
        next.push(saved)
      }
    }

    this.allProviders = next
    this.ensureVisibleProviderTab()
    this.ensureExpandedDetailSelection()
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
    const tabProviders = filterProvidersByTab(this.allProviders, this.currentTabKey)
    if (this.searchKeywords.trim() === '') {
      return tabProviders
    }
    const result: ModelProvider[] = []
    for (let i = 0; i < tabProviders.length; i++) {
      if (this.matchesSearch(tabProviders[i])) {
        result.push(tabProviders[i])
      }
    }
    return result
  }

  private getProviderListDataSource(): ModelProvider[] {
    return this.getFilteredProviders()
  }

  private getProviderListCachedCount(): number {
    const providerCount = this.getProviderListDataSource().length
    if (providerCount >= 60) {
      return 2
    }
    if (providerCount >= 20) {
      return 3
    }
    return 4
  }

  build() {
    Column() {
      if (this.showEmbeddedProviderDetailPage()) {
        this.EmbeddedProviderDetailPage()
      } else if (this.isEmbeddedSettingsDetailPane()) {
        Column() {
          this.DetailPaneHeader()
          this.CompactManageBody()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsNavigation() {
          this.CompactManageBody()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(getAppUiState().themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .bindToScrollable([this.providerListScroller])
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(true)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row({ space: 10 }) {
        Text($r('app.string.model_manage_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Button() {
          SymbolGlyph($r('sys.symbol.wand_and_stars'))
            .fontSize(18)
            .fontColor([$r('app.color.text_primary')])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.matchAllIcons()
        })

        Button() {
          SymbolGlyph($r('sys.symbol.plus_circle'))
            .fontSize(18)
            .fontColor([$r('app.color.text_primary')])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.openCreateProvider()
        })
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(getAppUiState().themeBackground)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private CompactTitleStackBuilder() {
    Row({ space: 6 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
      }
      .type(ButtonType.Normal)
      .stateEffect(false)
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.handleBack()
      })

      Text($r('app.string.model_manage_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Button() {
        SymbolGlyph($r('sys.symbol.wand_and_stars'))
          .fontSize(18)
          .fontColor([$r('app.color.text_primary')])
      }
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .backgroundColor($r('app.color.divider'))
      .onClick(() => {
        this.matchAllIcons()
      })

      Button() {
        SymbolGlyph($r('sys.symbol.plus_circle'))
          .fontSize(18)
          .fontColor([$r('app.color.text_primary')])
      }
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .backgroundColor($r('app.color.divider'))
      .onClick(() => {
        this.openCreateProvider()
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private CompactPageHeader() {
    Column() {
      Column()
        .width('100%')
        .height(this.px2vp(this.topAvoidHeight))

      Row({ space: 6 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.text_primary')])
        }
        .type(ButtonType.Normal)
        .stateEffect(false)
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.handleBack()
        })

        Text($r('app.string.model_manage_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Button() {
          SymbolGlyph($r('sys.symbol.wand_and_stars'))
            .fontSize(18)
            .fontColor([$r('app.color.text_primary')])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.matchAllIcons()
        })

        Button() {
          SymbolGlyph($r('sys.symbol.plus_circle'))
            .fontSize(18)
            .fontColor([$r('app.color.text_primary')])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.openCreateProvider()
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 12 })
      .alignItems(VerticalAlign.Center)

      Column()
        .width('100%')
        .height(this.getCompactTitleBarMaskExtraHeight())
        .backgroundColor(withColorAlpha(getAppUiState().themeBackground, '00'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    }
    .width('100%')
    .backgroundColor(withColorAlpha(getAppUiState().themeBackground, 'E6'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .renderGroup(true)
  }

  @Builder
  CompactManageBody() {
    Column() {
      this.ProviderListPane(false)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  ProviderListPane(isExpandedPane: boolean) {
    if (!isExpandedPane && !this.isEmbeddedSettingsDetailPane()) {
      List({ space: 8, scroller: this.providerListScroller }) {
        ListItem() {
          Column()
            .width('100%')
            .height(this.getCompactContentTopPadding())
        }
        .focusable(false)
        .selectable(false)

        ListItem() {
          this.ProviderStatusTabs(false)
        }
        .focusable(false)
        .selectable(false)

        ListItem() {
          this.ProviderSearchBar(false)
        }
        .focusable(false)
        .selectable(false)

        if (this.isLoading) {
          ListItem() {
            this.LoadingView()
          }
        } else {
          Repeat<ModelProvider>(this.getProviderListDataSource())
            .each((obj: RepeatItem<ModelProvider>) => {
              ListItem({ style: ListItemStyle.NONE }) {
                ProviderCardItem({
                  provider: obj.item,
                  searchKeywords: this.searchKeywords,
                  active: !this.detailCreateMode && this.selectedProviderId === obj.item.id,
                  onCardClick: () => {
                    this.openProviderDetail(obj.item.id)
                  },
                  onToggleEnabled: () => {
                    this.toggleProviderEnabled(obj.item)
                  }
                })
              }
              .margin({ left: 16, right: 16 })
              .borderRadius(16)
              .clip(true)
            })
            .key((item: ModelProvider) => {
              return item.id
            })
            .virtualScroll({ totalCount: this.getProviderListDataSource().length })
            .onMove((from: number, to: number) => {
              if (this.searchKeywords.trim() !== '') {
                return
              }
              this.allProviders = reorderProvidersWithinTab(this.allProviders, this.currentTabKey, from, to)
              this.saveOrder()
            })

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
              .backgroundColor(getAppUiState().themeSurface)
              .borderRadius(24)
              .onClick(() => {
                this.openCreateProvider()
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })
          }
        }

        ListItem() {
          Column().height(100)
        }
        .focusable(false)
        .selectable(false)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(this.getProviderListCachedCount())
      .backgroundColor(getAppUiState().themeBackground)
    } else {
      this.ProviderListPaneContent(isExpandedPane)
    }
  }

  @Builder
  private ProviderListPaneContent(isExpandedPane: boolean) {
    Column() {
      this.ProviderStatusTabs(isExpandedPane)

      this.ProviderSearchBar(isExpandedPane)

      if (this.isLoading) {
        this.LoadingView()
      } else {
        List({ space: 8, scroller: this.providerListScroller }) {
          Repeat<ModelProvider>(this.getProviderListDataSource())
            .each((obj: RepeatItem<ModelProvider>) => {
              ListItem({ style: ListItemStyle.NONE }) {
                ProviderCardItem({
                  provider: obj.item,
                  searchKeywords: this.searchKeywords,
                  active: !this.detailCreateMode && this.selectedProviderId === obj.item.id,
                  onCardClick: () => {
                    this.openProviderDetail(obj.item.id)
                  },
                  onToggleEnabled: () => {
                    this.toggleProviderEnabled(obj.item)
                  }
                })
              }
              .margin({ left: 16, right: 16 })
              .borderRadius(16)
              .clip(true)
            })
            .key((item: ModelProvider) => {
              return item.id
            })
            .virtualScroll({ totalCount: this.getProviderListDataSource().length })
            .onMove((from: number, to: number) => {
              if (this.searchKeywords.trim() !== '') {
                return
              }
              this.allProviders = reorderProvidersWithinTab(this.allProviders, this.currentTabKey, from, to)
              this.saveOrder()
            })

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
              .backgroundColor(getAppUiState().themeSurface)
              .borderRadius(24)
              .onClick(() => {
                this.openCreateProvider()
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })
          }

          ListItem() {
            Column().height(100)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(this.getProviderListCachedCount())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  private ProviderSearchBar(isExpandedPane: boolean) {
    Row() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])

        TextInput({ text: this.searchKeywords, placeholder: $r('app.string.filter_models_placeholder') })
          .layoutWeight(1)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => {
            this.searchKeywords = value
          })
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12 })
      .backgroundColor(getAppUiState().themeBackground)
      .borderRadius(20)
      .border({
        width: 1,
        color: $r('app.color.divider')
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: isExpandedPane ? 16 : 0,
      bottom: 8
    })
  }

  @Builder
  private ProviderStatusTabs(isExpandedPane: boolean) {
    Row({ space: 20 }) {
      this.ProviderStatusTabButton(ProviderManageTabKey.ENABLED, $r('app.string.provider_tab_enabled'))
      this.ProviderStatusTabButton(ProviderManageTabKey.DISABLED, $r('app.string.provider_tab_disabled'))
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: isExpandedPane ? 16 : 8, bottom: 8 })
  }

  @Builder
  private ProviderStatusTabButton(tabKey: ProviderManageTabKey, title: Resource) {
    Button() {
      Column({ space: 6 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(this.currentTabKey === tabKey ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.currentTabKey === tabKey ? $r('app.color.text_primary') : $r('app.color.text_secondary'))

        Column()
          .width(this.currentTabKey === tabKey ? 24 : 14)
          .height(3)
          .borderRadius(2)
          .backgroundColor(this.currentTabKey === tabKey ? this.themePrimary : Color.Transparent)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .type(ButtonType.Normal)
    .stateEffect(false)
    .padding({ left: 0, right: 0, top: 4, bottom: 4 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (this.currentTabKey === tabKey) {
        return
      }
      this.currentTabKey = tabKey
    })
  }

  @Builder
  EmbeddedProviderDetailPage() {
    ProviderDetailPanel({
      providerId: this.selectedProviderId,
      isCreateMode: this.detailCreateMode,
      closeOnSave: true,
      closeOnModelsSelected: false,
      presentationMode: ProviderDetailPresentationMode.DETAIL_PANE,
      onProviderChanged: (providerId: string, wasCreateMode: boolean) => {
        this.refreshFromCache()
        if (wasCreateMode) {
          this.detailCreateMode = false
          this.selectedProviderId = providerId
        }
      },
      onClose: () => {
        this.requestCloseProviderDetail()
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
            this.openCreateProvider()
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

  // 一键同步模型能力并匹配图标
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
    let capabilityMatchedCount = 0
    let totalModels = 0
    // 去重：同一 logoUrl 只下载一次
    const downloadedUrls = new Set<string>()

    for (let i = 0; i < this.allProviders.length; i++) {
      const provider = this.allProviders[i]
      const providerCapabilityMatched = await matcher.applyCapabilitiesBatch(provider.models)
      capabilityMatchedCount += providerCapabilityMatched

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

      if (providerCapabilityMatched > 0) {
        await this.providerViewModel.saveProvider(provider)
      }
    }

    // 显式保存，确保冷启动后可直接恢复
    await matcher.savePersistedLogoIndex()

    // 触发 UI 刷新
    this.allProviders = [...this.allProviders]
    this.showManageToast(`已同步 ${capabilityMatchedCount}/${totalModels} 个模型能力，匹配 ${matchedCount}/${totalModels} 个模型图标`)
    this.isMatchingIcons = false
  }
}

@ComponentV2
struct ProviderCardItem {
  @Param provider: ModelProvider = new ModelProvider('', '', ProviderType.CUSTOM, '', $r('app.color.brand_custom'))
  @Param searchKeywords: string = ''
  @Param active: boolean = false
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  @Event onCardClick: () => void = () => {}
  @Event onToggleEnabled: () => void = () => {}

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
            textIconDisplayMode: resolveProviderTextIconDisplayMode(this.provider.isConnected),
            iconSize: 24,
            radius: 6,
            bgColor: $r('app.color.divider'),
            brandColor: this.provider.brandColor,
            fallbackSymbol: $r('sys.symbol.cloud'),
            fallbackColor: $r('app.color.text_tertiary')
          })
            .margin({ right: 8 })

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
              .fontColor(this.themePrimary)
              .backgroundColor(this.themePrimaryLight)
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
    .borderRadius(16)
    .clip(true)
    .backgroundColor(this.active ? this.themePrimaryLight : getAppUiState().themeSurface)
    .border(this.active ? { width: 1.5, color: this.themePrimary } : { width: 0, color: Color.Transparent })
  }
}

@Builder
export function ModelManagePageBuilder(name: string, param: Object) {
  NavDestination() {
    ModelManagePage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    modelManagePagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (tryHandleModelManageInternalBack()) {
      return true
    }
    if (modelManagePagePathStack !== null && modelManagePagePathStack.size() > 0) {
      modelManagePagePathStack.pop()
      return true
    }
    return false
  })
}

export function tryHandleModelManageInternalBack(): boolean {
  if (modelManageInternalBackHandler === null) {
    return false
  }
  return modelManageInternalBackHandler()
}
