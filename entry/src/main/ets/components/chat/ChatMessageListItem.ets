import { ChatMessage, MessageAttachment, MessageRole } from '../../models/ChatModels'
import { DateDivider } from '../DateDivider'
import { MessageBubble } from '../MessageBubble'
import { ChatMessageRowData } from './ChatMessageListDataSource'

export const CHAT_MESSAGE_LIST_ITEM_REUSE_ID: string = 'chat_message_list_item'

@ReusableV2
@ComponentV2
export struct ChatMessageListItem {
  @Param row: ChatMessageRowData = new ChatMessageRowData(
    new ChatMessage('', MessageRole.USER, ''),
    false,
    false,
    false,
    false,
    false,
    ''
  )
  @Param currentModelId: string = ''
  @Param chatFontSize: number = 15
  @Param themeRenderKey: string = ''
  @Param contentMaxWidth: number = 99999
  @Param isMultiSelectMode: boolean = false
  @Param previewContent: string = ''
  @Param previewAttachments: MessageAttachment[] = []
  @Event onRegenerate: () => void = () => {}
  @Event onDelete: () => void = () => {}
  @Event onEdit: () => void = () => {}
  @Event onCancelEdit: () => void = () => {}
  @Event onShareMessage: () => void = () => {}
  @Event onTranslate: (content: string, targetLang: string,
    callback: (result: string, errorMessage: string) => void) => void =
    (_content: string, _targetLang: string, _callback: (result: string, errorMessage: string) => void): void => {}
  @Event onImageClick: (images: Array<string>, imageIndex: number) => void =
    (_images: Array<string>, _imageIndex: number): void => {}
  @Event onTTS: (messageId: string, content: string) => void = (_messageId: string, _content: string): void => {}
  @Event onTTSStop: () => void = (): void => {}
  @Event onSelect: (messageId: string) => void = (_messageId: string): void => {}
  @Event onEnterMultiSelect: (messageId: string) => void = (_messageId: string): void => {}

  private getEffectiveContentMaxWidth(): number {
    return this.contentMaxWidth > 0 ? this.contentMaxWidth : 99999
  }

  build() {
    Row() {
      Column() {
        if (this.row.showDateDivider) {
          DateDivider({ timestamp: this.row.message.timestamp })
        }

        MessageBubble({
          message: this.row.message,
          showHeader: this.row.showHeader,
          currentModelId: this.currentModelId,
          chatFontSize: this.chatFontSize,
          themeRenderKey: this.themeRenderKey,
          isMultiSelectMode: this.isMultiSelectMode,
          isSelected: this.row.isSelected,
          isEditing: this.row.isEditing,
          previewContent: this.row.isEditing ? this.previewContent : '',
          previewAttachments: this.row.isEditing ? this.previewAttachments : [],
          onRegenerate: () => {
            this.onRegenerate()
          },
          onDelete: () => {
            this.onDelete()
          },
          onEdit: () => {
            this.onEdit()
          },
          onCancelEdit: () => {
            this.onCancelEdit()
          },
          onShareMessage: () => {
            this.onShareMessage()
          },
          onTranslate: (content: string, targetLang: string,
            callback: (result: string, errorMessage: string) => void): void => {
            this.onTranslate(content, targetLang, callback)
          },
          onImageClick: (images: Array<string>, imageIndex: number): void => {
            this.onImageClick(images, imageIndex)
          },
          onTTS: (messageId: string, content: string): void => {
            this.onTTS(messageId, content)
          },
          onTTSStop: (): void => {
            this.onTTSStop()
          },
          onSelect: (messageId: string): void => {
            this.onSelect(messageId)
          },
          onEnterMultiSelect: (messageId: string): void => {
            this.onEnterMultiSelect(messageId)
          }
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: this.getEffectiveContentMaxWidth() })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 14, right: 14, top: 5, bottom: 5 })
    .opacity(this.row.isDimmed ? 0.4 : 1)
  }
}
