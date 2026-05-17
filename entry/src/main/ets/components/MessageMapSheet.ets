import { ChatMessage, MessageRole } from '../models/ChatModels'
import {
  extractMessageSummary,
  buildHighlightedSpans,
  HighlightSegment
} from '../utils/MessageSummaryUtil'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

class MessageMapItem {
  originalIndex: number = 0
  message: ChatMessage
  summary: string = ''

  constructor(originalIndex: number, message: ChatMessage, summary: string) {
    this.originalIndex = originalIndex
    this.message = message
    this.summary = summary
  }
}

class MessageMapDataSource implements IDataSource {
  private items: MessageMapItem[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.items.length
  }

  getData(index: number): MessageMapItem {
    return this.items[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.includes(listener)) {
      return
    }
    this.listeners.push(listener)
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener)
  }

  setItems(items: MessageMapItem[]): void {
    this.items = items
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}

@ComponentV2
export struct MessageMapSheet {
  @Param messages: ChatMessage[] = []
  @Param currentMessageIndex: number = -1
  @Event onClose: () => void = () => {}
  @Event onJumpToMessage: (messageIndex: number) => void = (_idx: number) => {}

  @Local searchQuery: string = ''
  @Local syncVersion: number = 0
  @Local baseTotal: number = 0
  @Local visibleTotal: number = 0

  private dataSource: MessageMapDataSource = new MessageMapDataSource()
  private baseItems: MessageMapItem[] = []
  private scroller: Scroller = new Scroller()
  private currentItemArrayIndex: number = -1

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get userBubbleColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '40' : '22')
  }

  aboutToAppear(): void {
    this.rebuildBaseItems()
    this.applyFilter()
    // 打开时把列表滚到当前消息所在位置附近, 让用户立即看到"我在哪"
    if (this.currentItemArrayIndex >= 0) {
      setTimeout((): void => {
        this.scroller.scrollToIndex(this.currentItemArrayIndex, false, ScrollAlign.CENTER)
      }, 0)
    }
  }

  private rebuildBaseItems(): void {
    const items: MessageMapItem[] = []
    let currentArrayIdx: number = -1
    for (let i = 0; i < this.messages.length; i++) {
      const msg = this.messages[i]
      if (msg.role !== MessageRole.USER && msg.role !== MessageRole.ASSISTANT) {
        continue
      }
      const summary = extractMessageSummary(msg)
      if (i === this.currentMessageIndex) {
        currentArrayIdx = items.length
      }
      items.push(new MessageMapItem(i, msg, summary))
    }
    this.baseItems = items
    this.baseTotal = items.length
    this.currentItemArrayIndex = currentArrayIdx
  }

  @Monitor('searchQuery')
  private onSearchQueryChange(): void {
    this.applyFilter()
  }

  private applyFilter(): void {
    const query = this.searchQuery.trim().toLowerCase()
    let filtered: MessageMapItem[]
    if (query.length === 0) {
      filtered = this.baseItems
    } else {
      filtered = []
      for (let i = 0; i < this.baseItems.length; i++) {
        const item = this.baseItems[i]
        if (item.summary.toLowerCase().includes(query)) {
          filtered.push(item)
        }
      }
    }
    this.syncVersion += 1
    this.visibleTotal = filtered.length
    this.dataSource.setItems(filtered)
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.message_map_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor($r('app.color.divider'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.onClose()
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
        TextInput({
          text: this.searchQuery,
          placeholder: $r('app.string.message_map_search_placeholder')
        })
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .padding({ top: 0, bottom: 0, left: 0, right: 0 })
          .fontSize(14)
          .placeholderColor($r('app.color.text_tertiary'))
          .placeholderFont({ size: 14 })
          .onChange((value: string) => {
            this.searchQuery = value
          })
        Text(this.searchQuery.length > 0
          ? `${this.visibleTotal} / ${this.baseTotal}`
          : `${this.baseTotal}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .fontWeight(FontWeight.Medium)
        if (this.searchQuery.length > 0) {
          Row() {
            SymbolGlyph($r('sys.symbol.xmark_circle'))
              .fontSize(16)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .width(20)
          .height(20)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.searchQuery = ''
          })
        }
      }
      .width('auto')
      .height(40)
      .padding({ left: 12, right: 12 })
      .margin({ left: 20, right: 20, bottom: 12 })
      .borderRadius(20)
      .backgroundColor($r('app.color.divider'))
      .alignItems(VerticalAlign.Center)

      if (this.visibleTotal === 0) {
        Column() {
          SymbolGlyph(this.baseTotal === 0
            ? $r('sys.symbol.message')
            : $r('sys.symbol.magnifyingglass'))
            .fontSize(40)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ bottom: 12 })
          Text(this.baseTotal === 0
            ? $r('app.string.message_map_empty')
            : $r('app.string.message_map_no_match'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          List({ space: 8, scroller: this.scroller }) {
            LazyForEach(this.dataSource, (item: MessageMapItem, _index: number) => {
              ListItem() {
                this.MessageMapItemBuilder(item)
              }
            }, (item: MessageMapItem): string => {
              return `${item.message.id}|${item.message.role}|${item.summary.length}|${this.syncVersion}`
            })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 24 })
          .scrollBar(BarState.Auto)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private MessageMapItemBuilder(item: MessageMapItem) {
    Row({ space: 6 }) {
      if (item.message.role === MessageRole.USER) {
        this.MessageBubbleBuilder(item)
        if (item.originalIndex === this.currentMessageIndex) {
          this.CurrentIndicatorBuilder()
        }
      } else {
        if (item.originalIndex === this.currentMessageIndex) {
          this.CurrentIndicatorBuilder()
        }
        this.MessageBubbleBuilder(item)
      }
    }
    .width('100%')
    .justifyContent(item.message.role === MessageRole.USER
      ? FlexAlign.End
      : FlexAlign.Start)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private CurrentIndicatorBuilder() {
    Column()
      .width(3)
      .height(20)
      .borderRadius(1.5)
      .backgroundColor(this.themePrimary)
  }

  @Builder
  private MessageBubbleBuilder(item: MessageMapItem) {
    Text() {
      ForEach(buildHighlightedSpans(item.summary, this.searchQuery.trim()),
        (seg: HighlightSegment, _i: number) => {
          if (seg.hit) {
            Span(seg.text)
              .fontColor(this.themePrimary)
              .fontWeight(FontWeight.Medium)
          } else {
            Span(seg.text)
              .fontColor($r('app.color.text_primary'))
          }
        },
        (seg: HighlightSegment, idx: number): string => `${idx}|${seg.hit ? '1' : '0'}|${seg.text.length}`)
    }
    .fontSize(14)
    .maxLines(2)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .lineHeight(20)
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .constraintSize({ maxWidth: '78%' })
    .backgroundColor(item.message.role === MessageRole.USER
      ? this.userBubbleColor
      : $r('app.color.divider'))
    .borderRadius(item.message.role === MessageRole.USER
      ? { topLeft: 14, topRight: 14, bottomLeft: 14, bottomRight: 4 } as BorderRadiuses
      : { topLeft: 14, topRight: 14, bottomLeft: 4, bottomRight: 14 } as BorderRadiuses)
    .onClick(() => {
      this.onJumpToMessage(item.originalIndex)
    })
  }
}
