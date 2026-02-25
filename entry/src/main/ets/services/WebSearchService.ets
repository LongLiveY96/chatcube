import {
  getHttpService,
  HttpService,
  HttpRequestController,
  HttpRequestRuntimeOptions
} from './HttpService'
import { SearchReference, SearchServiceConfig, SearchEngine } from '../models/ChatModels'
import { getPreferencesService, PreferenceKeys } from './PreferencesService'
import { cleanSearchQuery as cleanSearchQueryShared } from '../utils/SearchQueryUtils'

// 搜索结果类（用于返回给业务层）
export class SearchResult {
  success: boolean
  query: string
  searchEngine: string
  references: SearchReference[]
  contentForAI: string
  errorMessage: string

  constructor(
    success: boolean,
    query: string,
    searchEngine: string,
    references: SearchReference[],
    contentForAI: string,
    errorMessage: string
  ) {
    this.success = success
    this.query = query
    this.searchEngine = searchEngine
    this.references = references
    this.contentForAI = contentForAI
    this.errorMessage = errorMessage
  }
}

// 单个搜索结果项
export class SearchResultItem {
  title: string = ''
  url: string = ''
  snippet: string = ''

  constructor(title: string, url: string, snippet: string) {
    this.title = title
    this.url = url
    this.snippet = snippet
  }
}

// 网页搜索结果类
export class WebSearchResult {
  success: boolean = false
  url: string = ''
  title: string = ''
  content: string = ''
  errorMessage: string = ''
  searchResults: SearchResultItem[] = []

  constructor(success: boolean, url: string, title: string, content: string, errorMessage: string, searchResults?: SearchResultItem[]) {
    this.success = success
    this.url = url
    this.title = title
    this.content = content
    this.errorMessage = errorMessage
    if (searchResults !== undefined) {
      this.searchResults = searchResults
    }
  }
}

// 运行时配置快照：单次搜索链路内复用，避免重复读取偏好设置
export class SearchRuntimeConfigSnapshot {
  enabled: boolean = true
  searchEngine: SearchEngine = SearchEngine.BING
  maxResults: number = 10
  timeout: number = 5000
  autoTestConnection: boolean = true
  exaApiKey: string = ''
  exaBaseUrl: string = 'https://api.exa.ai'
}

// 搜索执行选项（可选）
export interface WebSearchExecutionOptions {
  requestId?: string
  runtimeConfig?: SearchRuntimeConfigSnapshot
  cancelCheck?: () => boolean
}

// HTML 解析结果类
class HtmlParseResult {
  title: string = ''
  content: string = ''

  constructor(title: string, content: string) {
    this.title = title
    this.content = content
  }
}

// Bing 搜索结果类（内部使用）
class BingSearchResponse {
  success: boolean = false
  query: string = ''
  results: SearchResultItem[] = []
  errorMessage: string = ''

  constructor(success: boolean, query: string, results: SearchResultItem[], errorMessage: string) {
    this.success = success
    this.query = query
    this.results = results
    this.errorMessage = errorMessage
  }
}

class ExaSearchTextConfig {
  maxCharacters: number = 2500
}

class ExaSearchContentsConfig {
  text: ExaSearchTextConfig = new ExaSearchTextConfig()
}

class ExaSearchRequest {
  query: string = ''
  type: string = 'auto'
  numResults: number = 10
  contents: ExaSearchContentsConfig = new ExaSearchContentsConfig()

  constructor(query: string, numResults: number) {
    this.query = query
    this.numResults = numResults
  }
}

class RequestControllerEntry {
  controller: HttpRequestController
  refCount: number = 1

  constructor(controller: HttpRequestController) {
    this.controller = controller
  }
}

export class WebSearchService {
  private static instance: WebSearchService | null = null
  private httpService: HttpService

  // 保留旧字段，兼容现有调用方
  private config: SearchServiceConfig = new SearchServiceConfig()
  private exaApiKey: string = ''
  private exaBaseUrl: string = 'https://api.exa.ai'

  private requestControllerMap: Map<string, RequestControllerEntry> = new Map()

  private constructor() {
    this.httpService = getHttpService()
  }

  static getInstance(): WebSearchService {
    if (WebSearchService.instance === null) {
      WebSearchService.instance = new WebSearchService()
    }
    return WebSearchService.instance
  }

  private normalizeExaBaseUrl(raw: string): string {
    const trimmed = raw.trim()
    if (trimmed === '') {
      return 'https://api.exa.ai'
    }
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1)
    }
    return trimmed
  }

  private parseSearchEngine(raw: string): SearchEngine {
    if (raw === SearchEngine.EXA) {
      return SearchEngine.EXA
    }
    if (raw === SearchEngine.DUCKDUCKGO) {
      return SearchEngine.DUCKDUCKGO
    }
    if (raw === SearchEngine.TAVILY) {
      return SearchEngine.TAVILY
    }
    if (raw === SearchEngine.CUSTOM) {
      return SearchEngine.CUSTOM
    }
    return SearchEngine.BING
  }

  private normalizeTimeout(raw: number): number {
    if (raw <= 0) {
      return 5000
    }
    if (raw > 60000) {
      return 60000
    }
    return raw
  }

  private normalizeResultCount(raw: number): number {
    if (raw <= 0) {
      return 10
    }
    if (raw > 20) {
      return 20
    }
    return raw
  }

  private applyRuntimeConfig(snapshot: SearchRuntimeConfigSnapshot): void {
    this.config.enabled = snapshot.enabled
    this.config.searchEngine = snapshot.searchEngine
    this.config.maxResults = snapshot.maxResults
    this.config.timeout = snapshot.timeout
    this.config.autoTestConnection = snapshot.autoTestConnection
    this.exaApiKey = snapshot.exaApiKey
    this.exaBaseUrl = snapshot.exaBaseUrl
  }

  // 加载搜索服务配置（旧接口，保留）
  async loadConfig(): Promise<void> {
    const runtime = await this.getRuntimeConfigSnapshot()
    this.applyRuntimeConfig(runtime)
  }

  // 获取单次搜索链路可复用的配置快照
  async getRuntimeConfigSnapshot(): Promise<SearchRuntimeConfigSnapshot> {
    const prefsService = getPreferencesService()
    const snapshot = new SearchRuntimeConfigSnapshot()

    const enabled = await prefsService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    const engine = await prefsService.getString(PreferenceKeys.SEARCH_ENGINE, 'bing')
    const maxResults = await prefsService.getNumber(PreferenceKeys.SEARCH_MAX_RESULTS, 10)
    const timeout = await prefsService.getNumber(PreferenceKeys.SEARCH_TIMEOUT, 5000)
    const autoTest = await prefsService.getBoolean(PreferenceKeys.SEARCH_AUTO_TEST, true)
    const exaApiKey = await prefsService.getString(PreferenceKeys.SEARCH_EXA_API_KEY, '')
    const exaBaseUrl = await prefsService.getString(PreferenceKeys.SEARCH_EXA_BASE_URL, 'https://api.exa.ai')

    snapshot.enabled = enabled
    snapshot.searchEngine = this.parseSearchEngine(engine)
    snapshot.maxResults = this.normalizeResultCount(maxResults)
    snapshot.timeout = this.normalizeTimeout(timeout)
    snapshot.autoTestConnection = autoTest
    snapshot.exaApiKey = exaApiKey.trim()
    snapshot.exaBaseUrl = this.normalizeExaBaseUrl(exaBaseUrl)

    // 同步到旧字段，兼容依赖 this.config 的现有逻辑
    this.applyRuntimeConfig(snapshot)
    return snapshot
  }

  private resolvePreferredEngineName(runtime: SearchRuntimeConfigSnapshot): string {
    if (runtime.searchEngine === SearchEngine.EXA && runtime.exaApiKey !== '') {
      return 'Exa'
    }
    return 'Bing(local)'
  }

  async getPreferredEngineName(runtimeConfig?: SearchRuntimeConfigSnapshot): Promise<string> {
    const runtime = runtimeConfig !== undefined ? runtimeConfig : await this.getRuntimeConfigSnapshot()
    return this.resolvePreferredEngineName(runtime)
  }

  private acquireRequestController(requestId: string): HttpRequestController | null {
    if (requestId === '') {
      return null
    }

    const existing = this.requestControllerMap.get(requestId)
    if (existing !== undefined) {
      existing.refCount += 1
      return existing.controller
    }

    const controller = new HttpRequestController()
    this.requestControllerMap.set(requestId, new RequestControllerEntry(controller))
    return controller
  }

  private releaseRequestController(requestId: string): void {
    if (requestId === '') {
      return
    }

    const existing = this.requestControllerMap.get(requestId)
    if (existing === undefined) {
      return
    }

    existing.refCount -= 1
    if (existing.refCount <= 0) {
      this.requestControllerMap.delete(requestId)
    }
  }

  cancelRequest(requestId: string): void {
    if (requestId === '') {
      return
    }
    const existing = this.requestControllerMap.get(requestId)
    if (existing === undefined) {
      return
    }
    existing.controller.cancelAll()
    this.requestControllerMap.delete(requestId)
  }

  cancelAllRequests(): void {
    this.requestControllerMap.forEach((entry: RequestControllerEntry) => {
      entry.controller.cancelAll()
    })
    this.requestControllerMap.clear()
  }

  private isCancelled(controller: HttpRequestController | null, cancelCheck?: () => boolean): boolean {
    if (controller !== null && controller.isCancelled()) {
      return true
    }
    if (cancelCheck !== undefined && cancelCheck()) {
      if (controller !== null) {
        controller.cancelAll()
      }
      return true
    }
    return false
  }

  private buildHttpOptions(timeout: number, controller: HttpRequestController | null): HttpRequestRuntimeOptions {
    const options: HttpRequestRuntimeOptions = { timeout: this.normalizeTimeout(timeout) }
    if (controller !== null) {
      options.controller = controller
    }
    return options
  }

  private buildCancelledSearchResult(query: string, engineName: string): SearchResult {
    return new SearchResult(
      false,
      query,
      engineName,
      [],
      '',
      '请求已取消'
    )
  }

  private buildCancelledWebResult(url: string): WebSearchResult {
    return new WebSearchResult(false, url, '', '', '请求已取消')
  }

  // 统一搜索接口
  async search(query: string, options?: WebSearchExecutionOptions): Promise<SearchResult> {
    const runtime = options?.runtimeConfig !== undefined ? options.runtimeConfig : await this.getRuntimeConfigSnapshot()
    const requestId = options?.requestId !== undefined ? options.requestId : ''
    const cancelCheck = options?.cancelCheck
    const controller = this.acquireRequestController(requestId)

    try {
      if (this.isCancelled(controller, cancelCheck)) {
        return this.buildCancelledSearchResult(query, this.resolvePreferredEngineName(runtime))
      }

      if (!runtime.enabled) {
        return new SearchResult(false, query, this.resolvePreferredEngineName(runtime), [], '', '搜索服务未启用')
      }

      const cleanedQuery = cleanSearchQueryShared(query)
      if (cleanedQuery !== query) {
        console.info('WebSearchService', `Search query cleaned: "${query}" -> "${cleanedQuery}"`)
      }

      // 天气类查询：强制使用更可解析/更权威站点，避免结果被“查/查重/天眼查”等噪声污染
      let finalQuery = cleanedQuery
      if (this.isWeatherIntent(cleanedQuery)) {
        finalQuery = this.buildWeatherSiteQuery(cleanedQuery)
        if (finalQuery !== cleanedQuery) {
          console.info('WebSearchService', `Weather query rewritten: "${cleanedQuery}" -> "${finalQuery}"`)
        }
      }

      if (this.isCancelled(controller, cancelCheck)) {
        return this.buildCancelledSearchResult(finalQuery, this.resolvePreferredEngineName(runtime))
      }

      if (runtime.searchEngine === SearchEngine.EXA) {
        const exaResult = await this.exaSearchEnhanced(finalQuery, runtime, controller, cancelCheck)
        if (exaResult.success) {
          return exaResult
        }
        if (this.isCancelled(controller, cancelCheck)) {
          return this.buildCancelledSearchResult(finalQuery, 'Exa')
        }
        console.warn('WebSearchService', `[Exa] Failed, fallback to Bing: ${exaResult.errorMessage}`)
        const bingFallback = await this.bingSearchEnhanced(finalQuery, runtime, controller, cancelCheck)
        if (bingFallback.success) {
          return bingFallback
        }
        return exaResult
      }

      return await this.bingSearchEnhanced(finalQuery, runtime, controller, cancelCheck)
    } finally {
      this.releaseRequestController(requestId)
    }
  }

  private async bingSearchEnhanced(
    query: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<SearchResult> {
    const response = await this.bingSearchInternal(query, runtime.maxResults, runtime, controller, cancelCheck)

    if (!response.success) {
      return new SearchResult(
        false,
        query,
        'Bing(local)',
        [],
        '',
        response.errorMessage
      )
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(query, 'Bing(local)')
    }

    const weatherIntent = this.isWeatherIntent(query)

    // 天气类查询：如果强制站点仍然无结果，回退到备用站点再搜一次
    let effectiveResponse = response
    if (effectiveResponse.results.length === 0 && weatherIntent) {
      const fallbackQuery = this.buildWeatherFallbackQuery(query)
      if (fallbackQuery !== '' && fallbackQuery !== query) {
        const fallbackResp = await this.bingSearchInternal(fallbackQuery, runtime.maxResults, runtime, controller, cancelCheck)
        if (fallbackResp.success && fallbackResp.results.length > 0) {
          effectiveResponse = fallbackResp
        }
      }
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(query, 'Bing(local)')
    }

    // 天气/实时数据类问题：抓取网页正文摘要供模型提取数值
    let enriched = ''
    if (weatherIntent && effectiveResponse.results.length > 0) {
      enriched = await this.enrichTopPagesForAI(effectiveResponse.results, 2, runtime, controller, cancelCheck)
      if (enriched === '') {
        const fallbackQuery = this.buildWeatherFallbackQuery(effectiveResponse.query)
        if (fallbackQuery !== '' && fallbackQuery !== effectiveResponse.query) {
          const fallbackResp = await this.bingSearchInternal(fallbackQuery, runtime.maxResults, runtime, controller, cancelCheck)
          if (fallbackResp.success && fallbackResp.results.length > 0) {
            effectiveResponse = fallbackResp
            enriched = await this.enrichTopPagesForAI(effectiveResponse.results, 2, runtime, controller, cancelCheck)
          }
        }
      }
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(query, 'Bing(local)')
    }

    const references: SearchReference[] = []
    for (let i = 0; i < effectiveResponse.results.length; i++) {
      const item = effectiveResponse.results[i]
      references.push(new SearchReference(
        `ref_${Date.now()}_${i}`,
        item.title,
        item.url,
        item.snippet
      ))
    }

    let contentForAI = this.buildContentForAI(effectiveResponse.results)

    if (weatherIntent && enriched !== '') {
      contentForAI += '\n' + enriched
    }

    contentForAI = this.limitPromptContent(contentForAI, 6000)

    return new SearchResult(
      true,
      effectiveResponse.query,
      'Bing(local)',
      references,
      contentForAI,
      ''
    )
  }

  private async exaSearchEnhanced(
    query: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<SearchResult> {
    if (runtime.exaApiKey === '') {
      return new SearchResult(
        false,
        query,
        'Exa',
        [],
        '',
        'Exa API Key 未配置'
      )
    }

    const response = await this.exaSearch(query, runtime.maxResults, runtime, controller, cancelCheck)
    if (!response.success) {
      return new SearchResult(
        false,
        query,
        'Exa',
        [],
        '',
        response.errorMessage
      )
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(query, 'Exa')
    }

    const references: SearchReference[] = []
    for (let i = 0; i < response.results.length; i++) {
      const item = response.results[i]
      references.push(new SearchReference(
        `ref_${Date.now()}_${i}`,
        item.title,
        item.url,
        item.snippet
      ))
    }

    const contentForAI = this.limitPromptContent(this.buildContentForAI(response.results), 6000)
    return new SearchResult(
      true,
      query,
      'Exa',
      references,
      contentForAI,
      ''
    )
  }

  private async exaSearch(
    query: string,
    resultCount: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<BingSearchResponse> {
    try {
      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'x-api-key': runtime.exaApiKey
      }

      const request = new ExaSearchRequest(query, this.normalizeResultCount(resultCount))
      const body = JSON.stringify(request)
      const response = await this.httpService.postWithTimeout(
        `${runtime.exaBaseUrl}/search`,
        body,
        headers,
        runtime.timeout,
        this.buildHttpOptions(runtime.timeout, controller)
      )

      if (!response.success) {
        return new BingSearchResponse(false, query, [], response.errorMessage)
      }

      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const errorMessage = this.extractExaErrorMessage(response.data)
      if (errorMessage !== '') {
        return new BingSearchResponse(false, query, [], errorMessage)
      }

      const results = this.parseExaSearchResults(response.data, this.normalizeResultCount(resultCount))
      return new BingSearchResponse(true, query, results, '')
    } catch (error) {
      return new BingSearchResponse(false, query, [], `Exa 搜索失败: ${JSON.stringify(error)}`)
    }
  }

  private extractExaErrorMessage(json: string): string {
    if (json === '') {
      return ''
    }
    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const error = parsed['error']
      if (error === undefined || error === null) {
        return ''
      }
      if (typeof error === 'string') {
        return error
      }
      if (typeof error === 'object') {
        const errorObj = error as Record<string, Object>
        const message = this.readStringFromObject(errorObj, 'message')
        if (message !== '') {
          return message
        }
        return JSON.stringify(errorObj)
      }
      return JSON.stringify(error)
    } catch (_error) {
      return ''
    }
  }

  private parseExaSearchResults(json: string, maxCount: number): SearchResultItem[] {
    const results: SearchResultItem[] = []
    if (json === '') {
      return results
    }

    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const resultsValue = parsed['results']
      if (resultsValue === undefined || resultsValue === null || !Array.isArray(resultsValue)) {
        return results
      }

      const list = resultsValue as Object[]
      for (let i = 0; i < list.length && results.length < maxCount; i++) {
        const item = list[i]
        if (item === null || item === undefined || typeof item !== 'object' || Array.isArray(item)) {
          continue
        }
        const itemObj = item as Record<string, Object>
        const title = this.readStringFromObject(itemObj, 'title')
        const url = this.readStringFromObject(itemObj, 'url')
        const snippet = this.extractExaSnippet(itemObj)

        if (title === '' || url === '') {
          continue
        }
        results.push(new SearchResultItem(title, url, snippet))
      }
    } catch (error) {
      console.error('WebSearchService', `Parse Exa results failed: ${JSON.stringify(error)}`)
    }

    return results
  }

  private extractExaSnippet(itemObj: Record<string, Object>): string {
    const summary = this.readStringFromObject(itemObj, 'summary')
    if (summary !== '') {
      return this.normalizeSnippet(summary)
    }

    const text = this.readStringFromObject(itemObj, 'text')
    if (text !== '') {
      return this.normalizeSnippet(text)
    }

    const highlights = itemObj['highlights']
    if (highlights !== undefined && highlights !== null && Array.isArray(highlights)) {
      const list = highlights as Object[]
      for (let i = 0; i < list.length; i++) {
        if (typeof list[i] === 'string') {
          return this.normalizeSnippet(list[i] as string)
        }
      }
    }

    return ''
  }

  private normalizeSnippet(raw: string): string {
    const trimmed = raw.replace(/\s+/g, ' ').trim()
    if (trimmed.length <= 220) {
      return trimmed
    }
    return trimmed.substring(0, 220) + '...'
  }

  private readStringFromObject(obj: Record<string, Object>, key: string): string {
    const value = obj[key]
    if (value === undefined || value === null) {
      return ''
    }
    if (typeof value === 'string') {
      return value
    }
    return ''
  }

  private buildWeatherSiteQuery(query: string): string {
    if (query.includes('site:')) {
      return query
    }
    const city = this.extractCityFromWeatherQuery(query)
    const base = city !== '' ? `${city} 天气预报` : '天气预报'
    return `${base} site:weather.com.cn`
  }

  private buildWeatherFallbackQuery(query: string): string {
    if (query.includes('site:')) {
      const withoutSite = query.replace(/site:[^\s]+/g, '').trim()
      const city = this.extractCityFromWeatherQuery(withoutSite)
      const base = city !== '' ? `${city} 天气预报` : '天气预报'
      return `${base} site:nmc.cn`
    }
    const city = this.extractCityFromWeatherQuery(query)
    const base = city !== '' ? `${city} 天气预报` : '天气预报'
    return `${base} site:nmc.cn`
  }

  private extractCityFromWeatherQuery(query: string): string {
    let q = query.trim().replace(/\s+/g, ' ')
    q = q.replace(/site:[^\s]+/g, '').trim()
    q = q.replace(/(今天|今日|现在|当前|明天|后天)/g, '').trim()

    const match = /^(.*?)(?:的)?(?:天气预报|天气|气温|温度)/.exec(q)
    if (match && match[1] !== undefined) {
      const city = match[1].trim()
      if (city !== '') {
        return city
      }
    }

    const parts = q.split(' ')
    return parts.length > 0 ? parts[0].trim() : ''
  }

  private isWeatherIntent(text: string): boolean {
    const t = text.replace(/\s+/g, '')
    if (t.includes('weather.com.cn') || t.includes('nmc.cn')) {
      return true
    }
    const keywords: string[] = [
      '天气', '天气预报', '气温', '温度', '降雨', '降水', '湿度', '风速', '风力', '空气质量', 'AQI', 'PM2.5'
    ]
    for (let i = 0; i < keywords.length; i++) {
      if (t.includes(keywords[i])) {
        return true
      }
    }
    return false
  }

  private async enrichTopPagesForAI(
    results: SearchResultItem[],
    maxFetch: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<string> {
    const candidates: SearchResultItem[] = []
    for (let i = 0; i < results.length; i++) {
      if (candidates.length >= maxFetch) {
        break
      }
      const item = results[i]
      if (item.url === '' || this.isBingInternalUrl(item.url)) {
        continue
      }
      candidates.push(item)
    }

    if (candidates.length === 0) {
      return ''
    }

    const tasks: Promise<string>[] = []
    for (let i = 0; i < candidates.length; i++) {
      tasks.push(this.fetchSinglePageSummary(candidates[i].url, runtime, controller, cancelCheck))
    }

    const summaries = await Promise.all(tasks)
    const validSummaries: string[] = []
    for (let i = 0; i < summaries.length; i++) {
      if (summaries[i] !== '') {
        validSummaries.push(summaries[i])
      }
    }

    return validSummaries.join('\n').trim()
  }

  private async fetchSinglePageSummary(
    url: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<string> {
    if (this.isCancelled(controller, cancelCheck)) {
      return ''
    }

    try {
      const webResult = await this.fetchUrlContentInternal(url, runtime.timeout, controller, cancelCheck)
      if (!webResult.success) {
        return ''
      }
      if (webResult.content.trim() === '' || webResult.content.includes('无法提取正文内容')) {
        return ''
      }

      let text = webResult.content
      const maxLen = 1200
      if (text.length > maxLen) {
        text = text.substring(0, maxLen) + '...'
      }

      return `抓取到的网页正文摘要（用于提取具体数据）:\n标题: ${webResult.title}\n来源: ${webResult.url}\n${text}`
    } catch (_error) {
      return ''
    }
  }

  private limitPromptContent(content: string, maxChars: number): string {
    if (content.length <= maxChars) {
      return content
    }
    return content.substring(0, maxChars) + '\n\n[搜索上下文已截断]'
  }

  // 构建给 AI 的内容（限制总长度，避免上下文过大）
  private buildContentForAI(results: SearchResultItem[]): string {
    let content = '以下是搜索结果:\n\n'
    const maxChars = 3800

    for (let i = 0; i < results.length; i++) {
      const item = results[i]
      const block = `${i + 1}. ${item.title}\n   ${item.snippet}\n   来源: ${item.url}\n\n`
      if ((content + block).length > maxChars) {
        content += '[更多结果已省略]\n'
        break
      }
      content += block
    }
    return content
  }

  // ========== Bing 搜索功能 ==========
  // 执行 Bing 搜索（公开接口，兼容旧调用）
  async bingSearch(
    query: string,
    resultCount: number = 5,
    runtimeConfig?: SearchRuntimeConfigSnapshot,
    options?: WebSearchExecutionOptions
  ): Promise<BingSearchResponse> {
    const runtime = runtimeConfig !== undefined ? runtimeConfig : await this.getRuntimeConfigSnapshot()
    const requestId = options?.requestId !== undefined ? options.requestId : ''
    const controller = this.acquireRequestController(requestId)

    try {
      return await this.bingSearchInternal(query, resultCount, runtime, controller, options?.cancelCheck)
    } finally {
      this.releaseRequestController(requestId)
    }
  }

  private async bingSearchInternal(
    query: string,
    resultCount: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<BingSearchResponse> {
    try {
      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const encodedQuery = encodeURIComponent(query)
      const primaryUrl = `https://www.bing.com/search?q=${encodedQuery}&setlang=zh-hans`
      const primaryResponse = await this.bingSearchByUrl(primaryUrl, query, resultCount, runtime, controller, cancelCheck)

      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      // 若主域解析失败或结果为空，至少重试一次备用入口
      const needRetry = !primaryResponse.success || primaryResponse.results.length === 0
      if (!needRetry) {
        return primaryResponse
      }

      const fallbackUrl = `https://cn.bing.com/search?q=${encodedQuery}`
      const fallbackResponse = await this.bingSearchByUrl(fallbackUrl, query, resultCount, runtime, controller, cancelCheck)
      if (fallbackResponse.success && fallbackResponse.results.length > 0) {
        return fallbackResponse
      }

      if (!primaryResponse.success && fallbackResponse.success) {
        return fallbackResponse
      }

      return primaryResponse.success ? primaryResponse : fallbackResponse
    } catch (error) {
      return new BingSearchResponse(false, query, [], `Bing 搜索失败: ${JSON.stringify(error)}`)
    }
  }

  private async bingSearchByUrl(
    searchUrl: string,
    query: string,
    resultCount: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<BingSearchResponse> {
    if (this.isCancelled(controller, cancelCheck)) {
      return new BingSearchResponse(false, query, [], '请求已取消')
    }

    const response = await this.httpService.get(
      searchUrl,
      {},
      this.buildHttpOptions(runtime.timeout, controller)
    )

    if (!response.success) {
      return new BingSearchResponse(false, query, [], response.errorMessage)
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return new BingSearchResponse(false, query, [], '请求已取消')
    }

    const results = this.parseBingSearchResults(response.data, this.normalizeResultCount(resultCount))
    return new BingSearchResponse(true, query, results, '')
  }

  // 解析 Bing 搜索结果页 HTML（多策略，增强鲁棒性）
  private parseBingSearchResults(html: string, maxCount: number): SearchResultItem[] {
    const results: SearchResultItem[] = []
    const seenUrls: Map<string, boolean> = new Map()

    this.collectResultsFromBAlgoBlocks(html, maxCount, results, seenUrls)
    if (results.length < maxCount) {
      this.collectResultsFromHeadingLinks(html, maxCount, results, seenUrls)
    }

    return results
  }

  private collectResultsFromBAlgoBlocks(
    html: string,
    maxCount: number,
    output: SearchResultItem[],
    seenUrls: Map<string, boolean>
  ): void {
    const algoRegex = /<li[^>]*class=["'][^"']*b_algo[^"']*["'][^>]*>([\s\S]*?)<\/li>/gi
    let match = algoRegex.exec(html)

    while (match !== null && output.length < maxCount) {
      const block = match[1]
      const parsed = this.parseResultFromBlock(block)
      if (parsed !== null) {
        const normalizedUrl = parsed.url.trim()
        if (!seenUrls.has(normalizedUrl)) {
          seenUrls.set(normalizedUrl, true)
          output.push(parsed)
        }
      }
      match = algoRegex.exec(html)
    }
  }

  private collectResultsFromHeadingLinks(
    html: string,
    maxCount: number,
    output: SearchResultItem[],
    seenUrls: Map<string, boolean>
  ): void {
    const headingRegex = /<h2[^>]*>[\s\S]*?<a[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>[\s\S]*?<\/h2>/gi
    let match = headingRegex.exec(html)

    while (match !== null && output.length < maxCount) {
      const url = match[1]
      const title = this.stripHtmlTags(match[2]).trim()

      if (title !== '' && !this.isBingInternalUrl(url)) {
        const normalizedUrl = url.trim()
        if (!seenUrls.has(normalizedUrl)) {
          seenUrls.set(normalizedUrl, true)
          const snippet = this.extractSnippetNearMatch(html, match.index)
          output.push(new SearchResultItem(title, normalizedUrl, snippet))
        }
      }

      match = headingRegex.exec(html)
    }
  }

  private parseResultFromBlock(block: string): SearchResultItem | null {
    const titleMatch = /<h2[^>]*>([\s\S]*?)<\/h2>/i.exec(block)
    if (!titleMatch) {
      return null
    }

    const titleBlock = titleMatch[1]
    const linkMatch = /<a[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/i.exec(titleBlock)
    if (!linkMatch) {
      return null
    }

    const url = linkMatch[1]
    const title = this.stripHtmlTags(linkMatch[2]).trim()
    if (title === '' || this.isBingInternalUrl(url)) {
      return null
    }

    let snippetMatch = /<div[^>]*class=["'][^"']*b_caption[^"']*["'][^>]*>[\s\S]*?<p[^>]*>([\s\S]*?)<\/p>/i.exec(block)
    if (!snippetMatch) {
      snippetMatch = /<p[^>]*>([\s\S]*?)<\/p>/i.exec(block)
    }

    const snippet = snippetMatch ? this.stripHtmlTags(snippetMatch[1]).trim() : ''
    return new SearchResultItem(title, url.trim(), snippet)
  }

  private extractSnippetNearMatch(html: string, startIndex: number): string {
    const safeStart = startIndex >= 0 ? startIndex : 0
    const safeEnd = Math.min(html.length, safeStart + 1000)
    const segment = html.substring(safeStart, safeEnd)
    const snippetMatch = /<p[^>]*>([\s\S]*?)<\/p>/i.exec(segment)
    if (!snippetMatch) {
      return ''
    }
    return this.normalizeSnippet(this.stripHtmlTags(snippetMatch[1]).trim())
  }

  private isBingInternalUrl(url: string): boolean {
    const lower = url.toLowerCase()
    return lower.includes('bing.com') || lower.startsWith('/search') || lower.startsWith('/?')
  }

  // 移除 HTML 标签
  private stripHtmlTags(text: string): string {
    return text
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/\s+/g, ' ')
      .trim()
  }

  // ========== URL 抓取功能 ==========
  // 抓取网页内容
  async fetchUrlContent(url: string, options?: WebSearchExecutionOptions): Promise<WebSearchResult> {
    const runtime = options?.runtimeConfig !== undefined ? options.runtimeConfig : await this.getRuntimeConfigSnapshot()
    const requestId = options?.requestId !== undefined ? options.requestId : ''
    const controller = this.acquireRequestController(requestId)

    try {
      return await this.fetchUrlContentInternal(url, runtime.timeout, controller, options?.cancelCheck)
    } finally {
      this.releaseRequestController(requestId)
    }
  }

  private async fetchUrlContentInternal(
    url: string,
    timeout: number,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<WebSearchResult> {
    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledWebResult(url)
    }

    if (!this.isValidUrl(url)) {
      return new WebSearchResult(false, url, '', '', 'URL 格式无效')
    }

    let fullUrl = url
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      fullUrl = 'https://' + url
    }

    const response = await this.httpService.get(
      fullUrl,
      {},
      this.buildHttpOptions(timeout, controller)
    )

    if (!response.success) {
      if (this.isCancelled(controller, cancelCheck)) {
        return this.buildCancelledWebResult(fullUrl)
      }
      return new WebSearchResult(false, fullUrl, '', '', response.errorMessage)
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledWebResult(fullUrl)
    }

    const parsed = this.parseHtmlContent(response.data)
    return new WebSearchResult(true, fullUrl, parsed.title, parsed.content, '')
  }

  // 解析 HTML 提取正文
  private parseHtmlContent(html: string): HtmlParseResult {
    const titleMatch = html.match(/<title[^>]*>([^<]+)<\/title>/i)
    const title = titleMatch ? titleMatch[1].trim() : '未知标题'

    const cleanHtml = html
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
      .replace(/<nav[^>]*>[\s\S]*?<\/nav>/gi, '')
      .replace(/<footer[^>]*>[\s\S]*?<\/footer>/gi, '')
      .replace(/<header[^>]*>[\s\S]*?<\/header>/gi, '')
      .replace(/<br\s*\/?>/gi, '\n')

    const contentMatches = cleanHtml.match(/<(p|h[1-6]|li|td|th|span)[^>]*>([\s\S]*?)<\/\1>/gi)

    let content = ''
    if (contentMatches) {
      content = contentMatches
        .map((match: string): string => match
          .replace(/<[^>]+>/g, '')
          .replace(/&nbsp;/g, ' ')
          .replace(/&amp;/g, '&')
          .replace(/&lt;/g, '<')
          .replace(/&gt;/g, '>')
          .replace(/&quot;/g, '"')
          .replace(/&#39;/g, "'")
          .replace(/\n+/g, '\n')
          .trim())
        .filter((text: string): boolean => {
          if (text.length > 10) {
            return true
          }
          if (/(℃|°|AQI|PM2\.5|\d+\s*-\s*\d+)/i.test(text)) {
            return true
          }
          return false
        })
        .join('\n')
    }

    const maxContentLength = 8000
    if (content.length > maxContentLength) {
      content = content.substring(0, maxContentLength) + '...'
    }

    return new HtmlParseResult(title, content !== '' ? content : '无法提取正文内容')
  }

  // 验证 URL 格式
  isValidUrl(text: string): boolean {
    const urlPattern = /^https?:\/\/[\w\-.]+(:\d+)?(\/[\w\-._~:/?#[\]@!$&'()*+,;=]*)?$|^[\w\-.]+(:\d+)?(\/[\w\-._~:/?#[\]@!$&'()*+,;=]*)?$/
    return urlPattern.test(text.trim())
  }

  // 从文本中提取 URL
  extractUrl(text: string): string | null {
    const trimmed = text.trim()

    const httpPattern = /^https?:\/\/[^\s]+/
    const httpMatch = trimmed.match(httpPattern)
    if (httpMatch) {
      return httpMatch[0]
    }

    const domainPattern = /^[\w\-]+\.[\w\-]+(:\d+)?(\/[\w\-._~:/?#[\]@!$&'()*+,;=]*)?/
    const domainMatch = trimmed.match(domainPattern)
    if (domainMatch) {
      return domainMatch[0]
    }

    return null
  }
}

export function getWebSearchService(): WebSearchService {
  return WebSearchService.getInstance()
}
