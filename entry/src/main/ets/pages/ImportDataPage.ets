import { picker, fileIo } from '@kit.CoreFileKit'
import { getImportExportService, ImportOptions, ImportPreview } from '../services/ImportExportService'
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
  getHdsTopNavigationContentTopPadding
} from '../utils/HdsVisualEffectUtil'
import { ImportOptionsPanel, ImportConflictStrategy } from '../components/sync/ImportOptionsPanel'

let importDataPathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct ImportDataPage {
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

  @Local selectedFilePath: string = ''
  @Local preview: ImportPreview | null = null
  @Local conflictStrategy: ImportConflictStrategy = 'skip'
  @Local importProviders: boolean = true
  @Local importPreferences: boolean = true
  @Local isImporting: boolean = false
  @Local importProgress: number = 0
  @Local showPreview: boolean = false
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

  private showImportToast(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  private handleBack(): void {
    if (importDataPathStack !== null && importDataPathStack.size() > 0) {
      importDataPathStack.pop()
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

  async selectFile(): Promise<void> {
    try {
      const documentViewPicker = new picker.DocumentViewPicker()
      const documentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.maxSelectNumber = 1

      const uris = await documentViewPicker.select(documentSelectOptions)
      if (uris && uris.length > 0) {
        console.info('ImportDataPage', `Selected URI: ${uris[0]}`)

        // 将 URI 文件复制到应用缓存目录
        const context = this.getUIContext().getHostContext()
        if (context) {
          const tempPath = `${context.cacheDir}/import_selected_${Date.now()}.zip`
          console.info('ImportDataPage', `Copying to temp path: ${tempPath}`)

          try {
            // 通过 fd 操作复制文件（picker URI 不能直接作为路径）
            const srcFile = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY)
            const destFile = fileIo.openSync(tempPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
            await fileIo.copyFile(srcFile.fd, destFile.fd)
            fileIo.closeSync(srcFile)
            fileIo.closeSync(destFile)

            this.selectedFilePath = tempPath
            console.info('ImportDataPage', `File copied successfully to: ${tempPath}`)

            await this.loadPreview()
          } catch (copyError) {
            console.error('ImportDataPage', `File copy failed: ${JSON.stringify(copyError)}`)
            this.showImportToast($r('app.string.import_file_copy_failed'), 3000, SnackBarTone.ERROR)
          }
        }
      }
    } catch (error) {
      console.error('ImportDataPage', `File selection failed: ${JSON.stringify(error)}`)
      this.showImportToast($r('app.string.import_file_select_failed'), 2000, SnackBarTone.ERROR)
    }
  }

  async loadPreview(): Promise<void> {
    if (this.selectedFilePath === '') {
      return
    }

    try {
      console.info('ImportDataPage', `Loading preview for: ${this.selectedFilePath}`)

      const exportService = getImportExportService()
      const context = this.getUIContext().getHostContext()
      if (context) {
        await exportService.initialize(context)
      }

      console.info('ImportDataPage', 'Calling previewImport...')
      this.preview = await exportService.previewImport(this.selectedFilePath)
      console.info('ImportDataPage', `Preview loaded: ${this.preview.sessionsCount} sessions`)

      this.showPreview = true
    } catch (error) {
      console.error('ImportDataPage', `Preview failed: ${JSON.stringify(error)}`)
      console.error('ImportDataPage', `Error details: ${error}`)
      this.showImportToast($r('app.string.import_file_parse_failed'), 3000, SnackBarTone.ERROR)
      this.selectedFilePath = ''
    }
  }

  async startImport(): Promise<void> {
    if (this.selectedFilePath === '' || this.preview === null) {
      return
    }

    this.isImporting = true
    this.importProgress = 0

    try {
      const exportService = getImportExportService()
      const context = this.getUIContext().getHostContext()
      if (context) {
        await exportService.initialize(context)
      }

      const options: ImportOptions = {
        conflictStrategy: this.conflictStrategy,
        importProviders: this.importProviders,
        importPreferences: this.importPreferences
      }

      const result = await exportService.importData(this.selectedFilePath, options, (progress: number) => {
        this.importProgress = progress
      })

      console.info(
        'ImportDataPage',
        `Import summary: imported=${result.imported}, overwritten=${result.overwritten}, skipped=${result.skipped}, preferences=${result.preferencesRestored}`
      )

      // 构建详细的导入结果摘要
      const summaryParts: string[] = []
      if (result.imported > 0) {
        summaryParts.push(`导入 ${result.imported} 个会话`)
      }
      if (result.overwritten > 0) {
        summaryParts.push(`覆盖 ${result.overwritten} 个`)
      }
      if (result.skipped > 0) {
        summaryParts.push(`跳过 ${result.skipped} 个`)
      }
      if (result.preferencesRestored > 0) {
        summaryParts.push(`恢复 ${result.preferencesRestored} 项偏好设置`)
      }
      const summaryMessage = summaryParts.length > 0 ? summaryParts.join('，') : '导入完成'
      this.showImportToast(summaryMessage, 3000, SnackBarTone.SUCCESS)
      this.handleBack()
    } catch (error) {
      console.error('ImportDataPage', `Import failed: ${JSON.stringify(error)}`)
      this.showImportToast($r('app.string.import_failed'), 2000, SnackBarTone.ERROR)
    } finally {
      this.isImporting = false
    }
  }

  @Builder
  private PageContent() {
    Column() {
      if (this.isImporting) {
        Row() {
          Column() {
            Text($r('app.string.import_progress'))
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .margin({ bottom: 24 })

            Progress({ value: this.importProgress, total: 100, type: ProgressType.Ring })
              .width(120)
              .height(120)
              .style({ strokeWidth: 8 })
              .color(this.themePrimary)

            Text(`${Math.floor(this.importProgress)}%`)
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 16 })
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
      } else if (!this.showPreview) {
        Row() {
          Column() {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(64)
              .fontColor([$r('app.color.text_tertiary')])
              .margin({ bottom: 16 })

            Text($r('app.string.import_select_file'))
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
              .margin({ bottom: 24 })

            Button('选择 ZIP 文件')
              .width(200)
              .height(48)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(this.themePrimary)
              .borderRadius(12)
              .onClick(() => {
                this.selectFile()
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: this.getContentMaxWidth() })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .padding({
          left: 16,
          right: 16,
          top: this.isDetailPaneMode() ? 0 : this.getCompactContentTopPadding()
        })
      } else {
        Scroll(this.compactScroller) {
          Row() {
            Column() {
              if (!this.isDetailPaneMode()) {
                Blank()
                  .width('100%')
                  .height(this.getCompactContentTopPadding())
              }

              this.SectionTitle($r('app.string.import_preview'))

              Column() {
                this.InfoRow('会话', `${this.preview?.sessionsCount || 0} 个`)
                Divider().color($r('app.color.divider'))
                this.InfoRow('消息', `${this.preview?.messagesCount || 0} 条`)
                Divider().color($r('app.color.divider'))
                this.InfoRow('附件', `${this.preview?.attachmentsCount || 0} 个`)
                Divider().color($r('app.color.divider'))
                this.InfoRow('供应商', `${this.preview?.providersCount || 0} 个`)

                if (this.preview && this.preview.preferencesCount > 0) {
                  Divider().color($r('app.color.divider'))
                  this.InfoRow('偏好设置', `${this.preview.preferencesCount} 项`)
                }

                if (this.preview && this.preview.conflicts.length > 0) {
                  Divider().color($r('app.color.divider'))
                  Row() {
                    Text('⚠️ 冲突')
                      .fontSize(16)
                      .fontColor($r('app.color.status_error'))
                      .layoutWeight(1)

                    Text(`${this.preview.conflicts.length} 个`)
                      .fontSize(16)
                      .fontColor($r('app.color.status_error'))
                      .fontWeight(FontWeight.Medium)
                  }
                  .width('100%')
                  .padding(16)
                }
              }
              .width('100%')
              .backgroundColor(getAppUiState().themeSurface)
              .borderRadius(16)
              .margin({ bottom: 24 })

              ImportOptionsPanel({
                importProviders: this.importProviders,
                importPreferences: this.importPreferences,
                conflictStrategy: this.conflictStrategy,
                hasConflicts: this.preview !== null && this.preview.conflicts.length > 0,
                radioGroup: 'importPageConflictStrategy',
                onImportProvidersChange: (value: boolean) => { this.importProviders = value },
                onImportPreferencesChange: (value: boolean) => { this.importPreferences = value },
                onConflictStrategyChange: (value: ImportConflictStrategy) => { this.conflictStrategy = value }
              })
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
            Button($r('app.string.import_start'))
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(this.themePrimary)
              .borderRadius(12)
              .onClick(() => {
                this.startImport()
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
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.import_title'))
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
      title: $r('app.string.import_title'),
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
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Text(value)
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding(16)
  }
}

@Builder
export function ImportDataPageBuilder(name: string, param: Object) {
  NavDestination() {
    ImportDataPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    importDataPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (importDataPathStack !== null && importDataPathStack.size() > 0) {
      importDataPathStack.pop()
    }
    return true
  })
}
