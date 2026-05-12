/**
 * 供应商图标工具模块
 * 处理供应商和模型图标的显示逻辑
 *
 * 优先使用 AIIconMatcher 本地正则匹配（返回 rawfile 路径），
 * 匹配不到时回退 models.dev 网络缓存
 */

import { getPresetProviderIconPath } from '../config/PresetProviders'
import { ModelCapabilityMatcher } from '../services/ModelCapabilityMatcher'
import { IconDownloadCache } from '../services/IconDownloadCache'
import { matchModelIconPath } from '../services/registry/AIIconMatcher'

// 默认图标路径
const DEFAULT_ICON_PATH = ''

/**
 * 解析模型图标路径
 * 优先本地正则匹配（rawfile 路径），回退 models.dev 网络 URL
 */
function resolveModelIconPathInternal(modelId: string): string {
  // 优先本地正则匹配（确定性强，离线可用）
  const localPath = matchModelIconPath(modelId)
  if (localPath !== '') {
    return localPath
  }
  // 回退 models.dev 缓存
  return ModelCapabilityMatcher.getInstance().getLogoUrl(modelId)
}

export function resolveShareModelIdentity(modelId: string, currentModelId: string, modelName: string): string {
  if (modelId !== undefined && modelId !== '') {
    return modelId
  }
  if (currentModelId !== undefined && currentModelId !== '') {
    return currentModelId
  }
  if (modelName !== undefined && modelName !== '') {
    return modelName
  }
  return ''
}

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
 * 根据模型 ID 获取图标路径
 * 本地 rawfile 路径直接返回；网络 URL 走下载缓存
 */
export function getModelIconPath(modelId: string, providerId: string, providerIconPath?: string): string {
  const iconPath = resolveModelIconPathInternal(modelId)
  if (iconPath === '') {
    return ''
  }
  // 本地 rawfile 路径直接返回
  if (!isNetworkIconPath(iconPath)) {
    return iconPath
  }
  // 网络 URL 走缓存
  const cachedUri = IconDownloadCache.getInstance().getCachedIconUri(iconPath)
  if (cachedUri !== '') {
    return cachedUri
  }
  IconDownloadCache.getInstance().downloadAndCache(iconPath)
  return iconPath
}

/**
 * 仅返回本地已缓存的模型图标，不触发后台下载。
 * 适合截图、离屏渲染等不能容忍异步资源未就绪的场景。
 */
export function getCachedModelIconPath(modelId: string): string {
  const iconPath = resolveModelIconPathInternal(modelId)
  if (iconPath === '') {
    return ''
  }
  // 本地 rawfile 路径始终可用
  if (!isNetworkIconPath(iconPath)) {
    return iconPath
  }
  return IconDownloadCache.getInstance().getCachedIconUri(iconPath)
}

export async function preloadModelIcon(modelId: string): Promise<string> {
  const iconPath = resolveModelIconPathInternal(modelId)
  if (iconPath === '') {
    return ''
  }
  // 本地 rawfile 路径无需预加载
  if (!isNetworkIconPath(iconPath)) {
    return iconPath
  }
  return await IconDownloadCache.getInstance().downloadAndCache(iconPath)
}

/**
 * 构建图标资源的完整路径
 * 网络 URL 或沙箱路径原样返回
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
