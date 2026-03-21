import { motion } from '@kit.MultimodalAwarenessKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { setAppUiStateValue } from '../state/AppUiState'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { PreferenceKeys } from '../services/PreferencesService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { IndexSettingsSheetContent } from '../components/index/IndexSettingsSheetContent'
import { SettingsCompactPageHeader } from '../components/settings/SettingsCompactPageHeader'
import { IndexSettingsSheetActionCallbacks } from './index/IndexSettingsSheetCoordinator'
import { SettingsSheetType } from './index/IndexPageTypes'
import { getSettingsPageContentMaxWidth, getSettingsPageCompactTabsTotalInset } from '../utils/SettingsPageLayoutHelper'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState } from '../state/AppUiState'

let handAdaptiveSettingsPathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct HandAdaptiveSettingsPage {
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

  @Local handAdaptiveEnabled: boolean = false
  @Local handAdaptiveNewChat: boolean = false
  @Local handAdaptiveUnsupported: boolean = false

  private preferencesService = ServiceRegistry.preferences()
  private readonly probeHoldingHandCallback = (_status: motion.HoldingHandStatus): void => {}

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.loadSettings()
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
    if (handAdaptiveSettingsPathStack !== null && handAdaptiveSettingsPathStack.size() > 0) {
      handAdaptiveSettingsPathStack.pop()
    }
  }

  private async loadSettings(): Promise<void> {
    const enabled = await this.preferencesService.getBoolean(PreferenceKeys.HAND_ADAPTIVE_ENABLED, false)
    const newChatEnabled = await this.preferencesService.getBoolean(PreferenceKeys.HAND_ADAPTIVE_NEW_CHAT, enabled)
    this.handAdaptiveEnabled = enabled
    this.handAdaptiveNewChat = enabled ? newChatEnabled : false
    this.handAdaptiveUnsupported = enabled ? !this.isHoldingHandSupported() : false
  }

  private isHoldingHandSupported(): boolean {
    try {
      motion.on('holdingHandChanged', this.probeHoldingHandCallback)
      motion.off('holdingHandChanged', this.probeHoldingHandCallback)
      return true
    } catch (error) {
      const businessError = error as BusinessError
      console.error('HandAdaptiveSettingsPage',
        `Failed to probe holding hand support: ${JSON.stringify(businessError)}`)
      return false
    }
  }

  private async persistSettings(): Promise<void> {
    await this.preferencesService.setBoolean(PreferenceKeys.HAND_ADAPTIVE_ENABLED, this.handAdaptiveEnabled)
    await this.preferencesService.setBoolean(PreferenceKeys.HAND_ADAPTIVE_NEW_CHAT, this.handAdaptiveNewChat)
    AppStorage.setOrCreate(AppStorageKeys.SETTING_HAND_ADAPTIVE_ENABLED, this.handAdaptiveEnabled)
    AppStorage.setOrCreate(AppStorageKeys.SETTING_HAND_ADAPTIVE_NEW_CHAT, this.handAdaptiveNewChat)
    AppStorage.setOrCreate(AppStorageKeys.SETTING_HAND_ADAPTIVE_UNSUPPORTED, this.handAdaptiveUnsupported)
    setAppUiStateValue(AppStorageKeys.SETTINGS_HAND_ADAPTIVE_CHANGED_AT, Date.now())
  }

  private buildCallbacks(): IndexSettingsSheetActionCallbacks {
    const callbacks = new IndexSettingsSheetActionCallbacks()
    callbacks.onToggleHandAdaptiveEnabled = (value: boolean): void => {
      this.applyMasterSetting(value)
    }
    callbacks.onToggleHandAdaptiveNewChat = (value: boolean): void => {
      this.applyNewChatSetting(value)
    }
    return callbacks
  }

  private applyMasterSetting(value: boolean): void {
    this.handAdaptiveEnabled = value
    if (value) {
      this.handAdaptiveNewChat = true
      this.handAdaptiveUnsupported = !this.isHoldingHandSupported()
    } else {
      this.handAdaptiveNewChat = false
      this.handAdaptiveUnsupported = false
    }
    this.persistSettings().catch((error: Error): void => {
      console.error('HandAdaptiveSettingsPage', `Failed to persist master setting: ${JSON.stringify(error)}`)
    })
  }

  private applyNewChatSetting(value: boolean): void {
    this.handAdaptiveNewChat = value
    this.persistSettings().catch((error: Error): void => {
      console.error('HandAdaptiveSettingsPage', `Failed to persist new chat setting: ${JSON.stringify(error)}`)
    })
  }

  @Builder
  private PageContent() {
    Scroll() {
      Row() {
        Column() {
          IndexSettingsSheetContent({
            settingsSheetType: SettingsSheetType.HAND_ADAPTIVE,
            handAdaptiveEnabled: this.handAdaptiveEnabled,
            handAdaptiveNewChat: this.handAdaptiveNewChat,
            handAdaptiveUnsupported: this.handAdaptiveUnsupported,
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
        Text($r('app.string.hand_adaptive_title'))
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
            title: $r('app.string.hand_adaptive_title'),
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
export function HandAdaptiveSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    HandAdaptiveSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    handAdaptiveSettingsPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (handAdaptiveSettingsPathStack !== null && handAdaptiveSettingsPathStack.size() > 0) {
      handAdaptiveSettingsPathStack.pop()
    }
    return true
  })
}

