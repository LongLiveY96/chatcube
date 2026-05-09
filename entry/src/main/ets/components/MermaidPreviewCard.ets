import { webview } from '@kit.ArkWeb'
import { pasteboard } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { getAppUiState, observeAppUiState } from '../state/AppUiState'

const DOMAIN = 0x0002
const TAG = 'MermaidPreviewCard'
const MERMAID_PREVIEW_URL = 'resource://rawfile/mermaid/mermaid-preview.html'

interface MermaidRenderPayload {
  code: string
  dark: boolean
  primary: string
  primaryLight: string
  background: string
  text: string
  line: string
}

@ComponentV2
export struct MermaidPreviewCard {
  @Param mermaidCode: string = ''
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  @Local activeTab: number = 1
  @Local showFullScreen: boolean = false
  @Local copyBtnPressed: boolean = false
  @Local fullScreenBtnPressed: boolean = false
  private previewWebController: webview.WebviewController = new webview.WebviewController()
  private fullScreenWebController: webview.WebviewController = new webview.WebviewController()
  private isPreviewWebReady: boolean = false
  private isPreviewPageReady: boolean = false
  private isFullScreenWebReady: boolean = false
  private isFullScreenPageReady: boolean = false
  private darkModeObserverDisposer: (() => void) | null = null
  @Event onCopyCode: (code: string) => void = () => {
  }

  private getPreviewBackground(): string {
    return this.isDarkMode ? '#1a1a1a' : '#ffffff'
  }

  private getPreviewTextColor(): string {
    return this.isDarkMode ? '#e0e0e0' : '#333333'
  }

  private getPreviewLineColor(): string {
    return this.isDarkMode ? '#9a9a9a' : '#666666'
  }

  private getRenderScript(): string {
    const payload: MermaidRenderPayload = {
      code: this.mermaidCode,
      dark: this.isDarkMode,
      primary: this.themePrimary,
      primaryLight: this.themePrimaryLight,
      background: this.getPreviewBackground(),
      text: this.getPreviewTextColor(),
      line: this.getPreviewLineColor()
    }
    return 'window.renderMermaid(' + JSON.stringify(payload) + ')'
  }

  private renderWithController(controller: webview.WebviewController, ready: boolean): void {
    if (!ready) {
      return
    }
    try {
      controller.runJavaScript(this.getRenderScript())
        .catch((error: Error) => {
          hilog.error(DOMAIN, TAG, `Render script failed: ${JSON.stringify(error)}`)
        })
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Run render script failed: ${JSON.stringify(error)}`)
    }
  }

  private renderPreview(): void {
    this.renderWithController(this.previewWebController, this.isPreviewWebReady && this.isPreviewPageReady)
  }

  private renderFullScreenPreview(): void {
    this.renderWithController(this.fullScreenWebController, this.isFullScreenWebReady && this.isFullScreenPageReady)
  }

  private renderAllPreviews(): void {
    this.renderPreview()
    this.renderFullScreenPreview()
  }

  @Monitor('mermaidCode')
  onMermaidCodeChange(): void {
    this.renderAllPreviews()
  }

  onDarkModeChange(): void {
    this.renderAllPreviews()
  }

  aboutToAppear(): void {
    if (this.darkModeObserverDisposer === null) {
      this.darkModeObserverDisposer = observeAppUiState('isDarkMode', (): void => {
        this.onDarkModeChange()
      })
    }
  }

  aboutToDisappear(): void {
    if (this.darkModeObserverDisposer !== null) {
      this.darkModeObserverDisposer()
      this.darkModeObserverDisposer = null
    }
  }

  private copyToClipboard(text: string): void {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      const systemPasteboard = pasteboard.getSystemPasteboard()
      systemPasteboard.setData(pasteboardData)
        .catch((error: Error) => {
          hilog.error(DOMAIN, TAG, `Copy to clipboard failed: ${JSON.stringify(error)}`)
        })
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Copy to clipboard failed: ${JSON.stringify(error)}`)
    }
  }

  build() {
    Column() {
      Row() {
        Row() {
          Text('</>')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.activeTab === 0 ? this.themePrimary : $r('app.color.text_tertiary'))
          Text('代码')
            .fontSize(13)
            .fontWeight(this.activeTab === 0 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.activeTab === 0 ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .height(30)
        .padding({ left: 10, right: 10 })
        .backgroundColor(this.activeTab === 0 ? this.themePrimaryLight : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.activeTab = 0
        })

        Row() {
          SymbolGlyph($r('sys.symbol.eye'))
            .fontSize(14)
            .fontColor([this.activeTab === 1 ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('预览')
            .fontSize(13)
            .fontWeight(this.activeTab === 1 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.activeTab === 1 ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .height(30)
        .padding({ left: 10, right: 10 })
        .backgroundColor(this.activeTab === 1 ? this.themePrimaryLight : Color.Transparent)
        .borderRadius(8)
        .margin({ left: 4 })
        .onClick(() => {
          this.activeTab = 1
        })

        Blank()

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
            this.copyToClipboard(this.mermaidCode)
            this.onCopyCode(this.mermaidCode)
          })
        }

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

      if (this.activeTab === 0) {
        Scroll() {
          Text(this.mermaidCode)
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor(this.getPreviewTextColor())
            .lineHeight(18)
            .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 300 })
        .padding(12)
        .scrollBar(BarState.Auto)
        .backgroundColor($r('app.color.code_background'))
      }

      Web({ src: MERMAID_PREVIEW_URL, controller: this.previewWebController })
        .width('100%')
        .height(this.activeTab === 1 ? 300 : 0)
        .visibility(this.activeTab === 1 ? Visibility.Visible : Visibility.Hidden)
        .onControllerAttached(() => {
          this.isPreviewWebReady = true
          hilog.info(DOMAIN, TAG, 'Preview Web controller attached')
        })
        .onPageEnd(() => {
          this.isPreviewPageReady = true
          this.renderPreview()
        })
        .javaScriptAccess(true)
        .fileAccess(false)
        .backgroundColor(this.getPreviewBackground())
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
      title: { title: 'Mermaid 预览' }
    })
  }

  @Builder
  FullScreenBuilder() {
    Column() {
      Web({ src: MERMAID_PREVIEW_URL, controller: this.fullScreenWebController })
        .width('100%')
        .layoutWeight(1)
        .onControllerAttached(() => {
          this.isFullScreenWebReady = true
        })
        .onPageEnd(() => {
          this.isFullScreenPageReady = true
          this.renderFullScreenPreview()
        })
        .javaScriptAccess(true)
        .fileAccess(false)
        .backgroundColor(this.getPreviewBackground())
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
