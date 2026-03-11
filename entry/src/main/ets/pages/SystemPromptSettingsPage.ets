import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { PreferenceKeys } from '../services/PreferencesService'
import { normalizeSystemPromptTemplate, SystemPromptTemplateDefaults } from '../utils/SystemPromptTemplateUtils'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState } from '../state/AppUiState'

@Entry
@ComponentV2
struct SystemPromptSettingsPage {
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

  private preferencesService = ServiceRegistry.preferences()

  aboutToAppear(): void {
    this.loadSystemPrompt()
  }

  private async loadSystemPrompt(): Promise<void> {
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

        TextArea({ text: this.customSystemPrompt, placeholder: $r('app.string.system_prompt_placeholder') })
          .layoutWeight(1)
          .width('100%')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius(20)
          .padding(16)
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
    .padding({ left: 16, right: 16, bottom: 24 })
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
              mainTitle: $r('app.string.system_prompt_edit_title')
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
export function SystemPromptSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    SystemPromptSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
}

