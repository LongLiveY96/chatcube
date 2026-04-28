import { refreshAssistantAvatar } from '../services/AssistantAvatarCache'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'

export const ASSISTANT_AVATAR_MODE_SYMBOL: string = 'symbol'
export const ASSISTANT_AVATAR_MODE_IMAGE: string = 'image'

const QQ_AVATAR_PREFIX: string = 'qq:'

function stripLocalAvatarUriVersion(value: string): string {
  let source = value.trim()
  const fragmentIndex = source.indexOf('#')
  if (fragmentIndex >= 0) {
    source = source.substring(0, fragmentIndex)
  }
  const queryIndex = source.indexOf('?')
  return queryIndex >= 0 ? source.substring(0, queryIndex) : source
}

function appendAssistantAvatarCacheKey(source: string, cacheKey: number): string {
  if (cacheKey <= 0 || source === '') {
    return source
  }
  const fragmentIndex = source.indexOf('#')
  const sourceWithoutFragment = fragmentIndex >= 0 ? source.substring(0, fragmentIndex) : source
  const fragment = fragmentIndex >= 0 ? source.substring(fragmentIndex) : ''
  const separator = sourceWithoutFragment.indexOf('?') >= 0 ? '&' : '?'
  return `${sourceWithoutFragment}${separator}avatarCacheKey=${cacheKey}${fragment}`
}

function getLocalAvatarMimeType(source: string): string {
  const cleanSource = stripLocalAvatarUriVersion(source).toLowerCase()
  if (cleanSource.endsWith('.png')) {
    return 'image/png'
  }
  if (cleanSource.endsWith('.webp')) {
    return 'image/webp'
  }
  if (cleanSource.endsWith('.gif')) {
    return 'image/gif'
  }
  if (cleanSource.endsWith('.bmp')) {
    return 'image/bmp'
  }
  return 'image/jpeg'
}

function resolveLocalAvatarPath(source: string): string {
  const cleanSource = stripLocalAvatarUriVersion(source)
  if (!cleanSource.toLowerCase().startsWith('file://')) {
    return cleanSource
  }
  try {
    return new fileUri.FileUri(cleanSource).path
  } catch (_error) {
    return cleanSource.substring(7)
  }
}

function readLocalAvatarBuffer(source: string): ArrayBuffer | null {
  const localPath = resolveLocalAvatarPath(source)
  try {
    const file = fileIo.openSync(localPath, fileIo.OpenMode.READ_ONLY)
    try {
      const stat = fileIo.statSync(file.fd)
      if (stat.size <= 0) {
        return null
      }
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      return buffer
    } finally {
      fileIo.closeSync(file)
    }
  } catch (_error) {
    return null
  }
}

function resolveLocalAvatarDataSource(source: string): string {
  const buffer = readLocalAvatarBuffer(source)
  if (buffer === null) {
    return stripLocalAvatarUriVersion(source)
  }
  const base64Helper = new util.Base64Helper()
  const encoded = base64Helper.encodeToStringSync(new Uint8Array(buffer))
  return `data:${getLocalAvatarMimeType(source)};base64,${encoded}`
}

export function sanitizeAssistantQqNumber(value: string): string {
  return value.replace(/[^0-9]/g, '')
}

export function buildQqAssistantAvatarUrl(value: string): string {
  const qqNumber = sanitizeAssistantQqNumber(value)
  return qqNumber !== '' ? `http://q1.qlogo.cn/g?b=qq&nk=${qqNumber}&s=640` : ''
}

export function extractQqFromAssistantAvatar(value: string): string {
  const avatar = value.trim()
  const lower = avatar.toLowerCase()
  if (lower.startsWith(QQ_AVATAR_PREFIX)) {
    return sanitizeAssistantQqNumber(avatar.substring(QQ_AVATAR_PREFIX.length))
  }
  const qlogoMatch = avatar.match(/[?&]nk=([0-9]+)/)
  if (qlogoMatch !== null && qlogoMatch.length > 1) {
    return sanitizeAssistantQqNumber(qlogoMatch[1])
  }
  return ''
}

export function isQqAssistantAvatar(value: string): boolean {
  return extractQqFromAssistantAvatar(value) !== ''
}

export function isDirectImageAssistantAvatar(value: string): boolean {
  const lower = value.trim().toLowerCase()
  return lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('file://') ||
  lower.startsWith('data:image/')
}

export function isImageAssistantAvatar(value: string): boolean {
  return isQqAssistantAvatar(value) || isDirectImageAssistantAvatar(value)
}

export function resolveAssistantAvatarImageSource(value: string): string {
  const qqNumber = extractQqFromAssistantAvatar(value)
  if (qqNumber !== '') {
    return buildQqAssistantAvatarUrl(qqNumber)
  }
  const source = value.trim()
  if (source.toLowerCase().startsWith('file://')) {
    return stripLocalAvatarUriVersion(source)
  }
  return source
}

export function resolveAssistantAvatarRenderSource(value: string, cacheKey: number = 0): string {
  const source = resolveAssistantAvatarImageSource(value)
  if (cacheKey <= 0 || source === '') {
    return source
  }
  const lower = source.toLowerCase()
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return appendAssistantAvatarCacheKey(source, cacheKey)
  }
  return source
}

export function refreshAssistantAvatarCache(value: string): void {
  const source = resolveAssistantAvatarImageSource(value)
  const lower = source.toLowerCase()
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    refreshAssistantAvatar(source)
  }
}

export function getAssistantAvatarInputMode(value: string): string {
  if (isQqAssistantAvatar(value) || isDirectImageAssistantAvatar(value)) {
    return ASSISTANT_AVATAR_MODE_IMAGE
  }
  return ASSISTANT_AVATAR_MODE_SYMBOL
}

export function normalizeAssistantAvatarValue(value: string): string {
  const avatar = value.trim()
  if (avatar === '' || avatar === QQ_AVATAR_PREFIX) {
    return 'AI'
  }
  const qqNumber = extractQqFromAssistantAvatar(avatar)
  if (qqNumber !== '') {
    return buildQqAssistantAvatarUrl(qqNumber)
  }
  return avatar
}

export function getAssistantAvatarFallbackText(value: string): string {
  if (isQqAssistantAvatar(value)) {
    return 'QQ'
  }
  if (isDirectImageAssistantAvatar(value)) {
    return 'IMG'
  }
  return normalizeAssistantAvatarValue(value)
}

@ComponentV2
export struct AssistantAvatarView {
  @Param value: string = 'AI'
  @Param color: ResourceColor = '#0A59F7'
  @Param avatarSize: number = 44
  @Param radius: number = 15
  @Param fontSize: number = 23
  @Param cacheKey: number = 0
  @Local renderImageSource: string = ''

  aboutToAppear(): void {
    this.syncRenderImageSource()
  }

  @Monitor('value')
  onValueChange(): void {
    this.syncRenderImageSource()
  }

  @Monitor('cacheKey')
  onCacheKeyChange(): void {
    this.syncRenderImageSource()
  }

  private syncRenderImageSource(): void {
    const source = resolveAssistantAvatarImageSource(this.value)
    if (source.toLowerCase().startsWith('file://')) {
      this.renderImageSource = resolveLocalAvatarDataSource(source)
      return
    }
    this.renderImageSource = resolveAssistantAvatarRenderSource(this.value, this.cacheKey)
  }

  private getRenderImageSource(): string {
    if (this.renderImageSource !== '') {
      return this.renderImageSource
    }
    return resolveAssistantAvatarRenderSource(this.value, this.cacheKey)
  }

  @Builder
  private AvatarImage() {
    Image(this.getRenderImageSource())
      .width(this.avatarSize)
      .height(this.avatarSize)
      .objectFit(ImageFit.Cover)
      .sourceSize({
        width: this.avatarSize,
        height: this.avatarSize
      })
      .interpolation(ImageInterpolation.High)
      .borderRadius(this.radius)
      .clip(true)
  }

  build() {
    if (isImageAssistantAvatar(this.value)) {
      Stack() {
        if (this.cacheKey % 2 === 0) {
          this.AvatarImage()
        } else {
          this.AvatarImage()
        }
      }
      .width(this.avatarSize)
      .height(this.avatarSize)
      .borderRadius(this.radius)
      .clip(true)
    } else {
      Stack() {
        Text(getAssistantAvatarFallbackText(this.value))
          .fontSize(this.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: this.avatarSize - 8 })
      }
      .width(this.avatarSize)
      .height(this.avatarSize)
      .backgroundColor(this.color)
      .borderRadius(this.radius)
      .clip(true)
    }
  }
}
