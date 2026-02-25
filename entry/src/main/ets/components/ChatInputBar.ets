import { getModelIconPath, buildIconResourcePath } from '../utils/ProviderIconUtils'
import { MessageAttachment, AttachmentType } from '../models/ChatModels'
import {
  BaseItemInfo,
  PhotoSource,
  RecentPhotoComponent,
  RecentPhotoOptions,
  photoAccessHelper
} from '@kit.MediaLibraryKit'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { getAttachmentStorageService } from '../services/AttachmentStorageService'

@Component
export struct ChatInputBar {
  // 图标动画触发器
  @State iconTrigger: number = 0
  // pause 呼吸动效透明度
  @State breathOpacity: number = 1
  // 按钮按下状态
  @State sendBtnPressed: boolean = false
  @State sendBtnScale: number = 1
  @State sendBtnRotation: number = 0
  @State modelBtnPressed: boolean = false
  @State attachBtnPressed: boolean = false
  @Link @Watch('onInputOrAttachmentsChanged') inputText: string
  @Link @Watch('onInputOrAttachmentsChanged') attachments: MessageAttachment[]
  @Prop @Watch('onSendingChanged') isSending: boolean = false
  // isSending 为 true 且 AI 尚未开始输出时，pause 显示轻微呼吸感
  @Prop @Watch('onAwaitingChanged') isAwaitingResponse: boolean = false
  @Prop currentModelId: string = ''
  @Prop currentProviderId: string = ''
  @Prop currentModelName: string = ''
  @Prop currentProviderIconType: string = 'svg'
  @Prop currentProviderIconPath: string = ''
  @Prop currentProviderTextIcon: string = ''
  @Prop currentProviderTextIconBgColor: string = ''
  @Prop currentProviderCustomImagePath: string = ''
  @Prop currentProviderBrandColor: ResourceColor = ''
  // 是否自动聚焦输入框
  @Prop @Watch('onAutoFocusChanged') autoFocus: boolean = false
  // 主题颜色（从 ThemeService 同步）
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_user_bubble') themeUserBubble: string = '#0A59F7'
  @StorageProp('isDarkMode') isDarkMode: boolean = false
  // ========== 最近截图相关 ==========
  private recentPhotoOptions: RecentPhotoOptions = new RecentPhotoOptions()
  @State hasRecentPhoto: boolean = false // 当前是否存在符合时间条件的截图
  // ========== 编辑模式相关属性 ==========
  @Prop isEditing: boolean = false // 是否编辑模式
  onCancelEdit: () => void = () => {
  } // 取消编辑回调
  onSend: () => void = () => {
  }
  onStop: () => void = () => {
  }
  onModelIconClick: () => void = () => {
  }
  onAttachmentClick: () => void = () => {
  }
  onInputFocus: () => void = () => {
  } // 输入框获得焦点回调
  onInputBlur: () => void = () => {
  } // 输入框失去焦点回调
  // 最近截图检测回调（通知父组件渲染 banner）
  onRecentPhotoDetected: (detected: boolean) => void = () => {
  }
  private lastHasContent: boolean = false
  private breatheTimerId: number = -1
  // 焦点控制器
  private focusController: TextAreaController = new TextAreaController()

  private getCurrentModelIconPath(): string {
    if (this.currentModelId === '' || this.currentProviderId === '') {
      return ''
    }
    return getModelIconPath(this.currentModelId, this.currentProviderId, '')
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

  aboutToAppear(): void {
    this.lastHasContent = this.computeHasContent()
    this.updateBreathing()
    this.initRecentPhotoOptions()
  }

  aboutToDisappear(): void {
    this.stopBreathing()
  }

  // 监听 autoFocus 变化
  onAutoFocusChanged(): void {
    if (this.autoFocus) {
      // 延迟聚焦，确保组件已渲染
      setTimeout(() => {
        focusControl.requestFocus('chatInputTextArea')
      }, 50)
    }
  }

  build() {
    Column() {
      // 隐藏的 RecentPhotoComponent 用于检测截图
      this.HiddenRecentPhotoDetector()

      // 编辑模式提示条
      if (this.isEditing) {
        Row() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(12)
            .fontColor([this.themePrimary])

          Text($r('app.string.editing_message'))
            .fontSize(12)
            .fontColor(this.themePrimary)
            .margin({ left: 4 })
        }
        .width('100%')
        .height(28)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.chat_ai_bubble'))
        .borderRadius(8)
        .margin({ bottom: 8 })
      }

      // 附件预览区域
      this.AttachmentPreview()

      // 输入栏主体
      Row() {
        // 模型图标按钮 - 点击触发快速切换（编辑模式下也可点击切换模型）
        Button({ type: ButtonType.Circle }) {
          if (this.currentModelId !== '') {
            if (this.hasCurrentModelIcon()) {
              Column() {
                Image(this.getCurrentModelIconResourcePath())
                  .width(18)
                  .height(18)
                  .objectFit(ImageFit.Contain)
              }
              .width(28)
              .height(28)
              .borderRadius(8)
              .backgroundColor($r('app.color.model_icon_bg'))
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else {
              Column() {
                SymbolGlyph($r('sys.symbol.ai_edit'))
                  .fontSize(14)
                  .fontColor([$r('app.color.text_tertiary')])
              }
              .width(28)
              .height(28)
              .borderRadius(8)
              .backgroundColor($r('app.color.model_icon_bg'))
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
          } else {
            SymbolGlyph($r('sys.symbol.ai_edit'))
              .fontSize(22)
              .fontColor([$r('app.color.text_secondary')])
          }
        }
        .width(40)
        .height(40)
        .backgroundColor(this.modelBtnPressed ? $r('app.color.divider') : $r('app.color.chat_ai_bubble'))
        .scale({ x: this.modelBtnPressed ? 0.95 : 1, y: this.modelBtnPressed ? 0.95 : 1 })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.modelBtnPressed = true
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.modelBtnPressed = false
          }
        })
        .onClick(() => {
          this.onModelIconClick()
        })

        // 输入框
        TextArea({ text: this.inputText, placeholder: $r('app.string.input_placeholder') })
          .id('chatInputTextArea')
          .placeholderColor($r('app.color.text_tertiary'))
          .placeholderFont({ size: 16 })
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .constraintSize({ minHeight: 40, maxHeight: 120 })
          .padding({
            left: 12,
            right: 12,
            top: 10,
            bottom: 10
          })
          .onChange((value: string) => {
            this.inputText = value
          })
          .onFocus(() => {
            this.onInputFocus()
          })
          .onBlur(() => {
            this.onInputBlur()
          })

        // 附件按钮（+号）
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(20)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(40)
        .height(40)
        .backgroundColor(this.attachBtnPressed ? $r('app.color.divider') : Color.Transparent)
        .scale({ x: this.attachBtnPressed ? 0.95 : 1, y: this.attachBtnPressed ? 0.95 : 1 })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.attachBtnPressed = true
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.attachBtnPressed = false
          }
        })
        .onClick(() => {
          this.onAttachmentClick()
        })

        // 发送/停止按钮（编辑模式下为"保存并发送"）
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.getSendButtonSymbol())
            .fontSize(this.isSending ? 20 : 22)
            .fontColor([Color.White])
            .symbolEffect(
              new ReplaceSymbolEffect(EffectScope.WHOLE),
              this.iconTrigger
            )
            .opacity(this.breathOpacity)
            .animation({ duration: 850, curve: Curve.EaseInOut })
        }
        .width(40)
        .height(40)
        .backgroundColor(this.themeUserBubble)
        .shadow({
          radius: this.sendBtnPressed ? 24 : 16,
          color: this.themeUserBubble + (this.sendBtnPressed ? '66' : '40'),
          offsetX: 0,
          offsetY: this.sendBtnPressed ? 6 : 4
        })
        .scale({
          x: this.sendBtnPressed ? 0.95 * this.sendBtnScale : this.sendBtnScale,
          y: this.sendBtnPressed ? 0.95 * this.sendBtnScale : this.sendBtnScale
        })
        .rotate({ angle: this.sendBtnRotation })
        .animation({ duration: 200, curve: Curve.EaseInOut })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.sendBtnPressed = true
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.sendBtnPressed = false
          }
        })
        .onClick(() => {
          if (this.isSending) {
            this.onStop()
          } else {
            if (!this.computeHasContent()) {
              return
            }
            this.onSend()
          }
        })
      }
      .width('100%')
      .padding({
        left: 6,
        right: 6,
        top: 6,
        bottom: 6
      })
    }
    .width('100%')
    .borderRadius(24)
    .backgroundColor(Color.Transparent)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({
      width: this.isEditing ? 2 : 0.5,
      color: this.isEditing ? this.themePrimary : $r('app.color.divider')
    })
    .shadow({
      radius: this.isEditing ? 16 : 32,
      color: this.isEditing ? this.themePrimary + '26' : 'rgba(0, 0, 0, 0.1)',
      offsetX: 0,
      offsetY: this.isEditing ? -4 : 8
    })
    .animation({ duration: 200 })
    .width('100%')
    .clip(false)
  }

  @Builder
  AttachmentPreview() {
    Scroll() {
      Row() {
        ForEach(this.attachments, (attachment: MessageAttachment, index: number) => {
          this.AttachmentItem(attachment, index)
        })
      }
      .justifyContent(FlexAlign.Start)
      .padding({
        left: 8,
        right: 8,
        top: this.attachments.length > 0 ? 8 : 0,
        bottom: this.attachments.length > 0 ? 4 : 0
      })
      .height(this.attachments.length > 0 ? 'auto' : 0)
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
    .height(this.attachments.length > 0 ? 'auto' : 0)
  }

  // 隐藏的 RecentPhotoComponent 用于检测截图
  @Builder
  HiddenRecentPhotoDetector() {
    RecentPhotoComponent({
      recentPhotoOptions: this.recentPhotoOptions,
      onRecentPhotoClick: (info: BaseItemInfo): boolean => {
        // 无需处理，我们使用自定义UI
        return true
      },
      onRecentPhotoCheckResult: (exists: boolean): void => this.onReceiveCheckResult(exists)
    })
      .width(0)
      .height(0)
      .opacity(0)
  }

  @Builder
  AttachmentItem(attachment: MessageAttachment, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (attachment.type === AttachmentType.IMAGE) {
        // 图片预览 - 优先使用文件路径（需要 file:// 协议），备选使用 base64
        if (attachment.filePath !== '') {
          Image('file://' + attachment.filePath)
            .width(60)
            .height(60)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        } else if (attachment.base64Data !== '') {
          Image(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
            .width(60)
            .height(60)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        }
      } else {
        // 文件预览
        Column() {
          SymbolGlyph($r('sys.symbol.doc'))
            .fontSize(24)
            .fontColor([$r('app.color.text_secondary')])

          Text(attachment.name)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 50 })
        }
        .width(60)
        .height(60)
        .borderRadius(8)
        .backgroundColor($r('app.color.background'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      // 删除按钮
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(10)
          .fontColor([Color.White])
      }
      .width(18)
      .height(18)
      .backgroundColor('rgba(0, 0, 0, 0.6)')
      .margin({ top: -4, right: -4 })
      .onClick(() => {
        this.removeAttachment(index)
      })
    }
    .margin({ right: 8 })
  }

  private removeAttachment(index: number): void {
    this.attachments.splice(index, 1)
    // 触发数组更新
    this.attachments = [...this.attachments]
  }

  // ========== 最近截图相关方法 ==========

  // 初始化最近截图组件配置
  private initRecentPhotoOptions(): void {
    // 只监听图片类型
    this.recentPhotoOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
    // 时间范围：5分钟（300秒），适合刚截图的场景
    this.recentPhotoOptions.period = 300
    // 只监听截图来源
    this.recentPhotoOptions.photoSource = PhotoSource.SCREENSHOT
    console.info('ChatInputBar', 'RecentPhoto options initialized')
  }

  // 最近截图检查结果回调
  private onReceiveCheckResult(exists: boolean): void {
    console.info('ChatInputBar', `RecentPhoto check result: exists=${exists}`)
    this.hasRecentPhoto = exists
    // 通知父组件
    this.onRecentPhotoDetected(exists)
  }

  private computeHasContent(): boolean {
    return this.inputText.trim() !== '' || this.attachments.length > 0
  }

  private getSendButtonSymbol(): Resource {
    if (this.isSending) {
      return $r('sys.symbol.pause')
    }

    if (this.computeHasContent()) {
      return $r('sys.symbol.paperplane_right_fill')
    }

    return $r('sys.symbol.paperplane')
  }

  private onInputOrAttachmentsChanged(): void {
    if (this.isSending) {
      return
    }

    const hasContent = this.computeHasContent()
    if (hasContent === this.lastHasContent) {
      return
    }

    this.lastHasContent = hasContent
    this.iconTrigger++
  }

  private onSendingChanged(): void {
    this.iconTrigger++
    this.lastHasContent = this.computeHasContent()
    this.updateBreathing()
    // 发送按钮状态切换动画
    this.animateSendButton()
  }

  // 发送按钮状态切换动画
  private animateSendButton(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.sendBtnScale = this.isSending ? 0.9 : 1
      this.sendBtnRotation = 0
    })
  }

  private onAwaitingChanged(): void {
    this.updateBreathing()
  }

  private updateBreathing(): void {
    if (this.isSending && this.isAwaitingResponse) {
      this.startBreathing()
      return
    }

    this.stopBreathing()
  }

  private startBreathing(): void {
    if (this.breatheTimerId >= 0) {
      return
    }

    this.breathOpacity = 1
    this.breatheTimerId = setInterval(() => {
      this.breathOpacity = this.breathOpacity > 0.8 ? 0.35 : 1
    }, 850)
  }

  private stopBreathing(): void {
    if (this.breatheTimerId < 0) {
      this.breathOpacity = 1
      return
    }

    clearInterval(this.breatheTimerId)
    this.breatheTimerId = -1
    this.breathOpacity = 1
  }
}
