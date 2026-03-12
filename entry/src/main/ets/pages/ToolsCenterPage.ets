import { ToolsCenterPanel } from '../components/ToolsCenterPanel'
import { SettingsCompactPageHeader } from '../components/settings/SettingsCompactPageHeader'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'

let toolsCenterPagePathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct ToolsCenterPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private handleBack(): void {
    if (toolsCenterPagePathStack !== null && toolsCenterPagePathStack.size() > 0) {
      toolsCenterPagePathStack.pop()
    }
  }

  @Builder
  private PageContent() {
    Row() {
      Column() {
        ToolsCenterPanel({ showHeader: false })
      }
      .width('100%')
      .constraintSize({ maxWidth: this.getContentMaxWidth() })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.tools_center_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor($r('app.color.background'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        Column() {
          this.DetailPaneHeader()
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column() {
          SettingsCompactPageHeader({
            title: $r('app.string.tools_center_title'),
            topAvoidHeight: this.topAvoidHeight,
            onBack: () => {
              this.handleBack()
            }
          })
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.background'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

@Builder
export function ToolsCenterPageBuilder(name: string, param: Object) {
  NavDestination() {
    ToolsCenterPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    toolsCenterPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (toolsCenterPagePathStack !== null && toolsCenterPagePathStack.size() > 0) {
      toolsCenterPagePathStack.pop()
    }
    return true
  })
}

