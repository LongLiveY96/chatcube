import { webview } from '@kit.ArkWeb'
import { pasteboard } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0002
const TAG = 'HtmlPreviewCard'

@Component
export struct HtmlPreviewCard {
  @Prop @Watch('onHtmlCodeChange') htmlCode: string = ''
  @StorageProp('isDarkMode') @Watch('onDarkModeChange') isDarkMode: boolean = false
  @State activeTab: number = 1 // 0=代码, 1=预览
  @State showFullScreen: boolean = false
  @State copyBtnPressed: boolean = false
  @State fullScreenBtnPressed: boolean = false
  // Web 组件需要始终保持实例，避免被 if/else 销毁重建
  private previewWebController: webview.WebviewController = new webview.WebviewController()
  private fullScreenWebController: webview.WebviewController = new webview.WebviewController()
  private isPreviewWebReady: boolean = false
  onCopyCode: (code: string) => void = () => {
  }

  private getWrappedHtml(): string {
    const bgColor = this.isDarkMode ? '#1a1a1a' : '#ffffff'
    const textColor = this.isDarkMode ? '#e0e0e0' : '#333333'
    return '<!DOCTYPE html><html><head>' +
      '<meta charset="utf-8">' +
      '<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">' +
      '<style>' +
      '* { box-sizing: border-box; margin: 0; padding: 0; }' +
      'html, body { padding: 12px; font-family: HarmonyOS Sans, -apple-system, sans-serif; ' +
      'background: ' + bgColor + '; color: ' + textColor + '; overflow-x: hidden; }' +
      'img { max-width: 100%; height: auto; }' +
      'table { border-collapse: collapse; width: 100%; }' +
      'th, td { border: 1px solid ' + (this.isDarkMode ? '#444' : '#ddd') + '; padding: 8px; text-align: left; }' +
      'th { background: ' + (this.isDarkMode ? '#2a2a2a' : '#f5f5f5') + '; }' +
      'a { color: ' + (this.isDarkMode ? '#4da6ff' : '#007DFF') + '; }' +
      'pre, code { font-family: monospace; }' +
      'pre { padding: 12px; border-radius: 8px; overflow-x: auto; ' +
      'background: ' + (this.isDarkMode ? '#0d0d0d' : '#f6f8fa') + '; }' +
      '</style></head><body>' +
      this.htmlCode +
      '</body></html>'
  }

  private getDataUrl(): string {
    return 'data:text/html;charset=utf-8,' + encodeURIComponent(this.getWrappedHtml())
  }

  private reloadPreview(): void {
    if (this.isPreviewWebReady) {
      try {
        this.previewWebController.loadUrl(this.getDataUrl())
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'Failed to reload preview')
      }
    }
  }

  onHtmlCodeChange(): void {
    this.reloadPreview()
  }

  onDarkModeChange(): void {
    this.reloadPreview()
  }

  private copyToClipboard(text: string): void {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      const systemPasteboard = pasteboard.getSystemPasteboard()
      systemPasteboard.setData(pasteboardData)
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Copy to clipboard failed: ${JSON.stringify(error)}`)
    }
  }

  build() {
    Column() {
      // Tab 栏
      Row() {
        // 代码 Tab
        Row() {
          Text('</>')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.activeTab === 0 ? $r('app.color.primary') : $r('app.color.text_tertiary'))
          Text('代码')
            .fontSize(13)
            .fontWeight(this.activeTab === 0 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.activeTab === 0 ? $r('app.color.primary') : $r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .height(30)
        .padding({ left: 10, right: 10 })
        .backgroundColor(this.activeTab === 0 ? $r('app.color.primary_light') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.activeTab = 0
        })

        // 预览 Tab
        Row() {
          SymbolGlyph($r('sys.symbol.eye'))
            .fontSize(14)
            .fontColor([this.activeTab === 1 ? $r('app.color.primary') : $r('app.color.text_tertiary')])
          Text('预览')
            .fontSize(13)
            .fontWeight(this.activeTab === 1 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.activeTab === 1 ? $r('app.color.primary') : $r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .height(30)
        .padding({ left: 10, right: 10 })
        .backgroundColor(this.activeTab === 1 ? $r('app.color.primary_light') : Color.Transparent)
        .borderRadius(8)
        .margin({ left: 4 })
        .onClick(() => {
          this.activeTab = 1
        })

        Blank()

        // 复制按钮（仅代码模式）
        if (this.activeTab === 0) {
          Row() {
            SymbolGlyph($r('sys.symbol.checkmark_square_on_square'))
              .fontSize(14)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .width(28)
          .height(28)
          .borderRadius(14)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.copyBtnPressed ? $r('app.color.divider') : Color.Transparent)
          .scale({ x: this.copyBtnPressed ? 0.9 : 1, y: this.copyBtnPressed ? 0.9 : 1 })
          .animation({ duration: 150, curve: Curve.EaseOut })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.copyBtnPressed = true
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.copyBtnPressed = false
            }
          })
          .onClick(() => {
            this.copyToClipboard(this.htmlCode)
            this.onCopyCode(this.htmlCode)
          })
        }

        // 全屏按钮（仅预览模式）
        if (this.activeTab === 1) {
          Row() {
            SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
              .fontSize(14)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .width(28)
          .height(28)
          .borderRadius(14)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.fullScreenBtnPressed ? $r('app.color.divider') : Color.Transparent)
          .scale({ x: this.fullScreenBtnPressed ? 0.9 : 1, y: this.fullScreenBtnPressed ? 0.9 : 1 })
          .animation({ duration: 150, curve: Curve.EaseOut })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.fullScreenBtnPressed = true
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.fullScreenBtnPressed = false
            }
          })
          .onClick(() => {
            this.showFullScreen = true
          })
        }
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })

      Divider()
        .color($r('app.color.divider'))

      // 代码视图（条件渲染，轻量组件无销毁问题）
      if (this.activeTab === 0) {
        Scroll() {
          Text(this.htmlCode)
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor(this.isDarkMode ? '#E0E0E0' : '#333333')
            .lineHeight(18)
            .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 300 })
        .padding(12)
        .scrollBar(BarState.Auto)
        .backgroundColor($r('app.color.code_background'))
      }

      // 预览 Web 视图（始终渲染，用 visibility 切换，避免 WebView 销毁重建）
      Web({ src: this.getDataUrl(), controller: this.previewWebController })
        .width('100%')
        .height(this.activeTab === 1 ? 300 : 0)
        .visibility(this.activeTab === 1 ? Visibility.Visible : Visibility.Hidden)
        .onControllerAttached(() => {
          this.isPreviewWebReady = true
          hilog.info(DOMAIN, TAG, 'Preview Web controller attached')
        })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .backgroundColor(this.isDarkMode ? '#1a1a1a' : '#ffffff')
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
    .clip(true)
    .margin({ top: 8, bottom: 4 })
    .bindSheet($$this.showFullScreen, this.FullScreenBuilder(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.LARGE],
      dragBar: true,
      showClose: true,
      title: { title: 'HTML 预览' }
    })
  }

  @Builder
  FullScreenBuilder() {
    Column() {
      Web({ src: this.getDataUrl(), controller: this.fullScreenWebController })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .backgroundColor(this.isDarkMode ? '#1a1a1a' : '#ffffff')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
