import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { AppLanguage } from '../services/PreferencesService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { IndexSettingsSheetContent } from '../components/index/IndexSettingsSheetContent'
import { IndexSettingsSheetActionCallbacks } from './index/IndexSettingsSheetCoordinator'
import { SettingsSheetType } from './index/IndexPageTypes'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'

@Entry
@Component
struct LanguageSettingsPage {
  @StorageProp(AppStorageKeys.LAYOUT_SIZE_CLASS) layoutSizeClass: string = LayoutSizeClass.COMPACT
  @StorageProp(AppStorageKeys.WINDOW_WIDTH_VP) windowWidthVp: number = 0
  @StorageProp(AppStorageKeys.WINDOW_HEIGHT_VP) windowHeightVp: number = 0
  @StorageProp(AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE) settingsDetailPresentationMode: string = 'page'

  @State currentLanguage: AppLanguage = AppLanguage.SYSTEM

  private settingsManager = ServiceRegistry.settings()

  aboutToAppear(): void {
    this.currentLanguage = this.settingsManager.getLanguage()
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private buildCallbacks(): IndexSettingsSheetActionCallbacks {
    const callbacks = new IndexSettingsSheetActionCallbacks()
    callbacks.onSelectLanguage = async (language: AppLanguage): Promise<void> => {
      const previousLanguage = this.currentLanguage
      this.currentLanguage = language
      try {
        await this.settingsManager.setLanguage(language)
      } catch (error) {
        console.error('LanguageSettingsPage', `Failed to set language: ${JSON.stringify(error)}`)
        this.currentLanguage = previousLanguage
      }
    }
    return callbacks
  }

  @Builder
  private PageContent() {
    Scroll() {
      Row() {
        Column() {
          IndexSettingsSheetContent({
            settingsSheetType: SettingsSheetType.LANGUAGE,
            currentLanguage: this.currentLanguage,
            callbacks: this.buildCallbacks()
          })
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_language'))
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
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.background'))
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .titleBar({
          avoidLayoutSafeArea: true,
          enableComponentSafeArea: true,
          content: {
            title: {
              mainTitle: $r('app.string.settings_language')
            }
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

@Builder
export function LanguageSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    LanguageSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
}
