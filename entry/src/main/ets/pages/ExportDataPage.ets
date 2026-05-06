import { picker, fileIo } from '@kit.CoreFileKit'
import { ChatSession } from '../models/ChatModels'
import { ChatViewModel } from '../viewmodels/ChatViewModel'
import { getImportExportService, ExportOptions } from '../services/ImportExportService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import {
  getSettingsPageCompactTabsOverlayInset,
  getSettingsPageContentMaxWidth
} from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import { ExportOptionsPanel } from '../components/sync/ExportOptionsPanel'

let exportDataPathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct ExportDataPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get bottomAvoidHeight(): number {
    return getAppUiState().bottomAvoidHeight
  }
  // 主题颜色
  private get themePrimary(): string {
    return getAppUiState().themePrimary
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

  @Local sessions: ChatSession[] = []
  @Local selectedSessionIds: string[] = []
  @Local selectAll: boolean = true
  @Local includeAttachments: boolean = true
  @Local includeProviders: boolean = true
  @Local includePreferences: boolean = true
  @Local isExporting: boolean = false
  @Local exportProgress: number = 0
  private chatViewModel: ChatViewModel = ServiceRegistry.chat()
  private compactScroller: Scroller = new Scroller()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private getBaseBottomInset(): number {
    return this.px2vp(this.bottomAvoidHeight)
  }

  private getCompactTabsOverlayInset(): number {
    return getSettingsPageCompactTabsOverlayInset(this.getBaseBottomInset(), this.settingsDetailPresentationMode)
  }

  private getScrollBottomPadding(): number {
    return 100 + this.getCompactTabsOverlayInset()
  }

  private getBottomActionBarPadding(): number {
    return 12 + this.getBaseBottomInset() + this.getCompactTabsOverlayInset()
  }

  private showExportToast(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  private handleBack(): void {
    if (exportDataPathStack !== null && exportDataPathStack.size() > 0) {
      exportDataPathStack.pop()
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

  aboutToAppear(): void {
    this.loadSessions()
  }

  async loadSessions(): Promise<void> {
    this.sessions = await this.chatViewModel.getAllSessions()
    // 默认全选
    if (this.selectAll) {
      this.selectedSessionIds = this.sessions.map(s => s.id)
    }
  }

  toggleSelectAll(): void {
    this.selectAll = !this.selectAll
    if (this.selectAll) {
      this.selectedSessionIds = this.sessions.map(s => s.id)
    } else {
      this.selectedSessionIds = []
    }
  }

  toggleSession(sessionId: string): void {
    const index = this.selectedSessionIds.indexOf(sessionId)
    if (index >= 0) {
      this.selectedSessionIds.splice(index, 1)
    } else {
      this.selectedSessionIds.push(sessionId)
    }
    this.selectAll = this.selectedSessionIds.length === this.sessions.length
  }

  async startExport(): Promise<void> {
    if (this.selectedSessionIds.length === 0) {
      this.showExportToast($r('app.string.export_select_session_required'), 2000, SnackBarTone.ERROR)
      return
    }

    this.isExporting = true
    this.exportProgress = 0

    try {
      const exportService = getImportExportService()
      const context = this.getUIContext().getHostContext()
      if (context) {
        await exportService.initialize(context)
      }

      const options: ExportOptions = {
        sessionIds: this.selectAll ? undefined : this.selectedSessionIds,
        includeAttachments: this.includeAttachments,
        includeProviders: this.includeProviders,
        includeApiKeys: true,
        includePreferences: this.includePreferences
      }

      // 导出数据
      const zipPath = await exportService.exportData(options, (progress: number) => {
        this.exportProgress = progress
      })

      // 使用文件选择器保存
      const documentSaveOptions = new picker.DocumentSaveOptions()
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-').substring(0, 19)
      documentSaveOptions.newFileNames = [`chatcube_export_${timestamp}.zip`]
      documentSaveOptions.fileSuffixChoices = ['.zip']

      if (context) {
        const documentViewPicker = new picker.DocumentViewPicker(context)
        const saveUris = await documentViewPicker.save(documentSaveOptions)

        if (saveUris && saveUris.length > 0) {
          // 复制文件到用户选择的位置（通过 fd 操作，picker URI 不能直接作为路径）
          const srcFile = fileIo.openSync(zipPath, fileIo.OpenMode.READ_ONLY)
          const destFile = fileIo.openSync(saveUris[0], fileIo.OpenMode.READ_WRITE)
          await fileIo.copyFile(srcFile.fd, destFile.fd)
          fileIo.closeSync(srcFile)
          fileIo.closeSync(destFile)

          // 删除临时文件
          fileIo.unlinkSync(zipPath)

          this.showExportToast($r('app.string.export_success'), 2000, SnackBarTone.SUCCESS)
          this.handleBack()
        }
      }
    } catch (error) {
      console.error('ExportDataPage', `Export failed: ${JSON.stringify(error)}`)
      this.showExportToast($r('app.string.export_failed'), 2000, SnackBarTone.ERROR)
    } finally {
      this.isExporting = false
    }
  }

  @Builder
  private PageContent() {
    Column() {
      if (this.isExporting) {
        this.ExportingProgress()
      } else {
        Scroll(this.compactScroller) {
          Row() {
            Column() {
              if (!this.isDetailPaneMode()) {
                Blank()
                  .width('100%')
                  .height(this.getCompactContentTopPadding())
              }

              this.SectionTitle($r('app.string.export_select_sessions'))
              this.SessionPickerCard()

              this.SectionTitle($r('app.string.export_options'))

              ExportOptionsPanel({
                includeAttachments: this.includeAttachments,
                includeProviders: this.includeProviders,
                includePreferences: this.includePreferences,
                onIncludeAttachmentsChange: (value: boolean) => { this.includeAttachments = value },
                onIncludeProvidersChange: (value: boolean) => { this.includeProviders = value },
                onIncludePreferencesChange: (value: boolean) => { this.includePreferences = value }
              })

              this.ExportSecurityNotice()
            }
            .width('100%')
            .constraintSize({ maxWidth: this.getContentMaxWidth() })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ left: 16, right: 16, bottom: this.getScrollBottomPadding() })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Row() {
          Column() {
            Button($r('app.string.export_start'))
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(this.themePrimary)
              .borderRadius(12)
              .enabled(this.selectedSessionIds.length > 0)
              .onClick(() => {
                this.startExport()
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: this.getContentMaxWidth() })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: 16, right: 16, top: 12, bottom: this.getBottomActionBarPadding() })
        .backgroundColor(getAppUiState().themeBackground)
        .shadow({
          radius: 8,
          color: '#10000000',
          offsetY: -2
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private SessionPickerCard() {
    // 头部:全选 toggle + 已选计数
    Column() {
      Row() {
        Column() {
          Text($r('app.string.export_select_all'))
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
          Text(`已选 ${this.selectedSessionIds.length} / ${this.sessions.length}`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.selectAll })
          .onChange((_value: boolean) => {
            this.toggleSelectAll()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    }
    .width('100%')
    .backgroundColor(getAppUiState().themeSurface)
    .borderRadius(16)
    .margin({ bottom: 12 })

    // 会话列表
    Column() {
      ForEach(this.sessions, (session: ChatSession, index: number) => {
        Column() {
          this.SessionRow(session)
          if (index < this.sessions.length - 1) {
            Divider().color($r('app.color.divider')).margin({ left: 52 })
          }
        }
      }, (session: ChatSession) => session.id)
    }
    .width('100%')
    .backgroundColor(getAppUiState().themeSurface)
    .borderRadius(16)
    .margin({ bottom: 24 })
  }

  @Builder
  private SessionRow(session: ChatSession) {
    Row() {
      // 左侧选中状态图标
      Stack() {
        if (this.selectedSessionIds.includes(session.id)) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(22)
            .fontColor([this.themePrimary])
        } else {
          SymbolGlyph($r('sys.symbol.circle'))
            .fontSize(22)
            .fontColor([$r('app.color.text_tertiary')])
        }
      }
      .width(28)
      .height(28)
      .margin({ right: 12 })

      // 会话标题 + 副信息
      Column() {
        Text(session.title)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.buildSessionSubtitle(session))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 3 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => { this.toggleSession(session.id) })
  }

  private buildSessionSubtitle(session: ChatSession): string {
    const parts: string[] = []
    if (session.messageCount > 0) {
      parts.push(`${session.messageCount} 条消息`)
    }
    parts.push(this.formatRelativeTime(session.updatedAt))
    return parts.join(' · ')
  }

  private formatRelativeTime(ts: number): string {
    if (ts <= 0) {
      return ''
    }
    const diffMs = Date.now() - ts
    if (diffMs < 60_000) {
      return '刚刚'
    }
    if (diffMs < 3_600_000) {
      return `${Math.floor(diffMs / 60_000)} 分钟前`
    }
    if (diffMs < 86_400_000) {
      return `${Math.floor(diffMs / 3_600_000)} 小时前`
    }
    if (diffMs < 604_800_000) {
      return `${Math.floor(diffMs / 86_400_000)} 天前`
    }
    return new Date(ts).toLocaleDateString('zh-CN')
  }

  private getExportStageLabel(): Resource {
    if (this.exportProgress < 15) {
      return $r('app.string.export_stage_collecting')
    } else if (this.exportProgress < 30) {
      return $r('app.string.export_stage_processing')
    } else if (this.exportProgress < 60) {
      return $r('app.string.export_stage_writing')
    } else if (this.exportProgress < 90) {
      return $r('app.string.export_stage_archiving')
    }
    return $r('app.string.export_stage_finalizing')
  }

  @Builder
  private ExportingProgress() {
    Row() {
      Column() {
        Text($r('app.string.export_progress'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 28 })

        Stack() {
          Progress({ value: this.exportProgress, total: 100, type: ProgressType.Ring })
            .width(140)
            .height(140)
            .style({ strokeWidth: 10 })
            .color(this.themePrimary)

          Column() {
            Text(`${Math.floor(this.exportProgress)}`)
              .fontSize(34)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('%')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
        }
        .width(140)
        .height(140)

        Text(this.getExportStageLabel())
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 24 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .constraintSize({ maxWidth: this.getContentMaxWidth() })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({
      left: 16,
      right: 16,
      top: this.isDetailPaneMode() ? 0 : this.getCompactContentTopPadding()
    })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.export_title'))
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
    .backgroundColor(getAppUiState().themeBackground)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.export_title'),
      onBack: () => {
        this.handleBack()
      }
    })
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
        .backgroundColor(getAppUiState().themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .bindToScrollable([this.compactScroller])
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
  SectionTitle(title: Resource) {
    Text(title)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .fontWeight(FontWeight.Medium)
      .margin({ top: 24, bottom: 12, left: 4 })
  }

  @Builder
  ExportSecurityNotice() {
    Text($r('app.string.export_security_note'))
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .lineHeight(19)
      .margin({ top: 10, left: 4, right: 4 })
  }
}

@Builder
export function ExportDataPageBuilder(name: string, param: Object) {
  NavDestination() {
    ExportDataPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    exportDataPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (exportDataPathStack !== null && exportDataPathStack.size() > 0) {
      exportDataPathStack.pop()
    }
    return true
  })
}
