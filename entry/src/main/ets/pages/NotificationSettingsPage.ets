import { common } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { IndexSettingsSheetContent } from '../components/index/IndexSettingsSheetContent'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { IndexSettingsSheetActionCallbacks } from './index/IndexSettingsSheetCoordinator'
import { SettingsSheetType } from './index/IndexPageTypes'
import { getSettingsPageContentMaxWidth, getSettingsPageCompactTabsTotalInset } from '../utils/SettingsPageLayoutHelper'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'

let notificationSettingsPathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct NotificationSettingsPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get bottomAvoidHeight(): number {
    return getAppUiState().bottomAvoidHeight
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
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }

  @Local notifyEnabled: boolean = true
  @Local notifyOnComplete: boolean = true
  @Local notifyOnFailed: boolean = true

  private settingsManager = ServiceRegistry.settings()
  private compactScroller: Scroller = new Scroller()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.reloadSettings()
  }

  private reloadSettings(): void {
    this.notifyEnabled = this.settingsManager.getNotificationEnabled()
    this.notifyOnComplete = this.settingsManager.getNotifyOnCompleteEnabled()
    this.notifyOnFailed = this.settingsManager.getNotifyOnFailedEnabled()
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private getScrollBottomPadding(): number {
    return 24 + getSettingsPageCompactTabsTotalInset(this.px2vp(this.bottomAvoidHeight),
      this.settingsDetailPresentationMode)
  }

  private handleBack(): void {
    if (notificationSettingsPathStack !== null && notificationSettingsPathStack.size() > 0) {
      notificationSettingsPathStack.pop()
    }
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp,
      this.windowHeightVp, (): void => this.CompactTitleStackBuilder())
  }

  private buildCallbacks(): IndexSettingsSheetActionCallbacks {
    const callbacks = new IndexSettingsSheetActionCallbacks()
    callbacks.onToggleNotifyEnabled = async (value: boolean): Promise<void> => {
      const previousValue = this.notifyEnabled
      this.notifyEnabled = value
      try {
        await this.settingsManager.setNotificationEnabled(value)
      } catch (error) {
        console.error('NotificationSettingsPage', `Failed to set notification enabled: ${JSON.stringify(error)}`)
        this.notifyEnabled = previousValue
      }
    }
    callbacks.onToggleNotifyOnComplete = async (value: boolean): Promise<void> => {
      const previousValue = this.notifyOnComplete
      this.notifyOnComplete = value
      try {
        await this.settingsManager.setNotifyOnCompleteEnabled(value)
      } catch (error) {
        console.error('NotificationSettingsPage', `Failed to set notify on complete: ${JSON.stringify(error)}`)
        this.notifyOnComplete = previousValue
      }
    }
    callbacks.onToggleNotifyOnFailed = async (value: boolean): Promise<void> => {
      const previousValue = this.notifyOnFailed
      this.notifyOnFailed = value
      try {
        await this.settingsManager.setNotifyOnFailedEnabled(value)
      } catch (error) {
        console.error('NotificationSettingsPage', `Failed to set notify on failed: ${JSON.stringify(error)}`)
        this.notifyOnFailed = previousValue
      }
    }
    callbacks.onOpenSystemNotificationSettings = (): void => {
      this.openSystemNotificationSettings()
    }
    return callbacks
  }

  private openSystemNotificationSettings(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    notificationManager.openNotificationSettings(context).catch((error: Error): void => {
      console.error('NotificationSettingsPage', `Failed to open notification settings: ${JSON.stringify(error)}`)
      const options = new SnackBarDisplayOptions()
      options.message = $r('app.string.notification_open_settings_failed')
      options.tone = SnackBarTone.ERROR
      showSnackBar(this.getUIContext(), options)
    })
  }

  @Builder
  private PageContent() {
    Scroll(this.compactScroller) {
      Row() {
        Column() {
          if (!this.isDetailPaneMode()) {
            Blank()
              .width('100%')
              .height(this.getCompactContentTopPadding())
          }

          IndexSettingsSheetContent({
            settingsSheetType: SettingsSheetType.NOTIFICATION,
            notifyEnabled: this.notifyEnabled,
            notifyOnComplete: this.notifyOnComplete,
            notifyOnFailed: this.notifyOnFailed,
            callbacks: this.buildCallbacks()
          })
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, bottom: this.getScrollBottomPadding() })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_notifications'))
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
    .backgroundColor(getAppUiState().themeBackground)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.settings_notifications'),
      onBack: () => {
        this.handleBack()
      }
    })
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
        .height('100%')
        .backgroundColor(getAppUiState().themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .bindToScrollable([this.compactScroller])
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(true)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }
}

@Builder
export function NotificationSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    NotificationSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    notificationSettingsPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (notificationSettingsPathStack !== null && notificationSettingsPathStack.size() > 0) {
      notificationSettingsPathStack.pop()
    }
    return true
  })
}
