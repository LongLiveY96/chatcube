import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'

// HTTP 请求方法枚举
export enum HttpMethod {
  GET = 'GET',
  POST = 'POST',
  PUT = 'PUT',
  DELETE = 'DELETE',
  HEAD = 'HEAD',
  OPTIONS = 'OPTIONS'
}

// HTTP 请求配置
export interface HttpRequestConfig {
  url: string
  method: HttpMethod
  headers: Record<string, string>
  body: string | ArrayBuffer
  timeout: number
}

// 二进制传输进度回调（0-1）
export type BinaryProgressCallback = (progress: number) => void

// 数据发送进度信息
interface DataSendProgressInfo {
  sendSize: number
  totalSize: number
}

// HTTP 响应结果
export interface HttpResponse {
  success: boolean
  statusCode: number
  data: string
  errorMessage: string
}

// 请求运行时配置（用于超时覆盖和取消控制）
export interface HttpRequestRuntimeOptions {
  timeout?: number
  controller?: HttpRequestController
}

// 数据接收进度信息
interface DataReceiveProgressInfo {
  receiveSize: number
  totalSize: number
}

// 可取消 HTTP 请求控制器
export class HttpRequestController {
  private requestMap: Map<string, http.HttpRequest> = new Map()
  private cancelled: boolean = false
  private seq: number = 0

  isCancelled(): boolean {
    return this.cancelled
  }

  registerRequest(request: http.HttpRequest): string {
    if (this.cancelled) {
      try {
        request.destroy()
      } catch (_error) {}
      return ''
    }
    this.seq += 1
    const requestId = `req_${Date.now()}_${this.seq}`
    this.requestMap.set(requestId, request)
    return requestId
  }

  unregisterRequest(requestId: string): void {
    if (requestId === '') {
      return
    }
    this.requestMap.delete(requestId)
  }

  cancelAll(): void {
    this.cancelled = true
    this.requestMap.forEach((request: http.HttpRequest) => {
      try {
        request.destroy()
      } catch (_error) {}
    })
    this.requestMap.clear()
  }
}

// HTTP 服务类
export class HttpService {
  private static instance: HttpService | null = null

  private constructor() {
  }

  static getInstance(): HttpService {
    if (HttpService.instance === null) {
      HttpService.instance = new HttpService()
    }
    return HttpService.instance
  }

  // 将 HTTP 错误对象格式化为用户友好的中文提示
  static formatHttpError(error: object): string {
    let code = 0
    let message = ''
    try {
      const errorStr = JSON.stringify(error)
      const parsed = JSON.parse(errorStr) as Record<string, Object>
      if (parsed.code !== undefined) {
        code = parsed.code as number
      }
      if (parsed.message !== undefined) {
        message = parsed.message as string
      }
    } catch (_e) {
      return `请求失败: ${JSON.stringify(error)}`
    }

    if (code === 2300028) {
      return '连接超时，请检查网络或服务地址是否正确'
    } else if (code === 2300007) {
      return '无法连接到服务器，请检查网络连接'
    } else if (code === 2300006) {
      return '域名解析失败，请检查服务地址是否正确'
    } else if (code === 2300056) {
      return '接收数据失败，请检查网络连接后重试'
    } else if (code === 2300023) {
      return '数据写入失败，请检查网络连接后重试'
    } else if (code === 2300005) {
      return '无法解析代理，请检查网络设置'
    } else if (code === 2300035) {
      return 'SSL 连接失败，请检查服务地址是否支持 HTTPS'
    } else if (code === 2300060) {
      return 'SSL 证书验证失败，当前设备未信任该 HTTPS 证书链，请检查服务证书配置'
    } else if (message !== '') {
      return `请求失败: ${message} (${code})`
    } else if (code !== 0) {
      return `请求失败 (错误码: ${code})`
    }
    return `请求失败: ${JSON.stringify(error)}`
  }

  // 将 HTTP 状态码格式化为用户友好的中文提示，未识别的状态码返回 null
  static formatHttpStatusError(statusCode: number): string | null {
    if (statusCode === 401) {
      return '凭据无效，请检查用户名或密码'
    } else if (statusCode === 403) {
      return '权限不足，请检查账户对该资源的访问权限'
    } else if (statusCode === 404) {
      return '资源不存在，请检查地址或目录是否已创建'
    } else if (statusCode === 405) {
      return '服务端不支持该 HTTP 方法'
    } else if (statusCode === 409) {
      return '资源冲突，可能是父目录不存在'
    } else if (statusCode === 423) {
      return '资源被锁定，请稍后重试'
    } else if (statusCode === 507) {
      return '远端存储空间已满'
    } else if (statusCode >= 500 && statusCode < 600) {
      return `服务器内部错误 (${statusCode})`
    }
    return null
  }

  private buildCancelledResponse(): HttpResponse {
    return {
      success: false,
      statusCode: 0,
      data: '',
      errorMessage: 'Request cancelled'
    }
  }

  private destroyRequestSafely(httpRequest: http.HttpRequest): void {
    try {
      httpRequest.destroy()
    } catch (_error) {}
  }

  // 发送 HTTP 请求
  async request(config: HttpRequestConfig): Promise<HttpResponse> {
    return await this.requestWithController(config)
  }

  // 发送 HTTP 请求（支持取消控制器）
  async requestWithController(config: HttpRequestConfig, controller?: HttpRequestController): Promise<HttpResponse> {
    const httpRequest = http.createHttp()
    let requestId = ''

    if (controller !== undefined) {
      if (controller.isCancelled()) {
        this.destroyRequestSafely(httpRequest)
        return this.buildCancelledResponse()
      }
      requestId = controller.registerRequest(httpRequest)
      if (requestId === '') {
        this.destroyRequestSafely(httpRequest)
        return this.buildCancelledResponse()
      }
    }

    try {
      // 构建请求选项
      const options: http.HttpRequestOptions = {
        method: this.convertMethod(config.method),
        header: config.headers,
        extraData: config.body,
        connectTimeout: config.timeout,
        readTimeout: config.timeout
      }

      const response = await httpRequest.request(config.url, options)

      if (controller !== undefined && controller.isCancelled()) {
        return this.buildCancelledResponse()
      }

      const result: HttpResponse = {
        success: response.responseCode >= 200 && response.responseCode < 300,
        statusCode: response.responseCode,
        data: response.result as string,
        errorMessage: ''
      }

      if (!result.success) {
        result.errorMessage = `HTTP Error: ${response.responseCode}`
      }

      return result
    } catch (error) {
      if (controller !== undefined && controller.isCancelled()) {
        return this.buildCancelledResponse()
      }
      const errorResponse: HttpResponse = {
        success: false,
        statusCode: 0,
        data: '',
        errorMessage: HttpService.formatHttpError(error)
      }
      return errorResponse
    } finally {
      if (controller !== undefined) {
        controller.unregisterRequest(requestId)
      }
      this.destroyRequestSafely(httpRequest)
    }
  }

  // GET 请求
  async get(
    url: string,
    headers: Record<string, string> = {},
    options?: HttpRequestRuntimeOptions
  ): Promise<HttpResponse> {
    const defaultHeaders: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'DNT': '1',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1'
    }

    const mergedHeaders: Record<string, string> = {}
    const defaultKeys = Object.keys(defaultHeaders)
    for (let i = 0; i < defaultKeys.length; i++) {
      const key = defaultKeys[i]
      mergedHeaders[key] = defaultHeaders[key]
    }
    const headerKeys = Object.keys(headers)
    for (let i = 0; i < headerKeys.length; i++) {
      const key = headerKeys[i]
      mergedHeaders[key] = headers[key]
    }

    const config: HttpRequestConfig = {
      url: url,
      method: HttpMethod.GET,
      headers: mergedHeaders,
      body: '',
      timeout: options?.timeout !== undefined && options.timeout > 0 ? options.timeout : 30000
    }
    return await this.requestWithController(config, options?.controller)
  }

  // POST 请求
  async post(
    url: string,
    body: string,
    headers: Record<string, string> = {},
    options?: HttpRequestRuntimeOptions
  ): Promise<HttpResponse> {
    const config: HttpRequestConfig = {
      url: url,
      method: HttpMethod.POST,
      headers: headers,
      body: body,
      timeout: options?.timeout !== undefined && options.timeout > 0 ? options.timeout : 60000
    }
    return await this.requestWithController(config, options?.controller)
  }

  // POST 请求 (带超时配置)
  async postWithTimeout(
    url: string,
    body: string,
    headers: Record<string, string>,
    timeout: number,
    options?: HttpRequestRuntimeOptions
  ): Promise<HttpResponse> {
    const config: HttpRequestConfig = {
      url: url,
      method: HttpMethod.POST,
      headers: headers,
      body: body,
      timeout: timeout
    }
    return await this.requestWithController(config, options?.controller)
  }

  // HEAD 请求
  async head(
    url: string,
    headers: Record<string, string> = {},
    options?: HttpRequestRuntimeOptions
  ): Promise<HttpResponse> {
    const config: HttpRequestConfig = {
      url: url,
      method: HttpMethod.HEAD,
      headers: headers,
      body: '',
      timeout: options?.timeout !== undefined && options.timeout > 0 ? options.timeout : 30000
    }
    return await this.requestWithController(config, options?.controller)
  }

  // OPTIONS 请求
  async options(
    url: string,
    headers: Record<string, string> = {},
    runtime?: HttpRequestRuntimeOptions
  ): Promise<HttpResponse> {
    const config: HttpRequestConfig = {
      url: url,
      method: HttpMethod.OPTIONS,
      headers: headers,
      body: '',
      timeout: runtime?.timeout !== undefined && runtime.timeout > 0 ? runtime.timeout : 30000
    }
    return await this.requestWithController(config, runtime?.controller)
  }

  // 二进制 PUT 请求（用于上传文件，带发送进度回调）
  async putBinary(
    url: string,
    body: ArrayBuffer,
    headers: Record<string, string>,
    onProgress?: BinaryProgressCallback,
    runtime?: HttpRequestRuntimeOptions
  ): Promise<HttpResponse> {
    const httpRequest = http.createHttp()
    let requestId = ''
    const controller = runtime?.controller

    if (controller !== undefined) {
      if (controller.isCancelled()) {
        this.destroyRequestSafely(httpRequest)
        return this.buildCancelledResponse()
      }
      requestId = controller.registerRequest(httpRequest)
      if (requestId === '') {
        this.destroyRequestSafely(httpRequest)
        return this.buildCancelledResponse()
      }
    }

    if (onProgress !== undefined) {
      httpRequest.on('dataSendProgress', (info: DataSendProgressInfo) => {
        if (info.totalSize > 0) {
          const ratio = info.sendSize / info.totalSize
          onProgress(ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio))
        }
      })
    }

    try {
      const timeout = runtime?.timeout !== undefined && runtime.timeout > 0 ? runtime.timeout : 300000
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.PUT,
        header: headers,
        extraData: body,
        connectTimeout: 15000,
        readTimeout: timeout,
        expectDataType: http.HttpDataType.STRING
      }

      const response = await httpRequest.request(url, options)

      if (controller !== undefined && controller.isCancelled()) {
        return this.buildCancelledResponse()
      }

      const success = response.responseCode >= 200 && response.responseCode < 300
      const result: HttpResponse = {
        success: success,
        statusCode: response.responseCode,
        data: typeof response.result === 'string' ? response.result as string : '',
        errorMessage: ''
      }
      if (!success) {
        const mapped = HttpService.formatHttpStatusError(response.responseCode)
        result.errorMessage = mapped !== null ? mapped : `HTTP Error: ${response.responseCode}`
      }
      return result
    } catch (error) {
      if (controller !== undefined && controller.isCancelled()) {
        return this.buildCancelledResponse()
      }
      return {
        success: false,
        statusCode: 0,
        data: '',
        errorMessage: HttpService.formatHttpError(error)
      } as HttpResponse
    } finally {
      if (controller !== undefined) {
        controller.unregisterRequest(requestId)
      }
      this.destroyRequestSafely(httpRequest)
    }
  }

  // 二进制 GET 请求（用于下载文件，带接收进度回调）
  async getBinary(
    url: string,
    headers: Record<string, string>,
    onProgress?: BinaryProgressCallback,
    runtime?: HttpRequestRuntimeOptions
  ): Promise<ArrayBuffer> {
    const httpRequest = http.createHttp()
    let requestId = ''
    const controller = runtime?.controller

    if (controller !== undefined) {
      if (controller.isCancelled()) {
        this.destroyRequestSafely(httpRequest)
        throw new Error('Request cancelled')
      }
      requestId = controller.registerRequest(httpRequest)
      if (requestId === '') {
        this.destroyRequestSafely(httpRequest)
        throw new Error('Request cancelled')
      }
    }

    try {
      const timeout = runtime?.timeout !== undefined && runtime.timeout > 0 ? runtime.timeout : 300000
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        extraData: '',
        connectTimeout: 15000,
        readTimeout: timeout,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      }

      const response = await httpRequest.request(url, options)

      if (controller !== undefined && controller.isCancelled()) {
        throw new Error('Request cancelled')
      }

      if (response.responseCode < 200 || response.responseCode >= 300) {
        const mapped = HttpService.formatHttpStatusError(response.responseCode)
        const message = mapped !== null ? mapped : `HTTP Error: ${response.responseCode}`
        throw new Error(message)
      }

      // 下载完成时回调进度 100%
      if (onProgress !== undefined) {
        onProgress(1)
      }

      const result = response.result
      if (result instanceof ArrayBuffer) {
        return result
      }
      // 兜底：把字符串结果转为 ArrayBuffer
      if (typeof result === 'string') {
        const bytes = new util.TextEncoder().encodeInto(result as string)
        return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer
      }
      throw new Error('Unexpected response payload type')
    } finally {
      if (controller !== undefined) {
        controller.unregisterRequest(requestId)
      }
      this.destroyRequestSafely(httpRequest)
    }
  }

  // 流式 POST 请求
  streamPost(
    url: string,
    body: string,
    headers: Record<string, string>,
    onData: (chunk: ArrayBuffer) => void,
    onComplete?: (response: HttpResponse) => void,
    onError?: (error: string) => void
  ): http.HttpRequest {
    const httpRequest = http.createHttp()

    let dataEnded = false
    let resolvedCode: number = -1
    // 仅保留最后一个 data chunk 的引用（零拷贝），用于错误响应时提取错误信息
    let lastDataChunk: ArrayBuffer | null = null

    // 当 dataEnd 和 requestInStream 都完成后，再触发 onComplete
    const tryFinish = (): void => {
      if (!dataEnded || resolvedCode < 0) {
        return
      }
      const isSuccess = resolvedCode >= 200 && resolvedCode < 300
      const result: HttpResponse = {
        success: isSuccess,
        statusCode: resolvedCode,
        data: '',
        errorMessage: ''
      }
      if (!result.success) {
        let errorBody = ''
        if (lastDataChunk !== null) {
          errorBody = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(lastDataChunk))
        }
        if (errorBody !== '') {
          result.errorMessage = `HTTP ${resolvedCode}: ${errorBody}`
          console.error('HttpService', `[streamPost] Error response body: ${errorBody}`)
        } else {
          result.errorMessage = `HTTP Error: ${resolvedCode}`
        }
      }
      lastDataChunk = null
      if (onComplete) {
        onComplete(result)
      }
    }

    // 监听响应头事件
    httpRequest.on('headersReceive', (header: Object) => {
      console.info('HttpService', `[streamPost] Headers received: ${JSON.stringify(header)}`)
    })

    // 监听数据接收事件
    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      console.info('HttpService', `[streamPost] Data chunk received: ${data.byteLength} bytes`)
      onData(data)
      lastDataChunk = data
    })

    // 监听数据接收进度事件
    httpRequest.on('dataReceiveProgress', (info: DataReceiveProgressInfo) => {
      console.info('HttpService', `[streamPost] Progress: ${info.receiveSize}/${info.totalSize}`)
    })

    // 监听数据结束事件
    httpRequest.on('dataEnd', () => {
      console.info('HttpService', `[streamPost] Data end`)
      dataEnded = true
      tryFinish()
    })

    const config: HttpRequestConfig = {
      url: url,
      method: HttpMethod.POST,
      headers: headers,
      body: body,
      timeout: 300000
    }

    const options: http.HttpRequestOptions = {
      method: this.convertMethod(config.method),
      header: config.headers,
      extraData: config.body,
      connectTimeout: 15000,  // 连接超时 15 秒（断网场景更快响应）
      readTimeout: config.timeout,  // 读取超时保持 300 秒
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    }

    // 使用 requestInStream 进行流式请求
    httpRequest.requestInStream(config.url, options).then((code: number) => {
      console.info('HttpService', `[streamPost] requestInStream completed with code: ${code}`)
      resolvedCode = code
      tryFinish()
    }).catch((error: Error) => {
      console.error('HttpService', `[streamPost] Error: ${JSON.stringify(error)}`)
      if (onError) {
        onError(HttpService.formatHttpError(error))
      }
    })

    return httpRequest
  }

  // 转换 HTTP 方法
  private convertMethod(method: HttpMethod): http.RequestMethod {
    if (method === HttpMethod.GET) {
      return http.RequestMethod.GET
    } else if (method === HttpMethod.POST) {
      return http.RequestMethod.POST
    } else if (method === HttpMethod.PUT) {
      return http.RequestMethod.PUT
    } else if (method === HttpMethod.DELETE) {
      return http.RequestMethod.DELETE
    } else if (method === HttpMethod.HEAD) {
      return http.RequestMethod.HEAD
    } else if (method === HttpMethod.OPTIONS) {
      return http.RequestMethod.OPTIONS
    }
    return http.RequestMethod.GET
  }
}

// 导出单例实例获取方法
export function getHttpService(): HttpService {
  return HttpService.getInstance()
}
