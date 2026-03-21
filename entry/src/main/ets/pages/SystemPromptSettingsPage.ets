import { ServiceRegistry } from '../services/ServiceRegistry'
import { PreferenceKeys } from '../services/PreferencesService'
import { normalizeSystemPromptTemplate, SystemPromptTemplateDefaults } from '../utils/SystemPromptTemplateUtils'
import { getSettingsPageContentMaxWidth, getSettingsPageCompactTabsTotalInset } from '../utils/SettingsPageLayoutHelper'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState } from '../state/AppUiState'

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

  @Builder
  private PageContent() {
    Row() {
      Column({ space: 12 }) {
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
          .backgroundColor($r('app.color.surface'))
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
            .backgroundColor($r('app.color.surface'))
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
    .backgroundColor($r('app.color.background'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private CompactPageHeader() {
    Column() {
      Column()
        .width('100%')
        .height(px2vp(this.topAvoidHeight))

      Row({ space: 4 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.text_primary')])
        }
        .type(ButtonType.Normal)
        .stateEffect(false)
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.handleBack()
        })

        Text($r('app.string.system_prompt_edit_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .margin({ left: 4 })

        Column()
          .width(40)
          .height(40)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor($r('app.color.background'))
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
          this.CompactPageHeader()
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

