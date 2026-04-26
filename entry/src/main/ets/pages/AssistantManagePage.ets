import { Assistant, DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'
import { ModelProvider } from '../models/ChatModels'
import { HdsListItemCard } from '@kit.UIDesignKit'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { AssistantService } from '../services/AssistantService'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { ModelSelectorContent } from '../components/ModelSelector'
import { SettingsCompactPageHeader } from '../components/settings/SettingsCompactPageHeader'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth, getSettingsPageCompactTabsTotalInset } from '../utils/SettingsPageLayoutHelper'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { getAppUiState } from '../state/AppUiState'
import { buildPointLightBorderEffect } from '../utils/HdsVisualEffectUtil'

let assistantManagePathStack: NavPathStack | null = null

class AssistantManageRouteParams {
  action: string = ''
}

function resolveAssistantManageRouteParams(param: Object | null | undefined): AssistantManageRouteParams {
  if (param === null || param === undefined) {
    return new AssistantManageRouteParams()
  }
  return param as AssistantManageRouteParams
}

@Entry
@ComponentV2
struct AssistantManagePage {
  @Param initialAction: string = ''
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

  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }

  @Local assistants: Assistant[] = []
  @Local providers: ModelProvider[] = []
  @Local editorVisible: boolean = false
  @Local editingAssistantId: string = ''
  @Local editingCreatedAt: number = 0
  @Local editingSortOrder: number = 0
  @Local editingIsDefault: boolean = false
  @Local formName: string = ''
  @Local formAvatarSymbol: string = 'AI'
  @Local formColor: string = '#0A59F7'
  @Local formSystemPrompt: string = ''
  @Local formDefaultProviderId: string = ''
  @Local formDefaultModelId: string = ''
  @Local formDefaultModelName: string = ''
  @Local formTemperatureEnabled: boolean = false
  @Local formTemperature: number = 0.7
  @Local showModelSheet: boolean = false
  @Local consumedInitialAction: boolean = false

  private assistantService: AssistantService = ServiceRegistry.assistant()
  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()

  aboutToAppear(): void {
    this.loadData()
  }

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private getContentBottomPadding(): number {
    return 24 + getSettingsPageCompactTabsTotalInset(this.px2vp(this.bottomAvoidHeight),
      this.settingsDetailPresentationMode)
  }

  private showPageSnack(message: string | Resource, tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options = new SnackBarDisplayOptions()
    options.message = message
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  private handleBack(): void {
    if (assistantManagePathStack !== null && assistantManagePathStack.size() > 0) {
      assistantManagePathStack.pop()
    }
  }

  private async loadData(): Promise<void> {
    this.providers = await this.providerViewModel.loadProviders()
    this.assistants = await this.assistantService.getAllAssistants()
    if (!this.consumedInitialAction && this.initialAction === 'new') {
      this.consumedInitialAction = true
      this.startNewAssistant()
      return
    }
    if (!this.editorVisible && this.assistants.length > 0) {
      this.selectAssistant(this.assistants[0])
    }
  }

  private selectAssistant(assistant: Assistant): void {
    this.editorVisible = true
    this.editingAssistantId = assistant.id
    this.editingCreatedAt = assistant.createdAt
    this.editingSortOrder = assistant.sortOrder
    this.editingIsDefault = assistant.id === DEFAULT_ASSISTANT_ID || assistant.isDefault
    this.formName = assistant.name
    this.formAvatarSymbol = assistant.avatarSymbol !== '' ? assistant.avatarSymbol : 'AI'
    this.formColor = assistant.color !== '' ? assistant.color : '#0A59F7'
    this.formSystemPrompt = assistant.systemPrompt
    this.formDefaultProviderId = assistant.defaultProviderId
    this.formDefaultModelId = assistant.defaultModelId
    this.formDefaultModelName = assistant.defaultModelName
    this.formTemperatureEnabled = assistant.temperatureEnabled
    this.formTemperature = assistant.temperature
  }

  private startNewAssistant(): void {
    this.editorVisible = true
    this.editingAssistantId = ''
    this.editingCreatedAt = 0
    this.editingSortOrder = 0
    this.editingIsDefault = false
    this.formName = ''
    this.formAvatarSymbol = 'AI'
    this.formColor = '#0A59F7'
    this.formSystemPrompt = ''
    this.formDefaultProviderId = ''
    this.formDefaultModelId = ''
    this.formDefaultModelName = ''
    this.formTemperatureEnabled = false
    this.formTemperature = 0.7
  }

  private getColorOptions(): string[] {
    return ['#0A59F7', '#16A34A', '#DC2626', '#9333EA', '#EA580C', '#0891B2', '#475569', '#BE123C']
  }

  private getDefaultModelText(): ResourceStr {
    return this.formDefaultModelName !== '' ? this.formDefaultModelName : $r('app.string.assistant_model_follow_global')
  }

  private clearDefaultModel(): void {
    this.formDefaultProviderId = ''
    this.formDefaultModelId = ''
    this.formDefaultModelName = ''
  }

  private async saveCurrentAssistant(): Promise<void> {
    const name = this.formName.trim()
    if (name === '') {
      this.showPageSnack($r('app.string.assistant_name_required'), SnackBarTone.ERROR)
      return
    }

    const assistant = new Assistant(this.editingAssistantId, name)
    assistant.avatarSymbol = this.formAvatarSymbol.trim() !== '' ? this.formAvatarSymbol.trim() : 'AI'
    assistant.color = this.formColor
    assistant.systemPrompt = this.formSystemPrompt.trim()
    assistant.defaultProviderId = this.formDefaultProviderId
    assistant.defaultModelId = this.formDefaultModelId
    assistant.defaultModelName = this.formDefaultModelName
    assistant.temperatureEnabled = this.formTemperatureEnabled
    assistant.temperature = this.formTemperature
    assistant.createdAt = this.editingCreatedAt
    assistant.sortOrder = this.editingSortOrder
    assistant.isDefault = this.editingIsDefault

    if (assistant.id === '') {
      await this.assistantService.createAssistant(assistant)
    } else {
      await this.assistantService.saveAssistant(assistant)
    }
    await this.loadData()
    this.selectAssistant(assistant)
    this.showPageSnack($r('app.string.assistant_saved'), SnackBarTone.SUCCESS)
  }

  private async deleteAssistantNow(assistant: Assistant): Promise<void> {
    const deleted = await this.assistantService.deleteAssistant(assistant.id)
    if (!deleted) {
      this.showPageSnack($r('app.string.assistant_delete_failed'), SnackBarTone.ERROR)
      return
    }
    await this.loadData()
    if (this.assistants.length > 0) {
      this.selectAssistant(this.assistants[0])
    } else {
      this.editorVisible = false
    }
    this.showPageSnack($r('app.string.assistant_deleted'), SnackBarTone.SUCCESS)
  }

  private async deleteAssistant(assistant: Assistant): Promise<void> {
    if (assistant.id === DEFAULT_ASSISTANT_ID || assistant.isDefault) {
      return
    }
    const sessionCount = await this.assistantService.getAssistantSessionCount(assistant.id)
    if (sessionCount <= 0) {
      await this.deleteAssistantNow(assistant)
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.assistant_delete_with_chats_title'),
      message: $r('app.string.assistant_delete_with_chats_message'),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: $r('app.color.status_error'),
        action: async () => {
          await this.deleteAssistantNow(assistant)
        }
      }
    })
  }

  private selectDefaultModel(providerId: string, modelId: string, modelName: string): void {
    this.formDefaultProviderId = providerId
    this.formDefaultModelId = modelId
    this.formDefaultModelName = modelName !== '' ? modelName : modelId
    this.showModelSheet = false
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.assistant_manage_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Button() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(this.themePrimary)
        .onClick(() => {
          this.startNewAssistant()
        })
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
  private PageContent() {
    Scroll() {
      Row() {
        Column({ space: 16 }) {
          if (!this.isDetailPaneMode()) {
            Row() {
              Text($r('app.string.assistant_manage_title'))
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)

              Button() {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(18)
                  .fontColor([Color.White])
              }
              .width(36)
              .height(36)
              .borderRadius(18)
              .backgroundColor(this.themePrimary)
              .onClick(() => {
                this.startNewAssistant()
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }

          this.AssistantListCard()
          if (this.editorVisible) {
            this.AssistantEditorCard()
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, bottom: this.getContentBottomPadding() })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private AssistantListCard() {
    Column({ space: 10 }) {
      ForEach(this.assistants, (assistant: Assistant) => {
        this.AssistantRow(assistant)
      }, (assistant: Assistant) => assistant.id)
    }
    .width('100%')
  }

  @Builder
  private AssistantRow(assistant: Assistant) {
    HdsListItemCard({
      textItem: {
        customBuilder: (): void => {
          this.AssistantRowContent(assistant)
        }
      },
      cardBackgroundColor: assistant.id === this.editingAssistantId ? this.themePrimaryLight : $r('app.color.surface'),
      cardBorderRadius: 16,
      accessibilityOptions: {
        accessibilityText: assistant.name,
        accessibilityGroup: {
          isGroup: true
        }
      }
    })
    .width('100%')
    .visualEffect(buildPointLightBorderEffect())
    .onClick(() => {
      this.selectAssistant(assistant)
    })
  }

  @Builder
  private AssistantRowContent(assistant: Assistant) {
    Row({ space: 12 }) {
      Text(assistant.avatarSymbol !== '' ? assistant.avatarSymbol : 'AI')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .backgroundColor(assistant.color !== '' ? assistant.color : this.themePrimary)
        .borderRadius(17)

      Column({ space: 2 }) {
        Text(assistant.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(assistant.isDefault ? $r('app.string.assistant_default_badge') :
          $r('app.string.assistant_custom_badge'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (assistant.id === this.editingAssistantId) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([this.themePrimary])
      }

      if (assistant.id !== DEFAULT_ASSISTANT_ID && !assistant.isDefault) {
        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(17)
            .fontColor([$r('app.color.status_error')])
        }
        .type(ButtonType.Normal)
        .stateEffect(false)
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.deleteAssistant(assistant)
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private AssistantEditorCard() {
    Column({ space: 14 }) {
      this.FormTextField($r('app.string.assistant_name'), this.formName, $r('app.string.assistant_name_placeholder'),
        (value: string): void => {
          this.formName = value
        })
      this.FormTextField($r('app.string.assistant_avatar_symbol'), this.formAvatarSymbol,
        $r('app.string.assistant_avatar_placeholder'), (value: string): void => {
          this.formAvatarSymbol = value
        })

      this.ColorPicker()

      Text($r('app.string.assistant_prompt'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextArea({ text: this.formSystemPrompt, placeholder: $r('app.string.assistant_prompt_placeholder') })
        .width('100%')
        .height(150)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.background'))
        .borderRadius(16)
        .padding(14)
        .onChange((value: string) => {
          this.formSystemPrompt = value
        })

      this.DefaultModelRow()
      this.TemperatureRow()

      Row({ space: 12 }) {
        Button($r('app.string.save'))
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(this.themePrimary)
          .borderRadius(22)
          .onClick(() => {
            this.saveCurrentAssistant()
          })

        if (!this.editingIsDefault && this.editingAssistantId !== '') {
          Button($r('app.string.delete'))
            .layoutWeight(1)
            .height(44)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.status_error'))
            .backgroundColor($r('app.color.background'))
            .borderRadius(22)
            .onClick(() => {
              const assistant = this.assistants.find((item: Assistant) => item.id === this.editingAssistantId)
              if (assistant !== undefined) {
                this.deleteAssistant(assistant)
              }
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private FormTextField(label: ResourceStr, value: string, placeholder: ResourceStr, onChange: (value: string) => void) {
    Column({ space: 8 }) {
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ text: value, placeholder: placeholder })
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.background'))
        .borderRadius(16)
        .padding({ left: 14, right: 14 })
        .onChange((text: string) => {
          onChange(text)
        })
    }
    .width('100%')
  }

  @Builder
  private ColorPicker() {
    Column({ space: 8 }) {
      Text($r('app.string.assistant_color'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row({ space: 10 }) {
        ForEach(this.getColorOptions(), (color: string) => {
          Stack() {
            Circle()
              .width(30)
              .height(30)
              .fill(color)
            if (this.formColor === color) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(16)
                .fontColor([Color.White])
            }
          }
          .width(34)
          .height(34)
          .onClick(() => {
            this.formColor = color
          })
        }, (color: string) => color)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private DefaultModelRow() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text($r('app.string.assistant_default_model'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.getDefaultModelText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.formDefaultModelId !== '') {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor($r('app.color.background'))
        .onClick(() => {
          this.clearDefaultModel()
        })
      }

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.background'))
    .borderRadius(16)
    .onClick(() => {
      this.showModelSheet = true
    })
  }

  @Builder
  private TemperatureRow() {
    Column({ space: 10 }) {
      Row() {
        Text($r('app.string.assistant_temperature_override'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.formTemperatureEnabled })
          .onChange((value: boolean) => {
            this.formTemperatureEnabled = value
          })
      }
      .width('100%')

      if (this.formTemperatureEnabled) {
        Row({ space: 10 }) {
          Slider({ value: this.formTemperature, min: 0, max: 2, step: 0.1, style: SliderStyle.InSet })
            .layoutWeight(1)
            .selectedColor(this.themePrimary)
            .onChange((value: number, _mode: SliderChangeMode) => {
              this.formTemperature = Math.round(value * 10) / 10
            })
          Text(this.formTemperature.toFixed(1))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width(34)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.background'))
    .borderRadius(16)
  }

  @Builder
  private ModelSheetBuilder() {
    Column() {
      ModelSelectorContent({
        currentModelId: this.formDefaultModelId,
        currentProviderId: this.formDefaultProviderId,
        providers: this.providers,
        showEditEntry: false,
        showFavoriteActions: false,
        showFavoriteFilter: false,
        showClearSelectionOption: true,
        clearSelectionText: $r('app.string.assistant_model_follow_global'),
        emptyStateMode: 'settings',
        onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
          this.selectDefaultModel(providerId, modelId, modelName)
        },
        onClearSelection: (): void => {
          this.clearDefaultModel()
          this.showModelSheet = false
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        this.DetailPaneHeader()
        this.PageContent()
      } else {
        SettingsCompactPageHeader({
          title: $r('app.string.assistant_manage_title'),
          topAvoidHeight: this.topAvoidHeight,
          onBack: () => {
            this.handleBack()
          }
        })
        this.PageContent()
      }

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showModelSheet, this.ModelSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: true,
          title: { title: $r('app.string.assistant_default_model') }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

@Builder
export function AssistantManagePageBuilder(name: string, param: Object) {
  NavDestination() {
    AssistantManagePage({
      initialAction: resolveAssistantManageRouteParams(param).action ?? ''
    })
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    assistantManagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (assistantManagePathStack !== null && assistantManagePathStack.size() > 0) {
      assistantManagePathStack.pop()
    }
    return true
  })
}
