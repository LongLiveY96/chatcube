import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  buildPointLightBorderEffect
} from '../utils/HdsVisualEffectUtil'
import {
  getDatabaseService,
  ModelUsageRankingItem,
  UsageOverviewStats
} from '../services/DatabaseService'

const TAG = 'UsageStatsPage'
const RANGE_30D_MS: number = 30 * 24 * 60 * 60 * 1000
const RANKING_LIMIT: number = 10

let usageStatsPagePathStack: NavPathStack | null = null

enum UsageRangeKey {
  ALL = 'all',
  LAST_30D = 'last_30d'
}

@Entry
@ComponentV2
struct UsageStatsPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeSurface(): string {
    return getAppUiState().themeSurface
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

  @Local currentRange: UsageRangeKey = UsageRangeKey.ALL
  @Local overview: UsageOverviewStats = {
    sessionCount: 0,
    messageCount: 0,
    distinctModelCount: 0,
    activeDayCount: 0
  }
  @Local ranking: ModelUsageRankingItem[] = []
  @Local isLoading: boolean = true

  private compactScroller: Scroller = new Scroller()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.loadStats()
  }

  private getRangeStartMs(): number {
    if (this.currentRange === UsageRangeKey.LAST_30D) {
      return Date.now() - RANGE_30D_MS
    }
    return 0
  }

  private async loadStats(): Promise<void> {
    this.isLoading = true
    try {
      const db = getDatabaseService()
      const rangeStart = this.getRangeStartMs()
      const overview = await db.getUsageOverview(rangeStart)
      const ranking = await db.getModelUsageRanking(rangeStart, RANKING_LIMIT)
      this.overview = overview
      this.ranking = ranking
    } catch (error) {
      console.error(TAG, `Failed to load usage stats: ${JSON.stringify(error)}`)
    } finally {
      this.isLoading = false
    }
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private handleBack(): void {
    if (usageStatsPagePathStack !== null && usageStatsPagePathStack.size() > 0) {
      usageStatsPagePathStack.pop()
    }
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp,
      this.windowHeightVp, (): void => this.CompactTitleStackBuilder())
  }

  private getMaxRankingCount(): number {
    let max = 0
    for (let i = 0; i < this.ranking.length; i++) {
      const c = this.ranking[i].count
      if (c > max) {
        max = c
      }
    }
    return max
  }

  private getRankingFraction(count: number): number {
    const max = this.getMaxRankingCount()
    if (max <= 0) {
      return 0
    }
    const fraction = count / max
    if (fraction < 0.04) {
      return 0.04
    }
    return fraction
  }

  private getRankingDisplayName(item: ModelUsageRankingItem): string {
    if (item.modelName !== '') {
      return item.modelName
    }
    if (item.modelId !== '') {
      return item.modelId
    }
    return '—'
  }

  private isEmpty(): boolean {
    return this.ranking.length === 0 && this.overview.messageCount === 0
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.settings_usage_stats'),
      onBack: () => {
        this.handleBack()
      }
    })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_usage_stats'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(this.themeBackground)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private RangeTabButton(rangeKey: UsageRangeKey, title: ResourceStr) {
    Button() {
      Column({ space: 6 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(this.currentRange === rangeKey ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.currentRange === rangeKey ? $r('app.color.text_primary') : $r('app.color.text_secondary'))

        Column()
          .width(this.currentRange === rangeKey ? 24 : 14)
          .height(3)
          .borderRadius(2)
          .backgroundColor(this.currentRange === rangeKey ? this.themePrimary : Color.Transparent)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .type(ButtonType.Normal)
    .stateEffect(false)
    .padding({ left: 0, right: 0, top: 4, bottom: 4 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (this.currentRange === rangeKey) {
        return
      }
      this.currentRange = rangeKey
      this.loadStats()
    })
  }

  @Builder
  private RangeTabs() {
    Row({ space: 20 }) {
      this.RangeTabButton(UsageRangeKey.ALL, $r('app.string.usage_stats_range_all'))
      this.RangeTabButton(UsageRangeKey.LAST_30D, $r('app.string.usage_stats_range_30d'))
      Blank()
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 8, bottom: 8 })
  }

  @Builder
  private SectionTitle(title: ResourceStr, subtitle: ResourceStr | null) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      if (subtitle !== null) {
        Text(subtitle)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 4, bottom: 6 })
  }

  @Builder
  private MetricsGrid() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column() {
          this.InlineMetricCard($r('sys.symbol.message'),
            $r('app.string.usage_stats_metric_sessions'),
            this.overview.sessionCount,
            $r('app.string.usage_stats_unit_count'))
        }.layoutWeight(1)
        Column() {
          this.InlineMetricCard($r('sys.symbol.ellipsis_message'),
            $r('app.string.usage_stats_metric_messages'),
            this.overview.messageCount,
            $r('app.string.usage_stats_unit_count'))
        }.layoutWeight(1)
      }
      .width('100%')

      Row({ space: 10 }) {
        Column() {
          this.InlineMetricCard($r('sys.symbol.square_stack_3d'),
            $r('app.string.usage_stats_metric_models'),
            this.overview.distinctModelCount,
            $r('app.string.usage_stats_unit_count'))
        }.layoutWeight(1)
        Column() {
          this.InlineMetricCard($r('sys.symbol.calendar'),
            $r('app.string.usage_stats_metric_active_days'),
            this.overview.activeDayCount,
            $r('app.string.usage_stats_unit_day'))
        }.layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private InlineMetricCard(icon: Resource, title: ResourceStr, value: number, unit: ResourceStr) {
    Column() {
      Row({ space: 8 }) {
        Column() {
          SymbolGlyph(icon)
            .fontSize(16)
            .fontColor([this.themePrimary])
        }
        .width(28)
        .height(28)
        .borderRadius(9)
        .backgroundColor(this.themePrimaryLight)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Text(title)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 4 }) {
        Text(value.toString())
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(unit)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ bottom: 4 })
      }
      .width('100%')
      .margin({ top: 10 })
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.divider') })
    .visualEffect(buildPointLightBorderEffect())
  }

  @Builder
  private RankingRow(item: ModelUsageRankingItem, rank: number) {
    Column({ space: 8 }) {
      Row() {
        Text(`${rank}`)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(rank <= 3 ? this.themePrimary : $r('app.color.text_tertiary'))
          .width(22)

        Text(this.getRankingDisplayName(item))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`${item.count}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 进度条
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height(6)
          .borderRadius(3)
          .backgroundColor($r('app.color.divider'))

        Column()
          .width(`${this.getRankingFraction(item.count) * 100}%`)
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.themePrimary)
      }
      .width('100%')
      .margin({ left: 22 })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 14, right: 14 })
  }

  @Builder
  private RankingCard() {
    Column() {
      ForEach(this.ranking, (item: ModelUsageRankingItem, index: number) => {
        Column() {
          this.RankingRow(item, index + 1)
          if (index < this.ranking.length - 1) {
            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 50, right: 14 })
          }
        }
      }, (item: ModelUsageRankingItem, index: number) => `${index}_${item.modelName}_${item.modelId}`)
    }
    .width('100%')
    .backgroundColor(this.themeSurface)
    .borderRadius(18)
    .clip(true)
    .border({ width: 1, color: $r('app.color.divider') })
    .visualEffect(buildPointLightBorderEffect())
  }

  @Builder
  private EmptyState() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])
        .margin({ bottom: 4 })
      Text($r('app.string.usage_stats_empty_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      Text($r('app.string.usage_stats_empty_desc'))
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .padding({ top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private PageContent() {
    Scroll(this.compactScroller) {
      Row() {
        Column() {
          if (!this.isDetailPaneMode()) {
            Blank()
              .width('100%')
              .height(this.getCompactContentTopPadding())
          }

          this.RangeTabs()

          if (this.isEmpty() && !this.isLoading) {
            this.EmptyState()
          } else {
            // 总览
            Column() {
              this.SectionTitle($r('app.string.usage_stats_overview_title'), null)
              this.MetricsGrid()
            }
            .width('100%')
            .margin({ top: 6 })

            // 模型排行
            if (this.ranking.length > 0) {
              Column() {
                this.SectionTitle($r('app.string.usage_stats_ranking_title'),
                  $r('app.string.usage_stats_ranking_subtitle'))
                this.RankingCard()
              }
              .width('100%')
              .margin({ top: 18 })
            }
          }

          Blank().width('100%').height(28)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        Column() {
          this.DetailPaneHeader()
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .bindToScrollable([this.compactScroller])
        .titleMode(HdsNavigationTitleMode.MINI)
        .hideBackButton(true)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }
}

@Builder
export function UsageStatsPageBuilder(name: string, param: Object) {
  NavDestination() {
    UsageStatsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    usageStatsPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (usageStatsPagePathStack !== null && usageStatsPagePathStack.size() > 0) {
      usageStatsPagePathStack.pop()
    }
    return true
  })
}
