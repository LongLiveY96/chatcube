import { ToolPreviewEntry } from '../../utils/ToolPayloadSummaryUtils'
import { getAppUiState } from '../../state/AppUiState'
import { pickLocalizedText } from '../../utils/LocalizedTextUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'

@ComponentV2
export struct ChatToolExecutionApprovalSheetContent {
  @Param sourceLabel: string = ''
  @Param toolName: string = ''
  @Param argumentSummary: string = ''
  @Param argumentEntries: ToolPreviewEntry[] = []
  @Param argumentsPreview: string = '{}'
  @Param argumentsTruncated: boolean = false
  @Param showRawArguments: boolean = false
  @Param alwaysAllowAvailable: boolean = false
  @Param isWriteTool: boolean = false
  @Param themePrimary: ResourceColor = ''
  @Param isDarkMode: boolean = false
  @Event onToggleShowRaw: () => void = (): void => {}
  @Event onCancel: () => void = (): void => {}
  @Event onAlwaysAllow: () => void = (): void => {}
  @Event onApprove: () => void = (): void => {}

  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }

  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }

  private get themePrimarySubtleBackground(): string {
    return withColorAlpha(getAppUiState().themePrimary, this.isDarkMode ? '28' : '16')
  }

  private get riskAccentColor(): string {
    return '#D9485F'
  }

  private get riskBackgroundColor(): string {
    return withColorAlpha(this.riskAccentColor, this.isDarkMode ? '28' : '12')
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 4 }) {
          Text(pickLocalizedText('确认工具调用', 'Approve Tool Call'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text(pickLocalizedText(
            '该工具可能修改外部状态，请确认后再继续。',
            'This tool may change external state. Confirm before continuing.'
          ))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.isWriteTool) {
          Text(pickLocalizedText('写操作', 'Write'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(999)
            .backgroundColor('#D9485F')
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Column({ space: 10 }) {
        Column({ space: 4 }) {
          Text(pickLocalizedText('来源', 'Source'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.sourceLabel.trim() !== '' ? this.sourceLabel : pickLocalizedText('未知来源', 'Unknown source'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 4 }) {
          Text(pickLocalizedText('工具', 'Tool'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.toolName.trim() !== '' ? this.toolName : pickLocalizedText('未知工具', 'Unknown tool'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(14)
      .borderRadius(16)
      .backgroundColor(this.themeSurface)

      if (this.isWriteTool) {
        Column({ space: 6 }) {
          Text(pickLocalizedText('风险提醒', 'Risk Notice'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.riskAccentColor)

          Text(pickLocalizedText(
            '这是写操作工具。模型只是提出调用，真正执行前仍需要你明确批准。',
            'This is a write tool. The model only proposes the call, and you still have to explicitly approve it.'
          ))
            .fontSize(12)
            .lineHeight(18)
            .fontColor(getAppUiState().themeTextSecondary)
            .width('100%')
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(this.riskBackgroundColor)
      }

      Column({ space: 8 }) {
        Row() {
          Text(pickLocalizedText('关键参数', 'Key Arguments'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.showRawArguments
            ? pickLocalizedText('收起原始参数', 'Hide Raw Arguments')
            : pickLocalizedText('查看原始参数', 'Show Raw Arguments'))
            .fontSize(11)
            .fontColor(this.themePrimary)
            .onClick(() => {
              this.onToggleShowRaw()
            })
        }
        .width('100%')

        if (this.argumentEntries.length > 0) {
          Column({ space: 8 }) {
            ForEach(this.argumentEntries, (entry: ToolPreviewEntry) => {
              Row() {
                Text(entry.label)
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .width(72)

                Text(entry.value)
                  .layoutWeight(1)
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }, (entry: ToolPreviewEntry, index: number) => `${entry.label}_${index}`)
          }
          .width('100%')
          .padding(12)
          .borderRadius(14)
          .backgroundColor(this.themeSurface)
        } else {
          Text(this.argumentSummary)
            .width('100%')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .padding(12)
            .borderRadius(14)
            .backgroundColor(this.themeSurface)
        }

        if (this.showRawArguments) {
          Scroll() {
            Text(this.argumentsPreview)
              .width('100%')
              .fontSize(12)
              .lineHeight(18)
              .fontFamily('monospace')
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Start)
          }
          .width('100%')
          .constraintSize({ maxHeight: 220 })
          .padding(12)
          .borderRadius(14)
          .backgroundColor(this.isDarkMode ? '#14171F' : '#F6F8FC')
        }

        if (this.showRawArguments && this.argumentsTruncated) {
          Text(pickLocalizedText(
            '仅展示前 800 个字符，避免长参数把确认面板撑坏。',
            'Only the first 800 characters are shown to keep the approval panel readable.'
          ))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
      }
      .width('100%')

      Row({ space: 10 }) {
        Button(pickLocalizedText('拒绝', 'Deny'))
          .layoutWeight(1)
          .height(46)
          .type(ButtonType.Capsule)
          .backgroundColor(this.themeSurface)
          .fontColor($r('app.color.text_primary'))
          .border({
            width: 0.5,
            color: $r('app.color.divider')
          })
          .onClick(() => {
            this.onCancel()
          })

        if (this.alwaysAllowAvailable) {
          Button(pickLocalizedText('始终允许', 'Always Allow'))
            .layoutWeight(1)
            .height(46)
            .type(ButtonType.Capsule)
            .backgroundColor(this.themePrimarySubtleBackground)
            .fontColor(this.themePrimary)
            .border({
              width: 0.5,
              color: this.themePrimary
            })
            .onClick(() => {
              this.onAlwaysAllow()
            })
        }

        Button(pickLocalizedText('允许一次', 'Allow Once'))
          .layoutWeight(1)
          .height(46)
          .type(ButtonType.Capsule)
          .backgroundColor(this.themePrimary)
          .fontColor(Color.White)
          .onClick(() => {
            this.onApprove()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 24 })
    .backgroundColor(this.themeBackground)
  }
}
