/**
 * 服务商 QR 分享 payload 定义(版本 1)。
 * QR 二维码内容是 ProviderShareEnvelopeV1 序列化后的 JSON,
 * 解密后的明文是 ProviderShareDataV1 序列化后的 JSON。
 * 字段名缩短是为了节省 QR 容量。
 */

export const ENVELOPE_VERSION: number = 1
export const ENVELOPE_SOURCE: string = 'chatcube'
export const PASSWORD_MIN_LEN: number = 4
export const PASSWORD_MAX_LEN: number = 6
export const PBKDF2_ITERATIONS: number = 100000
export const AES_KEY_SIZE_BYTES: number = 32
export const PBKDF2_SALT_BYTES: number = 16
export const AES_IV_BYTES: number = 12
export const MAX_QR_PAYLOAD_BYTES: number = 800

export interface ProviderShareKdfSpec {
  alg: string   // 'pbkdf2-sha256'
  iter: number  // PBKDF2_ITERATIONS
  salt: string  // base64
}

export interface ProviderShareEnvelopeV1 {
  v: number                   // ENVELOPE_VERSION
  src: string                 // ENVELOPE_SOURCE
  kdf: ProviderShareKdfSpec
  iv: string                  // base64
  ct: string                  // base64 ciphertext + GCM auth tag
}

/**
 * 解密后的明文数据。
 * - n: 服务商显示名
 * - t: ProviderType 字符串值(openai/anthropic/deepseek/...)
 * - as: ApiStyle 字符串值(openai/anthropic/google)
 * - url: baseUrl
 * - k: apiKey(空串表示分享不含 apiKey 的元数据)
 * - ap: apiPath(可空)
 * - ot: OpenAITransport 字符串值(可空)
 * - ch: customHeadersJson(可空)
 */
export interface ProviderShareDataV1 {
  n: string
  t: string
  as: string
  url: string
  k: string
  ap: string
  ot: string
  ch: string
}

export type ProviderShareCodecError =
  | 'invalid_envelope'    // 不是 ChatCube QR / JSON 损坏 / 版本不对
  | 'wrong_password'      // GCM 完整性校验失败
  | 'payload_too_large'   // encode 时超出 MAX_QR_PAYLOAD_BYTES
  | 'crypto_unavailable'  // 加解密 API 抛错
  | 'unknown'

export interface ProviderShareCodecEncodeResult {
  ok: boolean
  payload: string
  error: ProviderShareCodecError | ''
}

export interface ProviderShareCodecDecodeResult {
  ok: boolean
  data: ProviderShareDataV1 | null
  error: ProviderShareCodecError | ''
}
