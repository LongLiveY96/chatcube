import { Assistant, DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'
import { ModelProvider } from '../models/ChatModels'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { AssistantService } from '../services/AssistantService'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { ModelSelectorContent } from '../components/ModelSelector'
import { SettingsCompactPageHeader } from '../components/settings/SettingsCompactPageHeader'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import {
  AssistantAvatarView,
  normalizeAssistantAvatarValue,
  refreshAssistantAvatarCache
} from '../components/AssistantAvatar'
import { AssistantAvatarEditorSheet } from '../components/AssistantAvatarEditorSheet'
import { getSettingsPageContentMaxWidth, getSettingsPageCompactTabsTotalInset } from '../utils/SettingsPageLayoutHelper'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { getAppUiState, observeAppUiState } from '../state/AppUiState'

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

  @Computed
  get assistantAvatarRefreshAt(): number {
    return getAppUiState().assistantAvatarRefreshAt
  }

  @Monitor('assistantAvatarRefreshAt')
  onAssistantAvatarRefreshMonitor(): void {
    if (this.assistantAvatarRefreshAt > 0 && this.assistantAvatarRefreshAt !== this.handledAssistantAvatarRefreshAt) {
      this.handledAssistantAvatarRefreshAt = this.assistantAvatarRefreshAt
      this.bumpAssistantAvatarRenderTick()
    }
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
  @Local showAvatarEditorSheet: boolean = false
  @Local assistantAvatarRenderTick: number = 0
  @Local consumedInitialAction: boolean = false

  private assistantService: AssistantService = ServiceRegistry.assistant()
  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()
  private assistantAvatarObserverDisposer: (() => void) | null = null
  private handledAssistantAvatarRefreshAt: number = 0

  aboutToAppear(): void {
    this.registerAssistantAvatarObserver()
    this.loadData()
  }

  aboutToDisappear(): void {
    if (this.assistantAvatarObserverDisposer !== null) {
      this.assistantAvatarObserverDisposer()
      this.assistantAvatarObserverDisposer = null
    }
  }

  private registerAssistantAvatarObserver(): void {
    if (this.assistantAvatarObserverDisposer === null) {
      this.assistantAvatarObserverDisposer = observeAppUiState(AppStorageKeys.ASSISTANT_AVATAR_REFRESH_AT, (): void => {
        this.onAssistantAvatarRefreshMonitor()
      })
    }
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
    this.bumpAssistantAvatarRenderTick()
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
    this.formAvatarSymbol = this.normalizeAvatarSymbol(assistant.avatarSymbol)
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

  private patchAssistantInMemory(assistant: Assistant): void {
    const nextAssistants: Assistant[] = []
    let replaced = false
    for (let i = 0; i < this.assistants.length; i++) {
      if (this.assistants[i].id === assistant.id) {
        nextAssistants.push(assistant)
        replaced = true
      } else {
        nextAssistants.push(this.assistants[i])
      }
    }
    if (replaced) {
      this.assistants = nextAssistants
      this.bumpAssistantAvatarRenderTick()
    }
  }

  private buildAssistantAvatarStateKey(assistants: Assistant[]): string {
    const parts: string[] = []
    for (let i = 0; i < assistants.length; i++) {
      parts.push(`${assistants[i].id}:${assistants[i].avatarSymbol}:${assistants[i].color}`)
    }
    return parts.join('|')
  }

  private bumpAssistantAvatarRenderTick(): void {
    this.assistantAvatarRenderTick += 1
  }

  private getDefaultModelText(): ResourceStr {
    return this.formDefaultModelName !== '' ? this.formDefaultModelName : $r('app.string.assistant_model_follow_global')
  }

  private getAssistantDefaultModelText(assistant: Assistant): ResourceStr {
    return assistant.defaultModelName !== '' ? assistant.defaultModelName : $r('app.string.assistant_model_follow_global')
  }

  private getAssistantAccentColor(assistant: Assistant): string {
    return assistant.color !== '' ? assistant.color : this.themePrimary
  }

  private getCurrentFormAccentColor(): string {
    return this.formColor !== '' ? this.formColor : this.themePrimary
  }

  private normalizeAvatarSymbol(value: string): string {
    return normalizeAssistantAvatarValue(value)
  }

  private setFormAvatarSymbol(value: string): void {
    this.formAvatarSymbol = this.normalizeAvatarSymbol(value)
    this.bumpAssistantAvatarRenderTick()
    refreshAssistantAvatarCache(this.formAvatarSymbol)
  }

  private getAssistantPromptStateText(assistant: Assistant): ResourceStr {
    return assistant.systemPrompt.trim() !== '' ? $r('app.string.assistant_prompt_configured') :
      $r('app.string.assistant_prompt_empty')
  }

  private getAssistantTemperatureText(assistant: Assistant): ResourceStr {
    return assistant.temperatureEnabled ? assistant.temperature.toFixed(1) : $r('app.string.assistant_temperature_global')
  }

  private getFormPromptStateText(): ResourceStr {
    return this.formSystemPrompt.trim() !== '' ? $r('app.string.assistant_prompt_configured') :
      $r('app.string.assistant_prompt_empty')
  }

  private getFormTemperatureText(): ResourceStr {
    return this.formTemperatureEnabled ? this.formTemperature.toFixed(1) : $r('app.string.assistant_temperature_global')
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
    assistant.avatarSymbol = this.normalizeAvatarSymbol(this.formAvatarSymbol)
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
    this.patchAssistantInMemory(assistant)
    await this.loadData()
    const savedAssistant = this.assistants.find((item: Assistant) => item.id === assistant.id)
    this.selectAssistant(savedAssistant !== undefined ? savedAssistant : assistant)
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
            Column() {
              Row() {
                Text($r('app.string.assistant_manage_title'))
                  .fontSize(22)
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
            .width('100%')
            .alignItems(HorizontalAlign.Start)
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
      }, (assistant: Assistant) =>
        `${assistant.id}:${assistant.avatarSymbol}:${assistant.color}:${this.assistantAvatarRenderTick}`)
    }
    .width('100%')
  }

  @Builder
  private AssistantRow(assistant: Assistant) {
    Column() {
      this.AssistantRowContent(assistant)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .border({
      width: assistant.id === this.editingAssistantId ? 1.5 : 1,
      color: assistant.id === this.editingAssistantId ? this.themePrimary : $r('app.color.divider')
    })
    .onClick(() => {
      this.selectAssistant(assistant)
    })
  }

  @Builder
  private AssistantRowContent(assistant: Assistant) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        this.AssistantAvatarBadge(assistant.avatarSymbol, this.getAssistantAccentColor(assistant), 44, 15, 23)

        Column({ space: 5 }) {
          Row({ space: 6 }) {
            Text(assistant.name)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            Text(assistant.isDefault ? $r('app.string.assistant_default_badge') :
              $r('app.string.assistant_custom_badge'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .height(22)
              .padding({ left: 8, right: 8 })
              .backgroundColor($r('app.color.background'))
              .borderRadius(11)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.getAssistantDefaultModelText(assistant))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (assistant.id === this.editingAssistantId) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(18)
            .fontColor([this.getAssistantAccentColor(assistant)])
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

      Row({ space: 8 }) {
        this.AssistantRowMeta($r('app.string.assistant_prompt_label'), this.getAssistantPromptStateText(assistant))
        this.AssistantRowMeta($r('app.string.assistant_temperature_override'), this.getAssistantTemperatureText(assistant))
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private AssistantRowMeta(label: ResourceStr, value: ResourceStr) {
    Row({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(28)
    .padding({ left: 10, right: 10 })
    .backgroundColor($r('app.color.background'))
    .borderRadius(10)
  }

  @Builder
  private AssistantEditorCard() {
    Column({ space: 14 }) {
      this.AssistantEditorPreview()

      this.NameAvatarRow()

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
  private AssistantEditorPreview() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        AssistantAvatarView({
          value: this.formAvatarSymbol,
          color: this.getCurrentFormAccentColor(),
          avatarSize: 52,
          radius: 18,
          fontSize: 28,
          cacheKey: this.assistantAvatarRenderTick
        })

        Column({ space: 5 }) {
          Row({ space: 6 }) {
            this.AssistantEditorStatusBadge(this.editingAssistantId === '' ? $r('app.string.new_assistant') :
              $r('app.string.edit_assistant'))

            Text(this.editingIsDefault ? $r('app.string.assistant_default_badge') :
              $r('app.string.assistant_custom_badge'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .height(22)
              .padding({ left: 8, right: 8 })
              .backgroundColor($r('app.color.background'))
              .borderRadius(11)
          }
          .width('100%')

          Text(this.formName.trim() !== '' ? this.formName.trim() : $r('app.string.assistant_name_placeholder'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        this.AssistantEditorMetric($r('app.string.assistant_model_label'), this.getDefaultModelText())
        this.AssistantEditorMetric($r('app.string.assistant_prompt_label'), this.getFormPromptStateText())
      }
      .width('100%')

      Row({ space: 8 }) {
        this.AssistantEditorMetric($r('app.string.assistant_temperature_override'), this.getFormTemperatureText())
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.background'))
    .borderRadius(16)
  }

  @Builder
  private AssistantEditorMetric(label: ResourceStr, value: ResourceStr) {
    Column({ space: 3 }) {
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .layoutWeight(1)
    .height(50)
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
  }

  @Builder
  private AssistantEditorStatusBadge(label: ResourceStr) {
    Row({ space: 5 }) {
      Circle()
        .width(6)
        .height(6)
        .fill(this.getCurrentFormAccentColor())
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(22)
    .padding({ left: 8, right: 8 })
    .backgroundColor($r('app.color.background'))
    .borderRadius(11)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private AssistantAvatarBadge(symbol: string, color: ResourceColor, size: number, radius: number, fontSize: number) {
    AssistantAvatarView({
      value: symbol,
      color: color,
      avatarSize: size,
      radius: radius,
      fontSize: fontSize,
      cacheKey: this.assistantAvatarRenderTick
    })
  }

  @Builder
  private NameAvatarRow() {
    Column({ space: 8 }) {
      Text($r('app.string.assistant_name'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row({ space: 12 }) {
        TextInput({ text: this.formName, placeholder: $r('app.string.assistant_name_placeholder') })
          .layoutWeight(1)
          .height(52)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.background'))
          .borderRadius(18)
          .padding({ left: 14, right: 14 })
          .onChange((text: string) => {
            this.formName = text
          })

        Button() {
          AssistantAvatarView({
            value: this.formAvatarSymbol,
            color: this.getCurrentFormAccentColor(),
            avatarSize: 60,
            radius: 20,
            fontSize: 34,
            cacheKey: this.assistantAvatarRenderTick
          })
        }
        .width(60)
        .height(60)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(20)
        .onClick(() => {
          this.showAvatarEditorSheet = true
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

  @Builder
  private AvatarEditorSheetBuilder() {
    AssistantAvatarEditorSheet({
      avatarValue: this.formAvatarSymbol,
      $avatarValue: (value: string): void => {
        this.setFormAvatarSymbol(value)
      },
      avatarColor: this.getCurrentFormAccentColor(),
      onClose: (): void => {
        this.showAvatarEditorSheet = false
      }
    })
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

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAvatarEditorSheet, this.AvatarEditorSheetBuilder(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          backgroundColor: $r('app.color.background'),
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.showAvatarEditorSheet = false
          }
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
