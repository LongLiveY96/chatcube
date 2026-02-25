import { http } from '@kit.NetworkKit'

// HTTP 请求方法枚举
export enum HttpMethod {
  GET = 'GET',
  POST = 'POST',
  PUT = 'PUT',
  DELETE = 'DELETE'
}

// HTTP 请求配置
export interface HttpRequestConfig {
  url: string
  method: HttpMethod
  headers: Record<string, string>
  body: string
  timeout: number
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
        errorMessage: `Request failed: ${JSON.stringify(error)}`
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

    let responseCode: number = 0

    // 监听响应头事件
    httpRequest.on('headersReceive', (header: Object) => {
      console.info('HttpService', `[streamPost] Headers received: ${JSON.stringify(header)}`)
    })

    // 监听数据接收事件
    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      console.info('HttpService', `[streamPost] Data chunk received: ${data.byteLength} bytes`)
      onData(data)
    })

    // 监听数据接收进度事件
    httpRequest.on('dataReceiveProgress', (info: DataReceiveProgressInfo) => {
      console.info('HttpService', `[streamPost] Progress: ${info.receiveSize}/${info.totalSize}`)
    })

    // 监听数据结束事件
    httpRequest.on('dataEnd', () => {
      console.info('HttpService', `[streamPost] Data end, responseCode: ${responseCode}`)
      // responseCode 为 0 时，表示流式请求正常完成（数据已通过 dataReceive 事件接收）
      const isSuccess = responseCode === 0 || (responseCode >= 200 && responseCode < 300)
      const result: HttpResponse = {
        success: isSuccess,
        statusCode: responseCode,
        data: '',
        errorMessage: ''
      }

      if (!result.success) {
        result.errorMessage = `HTTP Error: ${responseCode}`
      }

      if (onComplete) {
        onComplete(result)
      }
    })

    const config: HttpRequestConfig = {
      url: url,
      method: HttpMethod.POST,
      headers: headers,
      body: body,
      timeout: 120000
    }

    const options: http.HttpRequestOptions = {
      method: this.convertMethod(config.method),
      header: config.headers,
      extraData: config.body,
      connectTimeout: 15000,  // 连接超时 15 秒（断网场景更快响应）
      readTimeout: config.timeout,  // 读取超时保持 120 秒
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    }

    // 使用 requestInStream 进行流式请求
    httpRequest.requestInStream(config.url, options).then((code: number) => {
      console.info('HttpService', `[streamPost] requestInStream completed with code: ${code}`)
      responseCode = code
    }).catch((error: Error) => {
      console.error('HttpService', `[streamPost] Error: ${JSON.stringify(error)}`)
      if (onError) {
        onError(JSON.stringify(error))
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
    }
    return http.RequestMethod.GET
  }
}

// 导出单例实例获取方法
export function getHttpService(): HttpService {
  return HttpService.getInstance()
}
