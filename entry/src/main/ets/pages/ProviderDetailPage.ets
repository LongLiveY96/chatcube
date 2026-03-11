import { ProviderDetailPanel, ProviderDetailPresentationMode } from '../components/ProviderDetailSheet'
import { getCenteredPageMaxWidth, LayoutSizeClass } from '../config/LayoutProfile'

@Entry
@ComponentV2
struct ProviderDetailPage {
  @Param layoutSizeClass: string = LayoutSizeClass.COMPACT
  @Param windowWidthVp: number = 0

  @Local providerId: string = ''
  @Local routeReady: boolean = false

  private isExpandedLayout(): boolean {
    return this.layoutSizeClass === LayoutSizeClass.EXPANDED
  }

  private getContentMaxWidth(): number {
    if (!this.isExpandedLayout()) {
      return 99999
    }
    return getCenteredPageMaxWidth(this.windowWidthVp)
  }

  private closePage(): void {
    this.getUIContext().getRouter().back()
  }

  aboutToAppear(): void {
    const routerObj = this.getUIContext().getRouter()
    const params = routerObj.getParams() as Record<string, string>
    if (params !== null && params !== undefined && params['providerId'] !== undefined) {
      this.providerId = params['providerId']
    }
    this.routeReady = true
  }

  @Builder
  RouteLoadingView() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color($r('app.color.primary'))

      Text($r('app.string.loading'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Column() {
          if (this.routeReady) {
            ProviderDetailPanel({
              providerId: this.providerId,
              closeOnModelsSelected: false,
              presentationMode: ProviderDetailPresentationMode.PAGE,
              onClose: () => {
                this.closePage()
              }
            })
          } else {
            this.RouteLoadingView()
          }
        }
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
