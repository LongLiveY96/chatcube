/**
 * 编辑消息半模态面板组件（重构版）
 * 支持完整输入功能：联网查询状态展示、推理开关、附件管理
 */

import { ReasoningLevel, MessageAttachment, AttachmentType } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { ReasoningControlMode } from '../services/ProviderCompatibilityRegistry'

@ComponentV2
export struct EditMessageSheet {
  @Param editText: string = ''
  @Event $editText: (value: string) => void = () => {}
  @Param attachments: MessageAttachment[] = []
  @Event $attachments: (value: MessageAttachment[]) => void = () => {}
  @Param hasSelectedTools: boolean = false
  @Param reasoningAvailable: boolean = false
  @Param reasoningControlMode: ReasoningControlMode = ReasoningControlMode.NONE
  @Param reasoningXhighAvailable: boolean = false
  @Param reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  @Event $reasoningLevel: (value: ReasoningLevel) => void = () => {}
  @Param isUserMessage: boolean = true
  // 原始内容（用于判断是否有修改）
  originalContent: string = ''
  originalAttachments: MessageAttachment[] = []

  // 回调
  @Event onSaveAndSend: () => void = () => {}
  @Event onSave: () => void = () => {}
  @Event onClose: () => void = () => {}
  @Event onAttachmentClick: () => void = () => {}
  @Event onDeleteAttachment: (index: number) => void = () => {}

  // 内部状态
  @Local private iconTrigger: number = 0
  @Local private sendBtnPressed: boolean = false
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  build() {
    Column() {
      // 顶部工具栏（联网查询 + 推理）
      this.Toolbar()

      // 编辑区域
      TextArea({ text: this.editText, placeholder: $r('app.string.edit_message_placeholder') })
        .width('100%')
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(Color.Transparent)
        .fontSize(16)
        .onChange((value: string) => {
          this.$editText(value)
        })

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
      if (this.hasSelectedTools) {
        Row() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(14)
            .fontColor([Color.White])
          Text('工具')
            .fontSize(13)
            .fontColor(Color.White)
            .margin({ left: 4 })
        }
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(16)
        .backgroundColor(this.themePrimary)
      }

      if (this.reasoningAvailable) {
        // 推理控制按钮
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row() {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(14)
              .fontColor([this.isReasoningEnabled() ? Color.White : $r('app.color.text_secondary')])
            Text($r('app.string.chat_toolbar_reasoning'))
              .fontSize(13)
              .fontColor(this.isReasoningEnabled() ? Color.White : $r('app.color.text_secondary'))
              .margin({ left: 4 })
            Text(this.getReasoningLevelText(this.reasoningLevel))
              .fontSize(12)
              .fontColor(this.isReasoningEnabled() ? Color.White : $r('app.color.text_secondary'))
              .margin({ left: 6 })
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(10)
              .fontColor([this.isReasoningEnabled() ? Color.White : $r('app.color.text_secondary')])
              .margin({ left: 2 })
          }
        }
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .backgroundColor(this.isReasoningEnabled() ? this.themePrimary : $r('app.color.surface'))
        .margin({ left: this.hasSelectedTools ? 8 : 0 })
        .border(this.isReasoningEnabled() ? undefined : {
          width: 0.5,
          color: $r('app.color.divider')
        })
        .animation({ duration: 200, curve: Curve.EaseOut })
        .bindMenu(this.ReasoningMenuBuilder(), {
          placement: Placement.BottomLeft,
          offset: { x: 0, y: 8 },
          backgroundColor: $r('app.color.surface'),
          backgroundBlurStyle: BlurStyle.Regular
        })
      }

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

  private isReasoningEnabled(): boolean {
    return this.reasoningLevel !== ReasoningLevel.OFF
  }

  private getReasoningLevelText(level: ReasoningLevel): Resource {
    switch (level) {
      case ReasoningLevel.AUTO:
        return $r('app.string.reasoning_level_auto')
      case ReasoningLevel.LOW:
        return $r('app.string.reasoning_level_low')
      case ReasoningLevel.MEDIUM:
        return $r('app.string.reasoning_level_medium')
      case ReasoningLevel.HIGH:
        return $r('app.string.reasoning_level_high')
      case ReasoningLevel.XHIGH:
        return $r('app.string.reasoning_level_xhigh')
      case ReasoningLevel.CUSTOM:
        return $r('app.string.reasoning_budget_custom')
      default:
        return $r('app.string.reasoning_level_off')
    }
  }

  @Builder
  private ReasoningMenuBuilder() {
    Menu() {
      this.ReasoningMenuItem(ReasoningLevel.OFF)
      this.ReasoningMenuItem(ReasoningLevel.AUTO)
      if (this.reasoningControlMode === ReasoningControlMode.EFFORT) {
        this.ReasoningMenuItem(ReasoningLevel.LOW)
        this.ReasoningMenuItem(ReasoningLevel.MEDIUM)
        this.ReasoningMenuItem(ReasoningLevel.HIGH)
        if (this.reasoningXhighAvailable) {
          this.ReasoningMenuItem(ReasoningLevel.XHIGH)
        }
      }
    }
  }

  @Builder
  private ReasoningMenuItem(level: ReasoningLevel) {
    if (this.reasoningLevel === level) {
      MenuItem({
        startIcon: $r('sys.symbol.checkmark'),
        content: this.getReasoningLevelText(level)
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.$reasoningLevel(level)
        })
    } else {
      MenuItem({
        content: this.getReasoningLevelText(level)
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.$reasoningLevel(level)
        })
    }
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

