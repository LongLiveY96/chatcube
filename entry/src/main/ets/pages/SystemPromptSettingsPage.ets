import { ServiceRegistry } from '../services/ServiceRegistry'
import { PreferenceKeys } from '../services/PreferencesService'
import { normalizeSystemPromptTemplate, SystemPromptTemplateDefaults } from '../utils/SystemPromptTemplateUtils'
import { getSettingsPageContentMaxWidth, getSettingsPageCompactTabsTotalInset } from '../utils/SettingsPageLayoutHelper'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState } from '../state/AppUiState'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'

let systemPromptSettingsPathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct SystemPromptSettingsPage {
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
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }

  @Local customSystemPrompt: string = ''
  @Local systemPromptEnabled: boolean = true

  private preferencesService = ServiceRegistry.preferences()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.loadSystemPrompt()
  }

  private async loadSystemPrompt(): Promise<void> {
    this.systemPromptEnabled = await this.preferencesService.getBoolean(
      PreferenceKeys.SYSTEM_PROMPT_ENABLED,
      true
    )
    const saved = await this.preferencesService.getString(
      PreferenceKeys.CUSTOM_SYSTEM_PROMPT,
      SystemPromptTemplateDefaults.DEFAULT_TEMPLATE
    )
    this.customSystemPrompt = normalizeSystemPromptTemplate(saved)
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private getContentBottomPadding(): number {
    return 24 + getSettingsPageCompactTabsTotalInset(this.px2vp(this.bottomAvoidHeight),
      this.settingsDetailPresentationMode)
  }

  private saveSystemPrompt(): void {
    const normalizedTemplate = normalizeSystemPromptTemplate(this.customSystemPrompt)
    this.customSystemPrompt = normalizedTemplate
    this.preferencesService.setString(PreferenceKeys.CUSTOM_SYSTEM_PROMPT, normalizedTemplate).then((): void => {
      const options = new SnackBarDisplayOptions()
      options.message = $r('app.string.system_prompt_saved')
      options.tone = SnackBarTone.SUCCESS
      showSnackBar(this.getUIContext(), options)
    }).catch((error: Error): void => {
      console.error('SystemPromptSettingsPage', `Failed to save system prompt: ${JSON.stringify(error)}`)
    })
  }

  private resetSystemPrompt(): void {
    this.customSystemPrompt = SystemPromptTemplateDefaults.DEFAULT_TEMPLATE
  }

  private handleBack(): void {
    if (systemPromptSettingsPathStack !== null && systemPromptSettingsPathStack.size() > 0) {
      systemPromptSettingsPathStack.pop()
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

  @Builder
  private PageContent() {
    Row() {
      Column({ space: 12 }) {
        if (!this.isDetailPaneMode()) {
          Blank()
            .width('100%')
            .height(this.getCompactContentTopPadding())
        }

        Text($r('app.string.system_prompt_hint'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
          .width('100%')

        Text($r('app.string.system_prompt_variables_hint'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .lineHeight(16)
          .width('100%')

        Row() {
          Text($r('app.string.system_prompt_enabled_label'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.systemPromptEnabled })
            .onChange((isOn: boolean) => {
              this.systemPromptEnabled = isOn
              this.preferencesService.setBoolean(PreferenceKeys.SYSTEM_PROMPT_ENABLED, isOn)
            })
        }
        .width('100%')
        .padding({ left: 4, right: 4 })

        TextArea({ text: this.customSystemPrompt, placeholder: $r('app.string.system_prompt_placeholder') })
          .layoutWeight(1)
          .width('100%')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor(getAppUiState().themeSurface)
          .borderRadius(20)
          .padding(16)
          .enabled(this.systemPromptEnabled)
          .opacity(this.systemPromptEnabled ? 1 : 0.5)
          .onChange((value: string) => {
            this.customSystemPrompt = value
          })

        Row({ space: 12 }) {
          Button($r('app.string.system_prompt_clear'))
            .layoutWeight(1)
            .height(44)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor(getAppUiState().themeSurface)
            .borderRadius(22)
            .onClick(() => {
              this.resetSystemPrompt()
            })

          Button($r('app.string.save'))
            .layoutWeight(1)
            .height(44)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(this.themePrimary)
            .borderRadius(22)
            .onClick(() => {
              this.saveSystemPrompt()
            })
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .constraintSize({ maxWidth: this.getContentMaxWidth() })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 16, right: 16, bottom: this.getContentBottomPadding() })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.system_prompt_edit_title'))
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
      title: $r('app.string.system_prompt_edit_title'),
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
export function SystemPromptSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    SystemPromptSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    systemPromptSettingsPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (systemPromptSettingsPathStack !== null && systemPromptSettingsPathStack.size() > 0) {
      systemPromptSettingsPathStack.pop()
    }
    return true
  })
}

