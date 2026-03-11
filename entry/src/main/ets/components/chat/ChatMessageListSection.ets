import { ChatMessage, MessageAttachment } from '../../models/ChatModels'
import { MessageBubble } from '../MessageBubble'
import { DateDivider } from '../DateDivider'
import { DraftPreviewBubble } from './DraftPreviewBubble'
import { CHAT_NAVIGATION_BAR_DEFAULT_HEIGHT } from '../../config/ChatLayout'
import { shouldShowMessageHeader } from '../../utils/MessageListUtils'

@ComponentV2
export struct ChatMessageListSection {
  @Param isLoading: boolean = false
  @Param loadingColor: ResourceColor = '#0A59F7'
  @Param scroller: Scroller = new Scroller()
  @Param messages: ChatMessage[] = []
  @Param isEditingMessage: boolean = false
  @Param editingMessageId: string = ''
  @Param selectedMessageIds: Array<string> = []
  @Param isMultiSelectMode: boolean = false
  @Param inputText: string = ''
  @Param pendingAttachments: MessageAttachment[] = []
  @Param showDraftPreview: boolean = false
  @Param draftPreviewTimeText: string = ''
  @Param bottomPadding: number = 0
  @Param topInsetHeight: number = 0
  @Param currentModelId: string = ''
  @Param contentMaxWidth: number = 99999
  @Event onRegenerate: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  @Event onDelete: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  @Event onEdit: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  @Event onCancelEdit: () => void = (): void => {}
  @Event onShareMessage: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  @Event onTranslate: (content: string, targetLang: string, callback: (result: string, errorMessage: string) => void) => void =
    (_content: string, _targetLang: string, _callback: (result: string, errorMessage: string) => void): void => {}
  @Event onImageClick: (images: Array<string>, imageIndex: number) => void = (_images: Array<string>, _imageIndex: number): void => {
  }
  @Event onTTS: (messageId: string, content: string) => void = (_messageId: string, _content: string): void => {}
  @Event onTTSStop: () => void = (): void => {}
  @Event onSelect: (messageId: string) => void = (_messageId: string): void => {}
  @Event onEnterMultiSelect: (messageId: string) => void = (_messageId: string): void => {}
  @Event onListAppear: () => void = (): void => {}
  @Event onReachStart: () => void = (): void => {}
  @Event onReachEnd: () => void = (): void => {}
  @Event onDidScroll: (scrollOffset: number, scrollState: ScrollState) => void = (_scrollOffset: number,
    _scrollState: ScrollState): void => {}

  private checkShouldShowMessageHeader(message: ChatMessage, index: number): boolean {
    return shouldShowMessageHeader(message, index, (i: number) => this.messages[i])
  }

  private checkShouldShowDateDivider(message: ChatMessage, index: number): boolean {
    if (index === 0) {
      return true
    }
    const prevMessage = this.messages[index - 1]
    const currentDate = new Date(message.timestamp)
    const prevDate = new Date(prevMessage.timestamp)
    return currentDate.getFullYear() !== prevDate.getFullYear() ||
      currentDate.getMonth() !== prevDate.getMonth() ||
      currentDate.getDate() !== prevDate.getDate()
  }

  private getEffectiveContentMaxWidth(): number {
    return this.contentMaxWidth > 0 ? this.contentMaxWidth : 99999
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
              Column().height(CHAT_NAVIGATION_BAR_DEFAULT_HEIGHT + this.topInsetHeight)
            }
          }

          Repeat<ChatMessage>(this.messages)
            .each((ri: RepeatItem<ChatMessage>) => {
              ListItem() {
                Row() {
                  Column() {
                    if (this.checkShouldShowDateDivider(ri.item, ri.index)) {
                      DateDivider({ timestamp: ri.item.timestamp })
                    }

                    MessageBubble({
                      message: ri.item,
                      showHeader: this.checkShouldShowMessageHeader(ri.item, ri.index),
                      currentModelId: this.currentModelId,
                      isMultiSelectMode: this.isMultiSelectMode,
                      isSelected: this.selectedMessageIds.includes(ri.item.id),
                      isEditing: this.isEditingMessage && this.editingMessageId === ri.item.id,
                      previewContent: (this.isEditingMessage && this.editingMessageId === ri.item.id) ? this.inputText : '',
                      previewAttachments: (this.isEditingMessage && this.editingMessageId === ri.item.id) ?
                        this.pendingAttachments : [],
                      onRegenerate: () => {
                        this.onRegenerate(ri.item)
                      },
                      onDelete: () => {
                        this.onDelete(ri.item)
                      },
                      onEdit: () => {
                        this.onEdit(ri.item)
                      },
                      onCancelEdit: () => {
                        this.onCancelEdit()
                      },
                      onShareMessage: () => {
                        this.onShareMessage(ri.item)
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
                  .constraintSize({ maxWidth: this.getEffectiveContentMaxWidth() })
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
              }
              .padding({ left: 14, right: 14, top: 5, bottom: 5 })
              .opacity(this.isEditingMessage && this.editingMessageId !== ri.item.id ? 0.4 : 1)
              .animation({ duration: 200 })
            })
            .key((message: ChatMessage) => message.id)
            .virtualScroll({ totalCount: this.messages.length })

          if (!this.isEditingMessage && this.showDraftPreview) {
            ListItem() {
              Row() {
                Column() {
                  DraftPreviewBubble({
                    inputText: this.inputText,
                    pendingAttachments: this.pendingAttachments,
                    previewTimeText: this.draftPreviewTimeText
                  })
                }
                .width('100%')
                .constraintSize({ maxWidth: this.getEffectiveContentMaxWidth() })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
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
        .cachedCount(5)
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
