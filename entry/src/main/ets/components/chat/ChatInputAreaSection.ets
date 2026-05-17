import { MessageAttachment, ReasoningLevel } from '../../models/ChatModels'
import { ChatToolbar, SearchEngineMenuOption } from '../ChatToolbar'
import { ChatInputBar } from '../ChatInputBar'
import { ScreenshotBanner } from '../ScreenshotBanner'
import { ReasoningControlMode } from '../../services/registry/CompatibilityResolver'

@ComponentV2
export struct ChatInputAreaSection {
  @Param inputText: string = ''
  @Event onInputTextChange: (value: string) => void = (_value: string): void => {}
  @Param attachments: MessageAttachment[] = []
  @Event onAttachmentsChange: (value: MessageAttachment[]) => void = (_value: MessageAttachment[]): void => {}
  @Param isSending: boolean = false
  @Param isAwaitingResponse: boolean = false
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  @Param currentModelName: string = ''
  @Param currentProviderIconType: string = ''
  @Param currentProviderIconPath: string = ''
  @Param currentProviderTextIcon: string = ''
  @Param currentProviderTextIconBgColor: string = ''
  @Param currentProviderCustomImagePath: string = ''
  @Param currentProviderBrandColor: ResourceColor = ''
  @Param autoFocus: boolean = false
  @Param isEditing: boolean = false
  @Param webSearchAvailable: boolean = false
  @Param webSearchEnabled: boolean = false
  @Param availableSearchEngines: SearchEngineMenuOption[] = []
  @Param activeSearchEngineId: string = ''
  @Event onSearchEngineSelect: (engineId: string) => void = (_id: string): void => {}
  @Param toolSelectionAvailable: boolean = false
  @Param hasSelectedTools: boolean = false
  @Event onOpenTools: () => void = (): void => {}
  @Param reasoningAvailable: boolean = false
  @Param reasoningControlMode: ReasoningControlMode = ReasoningControlMode.NONE
  @Param reasoningXhighAvailable: boolean = false
  @Param reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  @Event onReasoningLevelChange: (value: ReasoningLevel) => void =
    (_value: ReasoningLevel): void => {}
  @Param hasRecentScreenshot: boolean = false
  @Param bottomAvoidHeight: number = 0
  @Param contentMaxWidth: number = 99999
  @Event onCancelEdit: () => void = () => {}
  @Event onSend: () => void = () => {}
  @Event onStop: () => void = () => {}
  @Event onModelIconClick: () => void = () => {}
  @Param isAttachmentPanelOpen: boolean = false
  @Event onAttachmentClick: () => void = () => {}
  @Event onInputFocus: () => void = () => {}
  @Event onInputBlur: () => void = () => {}
  @Event onComposerContentChanged: () => void = () => {}
  @Event onRecentPhotoDetected: (detected: boolean) => void = (_detected: boolean): void => {}

  private getEffectiveContentMaxWidth(): number {
    return this.contentMaxWidth > 0 ? this.contentMaxWidth : 99999
  }

  private getBottomSpacerHeight(): number {
    return this.bottomAvoidHeight
  }

  build() {
    Column() {
      Column() {
        Row() {
          ScreenshotBanner({
            attachments: this.attachments,
            hasRecentPhoto: this.hasRecentScreenshot,
            onAttachmentsChange: (value: MessageAttachment[]): void => {
              this.onAttachmentsChange(value)
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 4, bottom: 8 })

        ChatToolbar({
          webSearchAvailable: this.webSearchAvailable,
          webSearchEnabled: this.webSearchEnabled,
          availableSearchEngines: this.availableSearchEngines,
          activeSearchEngineId: this.activeSearchEngineId,
          onSearchEngineSelect: (engineId: string): void => {
            this.onSearchEngineSelect(engineId)
          },
          toolSelectionAvailable: this.toolSelectionAvailable,
          hasSelectedTools: this.hasSelectedTools,
          onOpenTools: (): void => {
            this.onOpenTools()
          },
          reasoningAvailable: this.reasoningAvailable,
          reasoningControlMode: this.reasoningControlMode,
          reasoningXhighAvailable: this.reasoningXhighAvailable,
          reasoningLevel: this.reasoningLevel,
          onReasoningLevelChange: (value: ReasoningLevel): void => {
            this.onReasoningLevelChange(value)
          }
        })

        ChatInputBar({
          isAttachmentPanelOpen: this.isAttachmentPanelOpen,
          inputText: this.inputText,
          onInputTextChange: (value: string): void => {
            this.onInputTextChange(value)
          },
          attachments: this.attachments,
          onAttachmentsChange: (value: MessageAttachment[]): void => {
            this.onAttachmentsChange(value)
          },
          isSending: this.isSending,
          isAwaitingResponse: this.isAwaitingResponse,
          currentModelId: this.currentModelId,
          currentProviderId: this.currentProviderId,
          currentModelName: this.currentModelName,
          currentProviderIconType: this.currentProviderIconType,
          currentProviderIconPath: this.currentProviderIconPath,
          currentProviderTextIcon: this.currentProviderTextIcon,
          currentProviderTextIconBgColor: this.currentProviderTextIconBgColor,
          currentProviderCustomImagePath: this.currentProviderCustomImagePath,
          currentProviderBrandColor: this.currentProviderBrandColor,
          autoFocus: this.autoFocus,
          isEditing: this.isEditing,
          onCancelEdit: (): void => {
            this.onCancelEdit()
          },
          onSend: (): void => {
            this.onSend()
          },
          onStop: (): void => {
            this.onStop()
          },
          onModelIconClick: (): void => {
            this.onModelIconClick()
          },
          onAttachmentClick: (): void => {
            this.onAttachmentClick()
          },
          onInputFocus: (): void => {
            this.onInputFocus()
          },
          onInputBlur: (): void => {
            this.onInputBlur()
          },
          onComposerContentChanged: (): void => {
            this.onComposerContentChanged()
          },
          onRecentPhotoDetected: (detected: boolean): void => {
            this.onRecentPhotoDetected(detected)
          }
        })

        // AI 生成标识（合规要求，底部居中显示）
        Row() {
          Text($r('app.string.ai_generated_label'))
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .opacity(0.75)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 3, bottom: 0 })

        Column()
          .width('100%')
          .height(this.getBottomSpacerHeight())
      }
      .width('100%')
      .constraintSize({ maxWidth: this.getEffectiveContentMaxWidth() })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16, top: 6 })
  }
}
