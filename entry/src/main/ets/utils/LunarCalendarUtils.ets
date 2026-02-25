/**
 * 农历日历工具类
 * 提供公历转农历功能
 */

// 农历数据表（1900-2100年）
// 每个数字的含义：
// - 低4位：闰月月份（0表示无闰月）
// - 第5位起：每月大小月标志（1=大月30天，0=小月29天）
const LUNAR_INFO: number[] = [
  0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,
  0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,
  0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,
  0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
  0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,
  0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5d0, 0x14573, 0x052d0, 0x0a9a8, 0x0e950, 0x06aa0,
  0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,
  0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b5a0, 0x195a6,
  0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
  0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0,
  0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,
  0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
  0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
  0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45,
  0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
  0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0,
  0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4,
  0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0,
  0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160,
  0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252,
  0x0d520
]

// 农历月份名称
const LUNAR_MONTH_NAMES: string[] = [
  '正月', '二月', '三月', '四月', '五月', '六月',
  '七月', '八月', '九月', '十月', '冬月', '腊月'
]

// 农历日期名称
const LUNAR_DAY_NAMES: string[] = [
  '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
  '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十'
]

// 天干
const TIAN_GAN: string[] = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸']

// 地支
const DI_ZHI: string[] = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥']

// 生肖
const SHENG_XIAO: string[] = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪']

/**
 * 农历日期结果类
 */
export class LunarDate {
  year: number = 0
  month: number = 0
  day: number = 0
  isLeapMonth: boolean = false
  yearGanZhi: string = ''
  shengXiao: string = ''
  monthName: string = ''
  dayName: string = ''

  constructor(
    year: number,
    month: number,
    day: number,
    isLeapMonth: boolean,
    yearGanZhi: string,
    shengXiao: string,
    monthName: string,
    dayName: string
  ) {
    this.year = year
    this.month = month
    this.day = day
    this.isLeapMonth = isLeapMonth
    this.yearGanZhi = yearGanZhi
    this.shengXiao = shengXiao
    this.monthName = monthName
    this.dayName = dayName
  }

  /**
   * 获取格式化的农历日期字符串
   * 例如：农历乙巳年（蛇年）腊月十三
   */
  toString(): string {
    const leapPrefix = this.isLeapMonth ? '闰' : ''
    return `农历${this.yearGanZhi}年（${this.shengXiao}年）${leapPrefix}${this.monthName}${this.dayName}`
  }

  /**
   * 获取简短的农历日期
   * 例如：腊月十三
   */
  toShortString(): string {
    const leapPrefix = this.isLeapMonth ? '闰' : ''
    return `${leapPrefix}${this.monthName}${this.dayName}`
  }
}

/**
 * 获取某年的闰月月份（0表示无闰月）
 */
function getLeapMonth(year: number): number {
  const index = year - 1900
  if (index < 0 || index >= LUNAR_INFO.length) {
    return 0
  }
  return LUNAR_INFO[index] & 0xf
}

/**
 * 获取某年闰月的天数（0表示无闰月）
 */
function getLeapMonthDays(year: number): number {
  if (getLeapMonth(year) === 0) {
    return 0
  }
  const index = year - 1900
  if (index < 0 || index >= LUNAR_INFO.length) {
    return 0
  }
  return (LUNAR_INFO[index] & 0x10000) !== 0 ? 30 : 29
}

/**
 * 获取某年某月的天数
 */
function getMonthDays(year: number, month: number): number {
  const index = year - 1900
  if (index < 0 || index >= LUNAR_INFO.length) {
    return 29
  }
  return (LUNAR_INFO[index] & (0x10000 >> month)) !== 0 ? 30 : 29
}

/**
 * 获取某年农历的总天数
 */
function getYearDays(year: number): number {
  let sum = 348
  const index = year - 1900
  if (index < 0 || index >= LUNAR_INFO.length) {
    return sum
  }
  for (let i = 0x8000; i > 0x8; i >>= 1) {
    if ((LUNAR_INFO[index] & i) !== 0) {
      sum += 1
    }
  }
  return sum + getLeapMonthDays(year)
}

/**
 * 获取干支年
 */
function getGanZhiYear(year: number): string {
  const ganIndex = (year - 4) % 10
  const zhiIndex = (year - 4) % 12
  return TIAN_GAN[ganIndex] + DI_ZHI[zhiIndex]
}

/**
 * 获取生肖
 */
function getShengXiao(year: number): string {
  return SHENG_XIAO[(year - 4) % 12]
}

/**
 * 公历转农历
 * @param solarYear 公历年
 * @param solarMonth 公历月（1-12）
 * @param solarDay 公历日
 * @returns 农历日期对象
 */
export function solarToLunar(solarYear: number, solarMonth: number, solarDay: number): LunarDate {
  // 计算距离1900年1月31日（农历1900年正月初一）的天数
  const baseDate = new Date(1900, 0, 31)
  const targetDate = new Date(solarYear, solarMonth - 1, solarDay)
  let offset = Math.floor((targetDate.getTime() - baseDate.getTime()) / (24 * 60 * 60 * 1000))

  // 计算农历年
  let lunarYear = 1900
  let yearDays = 0
  while (lunarYear < 2101 && offset > 0) {
    yearDays = getYearDays(lunarYear)
    if (offset < yearDays) {
      break
    }
    offset -= yearDays
    lunarYear++
  }

  // 计算农历月
  let lunarMonth = 1
  let isLeapMonth = false
  const leapMonth = getLeapMonth(lunarYear)
  let monthDays = 0

  for (let i = 1; i <= 12; i++) {
    // 闰月
    if (leapMonth > 0 && i === leapMonth + 1 && !isLeapMonth) {
      monthDays = getLeapMonthDays(lunarYear)
      isLeapMonth = true
      i--
    } else {
      monthDays = getMonthDays(lunarYear, i)
      isLeapMonth = false
    }

    if (offset < monthDays) {
      lunarMonth = i
      break
    }
    offset -= monthDays
  }

  // 农历日
  const lunarDay = offset + 1

  // 获取月份和日期名称
  const monthName = LUNAR_MONTH_NAMES[lunarMonth - 1]
  const dayName = LUNAR_DAY_NAMES[lunarDay - 1]
  const yearGanZhi = getGanZhiYear(lunarYear)
  const shengXiao = getShengXiao(lunarYear)

  return new LunarDate(
    lunarYear,
    lunarMonth,
    lunarDay,
    isLeapMonth,
    yearGanZhi,
    shengXiao,
    monthName,
    dayName
  )
}

/**
 * 获取当前日期的农历信息
 * @returns 农历日期对象
 */
export function getCurrentLunarDate(): LunarDate {
  const now = new Date()
  return solarToLunar(now.getFullYear(), now.getMonth() + 1, now.getDate())
}
