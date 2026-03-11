import { picker, fileIo } from '@kit.CoreFileKit'
import { ChatSession } from '../models/ChatModels'
import { ChatViewModel } from '../viewmodels/ChatViewModel'
import { getImportExportService, ExportOptions } from '../services/ImportExportService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'

@Entry
@ComponentV2
struct ExportDataPage {
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

  @Local sessions: ChatSession[] = []
  @Local selectedSessionIds: string[] = []
  @Local selectAll: boolean = true
  @Local includeAttachments: boolean = true
  @Local includeProviders: boolean = true
  @Local includeApiKeys: boolean = false
  @Local includePreferences: boolean = true
  @Local isExporting: boolean = false
  @Local exportProgress: number = 0
  private chatViewModel: ChatViewModel = ServiceRegistry.chat()

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

  private showExportToast(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
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
        includeApiKeys: this.includeApiKeys,
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
          // 复制文件到用户选择的位置
          const srcFile = fileIo.openSync(zipPath, fileIo.OpenMode.READ_ONLY)
          const stat = fileIo.statSync(srcFile.fd)
          const buffer = new ArrayBuffer(stat.size)
          fileIo.readSync(srcFile.fd, buffer)
          fileIo.closeSync(srcFile)

          const destFile = fileIo.openSync(saveUris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
          fileIo.writeSync(destFile.fd, buffer)
          fileIo.closeSync(destFile)

          // 删除临时文件
          fileIo.unlinkSync(zipPath)

          this.showExportToast($r('app.string.export_success'), 2000, SnackBarTone.SUCCESS)
          this.getUIContext().getRouter().back()
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
        Row() {
          Column() {
            Text($r('app.string.export_progress'))
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .margin({ bottom: 24 })

            Progress({ value: this.exportProgress, total: 100, type: ProgressType.Ring })
              .width(120)
              .height(120)
              .style({ strokeWidth: 8 })
              .color(this.themePrimary)

            Text(`${Math.floor(this.exportProgress)}%`)
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
      } else {
        Scroll() {
          Row() {
            Column() {
              this.SectionTitle($r('app.string.export_select_sessions'))

              Column() {
                Row() {
                  Checkbox({ name: 'selectAll', group: 'sessions' })
                    .select(this.selectAll)
                    .onChange((_value: boolean) => {
                      this.toggleSelectAll()
                    })
                    .margin({ right: 12 })

                  Text(this.selectAll ? $r('app.string.export_all_sessions') :
                    `已选择 ${this.selectedSessionIds.length} 个会话`)
                    .fontSize(16)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                }
                .width('100%')
                .padding(16)

                Divider().color($r('app.color.divider'))

                ForEach(this.sessions, (session: ChatSession) => {
                  Column() {
                    Row() {
                      Checkbox({ name: session.id, group: 'sessions' })
                        .select(this.selectedSessionIds.includes(session.id))
                        .onChange((_value: boolean) => {
                          this.toggleSession(session.id)
                        })
                        .margin({ right: 12 })

                      Column() {
                        Text(session.title)
                          .fontSize(16)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })

                        Text(new Date(session.updatedAt).toLocaleString('zh-CN'))
                          .fontSize(14)
                          .fontColor($r('app.color.text_secondary'))
                          .margin({ top: 4 })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                    }
                    .width('100%')
                    .padding(16)

                    if (session.id !== this.sessions[this.sessions.length - 1].id) {
                      Divider().color($r('app.color.divider')).margin({ left: 52 })
                    }
                  }
                }, (session: ChatSession) => session.id)
              }
              .width('100%')
              .backgroundColor($r('app.color.surface'))
              .borderRadius(16)
              .margin({ bottom: 24 })

              this.SectionTitle($r('app.string.export_options'))

              Column() {
                this.OptionRow($r('app.string.export_include_attachments'), '', this.includeAttachments,
                  (value: boolean) => { this.includeAttachments = value })
                Divider().color($r('app.color.divider'))
                this.OptionRow($r('app.string.export_include_providers'), '', this.includeProviders,
                  (value: boolean) => { this.includeProviders = value })
                Divider().color($r('app.color.divider'))
                this.OptionRow($r('app.string.export_include_api_keys'),
                  $r('app.string.export_include_api_keys_warning'), this.includeApiKeys,
                  (value: boolean) => { this.includeApiKeys = value })
                Divider().color($r('app.color.divider'))
                this.OptionRow($r('app.string.export_include_preferences'), '', this.includePreferences,
                  (value: boolean) => { this.includePreferences = value })
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
            Button($r('app.string.export_start'))
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(this.themePrimary)
              .borderRadius(12)
              .onClick(() => {
                this.startExport()
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
    .height('100%')
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
    .backgroundColor($r('app.color.background'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
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
        .layoutWeight(1)
        .backgroundColor($r('app.color.background'))
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .titleBar({
          avoidLayoutSafeArea: true,
          enableComponentSafeArea: true,
          content: {
            title: {
              mainTitle: $r('app.string.export_title')
            }
          }
        })
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
  OptionRow(
    title: Resource,
    warning: Resource | string,
    checked: boolean,
    onChange: (value: boolean) => void
  ) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))

        if (warning !== '') {
          Text(warning)
            .fontSize(14)
            .fontColor($r('app.color.status_error'))
            .margin({ top: 4 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .onChange(onChange)
    }
    .width('100%')
    .padding(16)
  }
}

@Builder
export function ExportDataPageBuilder(name: string, param: Object) {
  NavDestination() {
    ExportDataPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
}

