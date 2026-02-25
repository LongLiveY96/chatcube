import { picker, fileIo } from '@kit.CoreFileKit'
import { ChatSession } from '../models/ChatModels'
import { ChatViewModel } from '../viewmodels/ChatViewModel'
import { getImportExportService, ExportOptions } from '../services/ImportExportService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'

@Entry
@Component
struct ExportDataPage {
  @StorageProp('bottomAvoidHeight') bottomAvoidHeight: number = 0
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'

  @State sessions: ChatSession[] = []
  @State selectedSessionIds: string[] = []
  @State selectAll: boolean = true
  @State includeAttachments: boolean = true
  @State includeProviders: boolean = true
  @State includeApiKeys: boolean = false
  @State includePreferences: boolean = true
  @State isExporting: boolean = false
  @State exportProgress: number = 0
  private chatViewModel: ChatViewModel = ServiceRegistry.chat()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
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

  build() {
    Column() {
      HdsNavigation() {
        Column() {
        if (this.isExporting) {
          // 导出进度界面
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
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 导出配置界面
          Scroll() {
            Column() {
              // 会话选择
              this.SectionTitle($r('app.string.export_select_sessions'))

              Column() {
                // 全选按钮
                Row() {
                  Checkbox({ name: 'selectAll', group: 'sessions' })
                    .select(this.selectAll)
                    .onChange((value: boolean) => {
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

                // 会话列表
                ForEach(this.sessions, (session: ChatSession) => {
                  Column() {
                    Row() {
                      Checkbox({ name: session.id, group: 'sessions' })
                        .select(this.selectedSessionIds.includes(session.id))
                        .onChange((value: boolean) => {
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

              // 导出选项
              this.SectionTitle($r('app.string.export_options'))

              Column() {
                this.OptionRow(
                  $r('app.string.export_include_attachments'),
                  '',
                  this.includeAttachments,
                  (value: boolean) => {
                    this.includeAttachments = value
                  }
                )

                Divider().color($r('app.color.divider'))

                this.OptionRow(
                  $r('app.string.export_include_providers'),
                  '',
                  this.includeProviders,
                  (value: boolean) => {
                    this.includeProviders = value
                  }
                )

                Divider().color($r('app.color.divider'))

                this.OptionRow(
                  $r('app.string.export_include_api_keys'),
                  $r('app.string.export_include_api_keys_warning'),
                  this.includeApiKeys,
                  (value: boolean) => {
                    this.includeApiKeys = value
                  }
                )

                Divider().color($r('app.color.divider'))

                this.OptionRow(
                  $r('app.string.export_include_preferences'),
                  '',
                  this.includePreferences,
                  (value: boolean) => {
                    this.includePreferences = value
                  }
                )
              }
              .width('100%')
              .backgroundColor($r('app.color.surface'))
              .borderRadius(16)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 100 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)

          // 底部按钮
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
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background'))
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
