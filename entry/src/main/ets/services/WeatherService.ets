import { getHttpService, HttpService } from './HttpService'

// 天气地点信息
export class WeatherLocation {
  name: string = ''
  region: string = ''
  country: string = ''
  latitude: number = 0
  longitude: number = 0
  timezone: string = ''

  constructor(
    name: string,
    region: string,
    country: string,
    latitude: number,
    longitude: number,
    timezone: string
  ) {
    this.name = name
    this.region = region
    this.country = country
    this.latitude = latitude
    this.longitude = longitude
    this.timezone = timezone
  }

  getDisplayName(): string {
    const parts: string[] = []
    if (this.name !== '') {
      parts.push(this.name)
    }
    if (this.region !== '' && this.region !== this.name) {
      parts.push(this.region)
    }
    if (this.country !== '' && this.country !== this.region && this.country !== this.name) {
      parts.push(this.country)
    }
    if (parts.length === 0) {
      return '未知地点'
    }
    return parts.join(', ')
  }
}

// 当前天气快照
export class WeatherCurrentSnapshot {
  time: string = ''
  temperature: number = 0
  feelsLike: number = 0
  humidity: number = 0
  windSpeed: number = 0
  windDirection: number = 0
  precipitation: number = 0
  weatherCode: number = -1
  weatherText: string = ''

  constructor(
    time: string,
    temperature: number,
    feelsLike: number,
    humidity: number,
    windSpeed: number,
    windDirection: number,
    precipitation: number,
    weatherCode: number,
    weatherText: string
  ) {
    this.time = time
    this.temperature = temperature
    this.feelsLike = feelsLike
    this.humidity = humidity
    this.windSpeed = windSpeed
    this.windDirection = windDirection
    this.precipitation = precipitation
    this.weatherCode = weatherCode
    this.weatherText = weatherText
  }
}

// 逐日天气预报
export class WeatherForecastDay {
  date: string = ''
  weatherCode: number = -1
  weatherText: string = ''
  tempMin: number = 0
  tempMax: number = 0
  precipitationProbability: number = 0

  constructor(
    date: string,
    weatherCode: number,
    weatherText: string,
    tempMin: number,
    tempMax: number,
    precipitationProbability: number
  ) {
    this.date = date
    this.weatherCode = weatherCode
    this.weatherText = weatherText
    this.tempMin = tempMin
    this.tempMax = tempMax
    this.precipitationProbability = precipitationProbability
  }
}

// 天气查询返回结果（业务层）
export class WeatherQueryResult {
  success: boolean = false
  location: WeatherLocation
  current: WeatherCurrentSnapshot
  daily: WeatherForecastDay[] = []
  unit: string = 'celsius'
  source: string = ''
  errorMessage: string = ''

  constructor(
    success: boolean,
    location: WeatherLocation,
    current: WeatherCurrentSnapshot,
    daily: WeatherForecastDay[],
    unit: string,
    source: string,
    errorMessage: string
  ) {
    this.success = success
    this.location = location
    this.current = current
    this.daily = daily
    this.unit = unit
    this.source = source
    this.errorMessage = errorMessage
  }
}

interface OpenMeteoGeocodingLocation {
  name?: string
  country?: string
  admin1?: string
  latitude?: number
  longitude?: number
  timezone?: string
}

interface OpenMeteoGeocodingResponse {
  results?: OpenMeteoGeocodingLocation[]
}

interface OpenMeteoCurrentWeather {
  time?: string
  temperature_2m?: number
  apparent_temperature?: number
  relative_humidity_2m?: number
  wind_speed_10m?: number
  wind_direction_10m?: number
  precipitation?: number
  weather_code?: number
}

interface OpenMeteoDailyWeather {
  time?: string[]
  weather_code?: number[]
  temperature_2m_max?: number[]
  temperature_2m_min?: number[]
  precipitation_probability_max?: number[]
}

interface OpenMeteoForecastResponse {
  timezone?: string
  current?: OpenMeteoCurrentWeather
  daily?: OpenMeteoDailyWeather
}

class WeatherLocationLookupResult {
  success: boolean = false
  location: WeatherLocation
  errorMessage: string = ''

  constructor(success: boolean, location: WeatherLocation, errorMessage: string) {
    this.success = success
    this.location = location
    this.errorMessage = errorMessage
  }
}

export class WeatherService {
  private static instance: WeatherService | null = null
  private httpService: HttpService
  private readonly sourceName: string = 'Open-Meteo (https://open-meteo.com/, free no API key)'

  private constructor() {
    this.httpService = getHttpService()
  }

  static getInstance(): WeatherService {
    if (WeatherService.instance === null) {
      WeatherService.instance = new WeatherService()
    }
    return WeatherService.instance
  }

  async queryWeather(location: string, days: number = 3, unit: string = 'celsius'): Promise<WeatherQueryResult> {
    const normalizedLocation = this.normalizeLocation(location)
    if (normalizedLocation === '') {
      return this.buildErrorResult('查询地点不能为空')
    }

    const normalizedDays = this.normalizeDays(days)
    const normalizedUnit = this.normalizeUnit(unit)

    const locationResult = await this.lookupLocation(normalizedLocation)
    if (!locationResult.success) {
      return this.buildErrorResult(locationResult.errorMessage)
    }

    return await this.fetchForecast(locationResult.location, normalizedDays, normalizedUnit)
  }

  private buildErrorResult(message: string): WeatherQueryResult {
    return new WeatherQueryResult(
      false,
      this.buildEmptyLocation(),
      this.buildEmptyCurrent(),
      [],
      'celsius',
      this.sourceName,
      message
    )
  }

  private buildEmptyLocation(): WeatherLocation {
    return new WeatherLocation('', '', '', 0, 0, '')
  }

  private buildEmptyCurrent(): WeatherCurrentSnapshot {
    return new WeatherCurrentSnapshot('', 0, 0, 0, 0, 0, 0, -1, '未知')
  }

  private normalizeDays(raw: number): number {
    if (!Number.isFinite(raw)) {
      return 3
    }
    const value = Math.floor(raw)
    if (value < 1) {
      return 1
    }
    if (value > 7) {
      return 7
    }
    return value
  }

  private normalizeUnit(raw: string): string {
    const normalized = raw.trim().toLowerCase()
    if (normalized === 'fahrenheit' || normalized === 'f') {
      return 'fahrenheit'
    }
    return 'celsius'
  }

  private normalizeLocation(raw: string): string {
    let normalized = raw.trim()
    if (normalized === '') {
      return ''
    }

    normalized = normalized.replace(/(天气预报|天气|气温|温度|空气质量|aqi|pm2\.5)/gi, '')
    normalized = normalized.replace(/[，。！？?]/g, ' ')
    normalized = normalized.replace(/\s+/g, ' ').trim()

    if (normalized === '') {
      return raw.trim()
    }
    return normalized
  }

  private async lookupLocation(location: string): Promise<WeatherLocationLookupResult> {
    const url =
      'https://geocoding-api.open-meteo.com/v1/search?count=1&language=zh&format=json&name='
      + encodeURIComponent(location)

    const response = await this.httpService.get(
      url,
      { 'Accept': 'application/json' },
      { timeout: 8000 }
    )
    if (!response.success) {
      return new WeatherLocationLookupResult(false, this.buildEmptyLocation(), `地点解析失败: ${response.errorMessage}`)
    }

    try {
      const parsed = JSON.parse(response.data) as OpenMeteoGeocodingResponse
      if (parsed.results === undefined || parsed.results.length === 0) {
        return new WeatherLocationLookupResult(false, this.buildEmptyLocation(), `未找到地点: ${location}`)
      }

      const first = parsed.results[0]
      const name = first.name !== undefined ? first.name : location
      const region = first.admin1 !== undefined ? first.admin1 : ''
      const country = first.country !== undefined ? first.country : ''
      const latitude = first.latitude !== undefined ? first.latitude : 0
      const longitude = first.longitude !== undefined ? first.longitude : 0
      const timezone = first.timezone !== undefined ? first.timezone : ''

      const found = new WeatherLocation(name, region, country, latitude, longitude, timezone)
      return new WeatherLocationLookupResult(true, found, '')
    } catch (error) {
      return new WeatherLocationLookupResult(
        false,
        this.buildEmptyLocation(),
        `地点解析响应处理失败: ${JSON.stringify(error)}`
      )
    }
  }

  private async fetchForecast(location: WeatherLocation, days: number, unit: string): Promise<WeatherQueryResult> {
    const url = this.buildForecastUrl(location.latitude, location.longitude, days, unit)
    const response = await this.httpService.get(
      url,
      { 'Accept': 'application/json' },
      { timeout: 10000 }
    )
    if (!response.success) {
      return new WeatherQueryResult(
        false,
        location,
        this.buildEmptyCurrent(),
        [],
        unit,
        this.sourceName,
        `天气查询失败: ${response.errorMessage}`
      )
    }

    try {
      const parsed = JSON.parse(response.data) as OpenMeteoForecastResponse
      if (parsed.current === undefined || parsed.daily === undefined) {
        return new WeatherQueryResult(
          false,
          location,
          this.buildEmptyCurrent(),
          [],
          unit,
          this.sourceName,
          '天气数据不完整，请稍后重试'
        )
      }

      const current = this.buildCurrentSnapshot(parsed.current)
      const daily = this.buildDailyForecast(parsed.daily)
      if (daily.length === 0) {
        return new WeatherQueryResult(
          false,
          location,
          current,
          [],
          unit,
          this.sourceName,
          '天气预报数据为空，请稍后重试'
        )
      }

      if (parsed.timezone !== undefined && parsed.timezone.trim() !== '') {
        location.timezone = parsed.timezone.trim()
      }

      return new WeatherQueryResult(
        true,
        location,
        current,
        daily,
        unit,
        this.sourceName,
        ''
      )
    } catch (error) {
      return new WeatherQueryResult(
        false,
        location,
        this.buildEmptyCurrent(),
        [],
        unit,
        this.sourceName,
        `天气响应处理失败: ${JSON.stringify(error)}`
      )
    }
  }

  private buildForecastUrl(latitude: number, longitude: number, days: number, unit: string): string {
    const currentFields = 'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m,wind_direction_10m'
    const dailyFields = 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'

    return 'https://api.open-meteo.com/v1/forecast?latitude=' + latitude.toString()
      + '&longitude=' + longitude.toString()
      + '&current=' + encodeURIComponent(currentFields)
      + '&daily=' + encodeURIComponent(dailyFields)
      + '&timezone=auto'
      + '&forecast_days=' + days.toString()
      + '&temperature_unit=' + unit
      + '&wind_speed_unit=kmh'
  }

  private buildCurrentSnapshot(raw: OpenMeteoCurrentWeather): WeatherCurrentSnapshot {
    const weatherCode = raw.weather_code !== undefined ? Math.round(raw.weather_code) : -1
    return new WeatherCurrentSnapshot(
      raw.time !== undefined ? raw.time : '',
      raw.temperature_2m !== undefined ? raw.temperature_2m : 0,
      raw.apparent_temperature !== undefined ? raw.apparent_temperature : 0,
      raw.relative_humidity_2m !== undefined ? raw.relative_humidity_2m : 0,
      raw.wind_speed_10m !== undefined ? raw.wind_speed_10m : 0,
      raw.wind_direction_10m !== undefined ? raw.wind_direction_10m : 0,
      raw.precipitation !== undefined ? raw.precipitation : 0,
      weatherCode,
      this.mapWeatherCode(weatherCode)
    )
  }

  private buildDailyForecast(raw: OpenMeteoDailyWeather): WeatherForecastDay[] {
    const dates = raw.time !== undefined ? raw.time : []
    const weatherCodes = raw.weather_code !== undefined ? raw.weather_code : []
    const tempMax = raw.temperature_2m_max !== undefined ? raw.temperature_2m_max : []
    const tempMin = raw.temperature_2m_min !== undefined ? raw.temperature_2m_min : []
    const precipitationProbability = raw.precipitation_probability_max !== undefined ? raw.precipitation_probability_max : []

    const list: WeatherForecastDay[] = []
    for (let i = 0; i < dates.length; i++) {
      const code = i < weatherCodes.length ? Math.round(weatherCodes[i]) : -1
      const min = i < tempMin.length ? tempMin[i] : 0
      const max = i < tempMax.length ? tempMax[i] : 0
      const precipProb = i < precipitationProbability.length ? precipitationProbability[i] : 0
      list.push(new WeatherForecastDay(
        dates[i],
        code,
        this.mapWeatherCode(code),
        min,
        max,
        precipProb
      ))
    }
    return list
  }

  private mapWeatherCode(code: number): string {
    switch (code) {
      case 0:
        return '晴朗'
      case 1:
        return '基本晴朗'
      case 2:
        return '局部多云'
      case 3:
        return '阴天'
      case 45:
      case 48:
        return '有雾'
      case 51:
      case 53:
      case 55:
        return '毛毛雨'
      case 56:
      case 57:
        return '冻毛毛雨'
      case 61:
      case 63:
      case 65:
        return '降雨'
      case 66:
      case 67:
        return '冻雨'
      case 71:
      case 73:
      case 75:
        return '降雪'
      case 77:
        return '雪粒'
      case 80:
      case 81:
      case 82:
        return '阵雨'
      case 85:
      case 86:
        return '阵雪'
      case 95:
        return '雷暴'
      case 96:
      case 99:
        return '雷暴伴冰雹'
      default:
        return '未知'
    }
  }
}

export function getWeatherService(): WeatherService {
  return WeatherService.getInstance()
}
