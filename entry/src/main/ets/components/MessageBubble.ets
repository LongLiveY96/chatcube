import {
  ChatMessage,
  MessageRole,
  MessageAttachment,
  AttachmentType,
  ToolCall,
  ToolResult,
  SearchReference
} from '../models/ChatModels'
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in'
import { pasteboard } from '@kit.BasicServicesKit'
import { showToast } from '../utils/ToastUtil'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { getModelIconPath, buildIconResourcePath } from '../utils/ProviderIconUtils'
import { shouldShowAssistantMessageToolbar } from '../utils/MessageBubbleDisplayUtils'
import { AskUserCard } from './AskUserCard'
import { HtmlPreviewCard } from './HtmlPreviewCard'
import { MermaidPreviewCard } from './MermaidPreviewCard'
import { TypingDots } from './TypingDots'
import { AssistantAvatarView } from './AssistantAvatar'
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
import { isSearchToolFunctionName, isSearchToolId, isAskUserFunctionName, isScrapeWebFunctionName, isSearchWebFunctionName } from '../utils/SearchToolIdentityUtils'
import { MessagePart, MessagePartKind, ToolPartStatus } from '../models/MessageParts'
import {
  ensureMessageParts,
  groupMessageParts,
  MessagePartBlock,
  MessagePartBlockKind
} from '../utils/ChatMessagePartsHelper'
import { resolveToolSymbol } from '../utils/ToolIconMapping'
import { buildToolTitle } from '../utils/ToolTitleBuilder'
import { fingerprintLongString } from '../utils/MessageSignatureUtils'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'

const DOMAIN = 0x0002
const TAG = 'MessageBubble'

// 翻译目标语言配置
interface TranslateLanguage {
  code: string
  name: string
  nativeName: string
}

enum ContentSegmentType {
  MARKDOWN = 'markdown',
  HTML = 'html',
  MERMAID = 'mermaid'
}

// 内容分段（用于可预览代码块内联渲染）
interface ContentSegment {
  type: ContentSegmentType
  renderContent: string
}

interface ImageAttachmentEntry {
  attachment: MessageAttachment
  originalIndex: number
}

interface ToolSearchResultItemPayload {
  title?: string
  url?: string
  snippet?: string
}

interface ToolSearchResultPayload {
  query?: string
  searchEngine?: string
  results?: ToolSearchResultItemPayload[]
}

interface ToolSearchArgumentPayload {
  query?: string
  q?: string
  keyword?: string
  keywords?: string
}

interface AskUserTimelineQuestion {
  id: string
  question: string
  selectionType: string
}

interface AskUserTimelineAnswer {
  id: string
  question: string
  answer: string
  skipped: boolean
}

@ReusableV2
@ComponentV2
export struct MessageBubble {
  @Param message: ChatMessage = new ChatMessage('', MessageRole.USER, '')
  @Param renderSignature: string = ''
  @Param contentRenderSignature: string = ''
  @Param showHeader: boolean = true  // 是否显示消息头部（模型信息）
  @Param currentModelId: string = ''  // 当前会话的模型 ID（用于图标匹配回退）
  @Param assistantAvatarSymbol: string = 'AI'
  @Param assistantAvatarColor: string = '#4E6F9E'
  @Param assistantAvatarCacheKey: number = 0
  @Param themeRenderKey: string = ''
  @Param isMultiSelectMode: boolean = false  // 是否处于多选模式
  @Param isSelected: boolean = false  // 是否被选中
  @Param isEditing: boolean = false  // 是否处于编辑状态（被编辑的消息高亮显示）
  @Param previewContent: string = ''  // 编辑时的实时预览内容
  @Param previewAttachments: MessageAttachment[] = []  // 编辑时的实时预览附件
  @Local isReasoningExpanded: boolean = false  // 用户显式展开/折叠状态
  @Local reasoningElapsedMs: number = 0         // 流式中已思考毫秒数,驱动 UI 刷新
  @Local reasoningAutoPreview: boolean = false  // 流式中自动进入的预览态,用户切换后置 false
  @Local reasoningShimmerAlpha: number = 1.0    // shimmer 呼吸动画透明度
  // timeline 模式下: 每条 reasoning step 自己的展开/折叠状态用 key 列表跟踪;
  // - 包含 `${createdAt}` 表示用户手动展开
  // - 包含 `!${createdAt}` 表示用户手动折叠 (用于覆盖 active reasoning 的默认展开行为)
  // 未在列表中: 默认折叠, 但流式中正在思考的 active reasoning 仍默认展开
  @Local expandedReasoningKeys: string[] = []
  // timeline 工具 step 的展开状态; ask_user 已回答后默认收起到标题行。
  @Local expandedToolStepKeys: string[] = []
  @Local translatedText: string = ''  // 翻译结果
  @Local isTranslating: boolean = false  // 是否正在翻译
  @Local showTranslation: boolean = false  // 是否显示翻译结果
  @Local isTranslationExpanded: boolean = true  // 翻译结果是否展开
  @Local currentTranslateLang: string = ''  // 当前翻译的目标语言
  @Local showLatexPreview: boolean = false
  @Local latexPreviewPixelMap: image.PixelMap | null = null
  @Local latexPreviewScale: number = 1
  @Local latexPreviewLastScale: number = 1
  @Local latexPreviewOffsetX: number = 0
  @Local latexPreviewOffsetY: number = 0
  @Local latexPreviewLastOffsetX: number = 0
  @Local latexPreviewLastOffsetY: number = 0
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
  private get themePrimarySubtleBackground(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '28' : '16')
  }

  // 聊天字体大小
  @Param chatFontSize: number = 15

  // ========== Markdown 配置 ==========
  // MarkdownController 实例
  private markdownController: MarkdownController = new MarkdownController()
  private reasoningMarkdownController: MarkdownController = new MarkdownController()
  private translationMarkdownController: MarkdownController = new MarkdownController()
  private partMarkdownControllers: Map<string, MarkdownController> = new Map()
  private partMarkdownControllerTexts: Map<string, string> = new Map()
  private multiSelectTouchStartX: number = 0
  private multiSelectTouchStartY: number = 0
  private multiSelectTouchActive: boolean = false
  private static readonly MULTI_SELECT_TAP_THRESHOLD_VP: number = 8

  // ========== 流式渲染优化 ==========
  // lv-markdown-in 自带流式渲染，无需手动节流
  private boundMessageId: string = ''
  private translationRequestToken: number = 0
  // Reasoning 计时
  private reasoningStartAt: number = 0
  private reasoningFinalMs: number = 0
  private reasoningTimerId: number = -1
  private reasoningShimmerTimerId: number = -1
  private reasoningScroller: Scroller = new Scroller()
  private get speakingMessageId(): string {
    return getAppUiState().speakingMessageId
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
  private cachedHasPreviewSegments: boolean = false
  private cachedContentSegments: ContentSegment[] = []
  private cachedPreviewImageEntries: ImageAttachmentEntry[] = []
  private cachedMessageImageEntries: ImageAttachmentEntry[] = []
  private cachedMessageFileAttachments: MessageAttachment[] = []
  private cachedPreviewImageGridRows: number[] = []
  private cachedMessageImageGridRows: number[] = []
  private derivedCacheSignature: string = ''
  private finalizedMarkdownRenderTextCache: Map<string, string> = new Map()

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
  // ask_user 答复回调: 用户在 AskUserCard 点击提交后, 经此链路回到 ChatPage.handleAskUserAnswer
  @Event onAskUserAnswer: (toolCallId: string, answerJson: string) => void = () => {}

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
    this.syncReasoningRuntime()
  }

  aboutToDisappear(): void {
    this.stopReasoningTimer()
    this.stopReasoningShimmer()
  }

  // ReusableV2: 从复用池取出时回调, 此时 @Param 已经按官方文档"很可能在重赋值之后"调用,
  // 但保险起见显式置空 boundMessageId 让 syncMessageScopedState 一定走完整 reset 路径。
  // 翻译 controller、markdown 样式配置随实例保留无需重建, 显著节省 configureMarkdownStyles 的开销。
  aboutToReuse(): void {
    this.boundMessageId = ''
    this.syncMessageScopedState()
    this.syncDerivedRenderCaches()
    this.syncReasoningRuntime()
  }

  // ReusableV2: 进入复用池前回调, 停掉所有计时器避免在不可见的回收态继续刷帧
  aboutToRecycle(): void {
    this.stopReasoningTimer()
    this.stopReasoningShimmer()
  }

  // 消息状态变化回调（优化跳动点动画性能）
  @Monitor('message')
  onMessageStateChange(): void {
    this.syncMessageScopedState()
    this.syncDerivedRenderCaches()
    this.syncReasoningRuntime()
  }

  @Monitor('contentRenderSignature')
  onContentRenderSignatureChange(): void {
    this.syncMessageScopedState()
    this.syncDerivedRenderCaches()
    this.syncReasoningRuntime()
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
    this.reasoningAutoPreview = false
    this.reasoningElapsedMs = 0
    this.reasoningStartAt = 0
    this.reasoningFinalMs = 0
    this.reasoningShimmerAlpha = 1.0
    this.expandedReasoningKeys = []
    this.expandedToolStepKeys = []
    this.stopReasoningTimer()
    this.stopReasoningShimmer()
    this.translatedText = ''
    this.isTranslating = false
    this.showTranslation = false
    this.isTranslationExpanded = true
    this.currentTranslateLang = ''
    this.partMarkdownControllers.clear()
    this.partMarkdownControllerTexts.clear()
    this.finalizedMarkdownRenderTextCache.clear()
    // latex 预览状态: 切换消息时若上一条打开过预览, 必须复位避免新消息加载旧 pixelMap
    this.showLatexPreview = false
    this.latexPreviewPixelMap = null
    this.latexPreviewScale = 1
    this.latexPreviewLastScale = 1
    this.latexPreviewOffsetX = 0
    this.latexPreviewOffsetY = 0
    this.latexPreviewLastOffsetX = 0
    this.latexPreviewLastOffsetY = 0
    // 派生缓存指纹失效, 下一次 ensureDerivedRenderCaches 会重算
    this.derivedCacheSignature = ''
  }

  // 流式拿到第一段 reasoning 时启动定时器,每 120ms 刷新已思考时长,驱动 UI 计数和 shimmer
  private startReasoningTimer(): void {
    if (this.reasoningTimerId !== -1) {
      return
    }
    this.reasoningStartAt = Date.now()
    this.reasoningElapsedMs = 0
    this.reasoningTimerId = setInterval(() => {
      this.reasoningElapsedMs = Date.now() - this.reasoningStartAt
    }, 120)
  }

  private stopReasoningTimer(): void {
    if (this.reasoningTimerId === -1) {
      return
    }
    clearInterval(this.reasoningTimerId)
    this.reasoningTimerId = -1
    if (this.reasoningStartAt > 0) {
      this.reasoningFinalMs = Date.now() - this.reasoningStartAt
    }
  }

  private startReasoningShimmer(): void {
    if (this.reasoningShimmerTimerId !== -1) {
      return
    }
    let high = false
    this.reasoningShimmerTimerId = setInterval(() => {
      high = !high
      this.getUIContext().animateTo({ duration: 700, curve: Curve.EaseInOut }, () => {
        this.reasoningShimmerAlpha = high ? 0.55 : 1.0
      })
    }, 700)
  }

  private stopReasoningShimmer(): void {
    if (this.reasoningShimmerTimerId !== -1) {
      clearInterval(this.reasoningShimmerTimerId)
      this.reasoningShimmerTimerId = -1
    }
    this.reasoningShimmerAlpha = 1.0
  }

  // 根据消息当前状态驱动 reasoning 计时器/shimmer/自动预览的开关
  private syncReasoningRuntime(): void {
    const isGenerating = this.message.isGenerating
    const hasReasoning = this.message.reasoningContent.length > 0
    const usesPartsTimeline = this.shouldRenderPartsTimeline()
    if (isGenerating && hasReasoning) {
      if (this.reasoningTimerId === -1) {
        this.startReasoningTimer()
      }
      if (usesPartsTimeline) {
        this.stopReasoningShimmer()
        this.reasoningAutoPreview = false
        return
      }
      if (this.reasoningShimmerTimerId === -1) {
        this.startReasoningShimmer()
      }
      // 用户没主动操作时,流式中默认进入预览态
      if (!this.isReasoningExpanded && !this.reasoningAutoPreview) {
        this.reasoningAutoPreview = true
      }
      // 流式中滚动到思考内容底部,跟随最新输出
      if (this.reasoningAutoPreview) {
        this.reasoningScroller.scrollEdge(Edge.Bottom)
      }
    } else {
      this.stopReasoningTimer()
      this.stopReasoningShimmer()
      if (!isGenerating) {
        // 生成结束自动收起 preview,让用户看到完整对话内容
        this.reasoningAutoPreview = false
      }
    }
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
      fingerprintLongString(this.message.content),
      fingerprintLongString(this.message.reasoningContent),
      this.message.isGenerating ? '1' : '0',
      this.message.isSearching ? '1' : '0',
      this.currentModelId,
      this.isEditing ? '1' : '0',
      fingerprintLongString(this.previewContent),
      fingerprintLongString(this.translatedText),
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
    this.cachedReadonlyMessageContent = this.getMarkdownRenderText(this.message.content)
    this.cachedReadonlyReasoningContent = this.getMarkdownRenderText(this.message.reasoningContent)
    this.cachedReadonlyTranslatedText = this.convertTaskListToReadonly(this.translatedText)
    this.cachedHasPreviewSegments = !this.message.isGenerating && this.hasPreviewableCodeBlocks(this.message.content)
    this.cachedContentSegments = this.cachedHasPreviewSegments ? this.splitContentToSegments(this.message.content) : []
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
      .setImageClickListener((src: string): boolean => {
        return this.openImagePreviewForMarkdownSource(src, this.message.content)
      })
      .setLatexClickListener((_text: string, pixelMap: image.PixelMap): boolean => {
        this.latexPreviewPixelMap = pixelMap
        this.showLatexPreview = true
        return true
      })
      .setCodeCopyListener((code: string) => {
        this.copyToClipboard(code)
      })
      .setTextSelectionEnable(true)
      .setTextSelectionCopyListener((text: string) => {
        this.copyToClipboard(text)
      })
    markdownController.setBlockSpacing(mainBlockSpacing)

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
      .setImageClickListener((src: string): boolean => {
        return this.openImagePreviewForMarkdownSource(src, this.message.reasoningContent)
      })
      .setLatexClickListener((_text: string, pixelMap: image.PixelMap): boolean => {
        this.latexPreviewPixelMap = pixelMap
        this.showLatexPreview = true
        return true
      })
      .setCodeCopyListener((code: string) => {
        this.copyToClipboard(code)
      })
    reasoningMarkdownController.setBlockSpacing(compactBlockSpacing)

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
      .setImageClickListener((src: string): boolean => {
        return this.openImagePreviewForMarkdownSource(src, this.translatedText)
      })
      .setLatexClickListener((_text: string, pixelMap: image.PixelMap): boolean => {
        this.latexPreviewPixelMap = pixelMap
        this.showLatexPreview = true
        return true
      })
      .setCodeCopyListener((code: string) => {
        this.copyToClipboard(code)
      })
    translationMarkdownController.setBlockSpacing(compactBlockSpacing)
    this.configurePartMarkdownControllers()
  }

  private configurePartMarkdownController(controller: MarkdownController): void {
    const uiState = getAppUiState()
    const titleColor = uiState.themeMarkdownTitle
    const textColor = uiState.themeMarkdownText
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
    const latexTextColor = this.isDarkMode ? 0xFFE0E0E0 : 0xFF333333
    const fs = this.chatFontSize
    const mainTextSize = fs - 1
    const mainTitleSizes = getMarkdownTitleSizes(mainTextSize)

    controller
      .setTitleColor(titleColor)
      .setTextColor(textColor)
      .setTextSize(mainTextSize)
      .setTextLineHeight(getMarkdownTextLineHeight(mainTextSize))
      .setTitleSize(mainTitleSizes)
      .setTitleLineHeight(getMarkdownTitleLineHeights(mainTitleSizes))
      .setQuoteBackgroundColor(quoteBgColor)
      .setQuoteBorderColor(linkColor)
      .setQuotePadding(getMarkdownQuotePadding(mainTextSize))
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
      .setImageClickListener((src: string): boolean => {
        return this.openImagePreviewForMarkdownSource(src, this.message.content)
      })
      .setLatexClickListener((_text: string, pixelMap: image.PixelMap): boolean => {
        this.latexPreviewPixelMap = pixelMap
        this.showLatexPreview = true
        return true
      })
      .setCodeCopyListener((code: string) => {
        this.copyToClipboard(code)
      })
      .setTextSelectionEnable(true)
      .setTextSelectionCopyListener((text: string) => {
        this.copyToClipboard(text)
      })
    controller.setBlockSpacing(getMarkdownBlockSpacing(mainTextSize))
  }

  private configurePartMarkdownControllers(): void {
    this.partMarkdownControllers.forEach((controller: MarkdownController) => {
      this.configurePartMarkdownController(controller)
    })
  }

  private getPartMarkdownController(
    blockIndex: number,
    partIndex: number,
    segmentIndex: number,
    content: string
  ): MarkdownController {
    const key = this.message.id + '_' + blockIndex.toString() + '_' + partIndex.toString() + '_' + segmentIndex.toString()
    let controller = this.partMarkdownControllers.get(key)
    const previousText = this.partMarkdownControllerTexts.get(key)
    if (controller === undefined || previousText !== content) {
      controller = new MarkdownController()
      this.configurePartMarkdownController(controller)
      this.partMarkdownControllers.set(key, controller)
      this.partMarkdownControllerTexts.set(key, content)
    }
    return controller
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
    // 入退场动画: 仅 opacity, 不再用方向性 translate。
    // 原因: transition 是组件级, LazyForEach 复用未启用时, 滚出 cachedCount 后再
    // 回到视野会重新构造组件并重播该动画, 让用户误以为"消息重新加载"。
    // 缩到 150ms + 去掉 translate 让 GPU 走 compositor-only, 减少叠加可见性。
    // 真正消除重建开销需要给 MessageBubble 加 @Reusable, 后续单独 PoC。
    .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
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
    return /```html?\s*\n[\s\S]*?```/i.test(content)
  }

  private hasMermaidBlocks(content: string): boolean {
    return /```mermaid\s*\n[\s\S]*?```/i.test(content)
  }

  private hasPreviewableCodeBlocks(content: string): boolean {
    return this.hasHtmlBlocks(content) || this.hasMermaidBlocks(content)
  }

  private normalizeMarkdownImageSource(src: string): string {
    let normalized = src.trim()
    if (normalized.startsWith('<') && normalized.endsWith('>')) {
      normalized = normalized.substring(1, normalized.length - 1).trim()
    }
    return normalized
  }

  private collectMarkdownImageSources(content: string): Array<string> {
    const images: Array<string> = []
    if (content.trim().length === 0) {
      return images
    }

    const markdownText = content.replace(/```[\s\S]*?```/g, '')
    const pattern = /!\[[^\]]*]\(\s*(<[^>]+>|[^\s)]+)(?:\s+["'][^"']*["'])?\s*\)/g
    let match = pattern.exec(markdownText)
    while (match !== null) {
      const src = this.normalizeMarkdownImageSource(match[1])
      if (src.length > 0) {
        images.push(src)
      }
      match = pattern.exec(markdownText)
    }
    return images
  }

  private openImagePreviewForMarkdownSource(src: string, content: string): boolean {
    const imageSrc = this.normalizeMarkdownImageSource(src)
    if (imageSrc.length === 0) {
      return false
    }

    let images = this.collectMarkdownImageSources(content)
    let imageIndex = images.indexOf(imageSrc)
    if (imageIndex < 0) {
      images = [imageSrc]
      imageIndex = 0
    }

    this.onImageClick(images, imageIndex)
    return true
  }

  // 将内容按可预览代码块边界分段，用于内联预览渲染
  private splitContentToSegments(content: string): ContentSegment[] {
    const segments: ContentSegment[] = []
    const pattern = /```(html?|mermaid)\s*\n([\s\S]*?)```/gi
    let lastIndex = 0
    let match = pattern.exec(content)

    while (match !== null) {
      const matchIndex = match.index
      // 添加可预览代码块之前的文本段
      if (matchIndex > lastIndex) {
        const textContent = content.substring(lastIndex, matchIndex)
        if (textContent.trim().length > 0) {
          segments.push({
            type: ContentSegmentType.MARKDOWN,
            renderContent: this.convertTaskListToReadonly(textContent)
          } as ContentSegment)
        }
      }
      const segmentType = match[1].toLowerCase() === 'mermaid' ? ContentSegmentType.MERMAID : ContentSegmentType.HTML
      segments.push({ type: segmentType, renderContent: match[2] } as ContentSegment)
      lastIndex = matchIndex + match[0].length
      match = pattern.exec(content)
    }

    // 添加最后一个可预览代码块之后的剩余文本
    if (lastIndex < content.length) {
      const remaining = content.substring(lastIndex)
      if (remaining.trim().length > 0) {
        segments.push({
          type: ContentSegmentType.MARKDOWN,
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

  private hasPreviewSegments(): boolean {
    this.ensureDerivedRenderCaches()
    return this.cachedHasPreviewSegments
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

  private isMarkdownOutputFinalized(): boolean {
    // 手动停止会把 isGenerating 置为 false；只要不再吐字，就进入最终态规范化。
    return !this.message.isGenerating
  }

  private getMarkdownRenderText(content: string): string {
    if (!this.isMarkdownOutputFinalized()) {
      return content
    }
    const cachedText = this.finalizedMarkdownRenderTextCache.get(content)
    if (cachedText !== undefined) {
      return cachedText
    }
    const renderText = this.convertTaskListToReadonly(content)
    this.finalizedMarkdownRenderTextCache.set(content, renderText)
    return renderText
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
            // 助手头像
            Column() {
              AssistantAvatarView({
                value: this.assistantAvatarSymbol,
                color: this.assistantAvatarColor,
                avatarSize: 30,
                radius: 8,
                fontSize: 14,
                cacheKey: this.assistantAvatarCacheKey,
                modelId: this.message.modelId !== '' ? this.message.modelId : this.currentModelId,
                modelName: this.message.modelName
              })
            }
            .width(30)
            .height(30)
            .borderRadius(8)
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
            if (this.shouldRenderParts()) {
              // 新版统一渲染: 按 parts 的真实生成顺序渲染 text / reasoning / tool,
              // 跳过原本的聚合正文、ToolCallCard 列表和 ReasoningSection, 避免顺序错乱或重复渲染
              this.OrderedPartsTimeline()
              // ask_user 待答时保留独立交互卡片;提交后收缩到 timeline step 内。
              if (this.message.hasToolCalls()) {
                ForEach(this.message.toolCalls, (toolCall: ToolCall, index: number) => {
                  if (this.shouldRenderAskUserInteractionCard(toolCall, index)) {
                    AskUserCard({
                      toolCall: toolCall,
                      isAnswered: false,
                      answeredPayload: toolCall.approvalReason,
                      onAnswer: (toolCallId: string, answerJson: string): void => {
                        this.onAskUserAnswer(toolCallId, answerJson)
                      }
                    })
                      .margin({ bottom: 6 })
                  }
                }, (toolCall: ToolCall, index: number) => 'ask_' + toolCall.id + '_' + index.toString())
              }
            }

            // ========== 附件区域（AI 生成的图片） ==========
            if (this.message.hasAttachments()) {
              this.AssistantAttachments()
            }

            // ========== 加载状态（parts 为空且正在生成时） ==========
            if (this.message.parts.length === 0 && (this.message.isGenerating || this.message.isSearching)) {
              if (this.message.isSearching) {
                this.SearchingIndicatorInline()
              } else {
                this.TypingIndicator()
              }
            }

            // ========== 翻译结果区域（嵌入式可折叠卡片） ==========
            if (this.showTranslation) {
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
          if (this.shouldShowAssistantToolbar()) {
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
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(this.isMultiSelectMode && this.isSelected
            ? this.themePrimaryLight
            : this.themeAiBubble)
          .borderRadius(16)
          .border({
            width: this.isMultiSelectMode && this.isSelected ? 1.2 : 0.5,
            color: this.isMultiSelectMode && this.isSelected ? this.themePrimary : $r('app.color.bubble_border')
          })
          .clip(true)
      }
      .enabled(!this.isMultiSelectMode)
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(VerticalAlign.Top)
    .onTouch((event: TouchEvent) => {
      this.handleMultiSelectTouch(event)
    })
    .bindSheet($$this.showLatexPreview, this.LatexPreviewSheetBuilder(), {
      height: SheetSize.MEDIUM,
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      showClose: true,
      title: { title: 'LaTeX' },
      onDisappear: () => {
        this.latexPreviewPixelMap = null
        this.latexPreviewScale = 1
        this.latexPreviewLastScale = 1
        this.latexPreviewOffsetX = 0
        this.latexPreviewOffsetY = 0
        this.latexPreviewLastOffsetX = 0
        this.latexPreviewLastOffsetY = 0
      }
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

  // assistant 消息统一优先走 parts 渲染;旧字段只作为迁移来源和极端空数据兜底。
	  private shouldRenderPartsTimeline(): boolean {
    if (this.message.role === MessageRole.ASSISTANT) {
      ensureMessageParts(this.message)
    }
	    if (this.message.parts.length === 0) {
	      return false
	    }
    for (let i = 0; i < this.message.parts.length; i++) {
      const kind = this.message.parts[i].kind
      if (kind === MessagePartKind.REASONING || kind === MessagePartKind.TOOL) {
        return true
      }
    }
	    return false
	  }

  private shouldRenderParts(): boolean {
    if (this.message.role === MessageRole.ASSISTANT) {
      ensureMessageParts(this.message)
    }
    return this.message.parts.length > 0
  }

	  private getOrderedMessagePartBlocks(): MessagePartBlock[] {
    if (this.message.role === MessageRole.ASSISTANT) {
      ensureMessageParts(this.message)
    }
	    return groupMessageParts(this.message.parts)
	  }

	  private getRenderableThinkingSteps(parts: MessagePart[]): MessagePart[] {
	    const steps: MessagePart[] = []
	    for (let i = 0; i < parts.length; i++) {
	      const p = parts[i]
	      // 过滤空 reasoning: 流式期间偶尔会 push 内容为空的 reasoning part(边界重置),
	      // 折叠视图里显示两条 "思考中" 且没有正文会特别奇怪, 直接剔除
	      if (p.kind === MessagePartKind.REASONING) {
	        if (p.text.length > 0) {
	          steps.push(p)
	        }
	        continue
	      }
	      if (p.kind === MessagePartKind.TOOL) {
	        steps.push(p)
	      }
	    }
	    return steps
	  }

	  private getThinkingSteps(): MessagePart[] {
	    return this.getRenderableThinkingSteps(this.message.parts)
	  }

  // 判定某个 reasoning part 是否处于 "仍在思考中": 消息还在生成 + 该 part 是 parts 里最后一个 reasoning
  // 且其后没有任何 reasoning/tool/text part (即确实是当前正在输出的那段 reasoning)
  private isActiveReasoningPart(part: MessagePart): boolean {
    if (!this.message.isGenerating) {
      return false
    }
    if (part.kind !== MessagePartKind.REASONING) {
      return false
    }
    // 该 part 之后若还有其它 part (工具调用、文本、甚至另一段 reasoning), 说明这段已经结束
    for (let i = 0; i < this.message.parts.length; i++) {
      if (this.message.parts[i] !== part) {
        continue
      }
      return i === this.message.parts.length - 1
    }
    return false
  }

  // ===== Timeline 主题色 helper =====
  // timeline 块底色跟随当前 AI 气泡主题, 避免在自定义主题下出现固定色污染。
  private getTimelineBackgroundColor(): string {
    return this.themeAiBubble
  }
  // 竖线和图标遮罩 — 竖线要在底色上可见, 图标遮罩要和底色同色才能遮住竖线
  private getTimelineRailColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '88' : '55')
  }

  // ===== reasoning step 独立折叠状态 =====
  private getReasoningKey(part: MessagePart): string {
    return `r_${part.reasoningCreatedAt}`
  }

  private isReasoningStepExpanded(part: MessagePart): boolean {
    const key = this.getReasoningKey(part)
    const collapsedKey = `!${key}`
    if (this.expandedReasoningKeys.includes(collapsedKey)) {
      return false
    }
    if (this.expandedReasoningKeys.includes(key)) {
      return true
    }
    // 正在输出的 reasoning 展示完整正文;生成结束后默认收起,避免深度思考长文本外露。
    if (this.isActiveReasoningPart(part)) {
      return true
    }
    return false
  }

  private toggleReasoningStep(part: MessagePart): void {
    const key = this.getReasoningKey(part)
    const wasExpanded = this.isReasoningStepExpanded(part)
    const next: string[] = []
    for (let i = 0; i < this.expandedReasoningKeys.length; i++) {
      const k = this.expandedReasoningKeys[i]
      if (k !== key && k !== `!${key}`) {
        next.push(k)
      }
    }
    if (wasExpanded) {
      next.push(`!${key}`)
    } else {
      next.push(key)
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
      this.expandedReasoningKeys = next
    })
  }

  // timeline 标题只保留状态,不展示每段耗时和字数。
  private buildReasoningStepLabel(part: MessagePart): string {
    return this.isActiveReasoningPart(part) ? '深度思考中' : '深度思考'
  }

  // ===== tool step 点击行为 =====
  // 优先级:
  //  1. 抓取类 (scrape_web 等) → 直接 onOpenLink 打开 URL, 不弹中间 sheet
  //  2. 搜索类 (search_web 等) 且成功 → 弹 sheet 列本次引用
  //  3. 老消息: 仅当整条消息只有一个成功搜索 step 时,才允许降级用聚合 message.searchReferences
  //  4. 其它工具但 toolArguments 能解析出 url → 直接 onOpenLink
  //  5. 其它 → 不可点击
  private isToolStepClickable(part: MessagePart): boolean {
    if (isAskUserFunctionName(part.toolName)) {
      return false
    }
    if (isScrapeWebFunctionName(part.toolName)) {
      // 抓取类只要能取到 url 就可点
      return this.extractToolStepUrl(part) !== '' || this.firstRefUrl(part) !== ''
    }
    if (isSearchWebFunctionName(part.toolName)) {
      if (!this.isSuccessfulToolStep(part)) {
        return false
      }
      return this.resolveToolStepSearchReferences(part).length > 0
    }
    return this.extractToolStepUrl(part) !== ''
  }

  private isSuccessfulToolStep(part: MessagePart): boolean {
    return part.toolStatus === ToolPartStatus.SUCCEEDED && !part.toolIsError
  }

  private getToolStepKey(part: MessagePart): string {
    return part.toolCallId !== '' ? `tool_${part.toolCallId}` : `tool_${part.toolName}_${part.toolArguments.length}`
  }

  private isToolStepExpanded(part: MessagePart): boolean {
    return this.expandedToolStepKeys.includes(this.getToolStepKey(part))
  }

  private toggleToolStep(part: MessagePart): void {
    const key = this.getToolStepKey(part)
    const next: string[] = []
    let found = false
    for (let i = 0; i < this.expandedToolStepKeys.length; i++) {
      if (this.expandedToolStepKeys[i] === key) {
        found = true
        continue
      }
      next.push(this.expandedToolStepKeys[i])
    }
    if (!found) {
      next.push(key)
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
      this.expandedToolStepKeys = next
    })
  }

  private findToolResultForCall(toolCallId: string): ToolResult | null {
    for (let i = 0; i < this.message.toolResults.length; i++) {
      if (this.message.toolResults[i].toolCallId === toolCallId) {
        return this.message.toolResults[i]
      }
    }
    return null
  }

  private isAskUserToolCallAnswered(toolCall: ToolCall, index: number): boolean {
    if (toolCall.approvalState === 'answered') {
      return true
    }
    if (this.findToolResultForCall(toolCall.id) !== null) {
      return true
    }
    return index < this.message.toolResults.length
  }

  private shouldRenderAskUserInteractionCard(toolCall: ToolCall, index: number): boolean {
    if (!isAskUserFunctionName(toolCall.functionName) || this.shouldHideToolCallCard(toolCall)) {
      return false
    }
    return !this.isAskUserToolCallAnswered(toolCall, index)
  }

  private parseAskUserQuestions(raw: string): AskUserTimelineQuestion[] {
    const questions: AskUserTimelineQuestion[] = []
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>
      const rawQuestions = parsed.questions
      if (!Array.isArray(rawQuestions)) {
        return questions
      }
      const list = rawQuestions as Object[]
      for (let i = 0; i < list.length; i++) {
        const item = list[i] as Record<string, Object>
        if (item === null || item === undefined) {
          continue
        }
        const idValue = item.id
        const questionValue = item.question
        const typeValue = item.selection_type
        questions.push({
          id: typeof idValue === 'string' && idValue.trim() !== '' ? idValue : `q_${i}`,
          question: typeof questionValue === 'string' ? questionValue : '',
          selectionType: typeof typeValue === 'string' ? typeValue : 'text'
        })
      }
    } catch (_e) {
    }
    return questions
  }

  private readAskUserAnswerValue(value: Object | undefined): string {
    if (value === undefined || value === null) {
      return ''
    }
    if (typeof value === 'string') {
      return value.trim()
    }
    const record = value as Record<string, Object>
    const answer = record.answer
    if (typeof answer === 'string') {
      return answer.trim()
    }
    const customAnswer = record.custom_answer
    if (typeof customAnswer === 'string') {
      return customAnswer.trim()
    }
    const selectedOptions = record.selected_options
    if (Array.isArray(selectedOptions)) {
      const parts: string[] = []
      const selectedOptionList = selectedOptions as string[]
      for (let i = 0; i < selectedOptionList.length; i++) {
        const selected: string = selectedOptionList[i]
        if (typeof selected === 'string' && selected.trim() !== '') {
          parts.push(selected.trim())
        }
      }
      return parts.join(', ')
    }
    return ''
  }

  private isAskUserAnswerSkipped(value: Object | undefined, answer: string): boolean {
    if (value === undefined || value === null) {
      return answer === ''
    }
    if (typeof value === 'string') {
      return answer === ''
    }
    const record = value as Record<string, Object>
    const skipped = record.skipped
    return typeof skipped === 'boolean' ? skipped : answer === ''
  }

  private buildAskUserAnswerViews(part: MessagePart): AskUserTimelineAnswer[] {
    const questions = this.parseAskUserQuestions(part.toolArguments)
    const items: AskUserTimelineAnswer[] = []
    let answersRecord: Record<string, Object> | null = null
    try {
      const parsed = JSON.parse(part.toolResult.trim()) as Record<string, Object>
      const answers = parsed.answers
      if (answers !== undefined && answers !== null) {
        answersRecord = answers as Record<string, Object>
      }
    } catch (_e) {
    }

    if (questions.length > 0) {
      for (let i = 0; i < questions.length; i++) {
        const q = questions[i]
        const value = answersRecord !== null ? answersRecord[q.id] : undefined
        const answer = this.readAskUserAnswerValue(value)
        items.push({
          id: q.id,
          question: q.question,
          answer: answer,
          skipped: this.isAskUserAnswerSkipped(value, answer)
        })
      }
      return items
    }

    if (answersRecord !== null) {
      const keys = Object.keys(answersRecord)
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i]
        const value = answersRecord[key]
        const answer = this.readAskUserAnswerValue(value)
        items.push({
          id: key,
          question: key,
          answer: answer,
          skipped: this.isAskUserAnswerSkipped(value, answer)
        })
      }
    }
    return items
  }

  private hasAskUserStepContent(part: MessagePart): boolean {
    return this.parseAskUserQuestions(part.toolArguments).length > 0 || this.buildAskUserAnswerViews(part).length > 0
  }

  private isAskUserStepAnswered(part: MessagePart): boolean {
    return part.toolStatus === ToolPartStatus.ANSWERED ||
      (part.toolStatus === ToolPartStatus.SUCCEEDED && part.toolResult.trim() !== '')
  }

  private buildAskUserStepStatusText(part: MessagePart): string {
    if (!this.isAskUserStepAnswered(part)) {
      return '待回答'
    }
    const items = this.buildAskUserAnswerViews(part)
    let answered = 0
    let skipped = 0
    for (let i = 0; i < items.length; i++) {
      if (items[i].answer !== '') {
        answered++
      } else {
        skipped++
      }
    }
    if (answered === 0) {
      return '已跳过'
    }
    if (skipped > 0) {
      return `已回答 ${answered}`
    }
    return '已回答'
  }

  private countSuccessfulSearchToolSteps(): number {
    let count = 0
    for (let i = 0; i < this.message.parts.length; i++) {
      const p = this.message.parts[i]
      if (p.kind === MessagePartKind.TOOL && isSearchWebFunctionName(p.toolName) && this.isSuccessfulToolStep(p)) {
        count += 1
      }
    }
    return count
  }

  private canUseAggregateSearchReferencesForToolStep(part: MessagePart): boolean {
    if (!this.isSuccessfulToolStep(part) || this.message.searchReferences.length === 0) {
      return false
    }
    // 这是老消息兜底:新消息应使用 toolSearchReferences 或 toolResult 精确切片。
    // 多个搜索 step 时聚合列表无法证明属于当前 step,不能拿来展示,否则失败/空结果会串到别的搜索结果。
    return this.countSuccessfulSearchToolSteps() === 1
  }

  private buildSearchReferencesFromToolResult(part: MessagePart): SearchReference[] {
    const raw = part.toolResult.trim()
    if (raw === '') {
      return []
    }
    try {
      const parsed = JSON.parse(raw) as ToolSearchResultPayload
      if (!Array.isArray(parsed.results)) {
        return []
      }
      const refs: SearchReference[] = []
      for (let i = 0; i < parsed.results.length; i++) {
        const item = parsed.results[i]
        const title = typeof item.title === 'string' ? item.title : ''
        const url = typeof item.url === 'string' ? item.url : ''
        const snippet = typeof item.snippet === 'string' ? item.snippet : ''
        if (url.trim() === '' && title.trim() === '' && snippet.trim() === '') {
          continue
        }
        refs.push(new SearchReference(`tool_ref_${part.toolCallId}_${i}`, title, url, snippet))
      }
      return refs
    } catch (_e) {
      return []
    }
  }

  private resolveToolStepSearchReferences(part: MessagePart): SearchReference[] {
    if (!isSearchWebFunctionName(part.toolName) || !this.isSuccessfulToolStep(part)) {
      return []
    }
    if (part.toolSearchReferences.length > 0) {
      return part.toolSearchReferences
    }
    const refsFromResult = this.buildSearchReferencesFromToolResult(part)
    if (refsFromResult.length > 0) {
      return refsFromResult
    }
    if (this.canUseAggregateSearchReferencesForToolStep(part)) {
      return this.message.searchReferences
    }
    return []
  }

  private extractToolStepSearchQuery(part: MessagePart): string {
    try {
      const result = JSON.parse(part.toolResult.trim()) as ToolSearchResultPayload
      if (typeof result.query === 'string' && result.query.trim() !== '') {
        return result.query.trim()
      }
    } catch (_e) {
    }
    try {
      const args = JSON.parse(part.toolArguments.trim()) as ToolSearchArgumentPayload
      const candidate = args.query ?? args.q ?? args.keyword ?? args.keywords
      if (typeof candidate === 'string' && candidate.trim() !== '') {
        return candidate.trim()
      }
    } catch (_e) {
    }
    return this.extractSearchQuery()
  }

  private firstRefUrl(part: MessagePart): string {
    if (part.toolSearchReferences.length > 0 && part.toolSearchReferences[0].url.trim() !== '') {
      return part.toolSearchReferences[0].url.trim()
    }
    return ''
  }

  // 尝试从 toolArguments 里取一个 url 字段(抓取类工具通常都是 {"url": "..."} 或 {"urls": [...]}  )
  private extractToolStepUrl(part: MessagePart): string {
    const raw = part.toolArguments.trim()
    if (raw === '' || raw === '{}') {
      return ''
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>
      const candidate = parsed.url ?? parsed.URL ?? parsed.link
      if (typeof candidate === 'string' && candidate.trim() !== '') {
        return candidate.trim()
      }
      const urls = parsed.urls
      if (Array.isArray(urls) && urls.length > 0 && typeof urls[0] === 'string') {
        return (urls[0] as string).trim()
      }
    } catch (_e) {
      return ''
    }
    return ''
  }

  private handleToolStepClick(part: MessagePart): void {
    // 抓取类: 直接打开 URL
    if (isScrapeWebFunctionName(part.toolName)) {
      const url = this.extractToolStepUrl(part) !== '' ? this.extractToolStepUrl(part) : this.firstRefUrl(part)
      if (url !== '') {
        this.onOpenLink(this.buildToolStepTitle(part), url)
      }
      return
    }
    // 其它工具: 参数里有 url 就直接打开
    const url = this.extractToolStepUrl(part)
    if (url !== '') {
      this.onOpenLink(this.buildToolStepTitle(part), url)
    }
  }

	  @Builder
	  OrderedPartsTimeline() {
	    Column() {
	      ForEach(this.getOrderedMessagePartBlocks(), (block: MessagePartBlock, index: number) => {
	        if (block.kind === MessagePartBlockKind.THINKING) {
	          this.PartsTimelineBlock(this.getRenderableThinkingSteps(block.parts))
	        } else {
	          this.PartsContentBlock(block, index)
	        }
	      }, (block: MessagePartBlock, index: number) => {
	        // 必须把 block.parts.length 拼进 key, 否则 push 新 part (新 reasoning / 新 tool) 时,
	        // blocks 数组结构通常仍是 [THINKING] 或 [THINKING, CONTENT], index 不变, 老 key 'thinking_0' 不变,
	        // ForEach 会复用旧 PartsTimelineBlock 不重新调用, 内部 steps 静止 → 第一轮 reasoning 完成后 UI 卡死。
	        // V2 在 ForEach itemArray 引用变化但 key 不变时不会重建子组件, 必须 key 变化触发重建。
	        return block.kind + '_' + index.toString() + '_' + block.parts.length.toString()
	      })
	    }
	    .width('100%')
	  }

	  @Builder
	  PartsContentBlock(block: MessagePartBlock, blockIndex: number) {
	    Column() {
	      ForEach(block.parts, (part: MessagePart, index: number) => {
	        if (part.kind === MessagePartKind.TEXT) {
	          this.PartTextContent(part, blockIndex, index)
	        }
	      }, (part: MessagePart, index: number) => {
	        return part.kind + '_' + blockIndex.toString() + '_' + index.toString()
	      })
	    }
	    .width('100%')
	    .margin({ bottom: 8 })
	  }

	  // 注意: 必须接收整个 MessagePart 对象 (而非 part.text 字符串), 内部直接访问 part.text。
	  // MessagePart 是 @ObservedV2 + @Trace text, 只有在 Builder 内访问 part.text 才能让
	  // Markdown 的 text 属性建立响应式依赖, 流式增量 (pushPartText 中 last.text += delta) 才会实时刷新。
	  // 若把 part.text 在父 Builder 内提取成 string 再传入, 依赖会在参数边界处断链, 表现为正文不实时渲染。
	  @Builder
	  PartTextContent(part: MessagePart, blockIndex: number, partIndex: number) {
	    Column() {
	      if (part.text.trim() !== '') {
	        if (!this.message.isGenerating && this.hasPreviewableCodeBlocks(part.text)) {
	          ForEach(this.splitContentToSegments(part.text),
	            (segment: ContentSegment, index: number) => {
	              if (segment.type === ContentSegmentType.HTML) {
	                HtmlPreviewCard({
	                  htmlCode: segment.renderContent,
	                  onCopyCode: (code: string) => {
	                    this.copyToClipboard(code)
	                    showToast(this.getUIContext(), $r('app.string.copy_success'))
	                  }
	                })
	              } else if (segment.type === ContentSegmentType.MERMAID) {
	                MermaidPreviewCard({
	                  mermaidCode: segment.renderContent,
	                  onCopyCode: (code: string) => {
	                    this.copyToClipboard(code)
	                    showToast(this.getUIContext(), $r('app.string.copy_success'))
	                  }
	                })
	              } else {
	                Markdown({
	                  controller: this.getPartMarkdownController(blockIndex, partIndex, index, segment.renderContent),
	                  text: segment.renderContent
	                })
	                  .width('100%')
	                  .backgroundColor(Color.Transparent)
	              }
	            },
	            (segment: ContentSegment, index: number) => {
	              return 'part_segment_' + blockIndex.toString() + '_' + partIndex.toString() + '_' +
	                segment.type + '_' + index.toString()
	            }
	          )
	        } else {
	          Markdown({
	            controller: this.getPartMarkdownController(blockIndex, partIndex, -1, this.getMarkdownRenderText(part.text)),
	            text: this.getMarkdownRenderText(part.text)
	          })
	            .width('100%')
	            .backgroundColor(Color.Transparent)
	            .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
	        }
	      }
	    }
	    .width('100%')
	  }

	  // 交错 thinking 的时间线视图: 左侧竖线 + 依次渲染 reasoning / tool 步骤。
	  // 为了最小改动,这里不复用 ChainOfThought 组件,直接在 MessageBubble 里内联 Row/Column。
	  @Builder
	  PartsTimeline() {
	    this.PartsTimelineBlock(this.getThinkingSteps())
	  }

	  @Builder
	  PartsTimelineBlock(steps: MessagePart[]) {
	    Column() {
	      Stack({ alignContent: Alignment.TopStart }) {
	        // 竖线 (主题色 alpha, 在 timeline 底色上可见)
	        Column() {
	          ForEach(steps, (step: MessagePart, index: number) => {
	            this.TimelineStepRow(step, index < steps.length - 1)
	          }, (step: MessagePart, index: number) => {
	            return step.kind === MessagePartKind.TOOL
	              ? `tool_${step.toolCallId}_${index}`
              : `reasoning_${step.reasoningCreatedAt}_${index}`
          })
        }
        .width('100%')
      }
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.getTimelineBackgroundColor())
    .borderRadius(12)
    .border({ width: 0.5, color: this.getTimelineRailColor() })
    .margin({ bottom: 8 })
  }

  // 单条 timeline step 行: 左图标 + 右内容
  @Builder
  TimelineStepRow(step: MessagePart, hasNextStep: boolean) {
    Row({ space: 10 }) {
      Column() {
        Stack() {
          Column()
            .width(22)
            .height(22)
            .borderRadius(11)
            .backgroundColor(this.getTimelineBackgroundColor())
          if (step.kind === MessagePartKind.REASONING) {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(14)
              .fontColor([$r('app.color.text_secondary')])
          } else {
            SymbolGlyph(resolveToolSymbol(step.toolName))
              .fontSize(14)
              .fontColor([$r('app.color.text_secondary')])
          }
        }
        .width(24)
        .height(24)

        if (hasNextStep) {
          Column()
            .width(1.5)
            .height(4)
            .backgroundColor(this.getTimelineRailColor())
            .margin({ top: 2 })
        }
      }
      .width(24)
      .alignItems(HorizontalAlign.Center)

      Column() {
        if (step.kind === MessagePartKind.REASONING) {
          this.ReasoningStepContent(step)
        } else {
          this.ToolStepContent(step)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 1, bottom: 1 })
  }

  // reasoning step 内容: 标题行(可点击 toggle) + 正文 (展开时用 Markdown 渲染)
  @Builder
  ReasoningStepContent(step: MessagePart) {
    Column() {
      Row({ space: 6 }) {
        Text(this.buildReasoningStepLabel(step))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('app.color.text_secondary')])
          .rotate({ angle: this.isReasoningStepExpanded(step) ? 0 : -90 })
      }
      .width('100%')
      .onClick(() => {
        this.toggleReasoningStep(step)
      })

      if (this.isReasoningStepExpanded(step) && step.text.length > 0) {
        Column() {
          Markdown({
            controller: this.reasoningMarkdownController,
            text: this.getMarkdownRenderText(step.text)
          })
            .constraintSize({ maxWidth: '100%' })
            .backgroundColor(Color.Transparent)
        }
        .width('100%')
        .margin({ top: 6 })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // tool step 内容: 状态徽标在左, 标题中间(允许换行), 右侧 chevron 暗示可点
  @Builder
  ToolStepContent(step: MessagePart) {
    if (isAskUserFunctionName(step.toolName)) {
      this.AskUserStepContent(step)
    } else if (isSearchWebFunctionName(step.toolName) && this.isToolStepClickable(step)) {
      // 搜索类: 深度思考同款折叠/展开, 在下方直接展示搜索结果
      Column() {
        Row({ space: 6 }) {
          if (step.toolStatus === 'succeeded') {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(13)
              .fontColor([$r('app.color.status_success')])
          } else if (step.toolStatus === 'failed' || step.toolStatus === 'denied') {
            SymbolGlyph($r('sys.symbol.xmark_circle'))
              .fontSize(13)
              .fontColor([$r('app.color.status_error')])
          } else if (step.toolStatus === 'running') {
            Column()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(this.themePrimary)
          }

          Text(this.buildToolStepTitle(step))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([$r('app.color.text_tertiary')])
            .rotate({ angle: this.isToolStepExpanded(step) ? 0 : -90 })
            .animation({ duration: 200, curve: Curve.EaseOut })
        }
        .width('100%')
        .onClick(() => {
          this.toggleToolStep(step)
        })

        if (this.isToolStepExpanded(step)) {
          Column({ space: 6 }) {
            ForEach(this.resolveToolStepSearchReferences(step), (ref: SearchReference, index: number) => {
              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  Text(`${index + 1}`)
                    .fontSize(11)
                    .fontColor(Color.White)
                    .fontWeight(FontWeight.Medium)
                    .width(18)
                    .height(18)
                    .textAlign(TextAlign.Center)
                    .borderRadius(9)
                    .backgroundColor(this.themePrimary)
                  Text(ref.title)
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                    .fontWeight(FontWeight.Medium)
                    .layoutWeight(1)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')

                if (ref.snippet !== '') {
                  Text(ref.snippet)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ left: 24 })
                }

                Text(ref.url)
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ left: 24 })
              }
              .width('100%')
              .padding(10)
              .borderRadius(10)
              .backgroundColor($r('app.color.divider'))
              .onClick(() => {
                this.onOpenLink(ref.title, ref.url)
              })
            }, (ref: SearchReference, index: number) => `${ref.id}_${index}`)
          }
          .width('100%')
          .margin({ top: 8 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
    Row({ space: 6 }) {
      if (step.toolStatus === 'succeeded') {
        SymbolGlyph($r('sys.symbo' +
          'l.checkmark_circle'))
          .fontSize(13)
          .fontColor([$r('app.color.status_success')])
      } else if (step.toolStatus === 'failed' || step.toolStatus === 'denied') {
        SymbolGlyph($r('sys.symbol.xmark_circle'))
          .fontSize(13)
          .fontColor([$r('app.color.status_error')])
      } else if (step.toolStatus === 'pending') {
        Text('待确认')
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor(this.themePrimary)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      } else if (step.toolStatus === 'running') {
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.themePrimary)
      }

      Text(this.buildToolStepTitle(step))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      if (this.isToolStepClickable(step)) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: -90 })
      }
    }
    .width('100%')
    .onClick(() => {
      if (this.isToolStepClickable(step)) {
        this.handleToolStepClick(step)
      }
    })
    }
  }

  @Builder
  AskUserStepContent(step: MessagePart) {
    Column() {
      Row({ space: 6 }) {
        if (this.isAskUserStepAnswered(step)) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(13)
            .fontColor([$r('app.color.status_success')])
        } else if (step.toolStatus === 'failed' || step.toolStatus === 'denied') {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(13)
            .fontColor([$r('app.color.status_error')])
        } else {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.themePrimary)
        }

        Text(this.buildToolStepTitle(step))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Text(this.buildAskUserStepStatusText(step))
          .fontSize(10)
          .fontColor(this.isAskUserStepAnswered(step) ? $r('app.color.status_success') : $r('app.color.text_secondary'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor($r('app.color.surface'))

        if (this.hasAskUserStepContent(step)) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([$r('app.color.text_tertiary')])
            .rotate({ angle: this.isToolStepExpanded(step) ? 0 : -90 })
        }
      }
      .width('100%')
      .onClick(() => {
        if (this.hasAskUserStepContent(step)) {
          this.toggleToolStep(step)
        }
      })

      if (this.hasAskUserStepContent(step) && this.isToolStepExpanded(step)) {
        Column({ space: 8 }) {
          ForEach(this.buildAskUserAnswerViews(step), (item: AskUserTimelineAnswer, index: number) => {
            this.AskUserAnswerDetailItem(item, index)
          }, (item: AskUserTimelineAnswer, index: number) => `${item.id}_${index}`)
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 8, bottom: 2 })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }
    .width('100%')
  }

  @Builder
  AskUserAnswerDetailItem(item: AskUserTimelineAnswer, index: number) {
    Column({ space: 6 }) {
      Text(item.question !== '' ? item.question : `问题 ${index + 1}`)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text(item.answer !== '' ? item.answer : (item.skipped ? '已跳过' : '等待回答'))
        .fontSize(12)
        .fontColor(item.answer !== '' ? $r('app.color.text_secondary') : $r('app.color.text_tertiary'))
        .lineHeight(18)
        .width('100%')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(8)
    .backgroundColor($r('app.color.surface'))
  }

  private async saveLatexPixelMap(): Promise<void> {
    if (this.latexPreviewPixelMap === null) {
      return
    }
    try {
      const packer = image.createImagePacker()
      const data = await packer.packing(this.latexPreviewPixelMap, { format: 'image/png', quality: 100 })
      packer.release()
      const context = this.getUIContext().getHostContext()!
      const tempPath = `${context.tempDir}/latex_${Date.now()}.png`
      const file = fileIo.openSync(tempPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
      fileIo.writeSync(file.fd, data)
      fileIo.closeSync(file)
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: `LaTeX_${Date.now()}`,
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }
      const phHelper = photoAccessHelper.getPhotoAccessHelper(context)
      const srcUri = fileUri.getUriFromPath(tempPath)
      const destUris = await phHelper.showAssetsCreationDialog([srcUri], [config])
      if (destUris.length > 0) {
        const src = fileIo.openSync(tempPath, fileIo.OpenMode.READ_ONLY)
        const dest = fileIo.openSync(destUris[0], fileIo.OpenMode.WRITE_ONLY)
        fileIo.copyFileSync(src.fd, dest.fd)
        fileIo.closeSync(src)
        fileIo.closeSync(dest)
        showToast(this.getUIContext(), pickLocalizedText('已保存', 'Saved'))
      }
      fileIo.unlinkSync(tempPath)
    } catch (error) {
      console.error('MessageBubble', `Failed to save LaTeX image: ${JSON.stringify(error)}`)
      showToast(this.getUIContext(), pickLocalizedText('保存失败', 'Save failed'))
    }
  }

  @Builder
  LatexPreviewSheetBuilder() {
    Column() {
      if (this.latexPreviewPixelMap !== null) {
        Stack() {
          Image(this.latexPreviewPixelMap)
            .objectFit(ImageFit.Contain)
            .width('100%')
            .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .clip(true)
        .scale({ x: this.latexPreviewScale, y: this.latexPreviewScale })
        .translate({ x: this.latexPreviewOffsetX, y: this.latexPreviewOffsetY })
        .parallelGesture(
          PinchGesture({ fingers: 2 })
            .onActionUpdate((event: GestureEvent) => {
              this.latexPreviewScale = this.latexPreviewLastScale * event.scale
              if (this.latexPreviewScale < 0.5) {
                this.latexPreviewScale = 0.5
              }
              if (this.latexPreviewScale > 5) {
                this.latexPreviewScale = 5
              }
            })
            .onActionEnd(() => {
              this.latexPreviewLastScale = this.latexPreviewScale
            })
        )
        .gesture(
          PanGesture()
            .onActionUpdate((event: GestureEvent) => {
              this.latexPreviewOffsetX = this.latexPreviewLastOffsetX + event.offsetX
              this.latexPreviewOffsetY = this.latexPreviewLastOffsetY + event.offsetY
            })
            .onActionEnd(() => {
              this.latexPreviewLastOffsetX = this.latexPreviewOffsetX
              this.latexPreviewLastOffsetY = this.latexPreviewOffsetY
            })
        )

        Row({ space: 12 }) {
          Button(pickLocalizedText('保存图片', 'Save'))
            .height(36)
            .fontSize(13)
            .type(ButtonType.Capsule)
            .backgroundColor(this.themePrimary)
            .fontColor(Color.White)
            .onClick(() => {
              this.saveLatexPixelMap()
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 8, bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(getAppUiState().themeBackground)
  }

  private buildToolStepTitle(part: MessagePart): string {
    if (part.toolDisplayName.trim() !== '' && part.toolDisplayName !== part.toolName) {
      return part.toolDisplayName
    }
    // 复用 ToolTitleBuilder 的派发: 构造一个最小 ToolCall 对象传给 buildToolTitle
    const toolCall = new ToolCall(
      part.toolCallId,
      part.toolName,
      part.toolArguments,
      '',
      part.toolDisplayName,
      part.toolSourceType,
      part.toolSourceLabel,
      part.toolPermissionLevel
    )
    return buildToolTitle(toolCall)
  }

  // 当前 reasoning 卡片是否处于可见态(完整展开 or 预览)
  private isReasoningCardVisible(): boolean {
    return this.isReasoningExpanded || this.reasoningAutoPreview
  }

  // 点击标题栏切换展开:可见 → 完全收起;收起 → 完全展开
  private toggleReasoningCard(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      if (this.isReasoningCardVisible()) {
        this.isReasoningExpanded = false
        this.reasoningAutoPreview = false
      } else {
        this.isReasoningExpanded = true
        this.reasoningAutoPreview = false
      }
    })
  }

  // 流式中标题:已思考 X.X 秒
  private getReasoningThinkingLabel(): string {
    const seconds = Math.max(0, this.reasoningElapsedMs / 1000)
    return `深度思考中 · 已思考 ${seconds.toFixed(1)} 秒`
  }

  // 生成结束后标题:带总时长(若已记录)
  private getReasoningFinishedLabel(): string {
    if (this.reasoningFinalMs > 0) {
      return `深度思考 · 用时 ${(this.reasoningFinalMs / 1000).toFixed(1)} 秒`
    }
    return '深度思考'
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
    if (isSearchToolId(toolCall.toolId)) {
      return true
    }
    return this.isWebSearchFunctionName(toolCall.functionName)
  }

  private isWebSearchFunctionName(functionName: string): boolean {
    return isSearchToolFunctionName(functionName)
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
      const copyContent = this.message.content
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
