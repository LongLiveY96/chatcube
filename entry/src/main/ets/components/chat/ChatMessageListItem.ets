import { ChatMessage, MessageAttachment, MessageRole } from '../../models/ChatModels'
import { DateDivider } from '../DateDivider'
import { MessageBubble } from '../MessageBubble'

export const CHAT_MESSAGE_LIST_ITEM_REUSE_ID: string = 'chat_message_list_item'

@ComponentV2
export struct ChatMessageListItem {
  @Param message: ChatMessage = new ChatMessage('', MessageRole.USER, '')
  @Param showDateDivider: boolean = false
  @Param showHeader: boolean = false
  @Param isSelected: boolean = false
  @Param isEditing: boolean = false
  @Param selectableTextMessageId: string = ''
  @Param isDimmed: boolean = false
  @Param renderSignature: string = ''
  @Param contentRenderSignature: string = ''
  @Param currentModelId: string = ''
  @Param assistantAvatarSymbol: string = 'AI'
  @Param assistantAvatarColor: string = '#0A59F7'
  @Param assistantAvatarCacheKey: number = 0
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
  @Event onOpenLink: (title: string, url: string) => void = (_title: string, _url: string): void => {}
  @Event onTTS: (messageId: string, content: string) => void = (_messageId: string, _content: string): void => {}
  @Event onTTSStop: () => void = (): void => {}
  @Event onSelect: (messageId: string) => void = (_messageId: string): void => {}
  @Event onEnterMultiSelect: (messageId: string) => void = (_messageId: string): void => {}
  @Event onSetSelectableTextMessageId: (messageId: string) => void = (_messageId: string): void => {}

  private getEffectiveContentMaxWidth(): number {
    return this.contentMaxWidth > 0 ? this.contentMaxWidth : 99999
  }

  build() {
    Row() {
      Column() {
        if (this.showDateDivider) {
          DateDivider({ timestamp: this.message.timestamp })
        }

        MessageBubble({
          message: this.message,
          renderSignature: this.renderSignature,
          contentRenderSignature: this.contentRenderSignature,
          showHeader: this.showHeader,
          currentModelId: this.currentModelId,
          assistantAvatarSymbol: this.assistantAvatarSymbol,
          assistantAvatarColor: this.assistantAvatarColor,
          assistantAvatarCacheKey: this.assistantAvatarCacheKey,
          chatFontSize: this.chatFontSize,
          themeRenderKey: this.themeRenderKey,
          isMultiSelectMode: this.isMultiSelectMode,
          isSelected: this.isSelected,
          isEditing: this.isEditing,
          selectableTextMessageId: this.selectableTextMessageId,
          previewContent: this.isEditing ? this.previewContent : '',
          previewAttachments: this.isEditing ? this.previewAttachments : [],
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
          onOpenLink: (title: string, url: string): void => {
            this.onOpenLink(title, url)
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
          },
          onSetSelectableTextMessageId: (messageId: string): void => {
            this.onSetSelectableTextMessageId(messageId)
          }
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: this.getEffectiveContentMaxWidth() })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 14, right: 14, top: 5, bottom: 5 })
    .opacity(this.isDimmed ? 0.4 : 1)
  }
}
