/**
 * 编辑消息半模态面板组件（重构版）
 * 支持完整输入功能：联网查询状态展示、推理级别选择、附件管理
 */

import { ReasoningLevel, MessageAttachment, AttachmentType } from '../models/ChatModels'

@Component
export struct EditMessageSheet {
  // 输入内容
  @Link editText: string
  // 附件列表
  @Link attachments: MessageAttachment[]
  // 联网查询启用状态
  @Link webSearchEnabled: boolean
  // 推理级别
  @Link reasoningLevel: ReasoningLevel
  // 是否为用户消息（控制显示"保存并发送"）
  @Prop isUserMessage: boolean = true
  // 原始内容（用于判断是否有修改）
  originalContent: string = ''
  originalAttachments: MessageAttachment[] = []

  // 回调
  onSaveAndSend: () => void = () => {}
  onSave: () => void = () => {}
  onClose: () => void = () => {}
  onAttachmentClick: () => void = () => {}
  onDeleteAttachment: (index: number) => void = () => {}

  // 内部状态
  @State private iconTrigger: number = 0
  @State private sendBtnPressed: boolean = false
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'

  build() {
    Column() {
      // 顶部工具栏（联网查询 + 推理）
      this.Toolbar()

      // 编辑区域
      TextArea({ text: $$this.editText, placeholder: $r('app.string.edit_message_placeholder') })
        .width('100%')
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(Color.Transparent)
        .fontSize(16)

      // 附件预览区域
      if (this.attachments.length > 0) {
        this.AttachmentPreview()
      }

      // 底部输入栏（模型图标 + 附件按钮 + 保存按钮）
      this.BottomBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  Toolbar() {
    Row() {
      // 联网查询状态胶囊（仅在工具中心启用时展示）
      if (this.webSearchEnabled) {
        Row() {
          SymbolGlyph($r('sys.symbol.worldclock'))
            .fontSize(14)
            .fontColor([Color.White])
          Text($r('app.string.chat_toolbar_web_search'))
            .fontSize(13)
            .fontColor(Color.White)
            .margin({ left: 4 })
        }
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(16)
        .backgroundColor(this.themePrimary)
      }

      // 推理级别按钮
      Button({ type: ButtonType.Capsule, stateEffect: false }) {
        Row() {
          SymbolGlyph($r('sys.symbol.lightbulb'))
            .fontSize(14)
            .fontColor([this.reasoningLevel !== ReasoningLevel.OFF ? Color.White : $r('app.color.text_secondary')])
          Text(this.getReasoningText())
            .fontSize(13)
            .fontColor(this.reasoningLevel !== ReasoningLevel.OFF ? Color.White : $r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
      }
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(this.reasoningLevel !== ReasoningLevel.OFF ? this.themePrimary : $r('app.color.surface'))
      .margin({ left: this.webSearchEnabled ? 8 : 0 })
      .border(this.reasoningLevel !== ReasoningLevel.OFF ? undefined : {
        width: 0.5,
        color: $r('app.color.divider')
      })
      .animation({ duration: 200, curve: Curve.EaseOut })
      .bindMenu(this.ReasoningMenuBuilder(), {
        placement: Placement.TopLeft
      })

      Blank()

      Button() {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([Color.White])
      }
      .type(ButtonType.Circle)
      .width(32)
      .height(32)
      .backgroundColor(this.themePrimary)
      .onClick(() => this.onSave())
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
  }

  // 获取推理级别显示文本
  private getReasoningText(): string | Resource {
    switch (this.reasoningLevel) {
      case ReasoningLevel.OFF:
        return $r('app.string.chat_toolbar_reasoning')
      case ReasoningLevel.LOW:
        return $r('app.string.chat_toolbar_reasoning_low')
      case ReasoningLevel.MEDIUM:
        return $r('app.string.chat_toolbar_reasoning_medium')
      case ReasoningLevel.HIGH:
        return $r('app.string.chat_toolbar_reasoning_high')
      default:
        return $r('app.string.chat_toolbar_reasoning')
    }
  }

  // 推理级别菜单构建器
  @Builder
  ReasoningMenuBuilder() {
    Column() {
      // 关闭选项
      this.ReasoningMenuItem(ReasoningLevel.OFF, $r('app.string.chat_toolbar_reasoning_off'))
      Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
      // 轻度推理
      this.ReasoningMenuItem(ReasoningLevel.LOW, $r('app.string.chat_toolbar_reasoning_low'))
      Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
      // 中度推理
      this.ReasoningMenuItem(ReasoningLevel.MEDIUM, $r('app.string.chat_toolbar_reasoning_medium'))
      Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
      // 重度推理
      this.ReasoningMenuItem(ReasoningLevel.HIGH, $r('app.string.chat_toolbar_reasoning_high'))
    }
    .width(160)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  ReasoningMenuItem(level: ReasoningLevel, label: string | Resource) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor(this.reasoningLevel === level ? this.themePrimary : $r('app.color.text_primary'))

      Blank()

      if (this.reasoningLevel === level) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([this.themePrimary])
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      this.reasoningLevel = level
    })
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
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    }
    .width('100%')
    .height(80)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  @Builder
  AttachmentItem(attachment: MessageAttachment, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 图片或文件预览
      Column() {
        if (attachment.type === AttachmentType.IMAGE) {
          // 图片附件 - 使用与 ChatInputBar 和 MessageBubble 相同的加载逻辑
          if (attachment.filePath !== '') {
            Image('file://' + attachment.filePath)
              .width(64)
              .height(64)
              .objectFit(ImageFit.Cover)
              .borderRadius(8)
          } else if (attachment.base64Data !== '') {
            Image(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
              .width(64)
              .height(64)
              .objectFit(ImageFit.Cover)
              .borderRadius(8)
          }
        } else {
          // 文件附件
          Column() {
            SymbolGlyph($r('sys.symbol.doc'))
              .fontSize(24)
              .fontColor([$r('app.color.text_secondary')])
            Text(this.getFileExtension(attachment.name))
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width(64)
          .height(64)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
        }
      }

      // 删除按钮
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(10)
          .fontColor([Color.White])
      }
      .width(20)
      .height(20)
      .backgroundColor('rgba(0, 0, 0, 0.5)')
      .margin({ top: -4, right: -4 })
      .onClick(() => {
        this.onDeleteAttachment(index)
      })
    }
    .margin({ right: 8 })
  }

  // 获取文件扩展名
  private getFileExtension(fileName: string): string {
    const lastDotIndex = fileName.lastIndexOf('.')
    if (lastDotIndex > 0 && lastDotIndex < fileName.length - 1) {
      return fileName.substring(lastDotIndex + 1).toUpperCase()
    }
    return 'FILE'
  }

  @Builder
  BottomBar() {
    Row() {
      // 附件按钮
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(20)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.onAttachmentClick())

      Blank()

      // 保存并发送按钮（仅用户消息）
      if (this.isUserMessage) {
        Button({ type: ButtonType.Capsule }) {
          Text($r('app.string.save_and_send'))
            .fontSize(14)
            .fontColor(Color.White)
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(this.themePrimary)
        .onClick(() => this.onSaveAndSend())
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 16 })
  }
}
