/**
 * 图标下载缓存服务
 * 下载 models.dev SVG logo → 转 PNG → 缓存到沙箱
 */

import { http } from '@kit.NetworkKit'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { Context } from '@kit.AbilityKit'

const CACHE_DIR = 'icon_cache'
const ICON_SIZE = 128

export class IconDownloadCache {
  private static instance: IconDownloadCache | null = null
  private cacheDir: string = ''
  private isInitialized: boolean = false
  // url → 沙箱文件路径
  private memoryIndex: Map<string, string> = new Map()
  // 正在下载的 URL，防止重复请求
  private pendingDownloads: Map<string, Promise<string>> = new Map()

  private constructor() {}

  static getInstance(): IconDownloadCache {
    if (IconDownloadCache.instance === null) {
      IconDownloadCache.instance = new IconDownloadCache()
    }
    return IconDownloadCache.instance
  }

  async initialize(context: Context): Promise<void> {
    if (this.isInitialized) {
      return
    }
    this.cacheDir = `${context.filesDir}/${CACHE_DIR}`
    await this.ensureCacheDir()
    this.rebuildIndex()
    this.isInitialized = true
  }

  private async ensureCacheDir(): Promise<void> {
    try {
      fileIo.accessSync(this.cacheDir)
    } catch (_e) {
      fileIo.mkdirSync(this.cacheDir, true)
    }
  }
  // 启动时扫描缓存目录重建内存索引
  private rebuildIndex(): void {
    try {
      const entries = fileIo.listFileSync(this.cacheDir)
      for (let i = 0; i < entries.length; i++) {
        const fileName = entries[i]
        if (fileName.endsWith('.png')) {
          const filePath = `${this.cacheDir}/${fileName}`
          // 文件名格式: {hash}.png，对应的 url 无法反推，但可以在 downloadAndCache 时补充
          // 这里先用 filePath 作为 value，后续 getCachedIconUri 通过 hash 匹配
          const hash = fileName.substring(0, fileName.length - 4)
          this.memoryIndex.set(hash, filePath)
        }
      }
    } catch (_e) {
      // 目录为空或不存在，忽略
    }
  }

  // 同步获取已缓存的沙箱路径，未缓存返回空字符串
  getCachedIconUri(logoUrl: string): string {
    if (!this.isInitialized) {
      return ''
    }
    const hash = this.hashUrl(logoUrl)
    const cached = this.memoryIndex.get(hash)
    if (cached !== undefined) {
      return cached
    }
    return ''
  }

  // 异步下载 SVG 并转 PNG 缓存，返回沙箱路径。失败返回空字符串
  async downloadAndCache(logoUrl: string): Promise<string> {
    if (!this.isInitialized) {
      return ''
    }
    // 已缓存直接返回
    const existing = this.getCachedIconUri(logoUrl)
    if (existing !== '') {
      return existing
    }
    // 防止重复下载
    const pending = this.pendingDownloads.get(logoUrl)
    if (pending !== undefined) {
      return await pending
    }
    const promise = this.doDownloadAndCache(logoUrl)
    this.pendingDownloads.set(logoUrl, promise)
    const result = await promise
    this.pendingDownloads.delete(logoUrl)
    return result
  }
  private async doDownloadAndCache(logoUrl: string): Promise<string> {
    try {
      const httpRequest = http.createHttp()
      const response = await httpRequest.request(logoUrl, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      })
      httpRequest.destroy()

      if (response.responseCode !== 200) {
        return ''
      }

      const svgBuffer = response.result as ArrayBuffer
      if (svgBuffer.byteLength === 0) {
        return ''
      }

      // SVG → PixelMap → PNG
      const imageSource = image.createImageSource(svgBuffer)
      const decodingOptions: image.DecodingOptions = {
        desiredSize: { width: ICON_SIZE, height: ICON_SIZE }
      }
      const pixelMap = await imageSource.createPixelMap(decodingOptions)
      imageSource.release()

      const packer = image.createImagePacker()
      const packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100
      }
      const pngBuffer = await packer.packing(pixelMap, packOpts)
      packer.release()
      pixelMap.release()

      // 写入沙箱
      const hash = this.hashUrl(logoUrl)
      const filePath = `${this.cacheDir}/${hash}.png`
      const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
      fileIo.writeSync(file.fd, pngBuffer)
      fileIo.closeSync(file)

      this.memoryIndex.set(hash, filePath)
      return filePath
    } catch (error) {
      console.warn('IconDownloadCache', `Download failed for ${logoUrl}: ${JSON.stringify(error)}`)
      return ''
    }
  }

  // 简单字符串哈希，生成 hex 字符串作为文件名
  private hashUrl(url: string): string {
    let hash: number = 0
    for (let i = 0; i < url.length; i++) {
      const ch = url.charCodeAt(i)
      hash = ((hash << 5) - hash) + ch
      hash = hash & hash // 转为 32 位整数
    }
    // 转为无符号 hex
    const unsigned = hash >>> 0
    return unsigned.toString(16).padStart(8, '0')
  }
}

