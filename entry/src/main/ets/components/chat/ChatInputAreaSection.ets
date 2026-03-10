import { MessageAttachment, ReasoningLevel } from '../../models/ChatModels'
import { ChatToolbar } from '../ChatToolbar'
import { ChatInputBar } from '../ChatInputBar'
import { ScreenshotBanner } from '../ScreenshotBanner'

@Component
export struct ChatInputAreaSection {
  @Link inputText: string
  @Link attachments: MessageAttachment[]
  @Prop isSending: boolean = false
  @Prop isAwaitingResponse: boolean = false
  @Prop currentModelId: string = ''
  @Prop currentProviderId: string = ''
  @Prop currentModelName: string = ''
  @Prop currentProviderIconType: string = ''
  @Prop currentProviderIconPath: string = ''
  @Prop currentProviderTextIcon: string = ''
  @Prop currentProviderTextIconBgColor: string = ''
  @Prop currentProviderCustomImagePath: string = ''
  @Prop currentProviderBrandColor: ResourceColor = ''
  @Prop autoFocus: boolean = false
  @Prop isEditing: boolean = false
  @Prop webSearchAvailable: boolean = false
  @Link webSearchEnabled: boolean
  @Link reasoningLevel: ReasoningLevel
  @Prop hasRecentScreenshot: boolean = false
  @Prop bottomAvoidHeight: number = 0
  @Prop contentMaxWidth: number = 99999
  onCancelEdit: () => void = () => {}
  onSend: () => void = () => {}
  onStop: () => void = () => {}
  onModelIconClick: () => void = () => {}
  onAttachmentClick: () => void = () => {}
  onInputFocus: () => void = () => {}
  onInputBlur: () => void = () => {}
  onComposerContentChanged: () => void = () => {}
  onRecentPhotoDetected: (detected: boolean) => void = (_detected: boolean): void => {}

  private getEffectiveContentMaxWidth(): number {
    return this.contentMaxWidth > 0 ? this.contentMaxWidth : 99999
  }

  build() {
    Column() {
      Column() {
        Row() {
          ScreenshotBanner({
            attachments: $attachments,
            hasRecentPhoto: this.hasRecentScreenshot
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 4, bottom: 8 })

        ChatToolbar({
          webSearchAvailable: this.webSearchAvailable,
          webSearchEnabled: $webSearchEnabled,
          reasoningLevel: $reasoningLevel
        })

        ChatInputBar({
          inputText: $inputText,
          attachments: $attachments,
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
          .height(this.bottomAvoidHeight)
      }
      .width('100%')
      .constraintSize({ maxWidth: this.getEffectiveContentMaxWidth() })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16, top: 6 })
  }
}
