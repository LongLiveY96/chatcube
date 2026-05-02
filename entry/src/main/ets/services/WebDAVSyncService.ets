/**
 * WebDAV 同步编排层
 * 串接 ImportExportService 与 WebDAVService:
 *  - syncUp: 导出 zip -> 上传到 WebDAV
 *  - downloadRemoteToLocal + previewLocal + importLocal: 下载 -> 预览 -> 导入
 */

import { fileIo } from '@kit.CoreFileKit'
import { Context } from '@kit.AbilityKit'
import {
  ImportExportService,
  ExportOptions,
  ImportOptions,
  ImportPreview,
  ImportResult
} from './ImportExportService'
import {
  WebDAVService,
  WebDAVConfig,
  RemoteInfo,
  DEFAULT_WEBDAV_FILE_NAME
} from './WebDAVService'
import { getPreferencesService, PreferenceKeys } from './PreferencesService'
import { HttpRequestController } from './HttpService'

// 同步阶段
export type SyncStage = 'exporting' | 'uploading' | 'downloading' | 'importing'

// 阶段进度回调(progress 为该阶段内的 0-1 比例)
export type SyncProgressCallback = (stage: SyncStage, progress: number) => void

// 上传同步结果
export interface SyncUpResult {
  ok: boolean
  fileSize: number
  durationMs: number
  message: string
}

// 下载到本地结果
export interface DownloadResult {
  ok: boolean
  localPath: string
  durationMs: number
  message: string
}

// 导入结果
export interface SyncImportResult {
  ok: boolean
  result: ImportResult | null
  durationMs: number
  message: string
}

export class WebDAVSyncService {
  private static instance: WebDAVSyncService | null = null
  private context: Context | null = null

  private constructor() {}

  static getInstance(): WebDAVSyncService {
    if (WebDAVSyncService.instance === null) {
      WebDAVSyncService.instance = new WebDAVSyncService()
    }
    return WebDAVSyncService.instance
  }

  initialize(context: Context): void {
    this.context = context
  }

  // 从 Preferences 读取 WebDAV 配置(不含远端文件名)
  async loadConfig(): Promise<WebDAVConfig> {
    const prefs = getPreferencesService()
    const serverUrl = await prefs.getString(PreferenceKeys.WEBDAV_SERVER_URL, '')
    const username = await prefs.getString(PreferenceKeys.WEBDAV_USERNAME, '')
    const password = await prefs.getString(PreferenceKeys.WEBDAV_PASSWORD, '')
    const remoteDir = await prefs.getString(PreferenceKeys.WEBDAV_REMOTE_DIR, '')
    return {
      serverUrl: serverUrl,
      username: username,
      password: password,
      remoteDir: remoteDir
    } as WebDAVConfig
  }

  async loadRemoteFileName(): Promise<string> {
    const prefs = getPreferencesService()
    const name = await prefs.getString(PreferenceKeys.WEBDAV_REMOTE_FILE_NAME, DEFAULT_WEBDAV_FILE_NAME)
    return name.length > 0 ? name : DEFAULT_WEBDAV_FILE_NAME
  }

  // 校验配置是否完整
  private validateConfig(config: WebDAVConfig): string | null {
    if (config.serverUrl.trim().length === 0) {
      return '请先配置 WebDAV 服务地址'
    }
    if (config.username.trim().length === 0) {
      return '请先配置 WebDAV 用户名'
    }
    if (config.password.length === 0) {
      return '请先配置 WebDAV 密码'
    }
    return null
  }

  // 查询远端备份文件信息
  async getRemoteStatus(): Promise<RemoteInfo> {
    const config = await this.loadConfig()
    const validation = this.validateConfig(config)
    if (validation !== null) {
      return {
        exists: false,
        size: 0,
        lastModified: '',
        etag: '',
        statusCode: 0,
        message: validation
      } as RemoteInfo
    }
    const fileName = await this.loadRemoteFileName()
    return await WebDAVService.getInstance().headRemote(config, fileName)
  }

  // 同步上传:导出 zip 并上传到 WebDAV
  async syncUp(
    options: ExportOptions,
    onProgress?: SyncProgressCallback,
    controller?: HttpRequestController
  ): Promise<SyncUpResult> {
    const startTime = Date.now()
    const config = await this.loadConfig()
    const validation = this.validateConfig(config)
    if (validation !== null) {
      return {
        ok: false,
        fileSize: 0,
        durationMs: Date.now() - startTime,
        message: validation
      } as SyncUpResult
    }
    const fileName = await this.loadRemoteFileName()

    // 阶段 1: 导出
    const exportService = ImportExportService.getInstance()
    let zipPath = ''
    try {
      zipPath = await exportService.exportData(options, (pct: number) => {
        if (onProgress !== undefined) {
          onProgress('exporting', pct / 100)
        }
      })
    } catch (error) {
      console.error('WebDAVSyncService', `Export failed: ${JSON.stringify(error)}`)
      return {
        ok: false,
        fileSize: 0,
        durationMs: Date.now() - startTime,
        message: '导出本地数据失败'
      } as SyncUpResult
    }

    // 阶段 2: 上传
    const webdavService = WebDAVService.getInstance()
    const uploadResult = await webdavService.uploadBackup(
      config,
      zipPath,
      fileName,
      (ratio: number) => {
        if (onProgress !== undefined) {
          onProgress('uploading', ratio)
        }
      },
      controller
    )

    // 清理本地临时 zip
    this.deleteFileSafely(zipPath)

    if (!uploadResult.ok) {
      return {
        ok: false,
        fileSize: uploadResult.size,
        durationMs: Date.now() - startTime,
        message: uploadResult.message !== '' ? uploadResult.message : '上传失败'
      } as SyncUpResult
    }

    // 持久化最近一次同步信息
    const prefs = getPreferencesService()
    await prefs.setNumber(PreferenceKeys.WEBDAV_LAST_SYNC_TIME, Date.now())
    await prefs.setNumber(PreferenceKeys.WEBDAV_LAST_BACKUP_SIZE, uploadResult.size)

    return {
      ok: true,
      fileSize: uploadResult.size,
      durationMs: Date.now() - startTime,
      message: ''
    } as SyncUpResult
  }

  // 仅下载远端备份到本地缓存,返回本地路径
  async downloadRemoteToLocal(
    onProgress?: SyncProgressCallback,
    controller?: HttpRequestController
  ): Promise<DownloadResult> {
    const startTime = Date.now()
    const config = await this.loadConfig()
    const validation = this.validateConfig(config)
    if (validation !== null) {
      return {
        ok: false,
        localPath: '',
        durationMs: Date.now() - startTime,
        message: validation
      } as DownloadResult
    }
    const fileName = await this.loadRemoteFileName()
    const webdavService = WebDAVService.getInstance()

    try {
      const localPath = await webdavService.downloadBackup(config, fileName, (ratio: number) => {
        if (onProgress !== undefined) {
          onProgress('downloading', ratio)
        }
      }, controller)
      return {
        ok: true,
        localPath: localPath,
        durationMs: Date.now() - startTime,
        message: ''
      } as DownloadResult
    } catch (error) {
      const errMsg = (error as Error).message !== undefined ? (error as Error).message : ''
      console.error('WebDAVSyncService', `Download failed: ${errMsg || JSON.stringify(error)}`)
      return {
        ok: false,
        localPath: '',
        durationMs: Date.now() - startTime,
        message: errMsg !== '' ? errMsg : '下载失败'
      } as DownloadResult
    }
  }

  // 预览本地 zip(在下载之后调用)
  async previewLocal(localPath: string): Promise<ImportPreview> {
    return await ImportExportService.getInstance().previewImport(localPath)
  }

  // 从本地 zip 执行导入
  async importLocal(
    localPath: string,
    options: ImportOptions,
    onProgress?: SyncProgressCallback
  ): Promise<SyncImportResult> {
    const startTime = Date.now()
    try {
      const result = await ImportExportService.getInstance().importData(localPath, options, (pct: number) => {
        if (onProgress !== undefined) {
          onProgress('importing', pct / 100)
        }
      })
      // 标记同步时间(下载并导入也算一次同步)
      const prefs = getPreferencesService()
      await prefs.setNumber(PreferenceKeys.WEBDAV_LAST_SYNC_TIME, Date.now())
      // 清理本地临时 zip
      this.deleteFileSafely(localPath)
      return {
        ok: true,
        result: result,
        durationMs: Date.now() - startTime,
        message: ''
      } as SyncImportResult
    } catch (error) {
      console.error('WebDAVSyncService', `Import failed: ${JSON.stringify(error)}`)
      return {
        ok: false,
        result: null,
        durationMs: Date.now() - startTime,
        message: '导入失败'
      } as SyncImportResult
    }
  }

  // 取消时清理本地遗留文件
  cleanupLocal(localPath: string): void {
    this.deleteFileSafely(localPath)
  }

  private deleteFileSafely(path: string): void {
    if (path === '') {
      return
    }
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (error) {
      console.warn('WebDAVSyncService', `Cleanup file failed: ${JSON.stringify(error)}`)
    }
  }
}

export function getWebDAVSyncService(): WebDAVSyncService {
  return WebDAVSyncService.getInstance()
}
