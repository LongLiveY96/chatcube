import { cacheDownload } from '@kit.BasicServicesKit'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { getAppUiState, setAppUiStateValue } from '../state/AppUiState'

export class AssistantAvatarCache {
  private static instance: AssistantAvatarCache | null = null
  private pendingUrls: Set<string> = new Set()

  private constructor() {}

  static getInstance(): AssistantAvatarCache {
    if (AssistantAvatarCache.instance === null) {
      AssistantAvatarCache.instance = new AssistantAvatarCache()
    }
    return AssistantAvatarCache.instance
  }

  refresh(url: string): void {
    const normalized = url.trim()
    if (!this.isNetworkUrl(normalized)) {
      return
    }
    if (this.pendingUrls.has(normalized)) {
      return
    }
    this.pendingUrls.add(normalized)
    const done = (): void => {
      this.pendingUrls.delete(normalized)
      this.notifyAvatarChanged(normalized)
    }
    try {
      cacheDownload.onDownloadSuccess(normalized, done)
      cacheDownload.onDownloadError(normalized, done)
      cacheDownload.download(normalized, {
        cacheStrategy: cacheDownload.CacheStrategy.FORCE
      })
    } catch (_error) {
      this.pendingUrls.delete(normalized)
    }
  }

  private notifyAvatarChanged(url: string): void {
    try {
      cacheDownload.offDownloadSuccess(url)
      cacheDownload.offDownloadError(url)
    } catch (_error) {
    }
    const current = getAppUiState().assistantAvatarRefreshAt
    const now = Date.now()
    setAppUiStateValue(AppStorageKeys.ASSISTANT_AVATAR_REFRESH_AT, now > current ? now : current + 1)
  }

  private isNetworkUrl(url: string): boolean {
    const lower = url.toLowerCase()
    return lower.startsWith('http://') || lower.startsWith('https://')
  }
}

export function refreshAssistantAvatar(url: string): void {
  AssistantAvatarCache.getInstance().refresh(url)
}
