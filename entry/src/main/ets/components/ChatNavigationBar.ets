/**
 * 聊天导航栏组件
 * 包含返回按钮、标题显示与编辑、模型选择、新建对话、更多菜单
 */

import {
  createButtonTouchHandler,
  getButtonScale,
  getButtonAnimation
} from '../utils/ButtonAnimationUtils'
import {
  CHAT_NAVIGATION_BAR_MIN_HEIGHT
} from '../config/ChatLayout'
import { buildIconResourcePath, getModelIconPath, isNetworkIconPath, isSandboxIconPath } from '../utils/ProviderIconUtils'
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in'
import { getAppUiState, observeAppUiState } from '../state/AppUiState'

@ComponentV2
export struct ChatNavigationBar {
  // 会话标题
  @Param sessionTitle: string = '新对话'
  // 当前模型ID
  @Param currentModelId: string = ''
  // 当前服务商ID
  @Param currentProviderId: string = ''
  // 当前模型名称
  @Param currentModelName: string = ''
  // 当前服务商名称
  @Param currentProviderName: string = ''
  @Param currentProviderIconType: string = 'svg'
  @Param currentProviderIconPath: string = ''
  @Param currentProviderTextIcon: string = ''
  @Param currentProviderTextIconBgColor: string = ''
  @Param currentProviderCustomImagePath: string = ''
  @Param currentProviderBrandColor: ResourceColor = ''
  // 是否有消息（用于控制新建对话按钮显示）
  @Param hasMessages: boolean = false
  // 标题是否正在生成
  @Param isTitleGenerating: boolean = false
  // 标题生成是否失败
  @Param titleGenerateFailed: boolean = false
  @Param contentMaxWidth: number = 99999
  // 是否正在发送（用于禁用重新生成标题）
  @Param isSending: boolean = false
  @Param topInsetHeight: number = 0

  // 回调函数
  @Event onBack: () => void = () => {}
  @Event onModelSelect: () => void = () => {}
  @Event onNewChat: () => void = () => {}
  @Event onRegenerateTitle: () => void = () => {}
  @Event onTitleChanged: (newTitle: string) => void = () => {}
  @Event onDeleteChat: () => void = () => {}

  // 内部状态
  @Local private backBtnPressed: boolean = false
  @Local private newChatBtnPressed: boolean = false
  @Local private moreBtnPressed: boolean = false
  @Local private isEditingTitle: boolean = false
  @Local private editingTitleInput: string = ''
  // 主题颜色
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private titleMarkdownController: MarkdownController = new MarkdownController()
  private themeObserverDisposer: (() => void) | null = null

  aboutToAppear(): void {
    this.configureTitleMarkdownStyles()
    if (this.themeObserverDisposer === null) {
      this.themeObserverDisposer = observeAppUiState(['isDarkMode', 'themePrimary'], (): void => {
        this.onNavThemeStateChange()
      })
    }
  }

  onNavThemeStateChange(): void {
    this.configureTitleMarkdownStyles()
  }

  aboutToDisappear(): void {
    if (this.themeObserverDisposer !== null) {
      this.themeObserverDisposer()
      this.themeObserverDisposer = null
    }
  }

  private configureTitleMarkdownStyles(): void {
    const textColor = $r('app.color.text_primary')
    const latexTextColor = this.isDarkMode ? 0xFFE0E0E0 : 0xFF333333

    this.titleMarkdownController
      .setTitleColor(textColor)
      .setTextColor(textColor)
      .setTextSize(14)
      .setTextLineHeight(17)
      .setLatexMathTextColor(latexTextColor)
      .setLatexMathTextSize(16)
  }

  private hasCurrentModelIdentity(): boolean {
    return this.currentModelId !== '' || this.currentModelName !== ''
  }

  private getCurrentModelIconPath(): string {
    if (this.currentModelId !== '') {
      const iconById = getModelIconPath(this.currentModelId, this.currentProviderId, '')
      if (iconById !== '') {
        return iconById
      }
    }
    if (this.currentModelName !== '') {
      return getModelIconPath(this.currentModelName, this.currentProviderId, '')
    }
    return ''
  }

  private getCurrentModelIconResourcePath(): string {
    const iconPath = this.getCurrentModelIconPath()
    if (iconPath === '') {
      return ''
    }
    return buildIconResourcePath(iconPath)
  }

  private hasCurrentModelIcon(): boolean {
    return this.getCurrentModelIconResourcePath() !== ''
  }

  private isRawfileCurrentModelIcon(): boolean {
    const resourcePath = this.getCurrentModelIconResourcePath()
    return resourcePath !== '' && !isNetworkIconPath(resourcePath) && !isSandboxIconPath(resourcePath)
  }

  private getEffectiveContentMaxWidth(): number {
    return this.contentMaxWidth > 0 ? this.contentMaxWidth : 99999
  }

  build() {
    Column() {
      Row() {
        Column() {
          if (this.topInsetHeight > 0) {
            Column()
              .width('100%')
              .height(this.topInsetHeight)
          }

          Row() {
            // 返回按钮
            Stack({ alignContent: Alignment.TopEnd }) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.chevron_left'))
                  .fontSize(20)
                  .fontColor([$r('app.color.text_primary')])
              }
              .width(36)
              .height(36)
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .shadow({
                radius: this.backBtnPressed ? 10 : 0,
                color: 'rgba(0, 0, 0, 0.1)',
                offsetX: 0,
                offsetY: this.backBtnPressed ? 2 : 0
              })
              .scale(getButtonScale(this.backBtnPressed))
              .animation({ duration: 200, curve: Curve.EaseInOut })
              .onTouch(createButtonTouchHandler((pressed: boolean) => {
                this.backBtnPressed = pressed
              }))
              .onClick(() => {
                this.onBack()
              })
            }
            .width(40)
            .height(36)

            // 标题区域 - 点击可切换模型，长按编辑标题
            Row() {
              // 模型图标
              if (this.hasCurrentModelIdentity()) {
                if (this.hasCurrentModelIcon()) {
                  Column() {
                    if (this.isRawfileCurrentModelIcon()) {
                      Image($rawfile(this.getCurrentModelIconResourcePath()))
                        .width(13)
                        .height(13)
                        .objectFit(ImageFit.Contain)
                    } else {
                      Image(this.getCurrentModelIconResourcePath())
                        .width(13)
                        .height(13)
                        .objectFit(ImageFit.Contain)
                    }
                  }
                  .width(20)
                  .height(20)
                  .borderRadius(5)
                  .backgroundColor($r('app.color.model_icon_bg'))
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                } else {
                  Column() {
                    SymbolGlyph($r('sys.symbol.ai_edit'))
                      .fontSize(13)
                      .fontColor([$r('app.color.text_tertiary')])
                  }
                  .width(20)
                  .height(20)
                  .borderRadius(5)
                  .backgroundColor($r('app.color.model_icon_bg'))
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                }
              }

              if (this.isEditingTitle) {
                TextInput({ text: this.editingTitleInput, placeholder: '输入标题' })
                  .id('chat_title_input')
                  .defaultFocus(true)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor(Color.Transparent)
                  .border({ width: { bottom: 1 }, color: this.themePrimary })
                  .maxLength(50)
                  .height(36)
                  .layoutWeight(1)
                  .margin({ left: this.hasCurrentModelIdentity() ? 5 : 0 })
                  .onChange((value: string) => {
                    this.editingTitleInput = value
                  })
                  .onSubmit(() => {
                    this.finishEditingTitle()
                  })
                  .onBlur(() => {
                    this.finishEditingTitle()
                  })
              } else {
                Column() {
                  Row() {
                    if (this.titleContainsLatex()) {
                      Markdown({
                        controller: this.titleMarkdownController,
                        text: this.normalizeLatexInTitle(this.sessionTitle)
                      })
                        .layoutWeight(1)
                        .constraintSize({ maxHeight: 20 })
                        .clip(true)
                        .backgroundColor(Color.Transparent)
                    } else {
                      Text(this.sessionTitle)
                        .fontSize(15)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .lineHeight(17)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }

                    if (this.isTitleGenerating) {
                      LoadingProgress()
                        .width(12)
                        .height(12)
                        .color($r('app.color.text_tertiary'))
                        .margin({ left: 4 })
                    }

                    if (this.titleGenerateFailed && !this.isTitleGenerating) {
                      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                        .fontSize(12)
                        .fontColor([$r('app.color.text_tertiary')])
                        .margin({ left: 4 })
                        .onClick(() => {
                          this.onRegenerateTitle()
                        })
                    }
                  }

                  Text(this.getCurrentModelTitle())
                    .fontSize(9)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 0 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: this.hasCurrentModelIdentity() ? 5 : 0 })
                .layoutWeight(1)
              }

              if (!this.isEditingTitle) {
                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontSize(10)
                  .fontColor([$r('app.color.text_tertiary')])
                  .margin({ left: 2 })
              }
            }
            .layoutWeight(1)
            .margin({ left: 5 })
            .onClick(() => {
              if (!this.isEditingTitle) {
                this.onModelSelect()
              }
            })
            .gesture(
              LongPressGesture()
                .onAction(() => {
                  if (!this.isEditingTitle) {
                    this.startEditingTitle()
                  }
                })
            )

            if (this.hasMessages) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(18)
                  .fontColor([$r('app.color.text_primary')])
              }
              .width(36)
              .height(36)
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .margin({ left: 6 })
              .scale(getButtonScale(this.newChatBtnPressed))
              .animation(getButtonAnimation())
              .onTouch(createButtonTouchHandler((pressed: boolean) => {
                this.newChatBtnPressed = pressed
              }))
              .onClick(() => {
                this.onNewChat()
              })
            }

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                .fontSize(18)
                .fontColor([$r('app.color.text_primary')])
            }
            .width(36)
            .height(36)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .margin({ left: 6 })
            .scale(getButtonScale(this.moreBtnPressed))
            .animation(getButtonAnimation())
            .onTouch(createButtonTouchHandler((pressed: boolean) => {
              this.moreBtnPressed = pressed
            }))
            .bindMenu(this.buildMoreMenu())
          }
          .width('100%')
          .height(CHAT_NAVIGATION_BAR_MIN_HEIGHT)
          .alignItems(VerticalAlign.Center)
          .padding({ left: 8, right: 8 })
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getEffectiveContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
  }

  // 获取当前模型标题
  private getCurrentModelTitle(): string | Resource {
    if (this.currentModelName !== '' && this.currentProviderName !== '') {
      return `${this.currentModelName} (${this.currentProviderName})`
    } else if (this.currentModelName !== '') {
      return this.currentModelName
    }
    return $r('app.string.select_model')
  }

  // 开始编辑标题
  private startEditingTitle(): void {
    this.editingTitleInput = this.sessionTitle
    this.isEditingTitle = true
    // 长按进入编辑态后，主动请求输入框焦点，确保软键盘及时弹出
    setTimeout(() => {
      if (this.isEditingTitle) {
        this.getUIContext().getFocusController().requestFocus('chat_title_input')
      }
    }, 60)
  }

  // 完成编辑标题
  private finishEditingTitle(): void {
    this.isEditingTitle = false
    const newTitle = this.editingTitleInput.trim()
    if (newTitle !== '' && newTitle !== this.sessionTitle) {
      this.onTitleChanged(newTitle)
    }
  }

  private titleContainsLatex(): boolean {
    return /\$.+?\$/.test(this.sessionTitle) ||
      this.sessionTitle.includes('\\(') ||
      this.sessionTitle.includes('\\[')
  }

  private normalizeLatexInTitle(title: string): string {
    let result = title
    result = result.replace(/\\\[([\s\S]*?)\\\]/g, (_match: string, p1: string): string => `$$${p1}$$`)
    result = result.replace(/\\\(([\s\S]*?)\\\)/g, (_match: string, p1: string): string => `$${p1}$`)
    return result
  }

  // 构建更多菜单
  @Builder
  buildMoreMenu(): void {
    Menu() {
      MenuItem({
        startIcon: $r('sys.symbol.arrow_clockwise'),
        content: $r('app.string.regenerate_title')
      })
      .enabled(!this.isTitleGenerating && !this.isSending)
      .onClick(() => {
        this.onRegenerateTitle()
      })

      MenuItemGroup({ header: $r('app.string.danger_zone') }) {
        MenuItem({
          startIcon: $r('sys.symbol.trash'),
          content: $r('app.string.delete_chat')
        })
        .contentFontColor($r('app.color.status_error'))
        .onClick(() => {
          this.onDeleteChat()
        })
      }
    }
  }
}
