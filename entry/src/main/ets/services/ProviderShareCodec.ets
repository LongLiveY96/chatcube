import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { buffer, util } from '@kit.ArkTS'
import { ModelProvider } from '../models/ChatModels'
import {
  AES_IV_BYTES,
  AES_KEY_SIZE_BYTES,
  ENVELOPE_SOURCE,
  ENVELOPE_VERSION,
  MAX_QR_PAYLOAD_BYTES,
  PBKDF2_ITERATIONS,
  PBKDF2_SALT_BYTES,
  ProviderShareCodecDecodeResult,
  ProviderShareCodecEncodeResult,
  ProviderShareDataV1,
  ProviderShareEnvelopeV1,
  ProviderShareKdfSpec
} from '../models/ProviderSharePayload'

const KDF_ALG: string = 'pbkdf2-sha256'
const KDF_NAME_NATIVE: string = 'PBKDF2|SHA256'
const KDF_SPEC_ALG_NAME: string = 'PBKDF2'
const AES_CIPHER_TRANSFORMATION: string = 'AES256|GCM|PKCS7'
const AES_SYM_KEY_ALG: string = 'AES256'
const GCM_PARAMS_ALG_NAME: string = 'GcmParamsSpec'
const GCM_AUTH_TAG_LEN: number = 16

class ProviderShareCodec {
  /**
   * 把一个服务商序列化、加密成 envelope JSON 字符串(QR 内容)。
   * includeApiKey=false 时 apiKey 字段会被置空,接收方导入后需要自己填写 key。
   */
  async encode(
    provider: ModelProvider,
    password: string,
    includeApiKey: boolean
  ): Promise<ProviderShareCodecEncodeResult> {
    try {
      const data: ProviderShareDataV1 = {
        n: provider.name,
        t: provider.type as string,
        as: provider.apiStyle as string,
        url: provider.baseUrl,
        k: includeApiKey ? provider.apiKey : '',
        ap: provider.apiPath,
        ot: provider.openaiTransport as string,
        ch: provider.customHeadersJson
      }
      const plaintextJson = JSON.stringify(data)
      const plaintextBytes = new Uint8Array(buffer.from(plaintextJson, 'utf-8').buffer)

      const salt = this.generateRandomBytes(PBKDF2_SALT_BYTES)
      const iv = this.generateRandomBytes(AES_IV_BYTES)
      const symKey = await this.deriveAesKey(password, salt)
      const ciphertext = await this.runEncrypt(symKey, iv, plaintextBytes)

      const envelope: ProviderShareEnvelopeV1 = {
        v: ENVELOPE_VERSION,
        src: ENVELOPE_SOURCE,
        kdf: {
          alg: KDF_ALG,
          iter: PBKDF2_ITERATIONS,
          salt: this.base64Encode(salt)
        } as ProviderShareKdfSpec,
        iv: this.base64Encode(iv),
        ct: this.base64Encode(ciphertext)
      }
      const envelopeJson = JSON.stringify(envelope)

      if (envelopeJson.length > MAX_QR_PAYLOAD_BYTES) {
        return { ok: false, payload: '', error: 'payload_too_large' }
      }

      return { ok: true, payload: envelopeJson, error: '' }
    } catch (err) {
      console.error('ProviderShareCodec', `encode failed: ${JSON.stringify(err)}`)
      return { ok: false, payload: '', error: 'crypto_unavailable' }
    }
  }

  /**
   * 仅校验 envelope JSON 结构和 v/src 头,**不**解密。
   * 用于扫到 QR 后立即拦截非 ChatCube payload(URL QR / 名片 QR 等)。
   */
  peekEnvelope(envelopeJson: string): boolean {
    try {
      const parsed = JSON.parse(envelopeJson) as ProviderShareEnvelopeV1
      if (parsed === null || typeof parsed !== 'object') {
        return false
      }
      if (parsed.v !== ENVELOPE_VERSION || parsed.src !== ENVELOPE_SOURCE) {
        return false
      }
      if (parsed.kdf === undefined || parsed.kdf === null
        || typeof parsed.iv !== 'string' || typeof parsed.ct !== 'string') {
        return false
      }
      return true
    } catch (err) {
      return false
    }
  }

  /**
   * 解析 envelope JSON 字符串、校验来源、用密码解密、返回明文 data。
   * 校验失败 / 密码错 / JSON 损坏分别返回不同 error code。
   */
  async decode(envelopeJson: string, password: string): Promise<ProviderShareCodecDecodeResult> {
    let envelope: ProviderShareEnvelopeV1
    try {
      const parsed = JSON.parse(envelopeJson) as ProviderShareEnvelopeV1
      if (parsed === null || typeof parsed !== 'object') {
        return { ok: false, data: null, error: 'invalid_envelope' }
      }
      envelope = parsed
    } catch (err) {
      return { ok: false, data: null, error: 'invalid_envelope' }
    }

    if (envelope.v !== ENVELOPE_VERSION || envelope.src !== ENVELOPE_SOURCE) {
      return { ok: false, data: null, error: 'invalid_envelope' }
    }
    if (envelope.kdf === undefined || envelope.kdf === null
      || typeof envelope.iv !== 'string' || typeof envelope.ct !== 'string') {
      return { ok: false, data: null, error: 'invalid_envelope' }
    }

    let salt: Uint8Array
    let iv: Uint8Array
    let ciphertext: Uint8Array
    try {
      salt = this.base64Decode(envelope.kdf.salt)
      iv = this.base64Decode(envelope.iv)
      ciphertext = this.base64Decode(envelope.ct)
    } catch (err) {
      return { ok: false, data: null, error: 'invalid_envelope' }
    }

    let plaintextBytes: Uint8Array
    try {
      const symKey = await this.deriveAesKey(password, salt)
      plaintextBytes = await this.runDecrypt(symKey, iv, ciphertext)
    } catch (err) {
      // GCM auth tag 不匹配走这里
      console.info('ProviderShareCodec', `decrypt failed (likely wrong password): ${JSON.stringify(err)}`)
      return { ok: false, data: null, error: 'wrong_password' }
    }

    try {
      const plaintextJson = buffer.from(plaintextBytes).toString('utf-8')
      const data = JSON.parse(plaintextJson) as ProviderShareDataV1
      if (data === null || typeof data !== 'object'
        || typeof data.n !== 'string' || typeof data.t !== 'string'
        || typeof data.as !== 'string' || typeof data.url !== 'string') {
        return { ok: false, data: null, error: 'invalid_envelope' }
      }
      return { ok: true, data, error: '' }
    } catch (err) {
      return { ok: false, data: null, error: 'invalid_envelope' }
    }
  }

  private generateRandomBytes(len: number): Uint8Array {
    try {
      const random = cryptoFramework.createRandom()
      const blob = random.generateRandomSync(len)
      return blob.data
    } catch (err) {
      throw new Error(`generateRandomBytes failed: ${JSON.stringify(err)}`)
    }
  }

  private async deriveAesKey(password: string, salt: Uint8Array): Promise<cryptoFramework.SymKey> {
    try {
      const kdf = cryptoFramework.createKdf(KDF_NAME_NATIVE)
      const spec: cryptoFramework.PBKDF2Spec = {
        algName: KDF_SPEC_ALG_NAME,
        password: password,
        salt: salt,
        iterations: PBKDF2_ITERATIONS,
        keySize: AES_KEY_SIZE_BYTES
      }
      const secret = await kdf.generateSecret(spec)
      const symGenerator = cryptoFramework.createSymKeyGenerator(AES_SYM_KEY_ALG)
      return await symGenerator.convertKey({ data: secret.data })
    } catch (err) {
      throw new Error(`deriveAesKey failed: ${JSON.stringify(err)}`)
    }
  }

  private async runEncrypt(
    symKey: cryptoFramework.SymKey,
    iv: Uint8Array,
    plaintext: Uint8Array
  ): Promise<Uint8Array> {
    try {
      const cipher = cryptoFramework.createCipher(AES_CIPHER_TRANSFORMATION)
      const emptyAad = new Uint8Array(0)
      const gcmParams: cryptoFramework.GcmParamsSpec = {
        algName: GCM_PARAMS_ALG_NAME,
        iv: { data: iv },
        aad: { data: emptyAad },
        authTag: { data: new Uint8Array(GCM_AUTH_TAG_LEN) }
      }
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, gcmParams)
      const result = await cipher.doFinal({ data: plaintext })
      // HarmonyOS GCM 一次性 doFinal 返回 cipher + authTag 拼接 (tag 在末尾 16 字节)
      return result.data
    } catch (err) {
      throw new Error(`runEncrypt failed: ${JSON.stringify(err)}`)
    }
  }

  private async runDecrypt(
    symKey: cryptoFramework.SymKey,
    iv: Uint8Array,
    cipherWithTag: Uint8Array
  ): Promise<Uint8Array> {
    if (cipherWithTag.length < GCM_AUTH_TAG_LEN) {
      throw new Error('runDecrypt failed: ciphertext too short to contain auth tag')
    }
    try {
      // HarmonyOS GCM 解密语义: authTag 必须从密文末尾切出来, 通过 GcmParamsSpec.authTag 传入,
      // doFinal 只接收 cipher 部分(不含 tag)。整段 cipherWithTag 整个塞进 doFinal 会校验失败。
      // 用 slice 而不是 subarray 拿独立 buffer, 避免 GCM 实现对共享底层 buffer 的兼容性问题。
      const tagOffset = cipherWithTag.length - GCM_AUTH_TAG_LEN
      const cipherOnly = cipherWithTag.slice(0, tagOffset)
      const authTag = cipherWithTag.slice(tagOffset)
      const cipher = cryptoFramework.createCipher(AES_CIPHER_TRANSFORMATION)
      const emptyAad = new Uint8Array(0)
      const gcmParams: cryptoFramework.GcmParamsSpec = {
        algName: GCM_PARAMS_ALG_NAME,
        iv: { data: iv },
        aad: { data: emptyAad },
        authTag: { data: authTag }
      }
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, gcmParams)
      const result = await cipher.doFinal({ data: cipherOnly })
      return result.data
    } catch (err) {
      throw new Error(`runDecrypt failed: ${JSON.stringify(err)}`)
    }
  }

  private base64Encode(bytes: Uint8Array): string {
    const helper = new util.Base64Helper()
    return helper.encodeToStringSync(bytes)
  }

  private base64Decode(b64: string): Uint8Array {
    const helper = new util.Base64Helper()
    return helper.decodeSync(b64)
  }
}

let codecInstance: ProviderShareCodec | null = null

export function getProviderShareCodec(): ProviderShareCodec {
  if (codecInstance === null) {
    codecInstance = new ProviderShareCodec()
  }
  return codecInstance
}
