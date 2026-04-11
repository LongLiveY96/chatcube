import { MessageAttachment, ReasoningLevel } from '../../models/ChatModels'
import { ChatToolbar } from '../ChatToolbar'
import { ChatInputBar } from '../ChatInputBar'
import { ScreenshotBanner } from '../ScreenshotBanner'

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
  @Event onToggleWebSearch: () => void = (): void => {}
  @Param toolSelectionAvailable: boolean = false
  @Param hasSelectedTools: boolean = false
  @Event onOpenTools: () => void = (): void => {}
  @Param reasoningAvailable: boolean = false
  @Param reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  @Event onReasoningLevelChange: (value: ReasoningLevel) => void = (_value: ReasoningLevel): void => {}
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
    return this.bottomAvoidHeight + 4
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
          onToggleWebSearch: (): void => {
            this.onToggleWebSearch()
          },
          toolSelectionAvailable: this.toolSelectionAvailable,
          hasSelectedTools: this.hasSelectedTools,
          onOpenTools: (): void => {
            this.onOpenTools()
          },
          reasoningAvailable: this.reasoningAvailable,
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
