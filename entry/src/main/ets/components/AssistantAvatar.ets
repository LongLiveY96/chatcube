import { refreshAssistantAvatar } from '../services/AssistantAvatarCache'

export const ASSISTANT_AVATAR_MODE_SYMBOL: string = 'symbol'
export const ASSISTANT_AVATAR_MODE_IMAGE: string = 'image'

const QQ_AVATAR_PREFIX: string = 'qq:'

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
  return value.trim()
}

export function resolveAssistantAvatarRenderSource(value: string): string {
  return resolveAssistantAvatarImageSource(value)
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

  @Builder
  private AvatarImage() {
    Image(resolveAssistantAvatarRenderSource(this.value))
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
