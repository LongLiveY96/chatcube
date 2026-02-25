/**
 * 供应商图标工具模块
 * 处理供应商和模型图标的显示逻辑
 *
 * 模型图标完全走 models.dev 网络 logo + 沙箱缓存
 */

import { getPresetProviderIconPath } from '../config/PresetProviders'
import { ModelCapabilityMatcher } from '../services/ModelCapabilityMatcher'
import { IconDownloadCache } from '../services/IconDownloadCache'

// 默认图标路径
const DEFAULT_ICON_PATH = ''

/**
 * 获取供应商图标路径
 * @param providerId 供应商 ID
 * @param customIconPath 自定义图标路径（可选）
 * @returns 图标文件路径
 */
export function getProviderIconPath(providerId: string, customIconPath?: string): string {
  if (customIconPath !== undefined && customIconPath !== '') {
    return customIconPath
  }
  const presetIconPath = getPresetProviderIconPath(providerId)
  if (presetIconPath !== '') {
    return presetIconPath
  }
  return DEFAULT_ICON_PATH
}

/**
 * 根据模型 ID 获取图标路径（走 models.dev 网络 logo）
 * @param modelId 模型 ID（优先）或模型名称（回退）
 * @param providerId 供应商 ID（用于回退）
 * @param providerIconPath 供应商图标路径（用于回退）
 * @returns 图标路径（网络 URL 或沙箱路径）
 */
export function getModelIconPath(modelId: string, providerId: string, providerIconPath?: string): string {
  const matcher = ModelCapabilityMatcher.getInstance()
  const logoUrl = matcher.getLogoUrl(modelId)
  if (logoUrl !== '') {
    const cachedUri = IconDownloadCache.getInstance().getCachedIconUri(logoUrl)
    if (cachedUri !== '') {
      return cachedUri
    }
    // 后台触发下载缓存（不阻塞）
    IconDownloadCache.getInstance().downloadAndCache(logoUrl)
    return logoUrl
  }
  return ''
}

/**
 * 构建图标资源的完整路径
 * 网络 URL 或沙箱路径原样返回
 * @param iconPath 图标路径
 * @returns 完整路径
 */
export function buildIconResourcePath(iconPath: string): string {
  if (iconPath === '') {
    return ''
  }
  return iconPath
}

/**
 * 判断图标路径是否为网络 URL
 */
export function isNetworkIconPath(path: string): boolean {
  return path.startsWith('http://') || path.startsWith('https://')
}

/**
 * 判断图标路径是否为沙箱绝对路径
 */
export function isSandboxIconPath(path: string): boolean {
  return path.startsWith('/data/') || path.startsWith('file://')
}

/**
 * 检查供应商是否可删除
 */
export function canDeleteProvider(providerId: string, isPreset: boolean): boolean {
  if (isPreset) {
    return false
  }
  return true
}
