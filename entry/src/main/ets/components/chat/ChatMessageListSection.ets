import { ChatMessage, MessageAttachment } from '../../models/ChatModels'
import { DraftPreviewBubble } from './DraftPreviewBubble'
import { shouldShowMessageHeader } from '../../utils/MessageListUtils'
import { ChatMessageListItem } from './ChatMessageListItem'
import {
  buildChatMessageContentRenderSignature,
  buildChatMessageRowRenderSignature,
  ChatMessageListDataSource,
  ChatMessageRowData
} from './ChatMessageListDataSource'

@ComponentV2
export struct ChatMessageListSection {
  @Param isLoading: boolean = false
  @Param loadingColor: string = '#4E6F9E'
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
  @Param assistantAvatarSymbol: string = 'AI'
  @Param assistantAvatarColor: string = '#4E6F9E'
  @Param assistantAvatarCacheKey: number = 0
  @Param chatFontSize: number = 15
  @Param themeRenderKey: string = ''
  @Param contentMaxWidth: number = 99999
  @Param syncVersion: number = 0
  @Param syncMessageId: string = ''
  @Event onRegenerate: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  @Event onDelete: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  @Event onEdit: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  @Event onCancelEdit: () => void = (): void => {}
  @Event onShareMessage: (message: ChatMessage) => void = (_message: ChatMessage): void => {}
  @Event onTranslate: (content: string, targetLang: string, callback: (result: string, errorMessage: string) => void) => void =
    (_content: string, _targetLang: string, _callback: (result: string, errorMessage: string) => void): void => {}
  @Event onImageClick: (images: Array<string>, imageIndex: number) => void = (_images: Array<string>, _imageIndex: number): void => {
  }
  @Event onOpenLink: (title: string, url: string) => void = (_title: string, _url: string): void => {}
  @Event onTTS: (messageId: string, content: string) => void = (_messageId: string, _content: string): void => {}
  @Event onTTSStop: () => void = (): void => {}
  @Event onSelect: (messageId: string) => void = (_messageId: string): void => {}
  @Event onEnterMultiSelect: (messageId: string) => void = (_messageId: string): void => {}
  @Event onAskUserAnswer: (toolCallId: string, answerJson: string) => void =
    (_toolCallId: string, _answerJson: string): void => {}
  @Event onListAppear: () => void = (): void => {}
  @Event onReachStart: () => void = (): void => {}
  @Event onReachEnd: () => void = (): void => {}
  @Event onContentAreaChange: () => void = (): void => {}
  @Event onDidScroll: (scrollOffset: number, scrollState: ScrollState) => void = (_scrollOffset: number,
    _scrollState: ScrollState): void => {}
  @Event onScrollIndex: (firstIndex: number, lastIndex: number) => void = (_firstIndex: number,
    _lastIndex: number): void => {}
  private messageRows: ChatMessageRowData[] = []
  private messageRowDataSource: ChatMessageListDataSource = new ChatMessageListDataSource()

  aboutToAppear(): void {
    this.syncMessageRows(true)
  }

  @Monitor('syncVersion')
  onSyncVersionChange(): void {
    this.syncMessageRows(false, this.syncMessageId)
  }

  @Monitor('selectedMessageIds')
  onSelectedMessageIdsChange(): void {
    this.syncMessageRows()
  }

  @Monitor('isMultiSelectMode')
  onMultiSelectModeChange(): void {
    this.syncMessageRows()
  }

  @Monitor('isEditingMessage')
  onIsEditingMessageChange(): void {
    this.syncMessageRows()
  }

  @Monitor('inputText')
  onInputTextChange(): void {
    if (!this.isEditingMessage) {
      return
    }
    // 编辑态下 inputText 只影响"正在编辑那条"的 previewContent 签名,
    // 走 syncSingleMessageRow 避免对全列表逐条重算 contentRenderSignature。
    // 失败 fallback 到全量,保证 messageRows 长度与 messages 不一致时仍能纠正。
    if (!this.syncSingleMessageRow(this.editingMessageId)) {
      this.syncMessageRows()
    }
  }

  @Monitor('pendingAttachments')
  onPendingAttachmentsChange(): void {
    if (!this.isEditingMessage) {
      return
    }
    if (!this.syncSingleMessageRow(this.editingMessageId)) {
      this.syncMessageRows()
    }
  }

  @Monitor('editingMessageId')
  onEditingMessageIdChange(): void {
    this.syncMessageRows()
  }

  @Monitor('currentModelId')
  onCurrentModelIdChange(): void {
    this.syncMessageRows()
  }

  @Monitor('assistantAvatarSymbol')
  onAssistantAvatarSymbolChange(): void {
    this.syncMessageRows()
  }

  @Monitor('assistantAvatarColor')
  onAssistantAvatarColorChange(): void {
    this.syncMessageRows()
  }

  @Monitor('assistantAvatarCacheKey')
  onAssistantAvatarCacheKeyChange(): void {
    this.syncMessageRows()
  }

  @Monitor('chatFontSize')
  onChatFontSizeChange(): void {
    this.syncMessageRows()
  }

  @Monitor('themeRenderKey')
  onThemeRenderKeyChange(): void {
    this.syncMessageRows()
  }

  private checkShouldShowMessageHeader(message: ChatMessage, index: number): boolean {
    return shouldShowMessageHeader(message, index, (i: number) => this.messages[i])
  }

  private isValidMessageTimestamp(message: ChatMessage | null | undefined): boolean {
    if (message === undefined || message === null) {
      return false
    }
    return typeof message.timestamp === 'number' && !Number.isNaN(message.timestamp)
  }

  private checkShouldShowDateDivider(message: ChatMessage, index: number): boolean {
    if (index === 0 || !this.isValidMessageTimestamp(message)) {
      return true
    }
    const prevMessage = this.messages[index - 1]
    if (!this.isValidMessageTimestamp(prevMessage)) {
      return true
    }
    const currentDate = new Date(message.timestamp)
    const prevDate = new Date(prevMessage.timestamp)
    return currentDate.getFullYear() !== prevDate.getFullYear() ||
      currentDate.getMonth() !== prevDate.getMonth() ||
      currentDate.getDate() !== prevDate.getDate()
  }

  private getEffectiveContentMaxWidth(): number {
    return this.contentMaxWidth > 0 ? this.contentMaxWidth : 99999
  }

  private getListCachedCount(): number {
    if (this.messages.length >= 100) {
      return 2
    }
    if (this.messages.length >= 30) {
      return 3
    }
    return 4
  }

  // 取消 @ReusableV2 复用: LazyForEach + 手动 DataSource 下精确订阅会失效, 复用瞬间 @Param 不刷新会
  // 导致 AI 消息内容串到错位气泡上。靠 LazyForEach cachedCount 管理"延迟构造", 不再启用组件级复用。
  // 长会话快速 fling 时 MessageBubble 会重新构造 (MarkdownController x3 + configureMarkdownStyles),
  // 视为可接受代价, 后续单独做 Repeat 替代 PoC。

  private updateMessageRowData(
    row: ChatMessageRowData,
    message: ChatMessage,
    showDateDivider: boolean,
    showHeader: boolean,
    isSelected: boolean,
    isEditing: boolean,
    isDimmed: boolean,
    renderSignature: string,
    contentRenderSignature: string,
    assistantAvatarSymbol: string,
    assistantAvatarColor: string,
    assistantAvatarCacheKey: number
  ): void {
    row.message = message
    row.showDateDivider = showDateDivider
    row.showHeader = showHeader
    row.isSelected = isSelected
    row.isEditing = isEditing
    row.isDimmed = isDimmed
    row.renderSignature = renderSignature
    row.contentRenderSignature = contentRenderSignature
    row.assistantAvatarSymbol = assistantAvatarSymbol
    row.assistantAvatarColor = assistantAvatarColor
    row.assistantAvatarCacheKey = assistantAvatarCacheKey
  }

  private syncSingleMessageRow(changedMessageId: string): boolean {
    if (changedMessageId === '' || this.messageRows.length !== this.messages.length) {
      return false
    }
    let changedIndex = -1
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].id === changedMessageId) {
        changedIndex = i
        break
      }
    }
    if (changedIndex < 0) {
      return false
    }
    const existingRow = this.messageRows[changedIndex]
    const message = this.messages[changedIndex]
    if (existingRow === undefined || existingRow.stableId !== message.id) {
      return false
    }
    const isSelected = this.selectedMessageIds.includes(message.id)
    const isEditing = this.isEditingMessage && this.editingMessageId === message.id
    const isDimmed = this.isEditingMessage && !isEditing
    const showDateDivider = this.checkShouldShowDateDivider(message, changedIndex)
    const showHeader = this.checkShouldShowMessageHeader(message, changedIndex)
    const contentRenderSignature = buildChatMessageContentRenderSignature(
      message,
      isEditing,
      this.currentModelId,
      this.chatFontSize,
      this.themeRenderKey,
      this.inputText,
      this.pendingAttachments
    )
    const renderSignature = buildChatMessageRowRenderSignature(
      message,
      showDateDivider,
      showHeader,
      this.isMultiSelectMode,
      isSelected,
      isEditing,
      isDimmed,
      this.currentModelId,
      this.chatFontSize,
      this.themeRenderKey,
      this.inputText,
      this.pendingAttachments,
      this.assistantAvatarSymbol,
      this.assistantAvatarColor,
      this.assistantAvatarCacheKey,
      contentRenderSignature
    )
    const rowChanged = existingRow.renderSignature !== renderSignature ||
      existingRow.contentRenderSignature !== contentRenderSignature
    this.updateMessageRowData(
      existingRow,
      message,
      showDateDivider,
      showHeader,
      isSelected,
      isEditing,
      isDimmed,
      renderSignature,
      contentRenderSignature,
      this.assistantAvatarSymbol,
      this.assistantAvatarColor,
      this.assistantAvatarCacheKey
    )
    if (rowChanged) {
      this.messageRowDataSource.setItems(this.messageRows, false, [changedIndex])
    }
    return true
  }

  private syncMessageRows(forceReload: boolean = false, changedMessageId: string = ''): void {
    if (!forceReload && this.syncSingleMessageRow(changedMessageId)) {
      return
    }
    const selectedMessageIdSet = new Set<string>(this.selectedMessageIds)
    const existingRowMap = new Map<string, ChatMessageRowData>()
    for (let i = 0; i < this.messageRows.length; i++) {
      existingRowMap.set(this.messageRows[i].stableId, this.messageRows[i])
    }
    const nextRows: ChatMessageRowData[] = []
    const changedIndexes: number[] = []
    for (let i = 0; i < this.messages.length; i++) {
      const message = this.messages[i]
      const isSelected = selectedMessageIdSet.has(message.id)
      const isEditing = this.isEditingMessage && this.editingMessageId === message.id
      const isDimmed = this.isEditingMessage && !isEditing
      const showDateDivider = this.checkShouldShowDateDivider(message, i)
      const showHeader = this.checkShouldShowMessageHeader(message, i)
      const contentRenderSignature = buildChatMessageContentRenderSignature(
        message,
        isEditing,
        this.currentModelId,
        this.chatFontSize,
        this.themeRenderKey,
        this.inputText,
        this.pendingAttachments
      )
      const renderSignature = buildChatMessageRowRenderSignature(
        message,
        showDateDivider,
        showHeader,
        this.isMultiSelectMode,
        isSelected,
        isEditing,
        isDimmed,
        this.currentModelId,
        this.chatFontSize,
        this.themeRenderKey,
        this.inputText,
        this.pendingAttachments,
        this.assistantAvatarSymbol,
        this.assistantAvatarColor,
        this.assistantAvatarCacheKey,
        contentRenderSignature
      )
      const existingRow = existingRowMap.get(message.id)
      if (existingRow !== undefined) {
        const rowChanged = existingRow.renderSignature !== renderSignature ||
          existingRow.contentRenderSignature !== contentRenderSignature
        if (rowChanged) {
          changedIndexes.push(i)
        }
        this.updateMessageRowData(
          existingRow,
          message,
          showDateDivider,
          showHeader,
          isSelected,
          isEditing,
          isDimmed,
          renderSignature,
          contentRenderSignature,
          this.assistantAvatarSymbol,
          this.assistantAvatarColor,
          this.assistantAvatarCacheKey
        )
        nextRows.push(existingRow)
        continue
      }
      nextRows.push(new ChatMessageRowData(
        message,
        showDateDivider,
        showHeader,
        isSelected,
        isEditing,
        isDimmed,
        renderSignature,
        contentRenderSignature,
        this.assistantAvatarSymbol,
        this.assistantAvatarColor,
        this.assistantAvatarCacheKey
      ))
    }
    this.messageRows = nextRows
    this.messageRowDataSource.setItems(nextRows, forceReload, changedIndexes)
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
              Column().height(this.topInsetHeight)
            }
          }

          LazyForEach(this.messageRowDataSource, (item: ChatMessageRowData, _index: number) => {
            ListItem({ style: ListItemStyle.NONE }) {
              ChatMessageListItem({
                message: item.message,
                showDateDivider: item.showDateDivider,
                showHeader: item.showHeader,
                isSelected: item.isSelected,
                isEditing: item.isEditing,
                isDimmed: item.isDimmed,
                renderSignature: item.renderSignature,
                contentRenderSignature: item.contentRenderSignature,
                currentModelId: this.currentModelId,
                assistantAvatarSymbol: item.assistantAvatarSymbol,
                assistantAvatarColor: item.assistantAvatarColor,
                assistantAvatarCacheKey: item.assistantAvatarCacheKey,
                chatFontSize: this.chatFontSize,
                themeRenderKey: this.themeRenderKey,
                contentMaxWidth: this.getEffectiveContentMaxWidth(),
                isMultiSelectMode: this.isMultiSelectMode,
                previewContent: this.inputText,
                previewAttachments: this.pendingAttachments,
                onRegenerate: () => {
                  this.onRegenerate(item.message)
                },
                onDelete: () => {
                  this.onDelete(item.message)
                },
                onEdit: () => {
                  this.onEdit(item.message)
                },
                onCancelEdit: () => {
                  this.onCancelEdit()
                },
                onShareMessage: () => {
                  this.onShareMessage(item.message)
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
                onAskUserAnswer: (toolCallId: string, answerJson: string): void => {
                  this.onAskUserAnswer(toolCallId, answerJson)
                }
              })
                .width('100%')
            }
          }, (item: ChatMessageRowData): string => item.key)

          if (!this.isEditingMessage && this.showDraftPreview) {
            ListItem({ style: ListItemStyle.NONE }) {
              Row() {
                Column() {
                  DraftPreviewBubble({
                    inputText: this.inputText,
                    pendingAttachments: this.pendingAttachments,
                    previewTimeText: this.draftPreviewTimeText,
                    chatFontSize: this.chatFontSize
                  })
                }
                .width('100%')
                .constraintSize({ maxWidth: this.getEffectiveContentMaxWidth() })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
            .padding({ left: 14, right: 14, top: 5, bottom: 5 })
            .onAreaChange((_oldArea: Area, _newArea: Area) => {
              this.onContentAreaChange()
            })
          }

          ListItem({ style: ListItemStyle.NONE }) {
            Column().height(this.bottomPadding)
          }
          .onAreaChange((_oldArea: Area, _newArea: Area) => {
            this.onContentAreaChange()
          })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(this.getListCachedCount())
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
        .onScrollIndex((firstIndex: number, lastIndex: number) => {
          this.onScrollIndex(firstIndex, lastIndex)
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
