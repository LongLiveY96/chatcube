import { solarToLunar } from './LunarCalendarUtils'

export class SystemPromptTemplateDefaults {
  static readonly DEFAULT_TEMPLATE: string = `你是一个严谨、可靠、友好的 AI 助手。
当前日期时间：{{current_time}}

回答规则：
1. 当用户提到“今天、现在、最新、近期”等相对时间时，以当前日期时间为准。
2. 若回答中需要给出绝对日期或时间，必须与当前日期时间保持一致。
3. 信息不足时明确说明不确定性，不要编造事实。`
}

export class SystemPromptTemplateVariables {
  static readonly CURRENT_TIME: string = '{{current_time}}'
  static readonly CURRENT_DATE: string = '{{current_date}}'
  static readonly CURRENT_CLOCK: string = '{{current_clock}}'
  static readonly CURRENT_WEEKDAY: string = '{{current_weekday}}'
  static readonly CURRENT_LUNAR: string = '{{current_lunar}}'
}

function padZero(num: number): string {
  return num.toString().padStart(2, '0')
}

export function buildCurrentTimeContext(date: Date = new Date()): string {
  const year = date.getFullYear()
  const month = date.getMonth() + 1
  const day = date.getDate()
  const hours = date.getHours()
  const minutes = date.getMinutes()
  const weekDays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
  const weekDay = weekDays[date.getDay()]
  const lunar = solarToLunar(year, month, day)
  const lunarStr = lunar.toShortString()
  return `${year}年${padZero(month)}月${padZero(day)}日 ${weekDay} ${padZero(hours)}:${padZero(minutes)}（${lunarStr}）`
}

export function normalizeSystemPromptTemplate(template: string): string {
  if (template.trim() === '') {
    return SystemPromptTemplateDefaults.DEFAULT_TEMPLATE
  }
  return template
}

export function renderSystemPromptTemplate(template: string, date: Date = new Date()): string {
  const normalizedTemplate = normalizeSystemPromptTemplate(template)
  const year = date.getFullYear()
  const month = date.getMonth() + 1
  const day = date.getDate()
  const hours = date.getHours()
  const minutes = date.getMinutes()
  const weekDays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
  const weekDay = weekDays[date.getDay()]
  const lunar = solarToLunar(year, month, day)
  const lunarStr = lunar.toShortString()
  const currentTime = buildCurrentTimeContext(date)
  const currentDate = `${year}年${padZero(month)}月${padZero(day)}日`
  const currentClock = `${padZero(hours)}:${padZero(minutes)}`

  let rendered = normalizedTemplate
  rendered = rendered.replace(/\{\{\s*current_time\s*\}\}/g, currentTime)
  rendered = rendered.replace(/\{\{\s*current_datetime\s*\}\}/g, currentTime)
  rendered = rendered.replace(/\{\{\s*current_date\s*\}\}/g, currentDate)
  rendered = rendered.replace(/\{\{\s*current_clock\s*\}\}/g, currentClock)
  rendered = rendered.replace(/\{\{\s*current_weekday\s*\}\}/g, weekDay)
  rendered = rendered.replace(/\{\{\s*current_lunar\s*\}\}/g, lunarStr)
  return rendered
}
