/**
 * 聊天导航栏组件
 * 包含返回按钮、标题显示与编辑、模型选择、新建对话、更多菜单
 */

import {
  createButtonTouchHandler,
  getButtonScale,
  getButtonAnimation
} from '../utils/ButtonAnimationUtils'
import { buildIconResourcePath, getModelIconPath, isNetworkIconPath, isSandboxIconPath } from '../utils/ProviderIconUtils'
import { HdsVisualComponent, HdsSceneController, HdsSceneType, hdsEffect } from '@kit.UIDesignKit'

@Component
export struct ChatNavigationBar {
  // 会话标题
  @Prop sessionTitle: string = '新对话'
  // 当前模型ID
  @Prop currentModelId: string = ''
  // 当前服务商ID
  @Prop currentProviderId: string = ''
  // 当前模型名称
  @Prop currentModelName: string = ''
  // 当前服务商名称
  @Prop currentProviderName: string = ''
  @Prop currentProviderIconType: string = 'svg'
  @Prop currentProviderIconPath: string = ''
  @Prop currentProviderTextIcon: string = ''
  @Prop currentProviderTextIconBgColor: string = ''
  @Prop currentProviderCustomImagePath: string = ''
  @Prop currentProviderBrandColor: ResourceColor = ''
  // 是否有消息（用于控制新建对话按钮显示）
  @Prop hasMessages: boolean = false
  // 标题是否正在生成
  @Prop isTitleGenerating: boolean = false
  // 标题生成是否失败
  @Prop titleGenerateFailed: boolean = false
  // 顶部安全区域高度（vp）
  @Prop topAvoidHeight: number = 0
  // 是否正在发送（用于禁用重新生成标题）
  @Prop isSending: boolean = false
  // 其他会话未读完成提醒数量
  @Prop otherSessionUnreadCount: number = 0

  // 回调函数
  onBack: () => void = () => {}
  onModelSelect: () => void = () => {}
  onNewChat: () => void = () => {}
  onRegenerateTitle: () => void = () => {}
  onTitleChanged: (newTitle: string) => void = () => {}
  onNavigateToModelManage: () => void = () => {}
  onDeleteChat: () => void = () => {}

  // 内部状态
  @State private backBtnPressed: boolean = false
  @State private newChatBtnPressed: boolean = false
  @State private moreBtnPressed: boolean = false
  @State private isEditingTitle: boolean = false
  @State private editingTitleInput: string = ''
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('isDarkMode') isDarkMode: boolean = false
  @StorageProp('ui_visual_enhanced') uiVisualEnhanced: boolean = false
  private navSceneController: HdsSceneController = new HdsSceneController().setSceneParams({
    backgroundMaskColors: ['#00000000', '#1A0A59F7', '#00000000'],
    firstEdgeFlowLight: {
      startPos: 0,
      endPos: 0.48,
      color: '#66FFFFFF'
    },
    secondEdgeFlowLight: {
      startPos: 0,
      endPos: -0.48,
      color: '#330A59F7'
    }
  })

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

  private buildButtonPressEffect(pressed: boolean) {
    return new hdsEffect.HdsEffectBuilder()
      .pressShadow(pressed && this.uiVisualEnhanced ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
      .buildEffect()
  }

  build() {
    Column() {
      // 状态栏占位（额外增加 4vp 间距，避免双行标题紧贴状态栏）
      Column()
        .width('100%')
        .height(this.topAvoidHeight + 2)

      // 导航栏内容
      Stack({ alignContent: Alignment.Center }) {
        if (this.uiVisualEnhanced) {
          this.NavigationVisualLayer()
        }

        Row() {
        // 返回按钮
        Stack({ alignContent: Alignment.TopEnd }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(32)
          .height(32)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .shadow({
            radius: this.backBtnPressed ? 8 : 0,
            color: 'rgba(0, 0, 0, 0.1)',
            offsetX: 0,
            offsetY: this.backBtnPressed ? 2 : 0
          })
          .visualEffect(this.buildButtonPressEffect(this.backBtnPressed))
          .scale(getButtonScale(this.backBtnPressed))
          .animation({ duration: 200, curve: Curve.EaseInOut })
          .onTouch(createButtonTouchHandler((pressed: boolean) => {
            this.backBtnPressed = pressed
          }))
          .onClick(() => {
            this.onBack()
          })

          if (this.otherSessionUnreadCount > 0) {
            Text(this.getUnreadBadgeText())
              .fontSize(9)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .padding({ left: 4, right: 4 })
              .height(14)
              .backgroundColor($r('app.color.status_error'))
              .borderRadius(7)
              .position({ x: 22, y: -4 })
          }
        }
        .width(36)
        .height(32)

        // 标题区域 - 点击可切换模型，长按编辑标题
        Row() {
          // 模型图标
          if (this.hasCurrentModelIdentity()) {
            if (this.hasCurrentModelIcon()) {
              Column() {
                if (this.isRawfileCurrentModelIcon()) {
                  Image($rawfile(this.getCurrentModelIconResourcePath()))
                    .width(16)
                    .height(16)
                    .objectFit(ImageFit.Contain)
                } else {
                  Image(this.getCurrentModelIconResourcePath())
                    .width(16)
                    .height(16)
                    .objectFit(ImageFit.Contain)
                }
              }
              .width(22)
              .height(22)
              .borderRadius(5)
              .backgroundColor($r('app.color.model_icon_bg'))
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else {
              Column() {
                SymbolGlyph($r('sys.symbol.ai_edit'))
                  .fontSize(14)
                  .fontColor([$r('app.color.text_tertiary')])
              }
              .width(22)
              .height(22)
              .borderRadius(5)
              .backgroundColor($r('app.color.model_icon_bg'))
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
          }

          if (this.isEditingTitle) {
            // 编辑模式：显示输入框
            TextInput({ text: this.editingTitleInput, placeholder: '输入标题' })
              .id('chat_title_input')
              .defaultFocus(true)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor(Color.Transparent)
              .border({ width: { bottom: 1 }, color: this.themePrimary })
              .maxLength(50)
              .layoutWeight(1)
              .margin({ left: this.hasCurrentModelIdentity() ? 6 : 0 })
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
            // 显示模式：显示标题文本
            Column() {
              // 会话标题（带状态指示）
              Row() {
                Text(this.sessionTitle)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(2)
                  .lineHeight(20)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                // 标题生成中指示器
                if (this.isTitleGenerating) {
                  LoadingProgress()
                    .width(14)
                    .height(14)
                    .color($r('app.color.text_tertiary'))
                    .margin({ left: 6 })
                }

                // 标题生成失败重试图标
                if (this.titleGenerateFailed && !this.isTitleGenerating) {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(14)
                    .fontColor([$r('app.color.text_tertiary')])
                    .margin({ left: 6 })
                    .onClick(() => {
                      this.onRegenerateTitle()
                    })
                }
              }

              Text(this.getCurrentModelTitle())
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 1 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: this.hasCurrentModelIdentity() ? 6 : 0 })
            .layoutWeight(1)
          }

          // 下拉箭头（编辑模式不显示）
          if (!this.isEditingTitle) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([$r('app.color.text_tertiary')])
              .margin({ left: 2 })
          }
        }
        .layoutWeight(1)
        .margin({ left: 8 })
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

        // 新建对话按钮（仅在有消息时显示）
        if (this.hasMessages) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(16)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(32)
          .height(32)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .margin({ left: 6 })
          .visualEffect(this.buildButtonPressEffect(this.newChatBtnPressed))
          .scale(getButtonScale(this.newChatBtnPressed))
          .animation(getButtonAnimation())
          .onTouch(createButtonTouchHandler((pressed: boolean) => {
            this.newChatBtnPressed = pressed
          }))
          .onClick(() => {
            this.onNewChat()
          })
        }

        // 更多菜单按钮
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
            .fontSize(16)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(32)
        .height(32)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .margin({ left: 6 })
        .visualEffect(this.buildButtonPressEffect(this.moreBtnPressed))
        .scale(getButtonScale(this.moreBtnPressed))
        .animation(getButtonAnimation())
        .onTouch(createButtonTouchHandler((pressed: boolean) => {
          this.moreBtnPressed = pressed
        }))
        .bindMenu(this.buildMoreMenu())
        }
        .width('100%')
        .height(56)
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .height(56)
    }
    .width('100%')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
  }

  @Builder
  private NavigationVisualLayer(): void {
    HdsVisualComponent()
      .scene(HdsSceneType.DUAL_EDGE_FLOW_LIGHT_WITH_BACKGROUND_MASK, this.navSceneController)
      .width('100%')
      .height(48)
      .margin({ left: 12, right: 12 })
      .borderRadius(16)
      .opacity(this.isDarkMode ? 0.46 : 0.62)
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

  private getUnreadBadgeText(): string {
    if (this.otherSessionUnreadCount > 99) {
      return '99+'
    }
    return this.otherSessionUnreadCount.toString()
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

      MenuItem({
        startIcon: $r('sys.symbol.gearshape'),
        content: $r('app.string.model_manage_title')
      })
      .onClick(() => {
        this.onNavigateToModelManage()
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
