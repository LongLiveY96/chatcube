import {
  ProviderDetailPanel,
  ProviderDetailPresentationMode,
  tryHandleProviderDetailInternalBack
} from '../components/ProviderDetailSheet'
import { notifyModelManageRefresh } from './ModelManagePage'

export interface ProviderDetailRouteParams {
  providerId?: string
  isCreateMode?: boolean
}

function resolveProviderDetailRouteParams(param: Object): ProviderDetailRouteParams {
  return param as ProviderDetailRouteParams
}

let providerDetailPagePathStack: NavPathStack | null = null

function popProviderDetailPage(): boolean {
  if (providerDetailPagePathStack === null || providerDetailPagePathStack.size() <= 0) {
    return false
  }
  providerDetailPagePathStack.pop()
  return true
}

@ComponentV2
struct ProviderDetailPageContent {
  @Param providerId: string = ''
  @Param isCreateMode: boolean = false
  @Event onClose: () => void = () => {}

  build() {
    Column() {
      ProviderDetailPanel({
        providerId: this.providerId,
        isCreateMode: this.isCreateMode,
        closeOnModelsSelected: false,
        presentationMode: ProviderDetailPresentationMode.PAGE,
        onClose: this.onClose,
        onProviderChanged: (_providerId: string, _isCreateMode: boolean) => {
          notifyModelManageRefresh()
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

@Builder
export function ProviderDetailPageBuilder(name: string, param: Object) {
  NavDestination() {
    ProviderDetailPageContent({
      providerId: resolveProviderDetailRouteParams(param).providerId ?? '',
      isCreateMode: resolveProviderDetailRouteParams(param).isCreateMode ?? false,
      onClose: () => {
        popProviderDetailPage()
      }
    })
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    providerDetailPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (tryHandleProviderDetailInternalBack()) {
      return true
    }
    return popProviderDetailPage()
  })
}
