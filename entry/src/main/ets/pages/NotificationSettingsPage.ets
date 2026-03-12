import { common } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { IndexSettingsSheetContent } from '../components/index/IndexSettingsSheetContent'
import { SettingsCompactPageHeader } from '../components/settings/SettingsCompactPageHeader'
import { IndexSettingsSheetActionCallbacks } from './index/IndexSettingsSheetCoordinator'
import { SettingsSheetType } from './index/IndexPageTypes'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState } from '../state/AppUiState'

let notificationSettingsPathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct NotificationSettingsPage {
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

  @Local notifyEnabled: boolean = true
  @Local notifyOnComplete: boolean = true
  @Local notifyOnFailed: boolean = true

  private settingsManager = ServiceRegistry.settings()

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

  private handleBack(): void {
    if (notificationSettingsPathStack !== null && notificationSettingsPathStack.size() > 0) {
      notificationSettingsPathStack.pop()
    }
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
    Scroll() {
      Row() {
        Column() {
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
            title: $r('app.string.settings_notifications'),
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

