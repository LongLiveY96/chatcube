import { ChatMessage, MessageRole, MessageAttachment, AttachmentType, ToolCall, ToolResult } from '../models/ChatModels'
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in'
import { pasteboard } from '@kit.BasicServicesKit'
import { showToast } from '../utils/ToastUtil'
import { getModelIconPath, buildIconResourcePath } from '../utils/ProviderIconUtils'
import { shouldShowAssistantMessageToolbar } from '../utils/MessageBubbleDisplayUtils'
import { SearchReferenceCard } from './SearchReferenceCard'
import { ToolCallCard } from './ToolCallCard'
import { HtmlPreviewCard } from './HtmlPreviewCard'
import { TypingDots } from './TypingDots'
import { SelectableMarkdownContent, getSelectableMarkdownPlainText } from './SelectableMarkdownContent'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'
import {
  getMarkdownBlockSpacing,
  getMarkdownQuotePadding,
  getMarkdownTextLineHeight,
  getMarkdownTitleLineHeights,
  getMarkdownTitleSizes
} from '../utils/MarkdownTypographyUtils'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

const DOMAIN = 0x0002
const TAG = 'MessageBubble'

// 翻译目标语言配置
interface TranslateLanguage {
  code: string
  name: string
  nativeName: string
}

// 内容分段（用于 HTML 代码块内联预览）
interface ContentSegment {
  isHtml: boolean
  renderContent: string
}

interface ImageAttachmentEntry {
  attachment: MessageAttachment
  originalIndex: number
}

@ComponentV2
export struct MessageBubble {
  @Param message: ChatMessage = new ChatMessage('', MessageRole.USER, '')
  @Param renderSignature: string = ''
  @Param contentRenderSignature: string = ''
  @Param showHeader: boolean = true  // 是否显示消息头部（模型信息）
  @Param currentModelId: string = ''  // 当前会话的模型 ID（用于图标匹配回退）
  @Param themeRenderKey: string = ''
  @Param isMultiSelectMode: boolean = false  // 是否处于多选模式
  @Param isSelected: boolean = false  // 是否被选中
  @Param isEditing: boolean = false  // 是否处于编辑状态（被编辑的消息高亮显示）
  @Param selectableTextMessageId: string = ''
  @Param previewContent: string = ''  // 编辑时的实时预览内容
  @Param previewAttachments: MessageAttachment[] = []  // 编辑时的实时预览附件
  @Local isReasoningExpanded: boolean = false  // 推理内容是否展开
  @Local translatedText: string = ''  // 翻译结果
  @Local isTranslating: boolean = false  // 是否正在翻译
  @Local showTranslation: boolean = false  // 是否显示翻译结果
  @Local isTranslationExpanded: boolean = true  // 翻译结果是否展开
  @Local currentTranslateLang: string = ''  // 当前翻译的目标语言
  // 深色模式状态（用于主题适配）
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  // 主题颜色（从 ThemeService 同步）
  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }
  private get themeUserBubbleText(): string {
    return getAppUiState().themeUserBubbleText
  }
  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }

  // 聊天字体大小
  @Param chatFontSize: number = 15

  // ========== Markdown 配置 ==========
  // MarkdownController 实例
  private markdownController: MarkdownController = new MarkdownController()
  private reasoningMarkdownController: MarkdownController = new MarkdownController()
  private translationMarkdownController: MarkdownController = new MarkdownController()
  private multiSelectTouchStartX: number = 0
  private multiSelectTouchStartY: number = 0
  private multiSelectTouchActive: boolean = false
  private static readonly MULTI_SELECT_TAP_THRESHOLD_VP: number = 8

  // ========== 流式渲染优化 ==========
  // lv-markdown-in 自带流式渲染，无需手动节流
  private boundMessageId: string = ''
  private translationRequestToken: number = 0
  private get speakingMessageId(): string {
    return getAppUiState().speakingMessageId
  }
  private get isSelectableTextMode(): boolean {
    return this.selectableTextMessageId === this.message.id
  }
  // 聊天图片紧凑展示参数
  private compactImageMaxHeight: number = 100
  private compactImageContainerWidth: number = 180
  private compactImageGap: number = 6
  private cachedDisplayContent: string = ''
  private cachedHasDisplayAttachments: boolean = false
  private cachedHasPreviewTextContent: boolean = false
  private cachedHasMessageTextContent: boolean = false
  private cachedHasToolbarPayload: boolean = false
  private cachedCurrentMessageModelIconResourcePath: string = ''
  private cachedReadonlyMessageContent: string = ''
  private cachedReadonlyReasoningContent: string = ''
  private cachedReadonlyTranslatedText: string = ''
  private cachedHasHtmlSegments: boolean = false
  private cachedContentSegments: ContentSegment[] = []
  private cachedPreviewImageEntries: ImageAttachmentEntry[] = []
  private cachedMessageImageEntries: ImageAttachmentEntry[] = []
  private cachedMessageFileAttachments: MessageAttachment[] = []
  private cachedPreviewImageGridRows: number[] = []
  private cachedMessageImageGridRows: number[] = []
  private derivedCacheSignature: string = ''

  @Event onRegenerate: () => void = () => {}
  @Event onCopy: () => void = () => {}
  @Event onDelete: () => void = () => {}
  @Event onEdit: () => void = () => {}
  @Event onCancelEdit: () => void = () => {}  // 取消编辑回调
  @Event onShareMessage: () => void = () => {}
  @Event onTranslate: (content: string, targetLang: string, callback: (result: string, errorMessage: string) => void) => void = () => {}
  // 图片点击预览回调
  @Event onImageClick: (images: Array<string>, index: number) => void = () => {}
  @Event onOpenLink: (title: string, url: string) => void = () => {}
  // TTS朗读回调
  @Event onTTS: (messageId: string, content: string) => void = () => {}
  @Event onTTSStop: () => void = () => {}
  // 多选模式回调
  @Event onSelect: (messageId: string) => void = () => {}
  @Event onEnterMultiSelect: (messageId: string) => void = () => {}
  @Event onSetSelectableTextMessageId: (messageId: string) => void = (_messageId: string): void => {}

  // 支持的翻译语言列表
  private translateLanguages: TranslateLanguage[] = [
    { code: 'zh-CN', name: 'Chinese', nativeName: '简体中文' },
    { code: 'en', name: 'English', nativeName: 'English' },
    { code: 'zh-TW', name: 'Traditional Chinese', nativeName: '繁體中文' },
    { code: 'ja', name: 'Japanese', nativeName: '日本語' },
    { code: 'ko', name: 'Korean', nativeName: '한국어' },
    { code: 'fr', name: 'French', nativeName: 'Français' },
    { code: 'de', name: 'German', nativeName: 'Deutsch' },
    { code: 'it', name: 'Italian', nativeName: 'Italiano' },
    { code: 'es', name: 'Spanish', nativeName: 'Español' }
  ]

  // 获取当前消息模型图标文件名（空字符串表示无可用图标）
  private getCurrentMessageModelIconPath(): string {
    // 优先用 modelId → 回退到当前会话模型 ID → 最后回退到 modelName
    let id = this.message.modelId
    if (id === '' || id === undefined) {
      id = this.currentModelId
    }
    if (id === '' || id === undefined) {
      id = this.message.modelName
    }
    if (id === '' || id === undefined) {
      return ''
    }
    return getModelIconPath(id, '', '')
  }

  // 获取当前消息模型图标资源路径（空字符串表示无可用图标）
  private computeCurrentMessageModelIconResourcePath(): string {
    const iconPath = this.getCurrentMessageModelIconPath()
    if (iconPath === '') {
      return ''
    }
    return buildIconResourcePath(iconPath)
  }

  private getPrimaryTouchPoint(event: TouchEvent): TouchObject | null {
    if (event.changedTouches && event.changedTouches.length > 0) {
      return event.changedTouches[0]
    }
    if (event.touches && event.touches.length > 0) {
      return event.touches[0]
    }
    return null
  }

  private resetMultiSelectTouchState(): void {
    this.multiSelectTouchActive = false
    this.multiSelectTouchStartX = 0
    this.multiSelectTouchStartY = 0
  }

  private handleMultiSelectTouch(event: TouchEvent): void {
    if (!this.isMultiSelectMode) {
      return
    }
    const touchPoint = this.getPrimaryTouchPoint(event)
    switch (event.type) {
      case TouchType.Down:
        if (touchPoint === null) {
          this.resetMultiSelectTouchState()
          return
        }
        this.multiSelectTouchStartX = touchPoint.x
        this.multiSelectTouchStartY = touchPoint.y
        this.multiSelectTouchActive = true
        break
      case TouchType.Move:
        if (!this.multiSelectTouchActive || touchPoint === null) {
          return
        }
        if (Math.abs(touchPoint.x - this.multiSelectTouchStartX) > MessageBubble.MULTI_SELECT_TAP_THRESHOLD_VP ||
          Math.abs(touchPoint.y - this.multiSelectTouchStartY) > MessageBubble.MULTI_SELECT_TAP_THRESHOLD_VP) {
          this.multiSelectTouchActive = false
        }
        break
      case TouchType.Up:
        if (this.multiSelectTouchActive && touchPoint !== null &&
          Math.abs(touchPoint.x - this.multiSelectTouchStartX) <= MessageBubble.MULTI_SELECT_TAP_THRESHOLD_VP &&
          Math.abs(touchPoint.y - this.multiSelectTouchStartY) <= MessageBubble.MULTI_SELECT_TAP_THRESHOLD_VP) {
          event.stopPropagation()
          this.onSelect(this.message.id)
        }
        this.resetMultiSelectTouchState()
        break
      case TouchType.Cancel:
        this.resetMultiSelectTouchState()
        break
      default:
        break
    }
  }

  aboutToAppear(): void {
    this.syncMessageScopedState()
    this.syncDerivedRenderCaches()
    // 翻译内容动态变化，使用新的 Controller
    this.translationMarkdownController = new MarkdownController()

    // 配置 Markdown 样式
    this.configureMarkdownStyles()

    this.isReasoningExpanded = false
  }

  // 消息状态变化回调（优化跳动点动画性能）
  @Monitor('message')
  onMessageStateChange(): void {
    this.syncMessageScopedState()
    this.syncDerivedRenderCaches()
  }

  @Monitor('contentRenderSignature')
  onContentRenderSignatureChange(): void {
    this.syncMessageScopedState()
    this.syncDerivedRenderCaches()
  }

  @Monitor('previewContent')
  onPreviewContentChange(): void {
    this.syncDerivedRenderCaches()
  }

  @Monitor('previewAttachments')
  onPreviewAttachmentsChange(): void {
    this.syncDerivedRenderCaches()
  }

  @Monitor('isEditing')
  onIsEditingChange(): void {
    this.syncDerivedRenderCaches()
  }

  @Monitor('isMultiSelectMode')
  onIsMultiSelectModeChange(): void {
    if (this.isMultiSelectMode) {
      this.exitSelectableTextMode()
    }
  }

  @Monitor('currentModelId')
  onCurrentModelIdChange(): void {
    this.syncDerivedRenderCaches()
  }

  @Monitor('translatedText')
  onTranslatedTextChange(): void {
    this.syncDerivedRenderCaches()
  }

  private syncMessageScopedState(): void {
    if (this.message.id === this.boundMessageId) {
      return
    }
    this.boundMessageId = this.message.id
    this.resetMessageScopedState()
  }

  private resetMessageScopedState(): void {
    this.translationRequestToken++
    this.isReasoningExpanded = false
    this.translatedText = ''
    this.isTranslating = false
    this.showTranslation = false
    this.isTranslationExpanded = true
    this.currentTranslateLang = ''
  }

  private buildAttachmentSignature(attachments: MessageAttachment[]): string {
    if (attachments.length <= 0) {
      return '0'
    }
    const segments: string[] = []
    for (let i = 0; i < attachments.length; i++) {
      const attachment = attachments[i]
      segments.push([
        attachment.id,
        attachment.type,
        attachment.name,
        attachment.filePath,
        attachment.mimeType,
        attachment.size.toString(),
        attachment.base64Data.length.toString()
      ].join(':'))
    }
    return segments.join('|')
  }

  private buildDerivedCacheSignature(): string {
    return [
      this.message.id,
      this.message.role,
      this.message.timestamp.toString(),
      this.message.modelId,
      this.message.modelName,
      this.message.content,
      this.message.reasoningContent,
      this.message.isGenerating ? '1' : '0',
      this.message.isSearching ? '1' : '0',
      this.currentModelId,
      this.isEditing ? '1' : '0',
      this.previewContent,
      this.translatedText,
      this.buildAttachmentSignature(this.previewAttachments),
      this.buildAttachmentSignature(this.message.attachments)
    ].join('\u0001')
  }

  private ensureDerivedRenderCaches(): void {
    const nextSignature = this.buildDerivedCacheSignature()
    if (nextSignature === this.derivedCacheSignature) {
      return
    }
    this.derivedCacheSignature = nextSignature
    this.syncDerivedRenderCaches()
  }

  private syncDerivedRenderCaches(): void {
    this.cachedDisplayContent = this.computeDisplayContent()
    this.cachedHasDisplayAttachments = this.isEditing ? this.previewAttachments.length > 0 : this.message.hasAttachments()
    this.cachedHasPreviewTextContent = this.cachedDisplayContent.length > 0
    this.cachedHasMessageTextContent = this.message.content.trim().length > 0
    this.cachedHasToolbarPayload = this.cachedHasMessageTextContent || this.message.hasAttachments()
    this.cachedCurrentMessageModelIconResourcePath = this.computeCurrentMessageModelIconResourcePath()
    this.cachedReadonlyMessageContent = this.convertTaskListToReadonly(this.message.content)
    this.cachedReadonlyReasoningContent = this.convertTaskListToReadonly(this.message.reasoningContent)
    this.cachedReadonlyTranslatedText = this.convertTaskListToReadonly(this.translatedText)
    this.cachedHasHtmlSegments = !this.message.isGenerating && this.hasHtmlBlocks(this.message.content)
    this.cachedContentSegments = this.cachedHasHtmlSegments ? this.splitContentToSegments(this.message.content) : []
    this.cachedPreviewImageEntries = this.buildImageAttachmentEntries(this.previewAttachments)
    this.cachedMessageImageEntries = this.buildImageAttachmentEntries(this.message.attachments)
    this.cachedMessageFileAttachments = this.getFileAttachments(this.message.attachments)
    this.cachedPreviewImageGridRows = this.buildImageGridRows(this.cachedPreviewImageEntries.length)
    this.cachedMessageImageGridRows = this.buildImageGridRows(this.cachedMessageImageEntries.length)
  }

  // 配置 Markdown 样式
  private configureMarkdownStyles(): void {
    const uiState = getAppUiState()
    const titleColor = uiState.themeMarkdownTitle
    const textColor = uiState.themeMarkdownText
    const reasoningTextColor = uiState.themeTextSecondary
    const quoteBgColor = uiState.themeMarkdownQuoteBg
    const linkColor = uiState.themeMarkdownLink
    const linkBgColor = uiState.themeMarkdownLinkBg
    const inlineCodeBgColor = uiState.themeMarkdownCodeBg
    const inlineCodeTextColor = uiState.themeMarkdownCodeText
    const tableBgColor = uiState.themeMarkdownTableBg
    const tableHeaderBgColor = uiState.themeMarkdownTableHeaderBg
    const tableAltBgColor = uiState.themeMarkdownTableAltBg
    const tableBorderColor = uiState.themeMarkdownTableBorder
    const codeTheme = this.isDarkMode ? 'dark' : 'light'

    // 数学公式颜色接口需要 number（ARGB），不能直接传 ResourceColor
    const latexTextColor = this.isDarkMode ? 0xFFE0E0E0 : 0xFF333333
    const latexTextColorSecondary = 0xFF999999

    const fs = this.chatFontSize
    const mainTextSize = fs - 1
    const compactTextSize = fs - 2
    const mainTitleSizes = getMarkdownTitleSizes(mainTextSize)
    const compactTitleSizes = getMarkdownTitleSizes(compactTextSize, true)
    const mainBlockSpacing = getMarkdownBlockSpacing(mainTextSize)
    const compactBlockSpacing = getMarkdownBlockSpacing(compactTextSize, true)
    const mainQuotePadding = getMarkdownQuotePadding(mainTextSize)
    const compactQuotePadding = getMarkdownQuotePadding(compactTextSize, true)

    // 配置主内容 Markdown
    const markdownController = this.markdownController
    const reasoningMarkdownController = this.reasoningMarkdownController
    const translationMarkdownController = this.translationMarkdownController

    markdownController
      .setTitleColor(titleColor)
      .setTextColor(textColor)
      .setTextSize(mainTextSize)
      .setTextLineHeight(getMarkdownTextLineHeight(mainTextSize))
      .setTitleSize(mainTitleSizes)
      .setTitleLineHeight(getMarkdownTitleLineHeights(mainTitleSizes))
      .setQuoteBackgroundColor(quoteBgColor)
      .setQuoteBorderColor(linkColor)
      .setQuotePadding(mainQuotePadding)
      .setHyperlinkTextColor(linkColor)
      .setHyperlinkBackgroundColor(linkBgColor)
      .setInlineCodeColor(inlineCodeTextColor)
      .setInlineCodeBackgroundColor(inlineCodeBgColor)
      .setCodeBlockTheme(codeTheme)
      .setLatexMathTextColor(latexTextColor)
      .setLatexMathTextSize(fs + 2)
      .setTableBackgroundColor(tableBgColor)
      .setTableTitleBackgroundColor(tableHeaderBgColor)
      .setTableInterleaveBackgroundColor(tableAltBgColor)
      .setTableOuterBorderColor(tableBorderColor)
      .setTableInnerBorderColor(tableBorderColor)
      .setUlPointColor(textColor)
      .setLineColor(tableBorderColor)
      .setFootnoteTextColor(linkColor)
      .setHyperlinkClickListener((title: string, src: string): boolean => {
        return this.openWebSheetForLink(title, src)
      })
      .setCodeCopyListener((code: string) => {
        this.copyToClipboard(code)
      })
    markdownController.setBlockSpacing(mainBlockSpacing)
    markdownController.setCopyOption(CopyOptions.LocalDevice)

    // 配置推理内容 Markdown（更紧凑）
    reasoningMarkdownController
      .setTitleColor(reasoningTextColor)
      .setTextColor(reasoningTextColor)
      .setTextSize(compactTextSize)
      .setTextLineHeight(getMarkdownTextLineHeight(compactTextSize, true))
      .setTitleSize(compactTitleSizes)
      .setTitleLineHeight(getMarkdownTitleLineHeights(compactTitleSizes, true))
      .setQuoteBackgroundColor(quoteBgColor)
      .setQuoteBorderColor(linkColor)
      .setQuotePadding(compactQuotePadding)
      .setHyperlinkTextColor(linkColor)
      .setHyperlinkBackgroundColor(linkBgColor)
      .setInlineCodeColor(inlineCodeTextColor)
      .setInlineCodeBackgroundColor(inlineCodeBgColor)
      .setCodeBlockTheme(codeTheme)
      .setLatexMathTextColor(latexTextColorSecondary)
      .setLatexMathTextSize(fs)
      .setTableBackgroundColor(tableBgColor)
      .setTableTitleBackgroundColor(tableHeaderBgColor)
      .setTableInterleaveBackgroundColor(tableAltBgColor)
      .setTableOuterBorderColor(tableBorderColor)
      .setTableInnerBorderColor(tableBorderColor)
      .setUlPointColor(reasoningTextColor)
      .setLineColor(tableBorderColor)
      .setFootnoteTextColor(linkColor)
      .setHyperlinkClickListener((title: string, src: string): boolean => {
        return this.openWebSheetForLink(title, src)
      })
      .setCodeCopyListener((code: string) => {
        this.copyToClipboard(code)
      })
    reasoningMarkdownController.setBlockSpacing(compactBlockSpacing)
    reasoningMarkdownController.setCopyOption(CopyOptions.LocalDevice)

    // 配置翻译内容 Markdown
    translationMarkdownController
      .setTitleColor(titleColor)
      .setTextColor(textColor)
      .setTextSize(compactTextSize)
      .setTextLineHeight(getMarkdownTextLineHeight(compactTextSize, true))
      .setTitleSize(compactTitleSizes)
      .setTitleLineHeight(getMarkdownTitleLineHeights(compactTitleSizes, true))
      .setQuoteBackgroundColor(quoteBgColor)
      .setQuoteBorderColor(linkColor)
      .setQuotePadding(compactQuotePadding)
      .setHyperlinkTextColor(linkColor)
      .setHyperlinkBackgroundColor(linkBgColor)
      .setInlineCodeColor(inlineCodeTextColor)
      .setInlineCodeBackgroundColor(inlineCodeBgColor)
      .setCodeBlockTheme(codeTheme)
      .setLatexMathTextColor(latexTextColor)
      .setLatexMathTextSize(this.chatFontSize)
      .setTableBackgroundColor(tableBgColor)
      .setTableTitleBackgroundColor(tableHeaderBgColor)
      .setTableInterleaveBackgroundColor(tableAltBgColor)
      .setTableOuterBorderColor(tableBorderColor)
      .setTableInnerBorderColor(tableBorderColor)
      .setUlPointColor(textColor)
      .setLineColor(tableBorderColor)
      .setFootnoteTextColor(linkColor)
      .setHyperlinkClickListener((title: string, src: string): boolean => {
        return this.openWebSheetForLink(title, src)
      })
      .setCodeCopyListener((code: string) => {
        this.copyToClipboard(code)
      })
    translationMarkdownController.setBlockSpacing(compactBlockSpacing)
    translationMarkdownController.setCopyOption(CopyOptions.LocalDevice)
  }

  @Monitor('themeRenderKey')
  onThemeRenderKeyChange(): void {
    this.configureMarkdownStyles()
  }

  // 字体大小变化监听
  @Monitor('chatFontSize')
  onFontSizeChange(): void {
    this.configureMarkdownStyles()
  }

  // 计算是否应该显示推理内容（生成中自动展开）
  private get shouldShowReasoning(): boolean {
    return this.isReasoningExpanded || (this.message.isGenerating && this.message.reasoningContent.length > 0)
  }

  build() {
    Column() {
      // 编辑状态标签（点击可取消编辑）
      if (this.isEditing) {
        Row() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(10)
            .fontColor([this.themePrimary])

          Text($r('app.string.editing_message'))
            .fontSize(10)
            .fontColor(this.themePrimary)
            .margin({ left: 4 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.themeAiBubble)
        .borderRadius(10)
        .margin({ bottom: 4 })
        .alignSelf(ItemAlign.End)
        .onClick(() => {
          this.onCancelEdit()
        })
      }

      if (this.message.role === MessageRole.USER) {
        this.UserMessage()
      } else {
        this.AssistantMessage()
      }
    }
    .width('100%')
    // 新消息入场动画：用户消息从右侧滑入，AI消息从左侧滑入
    .transition(
      TransitionEffect.asymmetric(
        // 入场：滑入 + 淡入
        TransitionEffect.translate({
          x: this.message.role === MessageRole.USER ? 30 : -30
        }).combine(TransitionEffect.OPACITY),
        // 退场：仅淡出
        TransitionEffect.OPACITY
      ).animation({ duration: 250, curve: Curve.EaseOut })
    )
  }

  // 处理翻译
  private handleTranslate(targetLang: string): void {
    if (this.isTranslating) {
      return
    }
    const requestToken = ++this.translationRequestToken
    const requestMessageId = this.message.id
    this.isTranslating = true
    this.showTranslation = true
    this.isTranslationExpanded = true
    this.translatedText = ''
    this.currentTranslateLang = targetLang

    this.onTranslate(this.message.content, targetLang, (result: string, errorMessage: string) => {
      if (requestToken !== this.translationRequestToken || this.message.id !== requestMessageId) {
        return
      }
      this.translatedText = result
      this.isTranslating = false
      if (result === '' && errorMessage !== '') {
        showToast(this.getUIContext(), errorMessage, 3000)
      }
    })
  }

  // 获取显示内容（编辑模式下使用预览内容）
  private computeDisplayContent(): string {
    if (this.isEditing) {
      return this.previewContent
    }
    return this.message.content
  }

  private getDisplayContent(): string {
    this.ensureDerivedRenderCaches()
    return this.cachedDisplayContent
  }

  // 检查内容是否包含完整的 HTML 代码块
  private hasHtmlBlocks(content: string): boolean {
    return /```html?\s*\n[\s\S]*?```/.test(content)
  }

  // 将内容按 HTML 代码块边界分段，用于内联预览渲染
  private splitContentToSegments(content: string): ContentSegment[] {
    const segments: ContentSegment[] = []
    const pattern = /```html?\s*\n([\s\S]*?)```/g
    let lastIndex = 0
    let match = pattern.exec(content)

    while (match !== null) {
      const matchIndex = match.index
      // 添加 HTML 代码块之前的文本段
      if (matchIndex > lastIndex) {
        const textContent = content.substring(lastIndex, matchIndex)
        if (textContent.trim().length > 0) {
          segments.push({
            isHtml: false,
            renderContent: this.convertTaskListToReadonly(textContent)
          } as ContentSegment)
        }
      }
      // 添加 HTML 代码块段
      segments.push({ isHtml: true, renderContent: match[1] } as ContentSegment)
      lastIndex = matchIndex + match[0].length
      match = pattern.exec(content)
    }

    // 添加最后一个 HTML 代码块之后的剩余文本
    if (lastIndex < content.length) {
      const remaining = content.substring(lastIndex)
      if (remaining.trim().length > 0) {
        segments.push({
          isHtml: false,
          renderContent: this.convertTaskListToReadonly(remaining)
        } as ContentSegment)
      }
    }

    return segments
  }

  // 是否有显示附件（编辑模式下使用预览附件）
  private hasDisplayAttachments(): boolean {
    this.ensureDerivedRenderCaches()
    return this.cachedHasDisplayAttachments
  }

  // 获取附件图片数据源（优先 file://，其次 base64）
  private getAttachmentImageSource(attachment: MessageAttachment): string {
    if (attachment.filePath !== '') {
      return 'file://' + attachment.filePath
    }
    if (attachment.base64Data !== '') {
      return `data:${attachment.mimeType};base64,${attachment.base64Data}`
    }
    return ''
  }

  // 提取图片附件并保留原始索引（用于正确映射预览索引）
  private buildImageAttachmentEntries(attachments: MessageAttachment[]): ImageAttachmentEntry[] {
    const imageEntries: ImageAttachmentEntry[] = []
    for (let i = 0; i < attachments.length; i++) {
      if (attachments[i].type === AttachmentType.IMAGE) {
        imageEntries.push({
          attachment: attachments[i],
          originalIndex: i
        })
      }
    }
    return imageEntries
  }

  private getFileAttachments(attachments: MessageAttachment[]): MessageAttachment[] {
    const fileAttachments: MessageAttachment[] = []
    for (let i = 0; i < attachments.length; i++) {
      if (attachments[i].type === AttachmentType.FILE) {
        fileAttachments.push(attachments[i])
      }
    }
    return fileAttachments
  }

  private getPreviewImageEntries(): ImageAttachmentEntry[] {
    this.ensureDerivedRenderCaches()
    return this.cachedPreviewImageEntries
  }

  private getPreviewImageGridRows(): number[] {
    this.ensureDerivedRenderCaches()
    return this.cachedPreviewImageGridRows
  }

  private hasPreviewTextContent(): boolean {
    this.ensureDerivedRenderCaches()
    return this.cachedHasPreviewTextContent
  }

  private getMessageImageEntries(): ImageAttachmentEntry[] {
    this.ensureDerivedRenderCaches()
    return this.cachedMessageImageEntries
  }

  private getMessageImageGridRows(): number[] {
    this.ensureDerivedRenderCaches()
    return this.cachedMessageImageGridRows
  }

  private getMessageFileAttachments(): MessageAttachment[] {
    this.ensureDerivedRenderCaches()
    return this.cachedMessageFileAttachments
  }

  private hasMessageTextContent(): boolean {
    this.ensureDerivedRenderCaches()
    return this.cachedHasMessageTextContent
  }

  private hasToolbarPayload(): boolean {
    this.ensureDerivedRenderCaches()
    return this.cachedHasToolbarPayload
  }

  private getCurrentMessageModelIconResourcePath(): string {
    this.ensureDerivedRenderCaches()
    return this.cachedCurrentMessageModelIconResourcePath
  }

  private hasHtmlSegments(): boolean {
    this.ensureDerivedRenderCaches()
    return this.cachedHasHtmlSegments
  }

  private getContentSegments(): ContentSegment[] {
    this.ensureDerivedRenderCaches()
    return this.cachedContentSegments
  }

  private getReadonlyMessageContent(): string {
    this.ensureDerivedRenderCaches()
    return this.cachedReadonlyMessageContent
  }

  private getReadonlyReasoningContent(): string {
    this.ensureDerivedRenderCaches()
    return this.cachedReadonlyReasoningContent
  }

  private getReadonlyTranslatedText(): string {
    this.ensureDerivedRenderCaches()
    return this.cachedReadonlyTranslatedText
  }

  private shouldShowUserToolbar(): boolean {
    return !this.isMultiSelectMode && !this.isEditing && this.hasToolbarPayload()
  }

  private shouldShowAssistantToolbar(): boolean {
    return shouldShowAssistantMessageToolbar(this.message, this.isMultiSelectMode)
  }

  private canCopyMessageContent(): boolean {
    return this.hasMessageTextContent()
  }

  private canTranslateMessageContent(): boolean {
    return this.hasMessageTextContent()
  }

  private canReadMessageContent(): boolean {
    return this.hasMessageTextContent()
  }

  // 生成两列网格行索引
  private buildImageGridRows(imageCount: number): number[] {
    const rows: number[] = []
    if (imageCount <= 0) {
      return rows
    }
    const rowCount = Math.ceil(imageCount / 2)
    for (let i = 0; i < rowCount; i++) {
      rows.push(i)
    }
    return rows
  }

  // 清空翻译
  private clearTranslation(): void {
    this.translationRequestToken++
    this.showTranslation = false
    this.translatedText = ''
    this.isTranslating = false
    this.isTranslationExpanded = true
    this.currentTranslateLang = ''
  }

  // 将 hex 颜色向白色方向混合（用于多选选中态）
  private lightenColor(hex: string, amount: number): string {
    let c = hex.replace('#', '')
    if (c.length === 3) {
      c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2]
    }
    const r = Math.min(255, Math.round(parseInt(c.substring(0, 2), 16) + (255 - parseInt(c.substring(0, 2), 16)) * amount))
    const g = Math.min(255, Math.round(parseInt(c.substring(2, 4), 16) + (255 - parseInt(c.substring(2, 4), 16)) * amount))
    const b = Math.min(255, Math.round(parseInt(c.substring(4, 6), 16) + (255 - parseInt(c.substring(4, 6), 16)) * amount))
    return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`
  }

  private openWebSheetForLink(title: string, src: string): boolean {
    let url = src.trim()
    if (url === '') {
      return false
    }
    if (url.startsWith('mailto:') || url.startsWith('tel:')) {
      return false
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      // 兼容 markdown 中的裸域名链接
      if (url.indexOf('://') < 0) {
        url = 'https://' + url
      } else {
        return false
      }
    }

    this.onOpenLink(title.trim(), url)
    return true
  }

  @Builder
  UserMessage() {
    Column() {
      Row() {
        Blank()

        Row() {
          Column() {
            // 图片附件显示
            if (this.hasDisplayAttachments()) {
              if (this.isEditing) {
                this.PreviewAttachments()
              } else {
                this.UserAttachments()
              }
            }

            // 文本内容
            if (this.getDisplayContent().length > 0) {
              Text(this.getDisplayContent())
                .fontSize(this.chatFontSize)
                .fontColor(this.themeUserBubbleText)
                .lineHeight(Math.round(this.chatFontSize * 1.4))
            }
          }
          .padding(this.hasDisplayAttachments() ? { left: 8, right: 8, top: 8, bottom: 8 } : { left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(this.isMultiSelectMode && this.isSelected
            ? this.lightenColor(this.themeUserBubble, 0.15)
            : this.themeUserBubble)
          .borderRadius({
            topLeft: 20,
            topRight: 20,
            bottomLeft: 20,
            bottomRight: 6
          })
          .clip(true)
          .constraintSize({ maxWidth: '75%' })
          .border({
            width: this.isEditing ? 2 : (this.isMultiSelectMode && this.isSelected ? 1.2 : 0.5),
            color: this.isEditing
              ? '#FFFFFF'
              : (this.isMultiSelectMode && this.isSelected ? withColorAlpha(this.themePrimary, '66') : 'rgba(255, 255, 255, 0.15)')
          })

          // 多选选中竖条
          if (this.isMultiSelectMode && this.isSelected) {
            Column()
              .width(3)
              .borderRadius(1.5)
              .backgroundColor(this.themePrimary)
              .alignSelf(ItemAlign.Stretch)
              .margin({ left: 4 })
              .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
          }
        }
        .enabled(!this.isMultiSelectMode)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 用户消息工具栏
      if (this.shouldShowUserToolbar()) {
        Row() {
          Blank()

          // 复制
          if (this.canCopyMessageContent()) {
            SymbolGlyph($r('sys.symbol.checkmark_square_on_square'))
              .fontSize(14)
              .fontColor([$r('app.color.text_tertiary')])
              .onClick(() => { this.handleCopy() })
          }

          // 重新生成
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(14)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ left: this.canCopyMessageContent() ? 16 : 0 })
            .onClick(() => { this.onRegenerate() })

          // 编辑
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(14)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ left: 16 })
            .onClick(() => { this.onEdit() })

          // 更多
          SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
            .fontSize(14)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ left: 16 })
            .bindMenu(this.UserMoreMenu())
        }
        .width('100%')
        .margin({ top: 6 })
      }

    }
    .width('100%')
    .alignItems(HorizontalAlign.End)
    .onTouch((event: TouchEvent) => {
      this.handleMultiSelectTouch(event)
    })
  }

  // 编辑模式下的简化附件预览（无手势交互）
  @Builder
  PreviewAttachments() {
    Column() {
      if (this.getPreviewImageEntries().length === 1) {
        this.CompactPreviewSingleImage(
          this.getPreviewImageEntries()[0].attachment,
          this.hasPreviewTextContent() ? 6 : 0
        )
      } else if (this.getPreviewImageEntries().length > 1) {
        Column({ space: this.compactImageGap }) {
          ForEach(this.getPreviewImageGridRows(), (rowIndex: number) => {
            Row({ space: this.compactImageGap }) {
              this.CompactPreviewGridImage(this.getPreviewImageEntries()[rowIndex * 2].attachment)

              if (rowIndex * 2 + 1 < this.getPreviewImageEntries().length) {
                this.CompactPreviewGridImage(this.getPreviewImageEntries()[rowIndex * 2 + 1].attachment)
              } else {
                Blank()
                  .layoutWeight(1)
              }
            }
            .width(this.compactImageContainerWidth)
          }, (rowIndex: number) => rowIndex.toString())
        }
        .margin({ bottom: this.hasPreviewTextContent() ? 6 : 0 })
      }
    }
  }

  @Builder
  CompactPreviewSingleImage(attachment: MessageAttachment, bottomMargin: number) {
    if (this.getAttachmentImageSource(attachment) !== '') {
      Image(this.getAttachmentImageSource(attachment))
        .width(this.compactImageContainerWidth)
        .height(this.compactImageMaxHeight)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .clip(true)
        .margin({ bottom: bottomMargin })
    }
  }

  @Builder
  CompactPreviewGridImage(attachment: MessageAttachment) {
    if (this.getAttachmentImageSource(attachment) !== '') {
      Image(this.getAttachmentImageSource(attachment))
        .width('100%')
        .height(this.compactImageMaxHeight)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .clip(true)
        .layoutWeight(1)
    }
  }

  @Builder
  CompactSingleImage(attachment: MessageAttachment, attachmentIndex: number, bottomMargin: number) {
    if (this.getAttachmentImageSource(attachment) !== '') {
      Image(this.getAttachmentImageSource(attachment))
        .id('img_' + attachment.id)
        .width(this.compactImageContainerWidth)
        .height(this.compactImageMaxHeight)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .clip(true)
        .margin({ bottom: bottomMargin })
        .onClick(() => {
          this.handleImagePreview(attachmentIndex)
        })
    }
  }

  @Builder
  CompactGridImage(attachment: MessageAttachment, attachmentIndex: number) {
    if (this.getAttachmentImageSource(attachment) !== '') {
      Image(this.getAttachmentImageSource(attachment))
        .id('img_' + attachment.id)
        .width('100%')
        .height(this.compactImageMaxHeight)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .clip(true)
        .layoutWeight(1)
        .onClick(() => {
          this.handleImagePreview(attachmentIndex)
        })
    }
  }

  @Builder
  UserAttachments() {
    Column() {
      if (this.getMessageImageEntries().length === 1) {
        this.CompactSingleImage(
          this.getMessageImageEntries()[0].attachment,
          this.getMessageImageEntries()[0].originalIndex,
          this.hasMessageTextContent() ? 6 : 0
        )
      } else if (this.getMessageImageEntries().length > 1) {
        Column({ space: this.compactImageGap }) {
          ForEach(this.getMessageImageGridRows(), (rowIndex: number) => {
            Row({ space: this.compactImageGap }) {
              this.CompactGridImage(
                this.getMessageImageEntries()[rowIndex * 2].attachment,
                this.getMessageImageEntries()[rowIndex * 2].originalIndex
              )

              if (rowIndex * 2 + 1 < this.getMessageImageEntries().length) {
                this.CompactGridImage(
                  this.getMessageImageEntries()[rowIndex * 2 + 1].attachment,
                  this.getMessageImageEntries()[rowIndex * 2 + 1].originalIndex
                )
              } else {
                Blank()
                  .layoutWeight(1)
              }
            }
            .width(this.compactImageContainerWidth)
          }, (rowIndex: number) => `${this.message.id}_user_${rowIndex}`)
        }
        .margin({ bottom: this.hasMessageTextContent() ? 6 : 0 })
      }

      ForEach(this.getMessageFileAttachments(), (attachment: MessageAttachment, index: number) => {
        Row() {
          SymbolGlyph($r('sys.symbol.doc'))
            .fontSize(18)
            .fontColor(['rgba(255,255,255,0.8)'])

          Text(attachment.name)
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.9)')
            .margin({ left: 6 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .padding(8)
        .backgroundColor('rgba(255,255,255,0.15)')
        .borderRadius(8)
        .margin({ bottom: this.hasMessageTextContent() ? 6 : 0 })
      }, (attachment: MessageAttachment, index: number) => attachment.id || attachment.filePath || index.toString())
    }
    .alignItems(HorizontalAlign.End)
  }

  @Builder
  AssistantAttachments() {
    Column() {
      if (this.getMessageImageEntries().length === 1) {
        this.CompactSingleImage(
          this.getMessageImageEntries()[0].attachment,
          this.getMessageImageEntries()[0].originalIndex,
          8
        )
      } else if (this.getMessageImageEntries().length > 1) {
        Column({ space: this.compactImageGap }) {
          ForEach(this.getMessageImageGridRows(), (rowIndex: number) => {
            Row({ space: this.compactImageGap }) {
              this.CompactGridImage(
                this.getMessageImageEntries()[rowIndex * 2].attachment,
                this.getMessageImageEntries()[rowIndex * 2].originalIndex
              )

              if (rowIndex * 2 + 1 < this.getMessageImageEntries().length) {
                this.CompactGridImage(
                  this.getMessageImageEntries()[rowIndex * 2 + 1].attachment,
                  this.getMessageImageEntries()[rowIndex * 2 + 1].originalIndex
                )
              } else {
                Blank()
                  .layoutWeight(1)
              }
            }
            .width(this.compactImageContainerWidth)
          }, (rowIndex: number) => `${this.message.id}_ai_${rowIndex}`)
        }
        .margin({ bottom: 8 })
      }

      ForEach(this.getMessageFileAttachments(), (attachment: MessageAttachment, index: number) => {
        Row() {
          SymbolGlyph($r('sys.symbol.doc'))
            .fontSize(18)
            .fontColor([$r('app.color.text_tertiary')])

          Text(attachment.name)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 6 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .padding(8)
        .backgroundColor($r('app.color.divider'))
        .borderRadius(8)
        .margin({ bottom: 8 })
      }, (attachment: MessageAttachment, index: number) => attachment.id || attachment.filePath || index.toString())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 处理图片预览点击
  private handleImagePreview(clickedIndex: number): void {
    // 收集所有图片附件的路径
    const imageAttachments = this.message.getImageAttachments()
    const imagePaths: Array<string> = []

    for (let i = 0; i < imageAttachments.length; i++) {
      const attachment = imageAttachments[i]
      if (attachment.filePath !== '') {
        imagePaths.push('file://' + attachment.filePath)
      } else if (attachment.base64Data !== '') {
        imagePaths.push(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
      }
    }

    if (imagePaths.length > 0) {
      // 计算点击的图片在纯图片列表中的索引
      let imageIndex = 0
      let imageCount = 0
      for (let i = 0; i < this.message.attachments.length; i++) {
        if (this.message.attachments[i].type === AttachmentType.IMAGE) {
          if (i === clickedIndex) {
            imageIndex = imageCount
            break
          }
          imageCount++
        }
      }
      this.onImageClick(imagePaths, imageIndex)
    }
  }

  private enterSelectableTextMode(): void {
    if (!this.canCopyMessageContent() || this.isMultiSelectMode) {
      return
    }
    this.onSetSelectableTextMessageId(this.message.id)
  }

  private exitSelectableTextMode(): void {
    if (this.selectableTextMessageId === this.message.id) {
      this.onSetSelectableTextMessageId('')
    }
  }

  @Builder
  InlineSelectableTextContent() {
    Column() {
      SelectableMarkdownContent({
        content: this.message.content,
        fontSize: this.chatFontSize - 1,
        textColor: $r('app.color.text_primary')
      })
        .width('100%')
    }
    .width('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
  }

  // 翻译子菜单
  @Builder
  TranslateSubMenu() {
    Menu() {
      ForEach(this.translateLanguages, (lang: TranslateLanguage) => {
        MenuItem({ content: lang.nativeName })
          .onClick(() => { this.handleTranslate(lang.name) })
      }, (lang: TranslateLanguage) => lang.code)
    }
  }

  // AI 消息更多菜单（分享/多选/删除）
  @Builder
  AssistantMoreMenu() {
    Menu() {
      if (this.canCopyMessageContent()) {
        MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.textformat')).fontSize(16), content: $r('app.string.menu_select_text') })
          .contentFont({ size: 14 })
          .onClick(() => { this.enterSelectableTextMode() })
      }

      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')).fontSize(16), content: $r('app.string.menu_share') })
        .contentFont({ size: 14 })
        .onClick(() => { this.onShareMessage() })

      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')).fontSize(16), content: $r('app.string.menu_multi_select') })
        .contentFont({ size: 14 })
        .onClick(() => { this.onEnterMultiSelect(this.message.id) })

      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontSize(16), content: $r('app.string.delete') })
        .contentFont({ size: 14 })
        .contentFontColor($r('app.color.status_error'))
        .onClick(() => { this.onDelete() })
    }
  }

  // 用户消息更多菜单（分享/多选/删除）
  @Builder
  UserMoreMenu() {
    Menu() {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')).fontSize(16), content: $r('app.string.menu_share') })
        .contentFont({ size: 14 })
        .onClick(() => { this.onShareMessage() })

      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')).fontSize(16), content: $r('app.string.menu_multi_select') })
        .contentFont({ size: 14 })
        .onClick(() => { this.onEnterMultiSelect(this.message.id) })

      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontSize(16), content: $r('app.string.delete') })
        .contentFont({ size: 14 })
        .contentFontColor($r('app.color.status_error'))
        .onClick(() => { this.onDelete() })
    }
  }

  @Builder
  AssistantMessage() {
    Row() {
      // 多选选中竖条
      if (this.isMultiSelectMode && this.isSelected) {
        Column()
          .width(3)
          .borderRadius(1.5)
          .backgroundColor(this.themePrimary)
          .alignSelf(ItemAlign.Stretch)
          .margin({ right: 4 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }

      Column() {
        // 消息头部：图标 + 模型名 + 时间（水平排列）
        // 只在 showHeader 为 true 时显示
        if (this.showHeader) {
          Row() {
            // 模型图标 + 淡色圆形背景
            Column() {
              if (this.getCurrentMessageModelIconResourcePath() !== '') {
                Image(this.getCurrentMessageModelIconResourcePath())
                  .width(18)
                  .height(18)
                  .objectFit(ImageFit.Contain)
              } else {
                SymbolGlyph($r('sys.symbol.ai_edit'))
                  .fontSize(16)
                  .fontColor([this.themePrimary])
              }
            }
            .width(30)
            .height(30)
            .borderRadius(8)
            .backgroundColor($r('app.color.model_icon_bg'))
            .border({ width: 0.5, color: $r('app.color.bubble_border') })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            // 模型名称
            Text(this.message.modelName || 'AI')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .margin({ left: 10 })

            Blank()
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }

        // 内容区域 - 无气泡，全宽显示
        Column() {
          Column() {
            if (!this.isSelectableTextMode) {
              // ========== 工具调用区域 ==========
              if (this.message.hasToolCalls()) {
                ForEach(this.message.toolCalls, (toolCall: ToolCall, index: number) => {
                  if (!this.shouldHideToolCallCard(toolCall)) {
                    ToolCallCard({
                      toolCall: toolCall,
                      toolResult: index < this.message.toolResults.length ? this.message.toolResults[index] : null,
                      isExecuting: this.message.isGenerating && index >= this.message.toolResults.length
                    })
                      .margin({ bottom: 6 })
                  }
                }, (toolCall: ToolCall, index: number) => toolCall.id + '_' + index.toString())
              }

              // ========== 搜索引用区域 ==========
              if (this.message.hasSearchReferences()) {
                SearchReferenceCard({
                  query: this.extractSearchQuery(),
                  searchEngine: this.message.searchEngine || 'Web',
                  references: this.message.searchReferences,
                  sourceLabel: this.getSearchSourceLabel()
                })
                  .margin({ bottom: 6 })
              }

              // ========== 附件区域（AI 生成的图片） ==========
              if (this.message.hasAttachments()) {
                this.AssistantAttachments()
              }

              // ========== 推理内容区域（可折叠） ==========
              if (this.message.hasReasoningContent()) {
                this.ReasoningSection()
              }
            }

            // ========== 加载状态或主要内容区域 ==========
            if (this.isSelectableTextMode) {
              this.InlineSelectableTextContent()
            } else if (this.message.content.length === 0 && this.message.reasoningContent.length === 0 &&
                (this.message.isGenerating || this.message.isSearching)) {
              if (this.message.isSearching) {
                this.SearchingIndicatorInline()
              } else {
                this.TypingIndicator()
              }
            } else {
              if (this.hasHtmlSegments()) {
                ForEach(this.getContentSegments(),
                  (segment: ContentSegment, index: number) => {
                    if (segment.isHtml) {
                      HtmlPreviewCard({
                        htmlCode: segment.renderContent,
                        onCopyCode: (code: string) => {
                          this.copyToClipboard(code)
                          showToast(this.getUIContext(), $r('app.string.copy_success'))
                        }
                      })
                    } else {
                      Markdown({
                        controller: this.markdownController,
                        text: segment.renderContent
                      })
                        .width('100%')
                        .backgroundColor(Color.Transparent)
                        .gesture(
                          LongPressGesture()
                            .onAction(() => {
                              this.enterSelectableTextMode()
                            })
                        )
                    }
                  },
                  (segment: ContentSegment, index: number) => {
                    return 'segment_' + this.message.id + '_' + index.toString()
                  }
                )
              } else {
                Markdown({
                  controller: this.markdownController,
                  text: this.getReadonlyMessageContent()
                })
                  .width('100%')
                  .backgroundColor(Color.Transparent)
                  .gesture(
                    LongPressGesture()
                      .onAction(() => {
                        this.enterSelectableTextMode()
                      })
                  )
                  .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
              }
            }

            // ========== 翻译结果区域（嵌入式可折叠卡片） ==========
            if (!this.isSelectableTextMode && this.showTranslation) {
              this.TranslationCard()
            }
          }
          .width('100%')
          .onClick(() => {
            if (!this.isMultiSelectMode && (this.speakingMessageId === this.message.id)) {
              this.onTTSStop()
            }
          })
          // ========== 工具栏 ==========
          if (!this.isSelectableTextMode && this.shouldShowAssistantToolbar()) {
            Row() {
              // 复制
              if (this.canCopyMessageContent()) {
                SymbolGlyph($r('sys.symbol.checkmark_square_on_square'))
                  .fontSize(14)
                  .fontColor([$r('app.color.text_tertiary')])
                  .onClick(() => { this.handleCopy() })
              }

              // 重新生成
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(14)
                .fontColor([$r('app.color.text_tertiary')])
                .margin({ left: this.canCopyMessageContent() ? 16 : 0 })
                .onClick(() => { this.onRegenerate() })

              // 朗读
              if (this.canReadMessageContent()) {
                SymbolGlyph((this.speakingMessageId === this.message.id) ? $r('sys.symbol.pause') : $r('sys.symbol.speaker_wave_2'))
                  .fontSize(14)
                  .fontColor([(this.speakingMessageId === this.message.id) ? this.themePrimary : $r('app.color.text_tertiary')])
                  .margin({ left: 16 })
                  .onClick(() => {
                    if ((this.speakingMessageId === this.message.id)) { this.onTTSStop() } else { this.onTTS(this.message.id, this.message.content) }
                  })
              }

              // 翻译
              if (this.canTranslateMessageContent()) {
                SymbolGlyph($r('sys.symbol.translate'))
                  .fontSize(14)
                  .fontColor([$r('app.color.text_tertiary')])
                  .margin({ left: 16 })
                  .bindMenu(this.TranslateSubMenu())
              }

              // 更多
              SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                .fontSize(14)
                .fontColor([$r('app.color.text_tertiary')])
                .margin({ left: 16 })
                .bindMenu(this.AssistantMoreMenu())

              Blank()
            }
            .width('100%')
            .margin({ top: 6 })
          }
        }
        .width('100%')
        .margin({ top: this.showHeader ? 8 : 0 })
        .padding({ left: 14, right: 14, top: 12, bottom: 10 })
          .backgroundColor(this.isMultiSelectMode && this.isSelected
            ? this.themePrimaryLight
            : this.themeAiBubble)
          .borderRadius(16)
          .border({
            width: this.isSelectableTextMode ? 1.5 : (this.isMultiSelectMode && this.isSelected ? 1.2 : 0.5),
            color: this.isSelectableTextMode ? this.themeUserBubble : (this.isMultiSelectMode && this.isSelected ? this.themePrimary : $r('app.color.bubble_border'))
          })
          .clip(true)
      }
      .enabled(!this.isMultiSelectMode)
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ maxWidth: '92%' })
    .alignItems(VerticalAlign.Top)
    .onTouch((event: TouchEvent) => {
      this.handleMultiSelectTouch(event)
    })
  }

  // 等待 AI 响应的跳动点动画
  @Builder
  TypingIndicator() {
    Row() {
      // 三个跳动的点
      TypingDots({ dotSize: 7, spacing: 5 })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(this.themeAiBubble)
      .borderRadius({
        topLeft: 4,
        topRight: 18,
        bottomLeft: 18,
        bottomRight: 18
      })
      .clip(true)
      .shadow({
        radius: 8,
        color: 'rgba(0, 0, 0, 0.05)',
        offsetX: 0,
        offsetY: 1
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    // 跳动点淡出过渡动画
    .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
  }

  // 搜索状态指示器（AI 消息区域内联显示）
  @Builder
  SearchingIndicatorInline() {
    Row() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(13)
          .fontColor([this.themePrimary])

        Text(this.getSearchingIndicatorText())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .constraintSize({ maxWidth: 150 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 三个跳动的点
        TypingDots({ dotSize: 4, spacing: 2 })
      }
      .constraintSize({ maxWidth: 220 })
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.themeAiBubble)
      .borderRadius(14)
      .clip(true)
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    // 搜索指示器淡出过渡动画
    .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
  }

  // 翻译结果卡片（嵌入式可折叠）
  @Builder
  TranslationCard() {
    Column() {
      // 翻译标题栏（点击可折叠）
      Row() {
        SymbolGlyph($r('sys.symbol.translate'))
          .fontSize(14)
          .fontColor([$r('app.color.text_secondary')])

        Text($r('app.string.translation_label'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 6 })

        Blank()

        // 展开/折叠箭头
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: this.isTranslationExpanded ? 0 : -90 })
          .animation({ duration: 200, curve: Curve.EaseOut })
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
          this.isTranslationExpanded = !this.isTranslationExpanded
        })
      })

      // 翻译内容
      if (this.isTranslationExpanded) {
        Column() {
          if (this.isTranslating) {
            Row() {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(this.themePrimary)
              Text($r('app.string.translation_loading'))
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 8 })
            }
            .padding({ left: 12, right: 12, bottom: 12 })
          } else if (this.translatedText !== '') {
            Column() {
              Markdown({
                controller: this.translationMarkdownController,
                text: this.getReadonlyTranslatedText()
              })
                .constraintSize({ maxWidth: '100%' })
                .backgroundColor(Color.Transparent)
            }
            .width('100%')
            .padding({ left: 12, right: 12, bottom: 12 })
          }
        }
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }
    .width('100%')
    .margin({ top: 8 })
    .backgroundColor($r('app.color.divider'))
    .borderRadius(12)
    .clip(true)
  }

  // 推理内容区域（可折叠）
  @Builder
  ReasoningSection() {
    Column() {
      // 推理标题栏（点击可折叠/展开）
      Row() {
        // 思考图标
        SymbolGlyph($r('sys.symbol.lightbulb'))
          .fontSize(14)
          .fontColor([this.message.isGenerating ? this.themePrimary : $r('app.color.text_secondary')])

        // 标题文本：根据生成状态显示不同内容
        if (this.message.isGenerating && this.message.content.length === 0) {
          // 正在思考状态：显示跳动点动画（仅在内容尚未开始生成时）
          Row({ space: 4 }) {
            Text($r('app.string.reasoning_thinking'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)

            // 三个跳动的点
            TypingDots({ dotSize: 4, spacing: 2 })
          }
          .margin({ left: 6 })
        } else {
          // 静态状态：显示"思考过程"
          Text($r('app.string.reasoning_process'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 6 })
        }

        Blank()

        // 展开/折叠状态提示
        Text(this.isReasoningExpanded ? $r('app.string.common_collapse') : $r('app.string.common_expand'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))

        // 展开/折叠箭头
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('app.color.text_secondary')])
          .rotate({ angle: this.isReasoningExpanded ? 180 : 0 })
          .animation({ duration: 200, curve: Curve.EaseOut })
          .margin({ left: 4 })
      }
      .width('100%')
      .height(36)
      .padding({ left: 10, right: 10 })
      .backgroundColor($r('app.color.divider'))
      .borderRadius(8)
      .clip(true)
      .onClick(() => {
        this.isReasoningExpanded = !this.isReasoningExpanded
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        })
      })

      // 推理内容默认折叠，仅在用户显式展开后显示
      if (this.isReasoningExpanded) {
        Column() {
          Markdown({
            controller: this.reasoningMarkdownController,
            text: this.getReadonlyReasoningContent()
          })
            .constraintSize({ maxWidth: '100%' })
            .backgroundColor(Color.Transparent)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.divider'))
        .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 8, bottomRight: 8 })
        .clip(true)
        .margin({ top: -8 })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }
    .width('100%')
    .margin({ bottom: 4 })
  }

  /**
   * 将 Markdown 任务列表语法转换为只读字符
   * 避免 lv-markdown-in 渲染出可交互的 checkbox
   * - [ ] → - ☐ (空心方框)
   * - [x] 或 - [X] → - ☑ (勾选方框)
   */
  private convertTaskListToReadonly(content: string): string {
    if (content.length === 0) {
      return content
    }
    // 替换未完成任务: - [ ] 或 * [ ]
    let result = content.replace(/^(\s*[-*])\s*\[ \]/gm, '$1 ☐')
    // 替换已完成任务: - [x] 或 - [X] 或 * [x] 或 * [X]
    result = result.replace(/^(\s*[-*])\s*\[[xX]\]/gm, '$1 ☑')
    // 转换 LaTeX 分隔符: \[...\] -> $$...$$ , \(...\) -> $...$
    // 部分模型(如 OpenAI 系列)使用 \[...\] 和 \(...\) 格式，lv-markdown-in 只识别 $/$$ 格式
    result = this.normalizeLatexDelimiters(result)
    result = this.convertHeadingsWithLatex(result)
    return result
  }

  /**
   * lv-markdown-in 不渲染 Markdown 标题(##)内嵌的 LaTeX 公式，也不渲染加粗(**)内的 LaTeX。
   * 将含 LaTeX 的标题拆分：纯文本部分保留为标题，LaTeX 及后续内容移至下方独立段落渲染。
   */
  private convertHeadingsWithLatex(content: string): string {
    const codeBlocks: string[] = []
    let result = content.replace(/```[\s\S]*?```/g, (m: string): string => {
      codeBlocks.push(m)
      return `\u0000HCB${(codeBlocks.length - 1).toString()}\u0000`
    })

    result = result.replace(
      /^(#{1,6})\s+(.+)$/gm,
      (match: string, hashes: string, text: string): string => {
        if (!/\$.+?\$/.test(text)) {
          return match
        }
        const firstDollar = text.indexOf('$')
        const headingText = text.substring(0, firstDollar).trimEnd()
        const latexAndRest = text.substring(firstDollar)

        if (headingText.length > 0) {
          return `${hashes} ${headingText}\n\n${latexAndRest}`
        }
        return latexAndRest
      }
    )

    result = result.replace(/\u0000HCB(\d+)\u0000/g, (_m: string, idx: string): string => {
      return codeBlocks[parseInt(idx)]
    })
    return result
  }

  private normalizeLatexDelimiters(content: string): string {
    // 先保护代码块内容，避免误转换
    const codeBlocks: string[] = []
    let protected_ = content.replace(/```[\s\S]*?```|`[^`\n]+`/g, (match: string): string => {
      codeBlocks.push(match)
      return `\u0000CODE${(codeBlocks.length - 1).toString()}\u0000`
    })

    // 块级公式: \[...\] -> $$...$$
    protected_ = protected_.replace(/\\\[([\s\S]*?)\\\]/g, (_match: string, p1: string): string => {
      return `$$${p1}$$`
    })
    // 行内公式: \(...\) -> $...$
    protected_ = protected_.replace(/\\\(([\s\S]*?)\\\)/g, (_match: string, p1: string): string => {
      return `$${p1}$`
    })

    // 恢复代码块
    protected_ = protected_.replace(/\u0000CODE(\d+)\u0000/g, (_match: string, idx: string): string => {
      return codeBlocks[parseInt(idx)]
    })
    return protected_
  }

  // 提取搜索查询内容
  private extractSearchQuery(): string {
    if (this.message.searchQuery !== '') {
      return this.message.searchQuery
    }
    if (this.message.searchReferences.length > 0) {
      return '搜索结果'
    }
    return ''
  }

  private shouldHideToolCallCard(toolCall: ToolCall): boolean {
    return this.message.hasSearchReferences() && this.isWebSearchToolCall(toolCall)
  }

  private isWebSearchToolCall(toolCall: ToolCall): boolean {
    if (toolCall.toolId.trim() === 'web_search') {
      return true
    }
    return this.isWebSearchFunctionName(toolCall.functionName)
  }

  private isWebSearchFunctionName(functionName: string): boolean {
    const normalizedName = functionName.trim().toLowerCase().replace(/[\s\-]+/g, '_')
    return normalizedName === 'web_search' ||
      normalizedName === 'exa_search' ||
      normalizedName === 'websearch' ||
      normalizedName === 'search_web' ||
      normalizedName === 'internet_search' ||
      normalizedName === 'web_search_exa'
  }

  private getSearchSourceLabel(): string {
    const source = this.message.searchSource.trim()
    if (source === 'tool') {
      return '工具调用'
    }
    if (source === 'manual') {
      return '手动搜索'
    }
    // 兼容旧数据：没有持久化 searchSource 时，用是否存在 toolCalls 做推断
    return this.message.hasToolCalls() ? '工具调用' : '手动搜索'
  }

  private getSearchingIndicatorText(): string {
    const engine = this.message.searchEngine.trim()
    if (this.message.searchQuery !== '') {
      if (engine !== '') {
        return `我将为你通过${engine}查询：${this.message.searchQuery}`
      }
      return `我将为你查询：${this.message.searchQuery}`
    }
    if (engine !== '') {
      return `正在通过${engine}查询...`
    }
    return '正在查询...'
  }

  private handleCopy() {
    try {
      const copyContent = this.isSelectableTextMode ? getSelectableMarkdownPlainText(this.message.content) : this.message.content
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, copyContent)
      const systemPasteboard = pasteboard.getSystemPasteboard()
      systemPasteboard.setData(pasteboardData)
      showToast(this.getUIContext(), $r('app.string.copy_success'))
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Copy message failed: ${JSON.stringify(error)}`)
    }
  }

  // 复制指定文本到剪贴板（用于代码块复制）
  private copyToClipboard(text: string) {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      const systemPasteboard = pasteboard.getSystemPasteboard()
      systemPasteboard.setData(pasteboardData)
      showToast(this.getUIContext(), $r('app.string.copy_success'))
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Copy code failed: ${JSON.stringify(error)}`)
    }
  }
}
