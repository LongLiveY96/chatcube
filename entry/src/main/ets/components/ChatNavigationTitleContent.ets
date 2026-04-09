import { Markdown, MarkdownController } from '@luvi/lv-markdown-in'
import { ProviderIconSmall } from './ProviderIcon'
import { getAppUiState, observeAppUiState } from '../state/AppUiState'
import { buildIconResourcePath, getModelIconPath, isNetworkIconPath, isSandboxIconPath } from '../utils/ProviderIconUtils'
import {
  createButtonTouchHandler,
  getButtonAnimation,
  getButtonScale
} from '../utils/ButtonAnimationUtils'

export const CHAT_NAVIGATION_TITLE_STACK_BUILDER_HEIGHT = 56
const CHAT_NAVIGATION_ACTION_BUTTON_SIZE = 28

@ComponentV2
export struct ChatNavigationTitleContent {
  @Param sessionTitle: string = '新对话'
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  @Param currentModelName: string = ''
  @Param currentProviderName: string = ''
  @Param currentProviderIconType: string = 'svg'
  @Param currentProviderIconPath: string = ''
  @Param currentProviderTextIcon: string = ''
  @Param currentProviderTextIconBgColor: string = ''
  @Param currentProviderCustomImagePath: string = ''
  @Param currentProviderBrandColor: ResourceColor = ''
  @Param isTitleGenerating: boolean = false
  @Param titleGenerateFailed: boolean = false
  @Param editRequestVersion: number = 0
  @Param leftActionLaneWidth: number = 44
  @Param rightActionLaneWidth: number = 44
  @Param showNewChatAction: boolean = false

  @Event onBack: () => void = () => {}
  @Event onModelSelect: () => void = () => {}
  @Event onNewChat: () => void = () => {}
  @Event onMore: () => void = () => {}
  @Event onRegenerateTitle: () => void = () => {}
  @Event onWillEditTitle: () => void = () => {}
  @Event onTitleChanged: (newTitle: string) => void = (_newTitle: string): void => {}

  @Local private backBtnPressed: boolean = false
  @Local private newChatBtnPressed: boolean = false
  @Local private moreBtnPressed: boolean = false
  @Local private isEditingTitle: boolean = false
  @Local private editingTitleInput: string = ''
  private readonly titleInputFocusId: string = 'chat_navigation_title_input'
  private titleMarkdownController: MarkdownController = new MarkdownController()
  private themeObserverDisposer: (() => void) | null = null

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToAppear(): void {
    this.configureTitleMarkdownStyles()
    if (this.themeObserverDisposer === null) {
      this.themeObserverDisposer = observeAppUiState(['isDarkMode', 'themePrimary'], (): void => {
        this.configureTitleMarkdownStyles()
      })
    }
  }

  aboutToDisappear(): void {
    if (this.themeObserverDisposer !== null) {
      this.themeObserverDisposer()
      this.themeObserverDisposer = null
    }
  }

  @Monitor('editRequestVersion')
  onEditRequestVersionChange(): void {
    if (this.editRequestVersion <= 0) {
      return
    }
    this.startEditingTitle()
  }

  private configureTitleMarkdownStyles(): void {
    const latexTextColor = this.isDarkMode ? 0xFFE0E0E0 : 0xFF333333
    this.titleMarkdownController
      .setTitleColor($r('app.color.text_primary'))
      .setTextColor($r('app.color.text_primary'))
      .setTextSize(14)
      .setTextLineHeight(17)
      .setLatexMathTextColor(latexTextColor)
      .setLatexMathTextSize(15)
  }

  private getModelIdentityTextColor(): string {
    return this.isDarkMode ? '#F3F5F7' : '#1F2329'
  }

  private getModelIdentityChevronColor(): string {
    return this.isDarkMode ? '#C7CDD5' : '#5A6573'
  }

  private getNavigationActionButtonBackgroundColor(): string {
    return this.isDarkMode ? '#30FFFFFF' : '#D9FFFFFF'
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

  private hasProviderIdentity(): boolean {
    return this.currentProviderName !== '' ||
      this.currentProviderTextIcon !== '' ||
      this.currentProviderIconPath !== '' ||
      this.currentProviderCustomImagePath !== ''
  }

  private getCurrentModelTitle(): string | Resource {
    if (this.currentModelName !== '') {
      return this.currentModelName
    }
    return $r('app.string.select_model')
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

  private startEditingTitle(): void {
    if (this.isEditingTitle) {
      return
    }
    this.onWillEditTitle()
    this.editingTitleInput = this.sessionTitle
    this.isEditingTitle = true
    setTimeout(() => {
      if (this.isEditingTitle) {
        this.getUIContext().getFocusController().requestFocus(this.titleInputFocusId)
      }
    }, 60)
  }

  private finishEditingTitle(): void {
    this.isEditingTitle = false
    const nextTitle = this.editingTitleInput.trim()
    if (nextTitle !== '' && nextTitle !== this.sessionTitle) {
      this.onTitleChanged(nextTitle)
    }
  }

  @Builder
  private IdentityIconBuilder() {
    if (this.hasCurrentModelIcon()) {
      Column() {
        if (this.isRawfileCurrentModelIcon()) {
          Image($rawfile(this.getCurrentModelIconResourcePath()))
            .width(14)
            .height(14)
            .objectFit(ImageFit.Contain)
        } else {
          Image(this.getCurrentModelIconResourcePath())
            .width(14)
            .height(14)
            .objectFit(ImageFit.Contain)
        }
      }
      .width(22)
      .height(22)
      .borderRadius(6)
      .backgroundColor($r('app.color.model_icon_bg'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.hasProviderIdentity()) {
      ProviderIconSmall({
        iconPath: this.currentProviderIconPath,
        iconSize: 20,
        iconType: this.currentProviderIconType,
        textIcon: this.currentProviderTextIcon,
        textIconBgColor: this.currentProviderTextIconBgColor,
        customImagePath: this.currentProviderCustomImagePath,
        brandColor: this.currentProviderBrandColor,
        isDarkMode: this.isDarkMode
      })
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.ai_edit'))
          .fontSize(14)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width(22)
      .height(22)
      .borderRadius(6)
      .backgroundColor($r('app.color.model_icon_bg'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  private BackButtonBuilder() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(14)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(CHAT_NAVIGATION_ACTION_BUTTON_SIZE)
    .height(CHAT_NAVIGATION_ACTION_BUTTON_SIZE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .backgroundColor(this.getNavigationActionButtonBackgroundColor())
    .scale(getButtonScale(this.backBtnPressed))
    .animation(getButtonAnimation())
    .onTouch(createButtonTouchHandler((pressed: boolean): void => {
      this.backBtnPressed = pressed
    }))
    .onClick(() => {
      this.onBack()
    })
  }

  @Builder
  private NewChatButtonBuilder() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(14)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(CHAT_NAVIGATION_ACTION_BUTTON_SIZE)
    .height(CHAT_NAVIGATION_ACTION_BUTTON_SIZE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .backgroundColor(this.getNavigationActionButtonBackgroundColor())
    .scale(getButtonScale(this.newChatBtnPressed))
    .animation(getButtonAnimation())
    .onTouch(createButtonTouchHandler((pressed: boolean): void => {
      this.newChatBtnPressed = pressed
    }))
    .onClick(() => {
      this.onNewChat()
    })
  }

  @Builder
  private MoreButtonBuilder() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(13)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(CHAT_NAVIGATION_ACTION_BUTTON_SIZE)
    .height(CHAT_NAVIGATION_ACTION_BUTTON_SIZE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .backgroundColor(this.getNavigationActionButtonBackgroundColor())
    .scale(getButtonScale(this.moreBtnPressed))
    .animation(getButtonAnimation())
    .onTouch(createButtonTouchHandler((pressed: boolean): void => {
      this.moreBtnPressed = pressed
    }))
    .onClick(() => {
      this.onMore()
    })
  }

  build() {
    Row() {
      Row() {
        this.BackButtonBuilder()
      }
      .width(this.leftActionLaneWidth)
      .height(CHAT_NAVIGATION_TITLE_STACK_BUILDER_HEIGHT)
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)

      Column() {
        if (this.isEditingTitle) {
          TextInput({ text: this.editingTitleInput, placeholder: $r('app.string.chat_title_input_placeholder') })
            .id(this.titleInputFocusId)
            .defaultFocus(true)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor(Color.Transparent)
            .border({ width: { bottom: 1 }, color: this.themePrimary })
            .maxLength(50)
            .height(36)
            .width('100%')
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
          Row({ space: 8 }) {
            Row() {
              this.IdentityIconBuilder()
            }
            .margin({ top: 1 })

            Column({ space: 1 }) {
              Row() {
                if (this.titleContainsLatex()) {
                  Markdown({
                    controller: this.titleMarkdownController,
                    text: this.normalizeLatexInTitle(this.sessionTitle)
                  })
                    .layoutWeight(1)
                    .constraintSize({ maxHeight: 22 })
                    .clip(true)
                    .backgroundColor(Color.Transparent)
                } else {
                  Text(this.sessionTitle)
                    .layoutWeight(1)
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
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .gesture(
                LongPressGesture()
                  .onAction(() => {
                    this.startEditingTitle()
                  })
              )

              Row({ space: 3 }) {
                Text(this.getCurrentModelTitle())
                  .layoutWeight(1)
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getModelIdentityTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontSize(9)
                  .fontColor([this.getModelIdentityChevronColor()])
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.onModelSelect()
              })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }
      .layoutWeight(1)
      .height(CHAT_NAVIGATION_TITLE_STACK_BUILDER_HEIGHT)
      .padding({
        left: this.isEditingTitle ? 6 : 4,
        right: this.isEditingTitle ? 8 : 6,
        top: this.isEditingTitle ? 4 : 2,
        bottom: this.isEditingTitle ? 4 : 2
      })
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Color.Transparent)

      Row({ space: 6 }) {
        if (this.showNewChatAction) {
          this.NewChatButtonBuilder()
        }
        this.MoreButtonBuilder()
      }
      .width(this.rightActionLaneWidth)
      .height(CHAT_NAVIGATION_TITLE_STACK_BUILDER_HEIGHT)
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(CHAT_NAVIGATION_TITLE_STACK_BUILDER_HEIGHT)
    .padding({ left: 12, right: 12 })
    .translate({ y: -2 })
    .backgroundColor(Color.Transparent)
  }
}
