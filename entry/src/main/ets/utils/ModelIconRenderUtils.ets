import { buildIconResourcePath, getModelIconPath, isNetworkIconPath, isSandboxIconPath } from './ProviderIconUtils'

export enum ModelIconRenderType {
  NONE = 'none',
  RAWFILE = 'rawfile',
  URI = 'uri'
}

export class ModelIconRenderData {
  resourcePath: string = ''
  renderType: ModelIconRenderType = ModelIconRenderType.NONE

  constructor(resourcePath: string = '', renderType: ModelIconRenderType = ModelIconRenderType.NONE) {
    this.resourcePath = resourcePath
    this.renderType = renderType
  }

  hasIcon(): boolean {
    return this.resourcePath !== '' && this.renderType !== ModelIconRenderType.NONE
  }

  isRawfile(): boolean {
    return this.renderType === ModelIconRenderType.RAWFILE
  }
}

function resolveModelIconPath(modelId: string, providerId: string, modelName: string): string {
  if (modelId !== '') {
    const iconById = getModelIconPath(modelId, providerId, '')
    if (iconById !== '') {
      return iconById
    }
  }
  if (modelName !== '') {
    return getModelIconPath(modelName, providerId, '')
  }
  return ''
}

export function buildModelIconRenderData(modelId: string, providerId: string, modelName: string = ''): ModelIconRenderData {
  const iconPath = resolveModelIconPath(modelId, providerId, modelName)
  if (iconPath === '') {
    return new ModelIconRenderData('', ModelIconRenderType.NONE)
  }

  const resourcePath = buildIconResourcePath(iconPath)
  if (resourcePath === '') {
    return new ModelIconRenderData('', ModelIconRenderType.NONE)
  }

  const renderType = !isNetworkIconPath(resourcePath) && !isSandboxIconPath(resourcePath) ?
    ModelIconRenderType.RAWFILE :
    ModelIconRenderType.URI
  return new ModelIconRenderData(resourcePath, renderType)
}
