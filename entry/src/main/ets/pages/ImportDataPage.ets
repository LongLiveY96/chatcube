import { picker, fileIo } from '@kit.CoreFileKit'
import { getImportExportService, ImportOptions, ImportPreview } from '../services/ImportExportService'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'

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

  @Local selectedFilePath: string = ''
  @Local preview: ImportPreview | null = null
  @Local conflictStrategy: 'skip' | 'overwrite' | 'ask' = 'skip'
  @Local importProviders: boolean = true
  @Local importPreferences: boolean = true
  @Local isImporting: boolean = false
  @Local importProgress: number = 0
  @Local showPreview: boolean = false

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
            await fileIo.copyFile(uris[0], tempPath)

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
        .padding({ left: 16, right: 16 })
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
        .padding({ left: 16, right: 16 })
      } else {
        Scroll() {
          Row() {
            Column() {
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
              .backgroundColor($r('app.color.surface'))
              .borderRadius(16)
              .margin({ bottom: 24 })

              if (this.preview && this.preview.conflicts.length > 0) {
                this.SectionTitle($r('app.string.import_conflict_strategy'))

                Column() {
                  this.RadioRow($r('app.string.import_strategy_skip'), 'skip', this.conflictStrategy === 'skip', () => {
                    this.conflictStrategy = 'skip'
                  })
                  Divider().color($r('app.color.divider'))
                  this.RadioRow($r('app.string.import_strategy_overwrite'), 'overwrite',
                    this.conflictStrategy === 'overwrite', () => {
                      this.conflictStrategy = 'overwrite'
                    })
                  Divider().color($r('app.color.divider'))
                  this.RadioRow($r('app.string.import_strategy_ask'), 'ask', this.conflictStrategy === 'ask', () => {
                    this.conflictStrategy = 'ask'
                  })
                }
                .width('100%')
                .backgroundColor($r('app.color.surface'))
                .borderRadius(16)
                .margin({ bottom: 24 })
              }

              this.SectionTitle($r('app.string.import_options'))

              Column() {
                this.OptionRow($r('app.string.import_providers'), this.importProviders, (value: boolean) => {
                  this.importProviders = value
                })
                Divider().color($r('app.color.divider'))
                this.OptionRow($r('app.string.import_preferences'), this.importPreferences, (value: boolean) => {
                  this.importPreferences = value
                })
              }
              .width('100%')
              .backgroundColor($r('app.color.surface'))
              .borderRadius(16)
            }
            .width('100%')
            .constraintSize({ maxWidth: this.getContentMaxWidth() })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ left: 16, right: 16, bottom: 100 })
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
        .padding({ left: 16, right: 16, top: 12, bottom: 12 + this.px2vp(this.bottomAvoidHeight) })
        .backgroundColor($r('app.color.background'))
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
    .backgroundColor($r('app.color.background'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private CompactPageHeader() {
    Column() {
      Column()
        .width('100%')
        .height(this.px2vp(this.topAvoidHeight))

      Row({ space: 4 }) {
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

        Text($r('app.string.import_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .margin({ left: 4 })

        Column()
          .width(40)
          .height(40)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor($r('app.color.background'))
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
        Column() {
          this.CompactPageHeader()
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.background'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
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

  @Builder
  RadioRow(
    title: Resource,
    value: string,
    checked: boolean,
    onChange: () => void
  ) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Radio({ value: value, group: 'conflictStrategy' })
        .checked(checked)
        .onChange(onChange)
    }
    .width('100%')
    .padding(16)
    .onClick(onChange)
  }

  @Builder
  OptionRow(
    title: Resource,
    checked: boolean,
    onChange: (value: boolean) => void
  ) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .onChange(onChange)
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

