import { ChatMessage, MessageAttachment } from '../../models/ChatModels'
import { MessageBubble } from '../MessageBubble'
import { DateDivider } from '../DateDivider'
import { DraftPreviewBubble } from './DraftPreviewBubble'
import { MessageDataSource } from '../../datasource/MessageDataSource'
import { shouldShowMessageHeader } from '../../utils/MessageListUtils'

@Component
export struct ChatMessageListSection {
  @Prop isLoading: boolean = false
  @Prop loadingColor: ResourceColor = '#0A59F7'
  scroller: Scroller = new Scroller()
  messageDataSource: MessageDataSource = new MessageDataSource()
  @Prop topAvoidHeight: number = 0
  @Prop isEditingMessage: boolean = false
  @Prop editingMessageId: string = ''
  @Prop selectedMessageIds: Array<string> = []
  @Prop isMultiSelectMode: boolean = false
  @Prop inputText: string = ''
  @Prop pendingAttachments: MessageAttachment[] = []
  @Prop showDraftPreview: boolean = false
  @Prop draftPreviewTimeText: string = ''
  @Prop bottomPadding: number = 0
  @Prop currentModelId: string = ''
  onRegenerate: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  onDelete: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  onEdit: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  onCancelEdit: () => void = (): void => {}
  onShareMessage: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  onTranslate: (content: string, targetLang: string, callback: (result: string, errorMessage: string) => void) => void =
    (_content: string, _targetLang: string, _callback: (result: string, errorMessage: string) => void): void => {}
  onImageClick: (images: Array<string>, imageIndex: number) => void = (_images: Array<string>, _imageIndex: number): void => {
  }
  onTTS: (messageId: string, content: string) => void = (_messageId: string, _content: string): void => {}
  onTTSStop: () => void = (): void => {}
  onSelect: (messageId: string) => void = (_messageId: string): void => {}
  onEnterMultiSelect: (messageId: string) => void = (_messageId: string): void => {}
  onListAppear: () => void = (): void => {}
  onReachStart: () => void = (): void => {}
  onReachEnd: () => void = (): void => {}
  onDidScroll: (scrollOffset: number, scrollState: ScrollState) => void = (_scrollOffset: number,
    _scrollState: ScrollState): void => {}

  private checkShouldShowMessageHeader(message: ChatMessage, index: number): boolean {
    return shouldShowMessageHeader(message, index, (i: number) => this.messageDataSource.getData(i))
  }

  private checkShouldShowDateDivider(message: ChatMessage, index: number): boolean {
    if (index === 0) {
      return true
    }
    const prevMessage = this.messageDataSource.getData(index - 1)
    const currentDate = new Date(message.timestamp)
    const prevDate = new Date(prevMessage.timestamp)
    return currentDate.getFullYear() !== prevDate.getFullYear() ||
      currentDate.getMonth() !== prevDate.getMonth() ||
      currentDate.getDate() !== prevDate.getDate()
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(this.loadingColor)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.scroller }) {
          ListItem() {
            Column() {
              Column().height(this.topAvoidHeight + 68)
            }
          }

          LazyForEach(this.messageDataSource, (message: ChatMessage, index: number) => {
            ListItem() {
              Column() {
                if (this.checkShouldShowDateDivider(message, index)) {
                  DateDivider({ timestamp: message.timestamp })
                }

                MessageBubble({
                  message: message,
                  showHeader: this.checkShouldShowMessageHeader(message, index),
                  currentModelId: this.currentModelId,
                  isMultiSelectMode: this.isMultiSelectMode,
                  isSelected: this.selectedMessageIds.includes(message.id),
                  isEditing: this.isEditingMessage && this.editingMessageId === message.id,
                  previewContent: (this.isEditingMessage && this.editingMessageId === message.id) ? this.inputText : '',
                  previewAttachments: (this.isEditingMessage && this.editingMessageId === message.id) ?
                    this.pendingAttachments : [],
                  onRegenerate: () => {
                    this.onRegenerate(message)
                  },
                  onDelete: () => {
                    this.onDelete(message)
                  },
                  onEdit: () => {
                    this.onEdit(message)
                  },
                  onCancelEdit: () => {
                    this.onCancelEdit()
                  },
                  onShareMessage: () => {
                    this.onShareMessage(message)
                  },
                  onTranslate: (content: string, targetLang: string,
                    callback: (result: string, errorMessage: string) => void) => {
                    this.onTranslate(content, targetLang, callback)
                  },
                  onImageClick: (images: Array<string>, imageIndex: number) => {
                    this.onImageClick(images, imageIndex)
                  },
                  onTTS: (messageId: string, content: string) => {
                    this.onTTS(messageId, content)
                  },
                  onTTSStop: () => {
                    this.onTTSStop()
                  },
                  onSelect: (messageId: string) => {
                    this.onSelect(messageId)
                  },
                  onEnterMultiSelect: (messageId: string) => {
                    this.onEnterMultiSelect(messageId)
                  }
                })
              }
              .width('100%')
            }
            .padding({ left: 14, right: 14, top: 5, bottom: 5 })
            .opacity(this.isEditingMessage && this.editingMessageId !== message.id ? 0.4 : 1)
            .animation({ duration: 200 })
          }, (message: ChatMessage) => message.id)

          if (!this.isEditingMessage && this.showDraftPreview) {
            ListItem() {
              DraftPreviewBubble({
                inputText: this.inputText,
                pendingAttachments: this.pendingAttachments,
                previewTimeText: this.draftPreviewTimeText
              })
            }
            .padding({ left: 14, right: 14, top: 5, bottom: 5 })
          }

          ListItem() {
            Column().height(this.bottomPadding)
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backdropBlur(this.isEditingMessage ? 8 : 0)
        .animation({ duration: 200 })
        .onAppear(() => {
          this.onListAppear()
        })
        .onReachStart(() => {
          this.onReachStart()
        })
        .onReachEnd(() => {
          this.onReachEnd()
        })
        .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
          this.onDidScroll(scrollOffset, scrollState)
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
