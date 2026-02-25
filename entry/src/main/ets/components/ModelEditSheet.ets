/**
 * 模型编辑半模态组件
 * 单页滚动布局：核心信息 → 能力标签 → 可折叠高级参数
 */
import { ModelInfo, InputMode } from '../models/ChatModels'
import { LengthMetrics } from '@kit.ArkUI'

@Component
export struct ModelEditSheet {
  @ObjectLink model: ModelInfo
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @State tempName: string = ''
  // 能力开关状态（用于触发 UI 刷新）
  @State capSupportsTools: boolean = false
  @State capSupportsReasoning: boolean = false
  @State capSupportsWebSearch: boolean = false
  @State capSupportsVision: boolean = false
  @State capSupportsStreaming: boolean = false
  // 高级参数折叠状态
  @State isAdvancedExpanded: boolean = false
  // 高级参数本地状态（驱动 Slider 实时刷新）
  @State paramTemperature: number = 0.7
  @State paramTopP: number = 1.0
  @State paramPresencePenalty: number = 0
  @State paramFrequencyPenalty: number = 0
  // 回调函数
  onSave: () => Promise<void> = async (): Promise<void> => {
  }
  onCancel: () => void = () => {
  }

  aboutToAppear(): void {
    this.tempName = this.model.name
    this.capSupportsTools = this.model.capabilities.supportsTools
    this.capSupportsReasoning = this.model.capabilities.supportsReasoning
    this.capSupportsWebSearch = this.model.capabilities.supportsWebSearch
    this.capSupportsVision = this.model.capabilities.supportsVision
    this.capSupportsStreaming = this.model.capabilities.supportsStreaming
    this.paramTemperature = this.model.parameters.temperature
    this.paramTopP = this.model.parameters.topP
    this.paramPresencePenalty = this.model.parameters.presencePenalty
    this.paramFrequencyPenalty = this.model.parameters.frequencyPenalty
  }

  build() {
    Column() {
      this.HeaderBar()

      Scroll() {
        Column() {
          // 核心信息区
          this.ModelIdSection()
          this.ModelNameSection()
          // 能力标签区
          this.CapabilityChipsSection()
          // 可折叠高级参数区
          this.AdvancedParametersSection()
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 34 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  HeaderBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
      }
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .backgroundColor($r('app.color.divider'))
      .onClick(() => {
        this.onCancel()
      })

      Text('编辑模型')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Button() {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([Color.White])
      }
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .backgroundColor(this.themePrimary)
      .onClick(async () => {
        await this.onSave()
        this.onCancel()
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  ModelIdSection() {
    Row() {
      Column() {
        Text('模型 ID')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ bottom: 4 })

        Text(this.model.id)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button() {
        SymbolGlyph($r('sys.symbol.rectangle_on_rectangle'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .type(ButtonType.Circle)
      .width(32)
      .height(32)
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .margin({ bottom: 12 })
  }

  @Builder
  ModelNameSection() {
    Column() {
      Text('模型名称')
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ bottom: 8 })

      TextInput({ text: this.tempName, placeholder: '输入模型显示名称' })
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.divider'))
        .borderRadius(12)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.tempName = value
          this.model.name = value
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .margin({ bottom: 12 })
  }

  @Builder
  CapabilityChipsSection() {
    Column() {
      Text('模型能力')
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        // 工具调用
        Row() {
          SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
            .fontSize(16)
            .fontColor([this.capSupportsTools ? $r('app.color.primary') : $r('app.color.text_tertiary')])
          Text('工具调用')
            .fontSize(13)
            .fontColor(this.capSupportsTools ? $r('app.color.primary') : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capSupportsTools ? $r('app.color.primary_light') : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsTools = !this.capSupportsTools
          this.model.capabilities.supportsTools = this.capSupportsTools
        })

        // 推理
        Row() {
          SymbolGlyph($r('sys.symbol.AI_deep_thinking'))
            .fontSize(16)
            .fontColor([this.capSupportsReasoning ? $r('app.color.primary') : $r('app.color.text_tertiary')])
          Text('推理')
            .fontSize(13)
            .fontColor(this.capSupportsReasoning ? $r('app.color.primary') : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capSupportsReasoning ? $r('app.color.primary_light') : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsReasoning = !this.capSupportsReasoning
          this.model.capabilities.supportsReasoning = this.capSupportsReasoning
        })

        // 联网搜索
        Row() {
          SymbolGlyph($r('sys.symbol.ohos_wifi'))
            .fontSize(16)
            .fontColor([this.capSupportsWebSearch ? $r('app.color.primary') : $r('app.color.text_tertiary')])
          Text('联网搜索')
            .fontSize(13)
            .fontColor(this.capSupportsWebSearch ? $r('app.color.primary') : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })

        .backgroundColor(this.capSupportsWebSearch ? $r('app.color.primary_light') : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsWebSearch = !this.capSupportsWebSearch
          this.model.capabilities.supportsWebSearch = this.capSupportsWebSearch
        })

        // 视觉理解
        Row() {
          SymbolGlyph($r('sys.symbol.ohos_photo'))
            .fontSize(16)
            .fontColor([this.capSupportsVision ? $r('app.color.primary') : $r('app.color.text_tertiary')])
          Text('视觉理解')
            .fontSize(13)
            .fontColor(this.capSupportsVision ? $r('app.color.primary') : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capSupportsVision ? $r('app.color.primary_light') : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsVision = !this.capSupportsVision
          this.model.capabilities.supportsVision = this.capSupportsVision
          this.model.inputMode = this.capSupportsVision ? InputMode.VISION : InputMode.TEXT
        })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .margin({ bottom: 12 })
  }

  @Builder
  AdvancedParametersSection() {
    Column() {
      // 折叠标题行
      Row() {
        Text('高级参数')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: this.isAdvancedExpanded ? 90 : 0 })
          .animation({ duration: 200, curve: Curve.EaseOut })
      }
      .width('100%')
      .height(48)
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
          this.isAdvancedExpanded = !this.isAdvancedExpanded
        })
      })

      // 展开内容
      if (this.isAdvancedExpanded) {
        Column() {
          // 温度
          Column() {
            Row() {
              Column() {
                Text('温度 (Temperature)')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('控制输出的随机性，值越高越有创意')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramTemperature.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary'))
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramTemperature,
              min: 0,
              max: 2,
              step: 0.1
            })
              .selectedColor($r('app.color.primary'))
              .trackColor($r('app.color.divider'))
              .blockColor(Color.White)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramTemperature = v
                this.model.parameters.temperature = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          // Top P
          Column() {
            Row() {
              Column() {
                Text('Top P')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('核采样参数，控制词汇选择范围')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramTopP.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary'))
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramTopP,
              min: 0,
              max: 1,
              step: 0.05
            })
              .selectedColor($r('app.color.primary'))
              .trackColor($r('app.color.divider'))
              .blockColor(Color.White)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramTopP = v
                this.model.parameters.topP = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          // 存在惩罚
          Column() {
            Row() {
              Column() {
                Text('存在惩罚 (Presence Penalty)')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('减少重复话题的出现')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramPresencePenalty.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary'))
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramPresencePenalty,
              min: -2,
              max: 2,
              step: 0.1
            })
              .selectedColor($r('app.color.primary'))
              .trackColor($r('app.color.divider'))
              .blockColor(Color.White)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramPresencePenalty = v
                this.model.parameters.presencePenalty = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          // 频率惩罚
          Column() {
            Row() {
              Column() {
                Text('频率惩罚 (Frequency Penalty)')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('减少重复词汇的出现')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramFrequencyPenalty.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary'))
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramFrequencyPenalty,
              min: -2,
              max: 2,
              step: 0.1
            })
              .selectedColor($r('app.color.primary'))
              .trackColor($r('app.color.divider'))
              .blockColor(Color.White)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramFrequencyPenalty = v
                this.model.parameters.frequencyPenalty = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          // 重置按钮
          Button('重置为默认值')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.divider'))
            .borderRadius(12)
            .height(44)
            .width('100%')
            .margin({ top: 12 })
            .onClick(() => {
              this.model.parameters.reset()
              this.paramTemperature = this.model.parameters.temperature
              this.paramTopP = this.model.parameters.topP
              this.paramPresencePenalty = this.model.parameters.presencePenalty
              this.paramFrequencyPenalty = this.model.parameters.frequencyPenalty
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 0,
      bottom: 16
    })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
  }
}
