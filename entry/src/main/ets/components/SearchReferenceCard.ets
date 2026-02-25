import { SearchReference } from '../models/ChatModels'
import { webview } from '@kit.ArkWeb'

@Component
export struct SearchReferenceCard {
  @Prop query: string
  @Prop searchEngine: string
  @Prop references: SearchReference[]
  @Prop sourceLabel: string = ''  // 手动搜索 / 工具调用
  @State isExpanded: boolean = false  // 默认折叠
  @State showWebSheet: boolean = false
  @State sheetUrl: string = ''
  @State sheetTitle: string = ''
  private sheetWebController: webview.WebviewController = new webview.WebviewController()
  @StorageProp('isDarkMode') isDarkMode: boolean = false

  // 获取引用数量文本
  private getReferenceCountText(): string {
    return `${this.references.length}`
  }

  // 统一格式化展示的搜索关键词（单行、去掉多余空白）
  private getDisplayQuery(): string {
    const trimmed = this.query.trim()
    if (trimmed === '') {
      return ''
    }
    return trimmed.replace(/\s+/g, ' ')
  }

  // 获取阴影颜色（根据深浅模式）
  private getShadowColor(): ResourceColor {
    return this.isDarkMode ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.12)'
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ========== 悬浮联网查询标签 ==========
      Row() {
        // 联网搜索图标
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(13)
          .fontColor([$r('app.color.text_secondary')])

        // 标题文本
        Text($r('app.string.web_search'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 4 })

        // 来源标签（区分：Function Calling vs 手动搜索链路）
        if (this.sourceLabel.trim() !== '') {
          Text(this.sourceLabel.trim())
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 6 })
        }

        if (this.searchEngine.trim() !== '') {
          Text(this.searchEngine.trim())
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(8)
            .backgroundColor($r('app.color.divider'))
            .margin({ left: 6 })
        }

        // 实际搜索关键词（占据剩余空间，便于排查“关键词优化”是否跑偏）
        if (this.getDisplayQuery() !== '') {
          Text(this.getDisplayQuery())
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        } else {
          Text('')
            .layoutWeight(1)
        }

        // 分隔线
        Row()
          .width(1)
          .height(10)
          .backgroundColor($r('app.color.divider'))
          .margin({ left: 8, right: 8 })

        // 引用数量
        Text(this.getReferenceCountText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        // 展开/折叠箭头
        SymbolGlyph(this.isExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
          .margin({ left: 6 })
          .width(12)
          .height(12)
      }
      .height(28)
      .padding({ left: 10, right: 8 })
      .borderRadius(14)
      .clip(true)
      .shadow({
        radius: 8,
        color: this.getShadowColor(),
        offsetX: 0,
        offsetY: 2
      })
      .stateStyles({
        normal: {
          .backgroundColor($r('app.color.surface'))
        },
        pressed: {
          .backgroundColor($r('app.color.divider'))
        }
      })
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
          this.isExpanded = !this.isExpanded
        })
      })

      // 引用列表（可折叠）
      if (this.isExpanded) {
        Column({ space: 0 }) {
          ForEach(this.references, (ref: SearchReference, index: number) => {
            this.ReferenceItem(ref, index + 1)
          }, (ref: SearchReference) => ref.id)
        }
        .width('100%')
        .margin({ top: 36 })
        .clip(true)
      }
    }
    .width('100%')
    .alignContent(Alignment.TopStart)
    .bindSheet($$this.showWebSheet, this.WebSheetBuilder(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.LARGE],
      dragBar: true,
      showClose: true,
      title: { title: this.sheetTitle !== '' ? this.sheetTitle : $r('app.string.common_web_page') },
      onDisappear: () => {
        this.sheetUrl = ''
        this.sheetTitle = ''
      }
    })
  }

  @Builder
  WebSheetBuilder() {
    Column() {
      if (this.sheetUrl !== '') {
        Web({ src: this.sheetUrl, controller: this.sheetWebController })
          .width('100%')
          .layoutWeight(1)
      } else {
        Column() {
          Text($r('app.string.common_invalid_link'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  ReferenceItem(ref: SearchReference, index: number) {
    Column({ space: 6 }) {
      // 标题行：序号 + 标题
      Row({ space: 8 }) {
        // 序号圆圈
        Text(`${index}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .fontWeight(FontWeight.Medium)
          .width(18)
          .height(18)
          .textAlign(TextAlign.Center)
          .borderRadius(9)
          .backgroundColor($r('app.color.divider'))

        // 标题
        Text(ref.title)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')

      // 摘要
      if (ref.snippet !== '') {
        Text(ref.snippet)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 26 })
      }

      // URL
      Text(ref.url)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 26 })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 4, right: 4 })
    .stateStyles({
      normal: {
        .backgroundColor($r('app.color.surface'))
      },
      pressed: {
        .backgroundColor($r('app.color.divider'))
      }
    })
    .onClick(() => {
      this.sheetUrl = ref.url
      this.sheetTitle = ref.title
      this.showWebSheet = true
    })
  }
}
