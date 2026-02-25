import { AttachmentType, MessageAttachment } from '../../models/ChatModels'

@Component
export struct DraftPreviewBubble {
  @Prop inputText: string = ''
  @Prop pendingAttachments: MessageAttachment[] = []
  @StorageProp('theme_user_bubble') themeUserBubble: string = '#0A59F7'
  @StorageProp('theme_user_bubble_text') themeUserBubbleText: string = '#FFFFFF'
  @Prop previewTimeText: string = ''
  draftPreviewImageMaxHeight: number = 120
  draftPreviewImageContainerWidth: number = 180
  draftPreviewImageGap: number = 6

  private getDraftImageAttachmentIndices(): number[] {
    const imageIndices: number[] = []
    for (let i = 0; i < this.pendingAttachments.length; i++) {
      if (this.pendingAttachments[i].type === AttachmentType.IMAGE) {
        imageIndices.push(i)
      }
    }
    return imageIndices
  }

  private buildDraftImageGridRows(imageCount: number): number[] {
    const rows: number[] = []
    if (imageCount <= 0) {
      return rows
    }
    const rowCount = Math.ceil(imageCount / 2)
    for (let i = 0; i < rowCount; i++) {
      rows.push(i)
    }
    return rows
  }

  @Builder
  private DraftPreviewSingleImage(attachment: MessageAttachment, bottomMargin: number) {
    if (attachment.filePath !== '') {
      Image('file://' + attachment.filePath)
        .width(this.draftPreviewImageContainerWidth)
        .height(this.draftPreviewImageMaxHeight)
        .objectFit(ImageFit.Contain)
        .borderRadius(12)
        .clip(true)
        .margin({ bottom: bottomMargin })
    } else if (attachment.base64Data !== '') {
      Image(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
        .width(this.draftPreviewImageContainerWidth)
        .height(this.draftPreviewImageMaxHeight)
        .objectFit(ImageFit.Contain)
        .borderRadius(12)
        .clip(true)
        .margin({ bottom: bottomMargin })
    }
  }

  @Builder
  private DraftPreviewGridImage(attachment: MessageAttachment) {
    if (attachment.filePath !== '') {
      Image('file://' + attachment.filePath)
        .width('100%')
        .height(this.draftPreviewImageMaxHeight)
        .objectFit(ImageFit.Contain)
        .borderRadius(12)
        .clip(true)
        .layoutWeight(1)
    } else if (attachment.base64Data !== '') {
      Image(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
        .width('100%')
        .height(this.draftPreviewImageMaxHeight)
        .objectFit(ImageFit.Contain)
        .borderRadius(12)
        .clip(true)
        .layoutWeight(1)
    }
  }

  @Builder
  private DraftPreviewImages(draftImageIndices: number[]) {
    if (draftImageIndices.length === 1) {
      this.DraftPreviewSingleImage(this.pendingAttachments[draftImageIndices[0]], this.inputText.trim().length > 0 ? 6 : 0)
    } else if (draftImageIndices.length > 1) {
      Column({ space: this.draftPreviewImageGap }) {
        ForEach(this.buildDraftImageGridRows(draftImageIndices.length), (rowIndex: number) => {
          Row({ space: this.draftPreviewImageGap }) {
            this.DraftPreviewGridImage(this.pendingAttachments[draftImageIndices[rowIndex * 2]])

            if (rowIndex * 2 + 1 < draftImageIndices.length) {
              this.DraftPreviewGridImage(this.pendingAttachments[draftImageIndices[rowIndex * 2 + 1]])
            } else {
              Blank()
                .layoutWeight(1)
            }
          }
          .width(this.draftPreviewImageContainerWidth)
        }, (rowIndex: number) => rowIndex.toString())
      }
      .margin({ bottom: this.inputText.trim().length > 0 ? 6 : 0 })
    }
  }

  build() {
    Column() {
      Row() {
        Blank()

        Column() {
          if (this.pendingAttachments.length > 0) {
            this.DraftPreviewImages(this.getDraftImageAttachmentIndices())
          }

          if (this.inputText.trim().length > 0) {
            Text(this.inputText.trim())
              .fontSize(15)
              .fontColor(this.themeUserBubbleText)
              .lineHeight(22)
          } else {
            Text($r('app.string.input_placeholder'))
              .fontSize(15)
              .fontColor(this.themeUserBubbleText)
              .opacity(0.45)
              .lineHeight(22)
          }
        }
        .padding(this.pendingAttachments.length > 0 ?
          {
            left: 8,
            right: 8,
            top: 8,
            bottom: 8
          } :
          {
            left: 14,
            right: 14,
            top: 10,
            bottom: 10
          })
        .backgroundColor(this.themeUserBubble)
        .borderRadius({
          topLeft: 20,
          topRight: 20,
          bottomLeft: 20,
          bottomRight: 6
        })
        .clip(true)
        .constraintSize({ maxWidth: '75%' })
        .opacity(0.55)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .alignItems(HorizontalAlign.End)
  }
}
