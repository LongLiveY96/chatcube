// 应用统一错误码
export enum AppErrorCode {
  UNKNOWN = 'UNKNOWN',
  PREFERENCES_INIT_FAILED = 'PREFERENCES_INIT_FAILED',
  DATABASE_INIT_FAILED = 'DATABASE_INIT_FAILED',
  DATABASE_SCHEMA_INIT_FAILED = 'DATABASE_SCHEMA_INIT_FAILED',
  DATABASE_NOT_READY = 'DATABASE_NOT_READY'
}

// 应用统一错误类型
export class AppError extends Error {
  code: AppErrorCode = AppErrorCode.UNKNOWN
  causeDetail: string = ''
  recoverable: boolean = false

  constructor(
    code: AppErrorCode,
    message: string,
    causeDetail: string = '',
    recoverable: boolean = false
  ) {
    super(message)
    this.code = code
    this.causeDetail = causeDetail
    this.recoverable = recoverable
    this.name = 'AppError'
  }
}

// 统一 Result 封装
export class Result<T> {
  ok: boolean = false
  data: T | null = null
  error: AppError | null = null

  private constructor(ok: boolean, data: T | null, error: AppError | null) {
    this.ok = ok
    this.data = data
    this.error = error
  }

  static success<T>(data: T): Result<T> {
    return new Result<T>(true, data, null)
  }

  static failure<T>(error: AppError): Result<T> {
    return new Result<T>(false, null, error)
  }
}

// 将错误对象安全转为文本，避免日志中出现 [object Object]
export function toErrorDetail(error: Object | null): string {
  if (error === null) {
    return ''
  }
  const jsonText = JSON.stringify(error)
  if (jsonText !== undefined && jsonText !== null && jsonText !== '') {
    return jsonText
  }
  return error.toString()
}

