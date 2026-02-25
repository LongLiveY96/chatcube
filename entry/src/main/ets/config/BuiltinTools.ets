import { ToolDefinition, ToolConfig, ToolParameters, ToolFunction, ToolParameterProperty } from '../models/ChatModels'
import { ToolExecutor, RegisteredTool, getToolRegistry } from '../services/ToolRegistry'
import { getWebSearchService, SearchResult } from '../services/WebSearchService'
import { getWeatherService, WeatherQueryResult } from '../services/WeatherService'

// web_search 工具参数接口
interface WebSearchArgs {
  query: string
}

// weather_query 工具参数接口
interface WeatherQueryArgs {
  location: string
  days?: number | string
  unit?: string
}

// 搜索结果项接口（用于格式化输出）
class SearchResultItem {
  index: number = 0
  id: string = ''
  title: string = ''
  url: string = ''
  snippet: string = ''

  constructor(index: number, id: string, title: string, url: string, snippet: string) {
    this.index = index
    this.id = id
    this.title = title
    this.url = url
    this.snippet = snippet
  }
}

// 天气结果项接口（用于格式化输出）
class WeatherForecastOutputItem {
  date: string = ''
  weather: string = ''
  tempMin: number = 0
  tempMax: number = 0
  precipitationProbability: number = 0

  constructor(
    date: string,
    weather: string,
    tempMin: number,
    tempMax: number,
    precipitationProbability: number
  ) {
    this.date = date
    this.weather = weather
    this.tempMin = tempMin
    this.tempMax = tempMax
    this.precipitationProbability = precipitationProbability
  }
}

class WeatherCurrentOutput {
  time: string = ''
  weather: string = ''
  temperature: number = 0
  feelsLike: number = 0
  humidity: number = 0
  windSpeed: number = 0
  windDirection: number = 0
  precipitation: number = 0

  constructor(
    time: string,
    weather: string,
    temperature: number,
    feelsLike: number,
    humidity: number,
    windSpeed: number,
    windDirection: number,
    precipitation: number
  ) {
    this.time = time
    this.weather = weather
    this.temperature = temperature
    this.feelsLike = feelsLike
    this.humidity = humidity
    this.windSpeed = windSpeed
    this.windDirection = windDirection
    this.precipitation = precipitation
  }
}

class WeatherQueryOutput {
  location: string = ''
  timezone: string = ''
  latitude: number = 0
  longitude: number = 0
  unit: string = 'celsius'
  current: WeatherCurrentOutput
  forecast: WeatherForecastOutputItem[] = []
  source: string = ''
  summary: string = ''

  constructor(
    location: string,
    timezone: string,
    latitude: number,
    longitude: number,
    unit: string,
    current: WeatherCurrentOutput,
    forecast: WeatherForecastOutputItem[],
    source: string,
    summary: string
  ) {
    this.location = location
    this.timezone = timezone
    this.latitude = latitude
    this.longitude = longitude
    this.unit = unit
    this.current = current
    this.forecast = forecast
    this.source = source
    this.summary = summary
  }
}

// 搜索结果输出接口
class SearchResultOutput {
  query: string = ''
  searchEngine: string = ''
  results: SearchResultItem[] = []
  summary: string = ''

  constructor(query: string, searchEngine: string, results: SearchResultItem[], summary: string) {
    this.query = query
    this.searchEngine = searchEngine
    this.results = results
    this.summary = summary
  }
}

// 错误输出接口
class ErrorOutput {
  error: string = ''

  constructor(error: string) {
    this.error = error
  }
}

// web_search 执行器
class WebSearchExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as WebSearchArgs
      if (params.query === undefined || params.query === '') {
        return JSON.stringify(new ErrorOutput('搜索关键词不能为空'))
      }

      console.info('WebSearchExecutor', `Executing web search: ${params.query}`)
      const searchResult = await getWebSearchService().search(params.query)
      return this.formatResult(searchResult)
    } catch (error) {
      console.error('WebSearchExecutor', `Search error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ErrorOutput(`搜索失败: ${JSON.stringify(error)}`))
    }
  }

  private formatResult(result: SearchResult): string {
    if (!result.success) {
      return JSON.stringify(new ErrorOutput(result.errorMessage))
    }

    // 返回结构化的搜索结果（包含 index 和 id）
    const formattedResults: SearchResultItem[] = []
    for (let i = 0; i < result.references.length; i++) {
      const ref = result.references[i]
      formattedResults.push(new SearchResultItem(
        i + 1,  // index 从 1 开始
        ref.id,
        ref.title,
        ref.url,
        ref.snippet
      ))
    }

    const output = new SearchResultOutput(
      result.query,
      result.searchEngine,
      formattedResults,
      result.contentForAI
    )
    return JSON.stringify(output)
  }
}

// weather_query 执行器
class WeatherQueryExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as WeatherQueryArgs
      const location = params.location !== undefined ? params.location.trim() : ''
      if (location === '') {
        return JSON.stringify(new ErrorOutput('天气查询地点不能为空'))
      }

      const days = this.parseDays(params.days)
      const unit = this.normalizeUnit(params.unit)
      console.info('WeatherQueryExecutor', `Executing weather query: location=${location}, days=${days}, unit=${unit}`)
      const weatherResult = await getWeatherService().queryWeather(location, days, unit)
      return this.formatResult(weatherResult)
    } catch (error) {
      console.error('WeatherQueryExecutor', `Weather query error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ErrorOutput(`天气查询失败: ${JSON.stringify(error)}`))
    }
  }

  private parseDays(raw: number | string | undefined): number {
    if (raw === undefined) {
      return 3
    }
    if (typeof raw === 'number') {
      if (!Number.isFinite(raw)) {
        return 3
      }
      return this.clampDays(Math.floor(raw))
    }
    const parsed = parseInt(raw, 10)
    if (Number.isNaN(parsed)) {
      return 3
    }
    return this.clampDays(parsed)
  }

  private clampDays(days: number): number {
    if (days < 1) {
      return 1
    }
    if (days > 7) {
      return 7
    }
    return days
  }

  private normalizeUnit(raw: string | undefined): string {
    if (raw === undefined) {
      return 'celsius'
    }
    const normalized = raw.trim().toLowerCase()
    if (normalized === 'fahrenheit' || normalized === 'f') {
      return 'fahrenheit'
    }
    return 'celsius'
  }

  private formatResult(result: WeatherQueryResult): string {
    if (!result.success) {
      return JSON.stringify(new ErrorOutput(result.errorMessage))
    }

    const forecast: WeatherForecastOutputItem[] = []
    for (let i = 0; i < result.daily.length; i++) {
      const day = result.daily[i]
      forecast.push(new WeatherForecastOutputItem(
        day.date,
        day.weatherText,
        day.tempMin,
        day.tempMax,
        day.precipitationProbability
      ))
    }

    const current = new WeatherCurrentOutput(
      result.current.time,
      result.current.weatherText,
      result.current.temperature,
      result.current.feelsLike,
      result.current.humidity,
      result.current.windSpeed,
      result.current.windDirection,
      result.current.precipitation
    )
    const summary = this.buildSummary(result)

    const output = new WeatherQueryOutput(
      result.location.getDisplayName(),
      result.location.timezone,
      result.location.latitude,
      result.location.longitude,
      result.unit,
      current,
      forecast,
      result.source,
      summary
    )
    return JSON.stringify(output)
  }

  private buildSummary(result: WeatherQueryResult): string {
    const unitSymbol = this.getUnitSymbol(result.unit)
    let summary = `${result.location.getDisplayName()} 当前${result.current.weatherText}，`
      + `气温 ${result.current.temperature}${unitSymbol}（体感 ${result.current.feelsLike}${unitSymbol}）`
      + `，湿度 ${result.current.humidity}%`
      + `，风速 ${result.current.windSpeed} km/h。`

    if (result.daily.length > 0) {
      const first = result.daily[0]
      summary = `${summary} ${first.date} 预报：${first.weatherText}，`
        + `${first.tempMin}~${first.tempMax}${unitSymbol}，`
        + `降水概率 ${first.precipitationProbability}%。`
    }
    return summary
  }

  private getUnitSymbol(unit: string): string {
    if (unit === 'fahrenheit') {
      return '°F'
    }
    return '°C'
  }
}

// 创建 web_search 工具定义
function createWebSearchToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.addProperty('query', new ToolParameterProperty(
    'string',
    '搜索关键词（尽量简洁，避免“查下/帮我/请”等口语前缀），用于在互联网上搜索相关信息'
  ))
  parameters.addRequired('query')

  const func = new ToolFunction(
    'web_search',
    '搜索互联网获取最新信息。当用户询问实时信息、新闻、天气、股票、最新事件等需要联网查询的内容时使用此工具。调用时请优先使用“可检索的关键词短语”，不要把口语化指令当作关键词。',
    parameters
  )

  return new ToolDefinition(func)
}

// 创建 web_search 工具配置
function createWebSearchToolConfig(): ToolConfig {
  return new ToolConfig(
    'web_search',
    '联网搜索',
    '搜索互联网获取最新信息',
    null,
    false,
    false
  )
}

// 创建 weather_query 工具定义
function createWeatherQueryToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.addProperty('location', new ToolParameterProperty(
    'string',
    '城市或地区名称，如“北京”“上海”“San Francisco”'
  ))
  parameters.addProperty('days', new ToolParameterProperty(
    'integer',
    '预报天数，范围 1-7，默认 3'
  ))
  parameters.addProperty('unit', new ToolParameterProperty(
    'string',
    '温度单位，可选 celsius 或 fahrenheit，默认 celsius',
    ['celsius', 'fahrenheit']
  ))
  parameters.addRequired('location')

  const func = new ToolFunction(
    'weather_query',
    '查询指定地点的实时天气和未来天气预报（免费，无需 API Key）。当用户询问天气、气温、降雨、风力等信息时优先使用此工具。',
    parameters
  )

  return new ToolDefinition(func)
}

// 创建 weather_query 工具配置
function createWeatherQueryToolConfig(): ToolConfig {
  return new ToolConfig(
    'weather_query',
    '天气查询',
    '免费查询实时天气与未来预报（Open-Meteo，无需 API Key）',
    null,
    false,
    false
  )
}

// 注册所有内置工具
export function registerBuiltinTools(): void {
  const registry = getToolRegistry()
  let registeredNow = 0

  if (!registry.isToolRegistered('web_search')) {
    const webSearchTool = new RegisteredTool(
      'web_search',
      createWebSearchToolConfig(),
      createWebSearchToolDefinition(),
      new WebSearchExecutor()
    )
    registry.registerTool(webSearchTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered('weather_query')) {
    const weatherQueryTool = new RegisteredTool(
      'weather_query',
      createWeatherQueryToolConfig(),
      createWeatherQueryToolDefinition(),
      new WeatherQueryExecutor()
    )
    registry.registerTool(weatherQueryTool)
    registeredNow += 1
  }

  console.info(
    'BuiltinTools',
    `Builtin tools ready: total=${registry.getToolCount()}, newlyRegistered=${registeredNow}`
  )
}

// 获取所有内置工具 ID
export function getBuiltinToolIds(): string[] {
  return ['web_search', 'weather_query']
}
