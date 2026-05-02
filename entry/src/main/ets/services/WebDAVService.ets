/**
 * WebDAV 传输层服务
 * 仅依赖 NetworkKit 支持的 GET/PUT/DELETE/HEAD/OPTIONS 方法,
 * 不使用 PROPFIND/MKCOL,要求用户在服务端预先创建远端目录。
 */

import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { Context } from '@kit.AbilityKit'
import {
  HttpService,
  HttpResponse,
  HttpRequestController,
  HttpMethod,
  BinaryProgressCallback
} from './HttpService'

// WebDAV 连接配置
export interface WebDAVConfig {
  serverUrl: string
  username: string
  password: string
  remoteDir: string
}

// 测试连接结果
export interface TestResult {
  ok: boolean
  statusCode: number
  message: string
}

// 上传结果
export interface UploadResult {
  ok: boolean
  size: number
  statusCode: number
  message: string
}

// 远端文件信息
export interface RemoteInfo {
  exists: boolean
  size: number
  lastModified: string
  etag: string
  statusCode: number
  message: string
}

// 删除结果
export interface DeleteResult {
  ok: boolean
  statusCode: number
  message: string
}

// 默认远端文件名
export const DEFAULT_WEBDAV_FILE_NAME: string = 'chatcube_backup.zip'

export class WebDAVService {
  private static instance: WebDAVService | null = null
  private context: Context | null = null

  private constructor() {}

  static getInstance(): WebDAVService {
    if (WebDAVService.instance === null) {
      WebDAVService.instance = new WebDAVService()
    }
    return WebDAVService.instance
  }

  initialize(context: Context): void {
    this.context = context
  }

  // 构造 Authorization: Basic 头
  private buildAuthHeader(username: string, password: string): string {
    const helper = new util.Base64Helper()
    const encoded = helper.encodeToStringSync(this.stringToBytes(`${username}:${password}`))
    return `Basic ${encoded}`
  }

  private stringToBytes(input: string): Uint8Array {
    return new util.TextEncoder().encodeInto(input)
  }

  // 路径分段编码,保留 / 分隔符,处理中文 / 空格 / 特殊字符
  private encodePathSegments(path: string): string {
    if (path.length === 0) {
      return ''
    }
    const segments = path.split('/')
    const encoded: string[] = []
    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i]
      if (segment.length > 0) {
        encoded.push(encodeURIComponent(segment))
      }
    }
    return encoded.join('/')
  }

  // 拼接完整远端 URL
  private joinPath(serverUrl: string, remoteDir: string, fileName: string): string {
    let server = serverUrl.trim()
    while (server.endsWith('/')) {
      server = server.substring(0, server.length - 1)
    }
    let dir = remoteDir.trim()
    while (dir.startsWith('/')) {
      dir = dir.substring(1)
    }
    while (dir.endsWith('/')) {
      dir = dir.substring(0, dir.length - 1)
    }
    const file = fileName.trim()

    const encodedDir = this.encodePathSegments(dir)
    const encodedFile = this.encodePathSegments(file)

    if (encodedDir.length > 0 && encodedFile.length > 0) {
      return `${server}/${encodedDir}/${encodedFile}`
    } else if (encodedDir.length > 0) {
      return `${server}/${encodedDir}`
    } else if (encodedFile.length > 0) {
      return `${server}/${encodedFile}`
    }
    return server
  }

  // 通用请求头(认证 + WebDAV 必需头)
  private buildHeaders(config: WebDAVConfig, extra?: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {
      'Authorization': this.buildAuthHeader(config.username, config.password),
      'User-Agent': 'ChatCube-WebDAV/1.0',
      'Accept': '*/*'
    }
    if (extra !== undefined) {
      const keys = Object.keys(extra)
      for (let i = 0; i < keys.length; i++) {
        headers[keys[i]] = extra[keys[i]]
      }
    }
    return headers
  }

  // 测试连接(OPTIONS,如失败回退 HEAD)
  async testConnection(config: WebDAVConfig): Promise<TestResult> {
    const dirUrl = this.joinPath(config.serverUrl, config.remoteDir, '')
    const headers = this.buildHeaders(config)
    const httpService = HttpService.getInstance()

    let response: HttpResponse = await httpService.options(dirUrl, headers, { timeout: 30000 })
    if (response.success) {
      return {
        ok: true,
        statusCode: response.statusCode,
        message: '连接成功'
      } as TestResult
    }

    // 部分 WebDAV 服务对 OPTIONS 返回 405,回退 HEAD
    if (response.statusCode === 405) {
      response = await httpService.head(dirUrl, headers, { timeout: 30000 })
      if (response.success) {
        return {
          ok: true,
          statusCode: response.statusCode,
          message: '连接成功'
        } as TestResult
      }
    }

    const mapped = HttpService.formatHttpStatusError(response.statusCode)
    let message = response.errorMessage
    if (mapped !== null && mapped !== '') {
      message = mapped
    }
    if (message === '') {
      message = `连接失败 (HTTP ${response.statusCode})`
    }
    return {
      ok: false,
      statusCode: response.statusCode,
      message: message
    } as TestResult
  }

  // 查询远端文件信息
  async headRemote(config: WebDAVConfig, remoteFileName: string): Promise<RemoteInfo> {
    const url = this.joinPath(config.serverUrl, config.remoteDir, remoteFileName)
    const headers = this.buildHeaders(config)
    const httpService = HttpService.getInstance()
    const response = await httpService.head(url, headers, { timeout: 30000 })

    if (response.success) {
      return {
        exists: true,
        size: 0,
        lastModified: '',
        etag: '',
        statusCode: response.statusCode,
        message: ''
      } as RemoteInfo
    }

    if (response.statusCode === 404) {
      return {
        exists: false,
        size: 0,
        lastModified: '',
        etag: '',
        statusCode: 404,
        message: ''
      } as RemoteInfo
    }

    const mapped = HttpService.formatHttpStatusError(response.statusCode)
    return {
      exists: false,
      size: 0,
      lastModified: '',
      etag: '',
      statusCode: response.statusCode,
      message: mapped !== null ? mapped : response.errorMessage
    } as RemoteInfo
  }

  // 上传备份文件
  async uploadBackup(
    config: WebDAVConfig,
    localZipPath: string,
    remoteFileName: string,
    onProgress?: BinaryProgressCallback,
    controller?: HttpRequestController
  ): Promise<UploadResult> {
    let buffer: ArrayBuffer
    let size = 0
    try {
      const stat = fileIo.statSync(localZipPath)
      size = stat.size
      buffer = new ArrayBuffer(size)
      const file = fileIo.openSync(localZipPath, fileIo.OpenMode.READ_ONLY)
      try {
        fileIo.readSync(file.fd, buffer)
      } finally {
        fileIo.closeSync(file)
      }
    } catch (error) {
      console.error('WebDAVService', `Read local zip failed: ${JSON.stringify(error)}`)
      return {
        ok: false,
        size: 0,
        statusCode: 0,
        message: '读取本地备份文件失败'
      } as UploadResult
    }

    const url = this.joinPath(config.serverUrl, config.remoteDir, remoteFileName)
    const headers = this.buildHeaders(config, {
      'Content-Type': 'application/zip',
      'Content-Length': `${size}`
    })
    const httpService = HttpService.getInstance()
    const response = await httpService.putBinary(url, buffer, headers, onProgress, {
      timeout: 600000,
      controller: controller
    })

    if (response.success) {
      return {
        ok: true,
        size: size,
        statusCode: response.statusCode,
        message: ''
      } as UploadResult
    }

    return {
      ok: false,
      size: size,
      statusCode: response.statusCode,
      message: response.errorMessage
    } as UploadResult
  }

  // 下载备份文件到本地缓存,返回本地路径
  async downloadBackup(
    config: WebDAVConfig,
    remoteFileName: string,
    onProgress?: BinaryProgressCallback,
    controller?: HttpRequestController
  ): Promise<string> {
    if (this.context === null) {
      throw new Error('WebDAVService not initialized')
    }
    const url = this.joinPath(config.serverUrl, config.remoteDir, remoteFileName)
    const headers = this.buildHeaders(config)
    const httpService = HttpService.getInstance()
    const buffer = await httpService.getBinary(url, headers, onProgress, {
      timeout: 600000,
      controller: controller
    })

    const localPath = `${this.context.cacheDir}/chatcube_webdav_${Date.now()}.zip`
    const file = fileIo.openSync(
      localPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    )
    try {
      fileIo.writeSync(file.fd, buffer)
    } finally {
      fileIo.closeSync(file)
    }
    return localPath
  }

  // 删除远端文件
  async deleteRemote(config: WebDAVConfig, remoteFileName: string): Promise<DeleteResult> {
    const url = this.joinPath(config.serverUrl, config.remoteDir, remoteFileName)
    const headers = this.buildHeaders(config)
    const httpService = HttpService.getInstance()
    const response = await httpService.requestWithController({
      url: url,
      method: HttpMethod.DELETE,
      headers: headers,
      body: '',
      timeout: 30000
    })
    if (response.success || response.statusCode === 404) {
      return {
        ok: true,
        statusCode: response.statusCode,
        message: ''
      } as DeleteResult
    }
    const mapped = HttpService.formatHttpStatusError(response.statusCode)
    return {
      ok: false,
      statusCode: response.statusCode,
      message: mapped !== null ? mapped : response.errorMessage
    } as DeleteResult
  }
}

export function getWebDAVService(): WebDAVService {
  return WebDAVService.getInstance()
}
