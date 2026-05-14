import {
  ToolDefinition,
  ToolConfig,
  ToolParameters,
  ToolFunction,
  ToolParameterProperty,
  ToolPermissionLevel,
  ToolSourceType
} from '../models/ChatModels'
import { ToolExecutor, RegisteredTool, getToolRegistry } from '../services/ToolRegistry'
import { getWebSearchService, SearchResult, WebSearchResult } from '../services/WebSearchService'
import {
  ASK_USER_TOOL_ID,
  GET_TIME_INFO_TOOL_ID,
  LEGACY_WEB_SEARCH_TOOL_ID,
  SCRAPE_WEB_TOOL_ID,
  SEARCH_WEB_TOOL_ID
} from '../utils/SearchToolIdentityUtils'
import { i18n } from '@kit.LocalizationKit'

// search_web 工具参数接口
interface SearchWebArgs {
  query: string
}

// scrape_web 工具参数接口
interface ScrapeWebArgs {
  url?: string
  query?: string
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

class WebSearchResultFormatter {
  buildSnippet(content: string): string {
    const trimmed = content.replace(/\s+/g, ' ').trim()
    if (trimmed.length <= 200) {
      return trimmed
    }
    return trimmed.substring(0, 200) + '...'
  }

  formatWebResult(result: WebSearchResult): string {
    if (!result.success) {
      return JSON.stringify(new ErrorOutput(result.errorMessage))
    }

    const output = new SearchResultOutput(
      result.url,
      result.sourceName !== '' ? result.sourceName : 'URL抓取',
      [new SearchResultItem(
        1,
        `ref_${Date.now()}`,
        result.title,
        result.url,
        this.buildSnippet(result.content)
      )],
      `标题: ${result.title}\n来源: ${result.url}\n\n${result.content}`
    )
    return JSON.stringify(output)
  }

  formatResult(result: SearchResult): string {
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

// search_web 执行器
class SearchWebExecutor implements ToolExecutor {
  private formatter: WebSearchResultFormatter = new WebSearchResultFormatter()

  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as SearchWebArgs
      if (params.query === undefined || params.query.trim() === '') {
        return JSON.stringify(new ErrorOutput('搜索关键词不能为空'))
      }

      const query = params.query.trim()
      console.info('SearchWebExecutor', `Executing web search: ${query}`)
      const searchResult = await getWebSearchService().search(query)
      return this.formatter.formatResult(searchResult)
    } catch (error) {
      console.error('SearchWebExecutor', `Search error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ErrorOutput(`搜索失败: ${JSON.stringify(error)}`))
    }
  }
}

// scrape_web 执行器
class ScrapeWebExecutor implements ToolExecutor {
  private formatter: WebSearchResultFormatter = new WebSearchResultFormatter()

  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as ScrapeWebArgs
      const rawUrl = params.url !== undefined ? params.url : (params.query !== undefined ? params.query : '')
      if (rawUrl === undefined || rawUrl.trim() === '') {
        return JSON.stringify(new ErrorOutput('网页 URL 不能为空'))
      }

      const url = rawUrl.trim()
      console.info('ScrapeWebExecutor', `Executing web scrape: ${url}`)
      const webResult = await getWebSearchService().fetchUrlContent(url)
      return this.formatter.formatWebResult(webResult)
    } catch (error) {
      console.error('ScrapeWebExecutor', `Scrape error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ErrorOutput(`网页读取失败: ${JSON.stringify(error)}`))
    }
  }
}

// 兼容旧 web_search：历史调用和旧 provider 输出仍可执行，但新请求不再注入该工具。
class LegacyWebSearchExecutor implements ToolExecutor {
  private formatter: WebSearchResultFormatter = new WebSearchResultFormatter()

  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as SearchWebArgs
      if (params.query === undefined || params.query.trim() === '') {
        return JSON.stringify(new ErrorOutput('搜索关键词不能为空'))
      }

      const query = params.query.trim()
      const webSearchService = getWebSearchService()
      const extractedUrl = webSearchService.extractUrl(query)
      const isPureUrl = extractedUrl !== null && extractedUrl === query
      if (isPureUrl && extractedUrl !== null) {
        console.info('LegacyWebSearchExecutor', `Executing web scrape: ${extractedUrl}`)
        const webResult = await webSearchService.fetchUrlContent(extractedUrl)
        return this.formatter.formatWebResult(webResult)
      }

      console.info('LegacyWebSearchExecutor', `Executing web search: ${query}`)
      const searchResult = await webSearchService.search(query)
      return this.formatter.formatResult(searchResult)
    } catch (error) {
      console.error('LegacyWebSearchExecutor', `Search error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ErrorOutput(`搜索失败: ${JSON.stringify(error)}`))
    }
  }
}

function createSearchWebToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.addProperty('query', new ToolParameterProperty(
    'string',
    '聚焦搜索关键词。用于搜索外部实时、特定或需要验证的信息，不要传入整段用户问题。'
  ))
  parameters.addRequired('query')

  const func = new ToolFunction(
    SEARCH_WEB_TOOL_ID,
    'Search the web for up-to-date, specific, or verifiable information. First decide whether web access is truly needed; use your own knowledge for common stable facts and pure generation tasks. Each search has real cost, so generate focused keywords and run multiple searches only when more evidence is needed. Cite results with [1], [2] style source numbers.',
    parameters
  )

  return new ToolDefinition(func)
}

function createScrapeWebToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.addProperty('url', new ToolParameterProperty(
    'string',
    '要读取的网页 URL。用户给出 URL 或要求总结、分析某个网页时，原样传入 URL。'
  ))
  parameters.addRequired('url')

  const func = new ToolFunction(
    SCRAPE_WEB_TOOL_ID,
    'Scrape a URL for detailed page content. Use this when the user provides a specific URL, asks to read or summarize a page, or search snippets are insufficient. Avoid using it for common questions unless the user asks.',
    parameters
  )

  return new ToolDefinition(func)
}

function createLegacyWebSearchToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.addProperty('query', new ToolParameterProperty(
    'string',
    '聚焦搜索关键词或网页 URL。'
  ))
  parameters.addRequired('query')

  const func = new ToolFunction(
    LEGACY_WEB_SEARCH_TOOL_ID,
    '兼容旧版联网搜索工具。新请求会使用 search_web 或 scrape_web。',
    parameters
  )

  return new ToolDefinition(func)
}

function createSearchToolConfig(id: string, name: string, description: string): ToolConfig {
  return new ToolConfig(
    id,
    name,
    description,
    null,
    false,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    id,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== ask_user 工具 =====
// ask_user 是"人机交互工具"(human-in-the-loop): 模型提出问题, UI 展示 AskUserCard,
// 用户填完答案提交后, 答案 JSON 作为 tool_result 回传给模型。
// 这里只注册定义, 执行器是占位; 真正的等待/回收答案逻辑在 ToolExecutionService.handleAskUser
// 里拦截 ask_user 函数名并走 answerCallback 完成。

// 占位执行器: 不应被实际调用, 一旦被调用说明 ToolExecutionService 的分流失效
class AskUserExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    return JSON.stringify(new ErrorOutput('ask_user should be resolved by the user, not executed by the tool runtime'))
  }
}

function createAskUserToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  // questions[] 是对象数组 + enum, ToolParameters.addProperty 不足以表达,
  // 通过 JSON 字符串反序列化成 Object 再 setRawSchema, 避开 ArkTS "无类型对象字面量" 限制。
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "questions": {
        "type": "array",
        "description": "1-3 question prompts to clarify the user's intent. Each item must include id, question, selection_type; include options[] when selection_type is single or multi.",
        "minItems": 1,
        "maxItems": 3,
        "items": {
          "type": "object",
          "properties": {
            "id": {
              "type": "string",
              "description": "Unique identifier used to key the answer in the returned JSON, e.g. 'q1' or 'format'."
            },
            "question": {
              "type": "string",
              "description": "Concise question text shown to the user, 10-60 Chinese characters or ~100 English characters."
            },
            "selection_type": {
              "type": "string",
              "enum": ["single", "multi", "text"],
              "description": "single=user must pick one from options; multi=user may pick multiple from options; text=free-form input."
            },
            "options": {
              "type": "array",
              "description": "Required when selection_type is single or multi; optional hints when selection_type is text.",
              "items": { "type": "string" }
            }
          },
          "required": ["id", "question", "selection_type"]
        }
      }
    },
    "required": ["questions"]
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    ASK_USER_TOOL_ID,
    'Ask the user clarifying questions before proceeding. Use this ONLY when the request is genuinely ambiguous and choosing a default would lead to significant rework. Do NOT use it for trivial details you can infer. Batch 1-3 related questions in a single call to avoid multiple back-and-forth rounds. Each question needs a unique id, concise question text, selection_type (single|multi|text), and options[] when selection_type is single or multi. The tool result will be a JSON object of the user answers keyed by question id; use those answers to continue your reply.',
    parameters
  )

  return new ToolDefinition(func)
}

function createAskUserToolConfig(): ToolConfig {
  // permissionLevel 用 READ: ask_user 不是"写外部状态", 是"等用户答复",
  // 让 ToolExecutionService 早期 isAskUserFunctionName 分流直接走 handleAskUser,
  // 不走通用 write 审批 sheet, 避免两个弹窗争抢用户注意力。
  //
  // enabled 默认 true: 零配置即可用, 用户在"设置 > 工具服务 > 内置工具"里可显式关闭,
  // 关闭后 ChatPage.rebuildAvailableChatTools 会把它过滤出 availableChatTools,
  // AI 便感知不到该工具, 不会再发起调用。
  return new ToolConfig(
    ASK_USER_TOOL_ID,
    '向用户提问',
    '模型需要澄清时向你发起的提问, 你的答复会作为工具结果回给模型继续生成。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    ASK_USER_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== get_time_info 工具 =====
// 给模型提供"当前设备本地时间"的能力。无参数, 调用后返回 year/month/day/weekday/datetime/timezone 等字段。
// 与 rikkahub LocalTools.kt 的 timeTool 对齐, 但用 ArkTS 标准 Date + @kit.LocalizationKit 实现。

class TimeInfoOutput {
  year: number = 0
  month: number = 0
  day: number = 0
  weekday: string = ''
  weekday_en: string = ''
  weekday_index: number = 0
  date: string = ''
  time: string = ''
  datetime: string = ''
  timezone: string = ''
  utc_offset: string = ''
  timestamp_ms: number = 0
}

const WEEKDAY_NAMES_ZH: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
const WEEKDAY_NAMES_EN: string[] = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

function buildUtcOffset(now: Date): string {
  // getTimezoneOffset 返回 UTC - local 的分钟数, 东八区为 -480, 这里取反得到 +480
  const offsetMinutes = -now.getTimezoneOffset()
  const sign = offsetMinutes >= 0 ? '+' : '-'
  const abs = Math.abs(offsetMinutes)
  return `${sign}${pad2(Math.floor(abs / 60))}:${pad2(abs % 60)}`
}

function resolveTimezoneId(): string {
  try {
    return i18n.getTimeZone().getID()
  } catch (e) {
    return ''
  }
}

class GetTimeInfoExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    const now = new Date()
    const output = new TimeInfoOutput()
    output.year = now.getFullYear()
    output.month = now.getMonth() + 1
    output.day = now.getDate()
    const weekdayJs = now.getDay() // 0=Sunday ... 6=Saturday
    output.weekday = WEEKDAY_NAMES_ZH[weekdayJs]
    output.weekday_en = WEEKDAY_NAMES_EN[weekdayJs]
    // ISO 8601: 1=Monday ... 7=Sunday
    output.weekday_index = weekdayJs === 0 ? 7 : weekdayJs
    output.date = `${output.year}-${pad2(output.month)}-${pad2(output.day)}`
    output.time = `${pad2(now.getHours())}:${pad2(now.getMinutes())}:${pad2(now.getSeconds())}`
    output.utc_offset = buildUtcOffset(now)
    output.datetime = `${output.date}T${output.time}${output.utc_offset}`
    const tzId = resolveTimezoneId()
    output.timezone = tzId !== '' ? tzId : `UTC${output.utc_offset}`
    output.timestamp_ms = now.getTime()
    return JSON.stringify(output)
  }
}

function createGetTimeInfoToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  // 无参数, 但保留显式 type=object 结构, 避免某些 provider 校验空 schema 抱怨
  parameters.setRawSchema(JSON.parse('{"type":"object","properties":{}}') as Object)

  const func = new ToolFunction(
    GET_TIME_INFO_TOOL_ID,
    'Get the current local date and time from the device. Returns year/month/day, weekday, ISO date/time strings, timezone, UTC offset, and millisecond timestamp. Call this whenever the user asks "what time is it", needs to compute relative dates, or schedules anything tied to "today"/"now".',
    parameters
  )

  return new ToolDefinition(func)
}

function createGetTimeInfoToolConfig(): ToolConfig {
  // 纯读 + 无副作用, READ 权限即可, 不需要审批; 默认 enabled=true, 仍由助手白名单决定 AI 是否能看到。
  return new ToolConfig(
    GET_TIME_INFO_TOOL_ID,
    '获取当前时间',
    '返回设备当前本地日期、时间、时区、时间戳等信息, 供模型回答与时间相关的问题。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    GET_TIME_INFO_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// 注册所有内置工具
export function registerBuiltinTools(): void {
  const registry = getToolRegistry()
  let registeredNow = 0

  if (!registry.isToolRegistered(LEGACY_WEB_SEARCH_TOOL_ID)) {
    const webSearchTool = new RegisteredTool(
      LEGACY_WEB_SEARCH_TOOL_ID,
      createSearchToolConfig(LEGACY_WEB_SEARCH_TOOL_ID, '联网搜索', '兼容旧版联网搜索调用'),
      createLegacyWebSearchToolDefinition(),
      new LegacyWebSearchExecutor()
    )
    registry.registerTool(webSearchTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(SEARCH_WEB_TOOL_ID)) {
    const webSearchTool = new RegisteredTool(
      SEARCH_WEB_TOOL_ID,
      createSearchToolConfig(SEARCH_WEB_TOOL_ID, '联网搜索', '搜索互联网获取最新信息'),
      createSearchWebToolDefinition(),
      new SearchWebExecutor()
    )
    registry.registerTool(webSearchTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(SCRAPE_WEB_TOOL_ID)) {
    const scrapeWebTool = new RegisteredTool(
      SCRAPE_WEB_TOOL_ID,
      createSearchToolConfig(SCRAPE_WEB_TOOL_ID, '网页读取', '读取指定网页 URL 内容'),
      createScrapeWebToolDefinition(),
      new ScrapeWebExecutor()
    )
    registry.registerTool(scrapeWebTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(ASK_USER_TOOL_ID)) {
    const askUserTool = new RegisteredTool(
      ASK_USER_TOOL_ID,
      createAskUserToolConfig(),
      createAskUserToolDefinition(),
      new AskUserExecutor()
    )
    registry.registerTool(askUserTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(GET_TIME_INFO_TOOL_ID)) {
    const getTimeInfoTool = new RegisteredTool(
      GET_TIME_INFO_TOOL_ID,
      createGetTimeInfoToolConfig(),
      createGetTimeInfoToolDefinition(),
      new GetTimeInfoExecutor()
    )
    registry.registerTool(getTimeInfoTool)
    registeredNow += 1
  }

  console.info(
    'BuiltinTools',
    `Builtin tools ready: total=${registry.getToolCount()}, newlyRegistered=${registeredNow}`
  )
}

// 获取所有内置工具 ID
export function getBuiltinToolIds(): string[] {
  return [LEGACY_WEB_SEARCH_TOOL_ID, SEARCH_WEB_TOOL_ID, SCRAPE_WEB_TOOL_ID, ASK_USER_TOOL_ID, GET_TIME_INFO_TOOL_ID]
}
