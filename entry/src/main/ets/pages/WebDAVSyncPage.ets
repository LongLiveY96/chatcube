import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import {
  ExportOptions,
  ImportOptions,
  ImportPreview,
  getImportExportService
} from '../services/ImportExportService'
import {
  getWebDAVSyncService,
  WebDAVSyncService,
  SyncStage
} from '../services/WebDAVSyncService'
import { getWebDAVService, RemoteInfo, DEFAULT_WEBDAV_FILE_NAME } from '../services/WebDAVService'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
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
import { ExportOptionsPanel } from '../components/sync/ExportOptionsPanel'
import { ImportOptionsPanel, ImportConflictStrategy } from '../components/sync/ImportOptionsPanel'

let webdavSyncPathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct WebDAVSyncPage {
  private get topAvoidHeight(): number { return getAppUiState().topAvoidHeight }
  private get bottomAvoidHeight(): number { return getAppUiState().bottomAvoidHeight }
  private get themePrimary(): string { return getAppUiState().themePrimary }
  private get layoutSizeClass(): string { return getAppUiState().layoutSizeClass }
  private get windowWidthVp(): number { return getAppUiState().windowWidthVp }
  private get windowHeightVp(): number { return getAppUiState().windowHeightVp }
  private get settingsDetailPresentationMode(): string { return getAppUiState().settingsDetailPresentationMode }
  private get materialType(): number { return getAppUiState().materialType }
  private get materialLevel(): number { return getAppUiState().materialLevel }

  // 配置
  @Local serverUrl: string = ''
  @Local username: string = ''
  @Local password: string = ''
  @Local remoteDir: string = ''
  @Local remoteFileName: string = DEFAULT_WEBDAV_FILE_NAME

  // 导出选项
  @Local includeAttachments: boolean = true
  @Local includeProviders: boolean = true
  @Local includePreferences: boolean = true

  // 导入选项
  @Local importProviders: boolean = true
  @Local importPreferences: boolean = true
  @Local conflictStrategy: ImportConflictStrategy = 'skip'

  // 远端状态
  @Local lastSyncTime: number = 0
  @Local remoteExists: boolean = false
  @Local hasRemoteStatus: boolean = false
  @Local refreshingStatus: boolean = false

  // 操作状态
  @Local isTesting: boolean = false
  @Local isSyncing: boolean = false
  @Local stage: SyncStage | '' = ''
  @Local progress: number = 0

  // 下载/预览状态
  @Local downloadedLocalPath: string = ''
  @Local showPreviewDialog: boolean = false
  @Local preview: ImportPreview | null = null

  private compactScroller: Scroller = new Scroller()
  private syncService: WebDAVSyncService = getWebDAVSyncService()

  aboutToAppear(): void {
    this.loadConfigFromPrefs()
  }

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
    return 32 + this.getCompactTabsOverlayInset()
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp,
      this.windowHeightVp, (): void => this.CompactTitleStackBuilder())
  }

  private showToast(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  private handleBack(): void {
    if (webdavSyncPathStack !== null && webdavSyncPathStack.size() > 0) {
      webdavSyncPathStack.pop()
    }
  }

  private async loadConfigFromPrefs(): Promise<void> {
    const prefs = getPreferencesService()
    this.serverUrl = await prefs.getString(PreferenceKeys.WEBDAV_SERVER_URL, '')
    this.username = await prefs.getString(PreferenceKeys.WEBDAV_USERNAME, '')
    this.password = await prefs.getString(PreferenceKeys.WEBDAV_PASSWORD, '')
    this.remoteDir = await prefs.getString(PreferenceKeys.WEBDAV_REMOTE_DIR, '')
    const fileName = await prefs.getString(PreferenceKeys.WEBDAV_REMOTE_FILE_NAME, DEFAULT_WEBDAV_FILE_NAME)
    this.remoteFileName = fileName.length > 0 ? fileName : DEFAULT_WEBDAV_FILE_NAME
    this.lastSyncTime = await prefs.getNumber(PreferenceKeys.WEBDAV_LAST_SYNC_TIME, 0)
  }

  private isConfigComplete(): boolean {
    return this.serverUrl.trim().length > 0 &&
      this.username.trim().length > 0 &&
      this.password.length > 0
  }

  private async persistConfigSilently(): Promise<void> {
    const prefs = getPreferencesService()
    await prefs.setString(PreferenceKeys.WEBDAV_SERVER_URL, this.serverUrl.trim())
    await prefs.setString(PreferenceKeys.WEBDAV_USERNAME, this.username.trim())
    await prefs.setString(PreferenceKeys.WEBDAV_PASSWORD, this.password)
    await prefs.setString(PreferenceKeys.WEBDAV_REMOTE_DIR, this.remoteDir.trim())
    const fileName = this.remoteFileName.trim().length > 0 ? this.remoteFileName.trim() : DEFAULT_WEBDAV_FILE_NAME
    await prefs.setString(PreferenceKeys.WEBDAV_REMOTE_FILE_NAME, fileName)
    this.remoteFileName = fileName
  }

  private async saveConfig(): Promise<void> {
    await this.persistConfigSilently()
    this.showToast($r('app.string.webdav_config_saved'), 1500, SnackBarTone.SUCCESS)
  }

  private async testConnection(): Promise<void> {
    if (!this.isConfigComplete()) {
      this.showToast($r('app.string.webdav_config_incomplete'), 2000, SnackBarTone.ERROR)
      return
    }
    this.isTesting = true
    try {
      await this.persistConfigSilently()
      const result = await getWebDAVService().testConnection({
        serverUrl: this.serverUrl.trim(),
        username: this.username.trim(),
        password: this.password,
        remoteDir: this.remoteDir.trim()
      })
      if (result.ok) {
        this.showToast($r('app.string.webdav_test_success'), 2000, SnackBarTone.SUCCESS)
      } else {
        this.showToast(result.message, 3000, SnackBarTone.ERROR)
      }
    } finally {
      this.isTesting = false
    }
  }

  private async refreshRemoteStatus(): Promise<void> {
    if (!this.isConfigComplete()) {
      this.showToast($r('app.string.webdav_config_incomplete'), 2000, SnackBarTone.ERROR)
      return
    }
    this.refreshingStatus = true
    try {
      await this.persistConfigSilently()
      const info: RemoteInfo = await this.syncService.getRemoteStatus()
      this.hasRemoteStatus = true
      this.remoteExists = info.exists
      if (!info.exists && info.statusCode !== 404 && info.message !== '') {
        this.showToast(info.message, 3000, SnackBarTone.ERROR)
      }
    } finally {
      this.refreshingStatus = false
    }
  }

  private async ensureContextInitialized(): Promise<boolean> {
    const context = this.getUIContext().getHostContext()
    if (!context) {
      this.showToast('应用上下文不可用', 2000, SnackBarTone.ERROR)
      return false
    }
    getWebDAVService().initialize(context)
    this.syncService.initialize(context)
    await getImportExportService().initialize(context)
    return true
  }

  private async startUpload(): Promise<void> {
    if (!this.isConfigComplete()) {
      this.showToast($r('app.string.webdav_config_incomplete'), 2000, SnackBarTone.ERROR)
      return
    }
    if (!await this.ensureContextInitialized()) {
      return
    }
    await this.persistConfigSilently()

    this.isSyncing = true
    this.stage = 'exporting'
    this.progress = 0

    const options: ExportOptions = {
      includeAttachments: this.includeAttachments,
      includeProviders: this.includeProviders,
      includeApiKeys: true,
      includePreferences: this.includePreferences
    }

    try {
      const result = await this.syncService.syncUp(options, (stage: SyncStage, ratio: number) => {
        this.stage = stage
        this.progress = Math.floor(ratio * 100)
      })
      if (result.ok) {
        this.lastSyncTime = Date.now()
        this.hasRemoteStatus = true
        this.remoteExists = true
        this.showToast($r('app.string.webdav_sync_success'), 2000, SnackBarTone.SUCCESS)
      } else {
        const message = result.message !== '' ? result.message : '同步失败'
        this.showToast(message, 3000, SnackBarTone.ERROR)
      }
    } finally {
      this.isSyncing = false
      this.stage = ''
      this.progress = 0
    }
  }

  private async startDownload(): Promise<void> {
    if (!this.isConfigComplete()) {
      this.showToast($r('app.string.webdav_config_incomplete'), 2000, SnackBarTone.ERROR)
      return
    }
    if (!await this.ensureContextInitialized()) {
      return
    }
    await this.persistConfigSilently()

    this.isSyncing = true
    this.stage = 'downloading'
    this.progress = 0

    try {
      const downloadResult = await this.syncService.downloadRemoteToLocal((stage: SyncStage, ratio: number) => {
        this.stage = stage
        this.progress = Math.floor(ratio * 100)
      })
      if (!downloadResult.ok) {
        const message = downloadResult.message !== '' ? downloadResult.message : '下载失败'
        this.showToast(message, 3000, SnackBarTone.ERROR)
        return
      }
      this.downloadedLocalPath = downloadResult.localPath

      // 下载成功后预览
      this.preview = await this.syncService.previewLocal(this.downloadedLocalPath)
      this.showPreviewDialog = true
    } catch (error) {
      console.error('WebDAVSyncPage', `Download/preview failed: ${JSON.stringify(error)}`)
      this.showToast('下载或预览失败', 3000, SnackBarTone.ERROR)
      this.cleanupDownload()
    } finally {
      this.isSyncing = false
      this.stage = ''
      this.progress = 0
    }
  }

  private cleanupDownload(): void {
    if (this.downloadedLocalPath !== '') {
      this.syncService.cleanupLocal(this.downloadedLocalPath)
      this.downloadedLocalPath = ''
    }
    this.preview = null
    this.showPreviewDialog = false
  }

  private async confirmImport(): Promise<void> {
    if (this.downloadedLocalPath === '' || this.preview === null) {
      this.showPreviewDialog = false
      return
    }
    this.showPreviewDialog = false
    this.isSyncing = true
    this.stage = 'importing'
    this.progress = 0

    const options: ImportOptions = {
      conflictStrategy: this.conflictStrategy,
      importProviders: this.importProviders,
      importPreferences: this.importPreferences
    }

    try {
      const result = await this.syncService.importLocal(this.downloadedLocalPath, options,
        (stage: SyncStage, ratio: number) => {
          this.stage = stage
          this.progress = Math.floor(ratio * 100)
        })
      if (result.ok && result.result !== null) {
        const r = result.result
        const parts: string[] = []
        if (r.imported > 0) {
          parts.push(`导入 ${r.imported} 个会话`)
        }
        if (r.overwritten > 0) {
          parts.push(`覆盖 ${r.overwritten} 个`)
        }
        if (r.skipped > 0) {
          parts.push(`跳过 ${r.skipped} 个`)
        }
        if (r.preferencesRestored > 0) {
          parts.push(`恢复 ${r.preferencesRestored} 项偏好`)
        }
        const summary = parts.length > 0 ? parts.join('，') : '导入完成'
        this.lastSyncTime = Date.now()
        this.showToast(summary, 3000, SnackBarTone.SUCCESS)
      } else {
        this.showToast(result.message !== '' ? result.message : '导入失败', 3000, SnackBarTone.ERROR)
      }
    } finally {
      this.downloadedLocalPath = ''
      this.preview = null
      this.isSyncing = false
      this.stage = ''
      this.progress = 0
    }
  }

  private getStageMessage(): Resource | string {
    if (this.stage === 'exporting') {
      return $r('app.string.webdav_stage_exporting')
    } else if (this.stage === 'uploading') {
      return $r('app.string.webdav_stage_uploading')
    } else if (this.stage === 'downloading') {
      return $r('app.string.webdav_stage_downloading')
    } else if (this.stage === 'importing') {
      return $r('app.string.webdav_stage_importing')
    }
    return ''
  }

  private formatDateTime(ts: number): string {
    if (ts <= 0) {
      return ''
    }
    return new Date(ts).toLocaleString('zh-CN')
  }

  @Builder
  private SectionTitle(title: Resource) {
    Text(title)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .fontWeight(FontWeight.Medium)
      .margin({ top: 24, bottom: 12, left: 4 })
  }

  @Builder
  private InputRow(label: Resource, value: string, placeholder: Resource | string, isPassword: boolean,
    onChange: (text: string) => void) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 6, left: 4 })
      TextInput({ text: value, placeholder: placeholder })
        .type(isPassword ? InputType.Password : InputType.Normal)
        .fontSize(15)
        .height(46)
        .backgroundColor(getAppUiState().themeSurface)
        .borderRadius(10)
        .padding({ left: 12, right: 12 })
        .onChange(onChange)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: 12 })
  }

  @Builder
  private ConfigSection() {
    this.SectionTitle($r('app.string.webdav_section_config'))

    Column() {
      this.InputRow($r('app.string.webdav_server_url'), this.serverUrl,
        $r('app.string.webdav_server_url_placeholder'), false,
        (text: string) => { this.serverUrl = text })
      this.InputRow($r('app.string.webdav_username'), this.username, '', false,
        (text: string) => { this.username = text })
      this.InputRow($r('app.string.webdav_password'), this.password, '', true,
        (text: string) => { this.password = text })
      this.InputRow($r('app.string.webdav_remote_dir'), this.remoteDir,
        $r('app.string.webdav_remote_dir_placeholder'), false,
        (text: string) => { this.remoteDir = text })
      this.InputRow($r('app.string.webdav_remote_file_name'), this.remoteFileName, DEFAULT_WEBDAV_FILE_NAME, false,
        (text: string) => { this.remoteFileName = text })

      Row({ space: 12 }) {
        Button($r('app.string.webdav_test_connection'))
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor(this.themePrimary)
          .borderRadius(10)
          .border({ width: 1, color: this.themePrimary })
          .enabled(!this.isTesting && !this.isSyncing)
          .onClick(() => { this.testConnection() })
        Button($r('app.string.webdav_save_config'))
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .backgroundColor(this.themePrimary)
          .borderRadius(10)
          .enabled(!this.isSyncing)
          .onClick(() => { this.saveConfig() })
      }
      .width('100%')
      .margin({ top: 4 })

      Text($r('app.string.webdav_directory_must_exist_note'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(18)
        .margin({ top: 12, left: 4, right: 4 })

      Text($r('app.string.webdav_security_note'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(18)
        .margin({ top: 8, left: 4, right: 4 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(getAppUiState().themeSurface)
    .borderRadius(16)
  }

  @Builder
  private RemoteStatusSection() {
    this.SectionTitle($r('app.string.webdav_section_remote_status'))

    Column() {
      Row() {
        Text($r('app.string.webdav_last_sync_time'))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.lastSyncTime > 0) {
          Text(this.formatDateTime(this.lastSyncTime))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        } else {
          Text($r('app.string.webdav_last_sync_never'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .width('100%')
      .padding(14)

      Divider().color($r('app.color.divider'))

      Row() {
        Text($r('app.string.webdav_remote_file_size'))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (!this.hasRemoteStatus) {
          Text('—')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        } else if (this.remoteExists) {
          Text($r('app.string.webdav_remote_backup_present'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        } else {
          Text($r('app.string.webdav_no_remote_backup'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .width('100%')
      .padding(14)

      Divider().color($r('app.color.divider'))

      Button($r('app.string.webdav_refresh_remote_status'))
        .width('100%')
        .height(42)
        .fontSize(14)
        .backgroundColor(Color.Transparent)
        .fontColor(this.themePrimary)
        .enabled(!this.refreshingStatus && !this.isSyncing)
        .onClick(() => { this.refreshRemoteStatus() })
    }
    .width('100%')
    .backgroundColor(getAppUiState().themeSurface)
    .borderRadius(16)
  }

  @Builder
  private UploadSection() {
    this.SectionTitle($r('app.string.webdav_section_upload'))

    ExportOptionsPanel({
      includeAttachments: this.includeAttachments,
      includeProviders: this.includeProviders,
      includePreferences: this.includePreferences,
      onIncludeAttachmentsChange: (value: boolean) => { this.includeAttachments = value },
      onIncludeProvidersChange: (value: boolean) => { this.includeProviders = value },
      onIncludePreferencesChange: (value: boolean) => { this.includePreferences = value }
    })

    Button($r('app.string.webdav_upload_backup'))
      .width('100%')
      .height(48)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .backgroundColor(this.themePrimary)
      .borderRadius(12)
      .margin({ top: 16 })
      .enabled(!this.isSyncing)
      .onClick(() => { this.startUpload() })
  }

  @Builder
  private DownloadSection() {
    this.SectionTitle($r('app.string.webdav_section_download'))

    ImportOptionsPanel({
      importProviders: this.importProviders,
      importPreferences: this.importPreferences,
      conflictStrategy: this.conflictStrategy,
      hasConflicts: false,
      radioGroup: 'webdavConflictStrategy',
      onImportProvidersChange: (value: boolean) => { this.importProviders = value },
      onImportPreferencesChange: (value: boolean) => { this.importPreferences = value },
      onConflictStrategyChange: (value: ImportConflictStrategy) => { this.conflictStrategy = value }
    })

    Button($r('app.string.webdav_download_backup'))
      .width('100%')
      .height(48)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .backgroundColor(this.themePrimary)
      .borderRadius(12)
      .margin({ top: 16 })
      .enabled(!this.isSyncing)
      .onClick(() => { this.startDownload() })
  }

  @Builder
  private SyncProgress() {
    Column() {
      Text(this.getStageMessage())
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 24 })

      Progress({ value: this.progress, total: 100, type: ProgressType.Ring })
        .width(120)
        .height(120)
        .style({ strokeWidth: 8 })
        .color(this.themePrimary)

      Text(`${this.progress}%`)
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private PreviewDialog() {
    Column() {
      Text($r('app.string.webdav_preview_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 })

      if (this.preview !== null) {
        Column() {
          this.PreviewInfoRow('会话', `${this.preview!.sessionsCount} 个`)
          Divider().color($r('app.color.divider'))
          this.PreviewInfoRow('消息', `${this.preview!.messagesCount} 条`)
          Divider().color($r('app.color.divider'))
          this.PreviewInfoRow('附件', `${this.preview!.attachmentsCount} 个`)
          Divider().color($r('app.color.divider'))
          this.PreviewInfoRow('供应商', `${this.preview!.providersCount} 个`)
          if (this.preview!.preferencesCount > 0) {
            Divider().color($r('app.color.divider'))
            this.PreviewInfoRow('偏好设置', `${this.preview!.preferencesCount} 项`)
          }
          if (this.preview!.conflicts.length > 0) {
            Divider().color($r('app.color.divider'))
            Row() {
              Text('⚠️ 冲突')
                .fontSize(15)
                .fontColor($r('app.color.status_error'))
                .layoutWeight(1)
              Text(`${this.preview!.conflicts.length} 个`)
                .fontSize(15)
                .fontColor($r('app.color.status_error'))
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .padding(14)
          }
        }
        .width('100%')
        .backgroundColor(getAppUiState().themeSurface)
        .borderRadius(12)
      }

      Row({ space: 12 }) {
        Button($r('app.string.webdav_preview_cancel'))
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor(Color.Transparent)
          .fontColor(this.themePrimary)
          .borderRadius(10)
          .border({ width: 1, color: this.themePrimary })
          .onClick(() => { this.cleanupDownload() })
        Button($r('app.string.webdav_preview_confirm'))
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor(this.themePrimary)
          .borderRadius(10)
          .onClick(() => { this.confirmImport() })
      }
      .width('100%')
      .margin({ top: 20 })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(getAppUiState().themeBackground)
    .borderRadius(20)
  }

  @Builder
  private PreviewInfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding(14)
  }

  @Builder
  private MainContent() {
    Scroll(this.compactScroller) {
      Row() {
        Column() {
          if (!this.isDetailPaneMode()) {
            Blank().width('100%').height(this.getCompactContentTopPadding())
          }

          this.ConfigSection()
          this.RemoteStatusSection()
          this.UploadSection()
          this.DownloadSection()
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
  }

  @Builder
  private PageContent() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isSyncing) {
        this.SyncProgress()
      } else {
        this.MainContent()
      }
      if (this.showPreviewDialog) {
        Column() {
          Column() {
            this.PreviewDialog()
          }
          .width('92%')
          .constraintSize({ maxWidth: 480 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#80000000')
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_webdav_sync'))
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
      title: $r('app.string.settings_webdav_sync'),
      onBack: () => { this.handleBack() }
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
}

@Builder
export function WebDAVSyncPageBuilder(name: string, param: Object) {
  NavDestination() {
    WebDAVSyncPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    webdavSyncPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (webdavSyncPathStack !== null && webdavSyncPathStack.size() > 0) {
      webdavSyncPathStack.pop()
    }
    return true
  })
}
