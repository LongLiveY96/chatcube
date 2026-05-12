/**
 * 模型编辑半模态组件
 * 单页滚动布局：核心信息 → 能力标签
 *
 * 历史背景:这里曾经有一个"高级参数"折叠区,放 temperature / topP / presencePenalty / frequencyPenalty
 * 等采样参数。2026/05 重构后,所有采样参数都搬到助手设置(Assistant.xxxEnabled / xxx),模型级整段废弃。
 */
import { ModelInfo, InputMode, OutputMode, ModelInfoExtendedJson } from '../models/ChatModels'
import { LengthMetrics } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'
import { lookupModelAbilities, ModelAbility, ModelModality } from '../services/registry/ModelAbilityRegistry'

@ComponentV2
export struct ModelEditSheet {
  @Param model: ModelInfo = new ModelInfo('', '')
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  @Local tempName: string = ''
  // 能力开关状态（用于触发 UI 刷新）
  @Local capSupportsTools: boolean = false
  @Local capSupportsReasoning: boolean = false
  @Local capSupportsWebSearch: boolean = false
  @Local capSupportsVision: boolean = false
  @Local capSupportsStreaming: boolean = false
  @Local capOutputImage: boolean = false
  @Local reasoningStrategyOverride: string = ''
  // 回调函数
  @Event onSave: (draft: ModelInfoExtendedJson) => Promise<void> = async (_draft: ModelInfoExtendedJson): Promise<void> => {
  }
  @Event onCancel: () => void = () => {
  }

  aboutToAppear(): void {
    this.syncDraftFromModel()
  }

  private syncDraftFromModel(): void {
    this.tempName = this.model.name
    this.capSupportsTools = this.model.capabilities.supportsTools
    this.capSupportsReasoning = this.model.capabilities.supportsReasoning
    this.capSupportsWebSearch = this.model.capabilities.supportsWebSearch
    this.capSupportsVision = this.model.capabilities.supportsVision
    this.capSupportsStreaming = this.model.capabilities.supportsStreaming
    this.capOutputImage = this.model.outputMode === OutputMode.IMAGE
    this.reasoningStrategyOverride = this.model.reasoningStrategyOverride
  }

  private resetCapabilities(): void {
    const result = lookupModelAbilities(this.model.id)
    this.capSupportsTools = result.abilities.includes(ModelAbility.TOOL)
    this.capSupportsReasoning = result.abilities.includes(ModelAbility.REASONING)
    this.capSupportsVision = result.inputModalities.includes(ModelModality.IMAGE)
    this.capOutputImage = result.outputModalities.includes(ModelModality.IMAGE)
    this.capSupportsWebSearch = false
    this.capSupportsStreaming = true
  }

  private buildDraft(): ModelInfoExtendedJson {
    return {
      id: this.model.id,
      name: this.tempName,
      contextLength: this.model.contextLength,
      isEnabled: this.model.isEnabled,
      isRecommended: this.model.isRecommended,
      modelType: this.model.modelType,
      inputMode: this.capSupportsVision ? InputMode.VISION : InputMode.TEXT,
      outputMode: this.capOutputImage ? OutputMode.IMAGE : OutputMode.TEXT,
      capabilities: {
        supportsTools: this.capSupportsTools,
        supportsReasoning: this.capSupportsReasoning,
        supportsWebSearch: this.capSupportsWebSearch,
        supportsVision: this.capSupportsVision,
        supportsStreaming: this.capSupportsStreaming
      },
      reasoningStrategyOverride: this.reasoningStrategyOverride
    }
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
    .backgroundColor(getAppUiState().themeBackground)
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
        await this.onSave(this.buildDraft())
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
    .backgroundColor(getAppUiState().themeSurface)
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
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(getAppUiState().themeSurface)
    .borderRadius(16)
    .margin({ bottom: 12 })
  }

  @Builder
  CapabilityChipsSection() {
    Column() {
      Row() {
        Text('模型能力')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))

        Blank()

        Text('重置')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .onClick(() => {
            this.resetCapabilities()
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        // 工具调用
        Row() {
          SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
            .fontSize(16)
            .fontColor([this.capSupportsTools ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('工具调用')
            .fontSize(13)
            .fontColor(this.capSupportsTools ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capSupportsTools ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsTools = !this.capSupportsTools
        })

        // 推理
        Row() {
          SymbolGlyph($r('sys.symbol.AI_deep_thinking'))
            .fontSize(16)
            .fontColor([this.capSupportsReasoning ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('推理')
            .fontSize(13)
            .fontColor(this.capSupportsReasoning ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capSupportsReasoning ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsReasoning = !this.capSupportsReasoning
        })

        // 联网搜索
        Row() {
          SymbolGlyph($r('sys.symbol.ohos_wifi'))
            .fontSize(16)
            .fontColor([this.capSupportsWebSearch ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('联网搜索')
            .fontSize(13)
            .fontColor(this.capSupportsWebSearch ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })

        .backgroundColor(this.capSupportsWebSearch ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsWebSearch = !this.capSupportsWebSearch
        })

        // 视觉理解
        Row() {
          SymbolGlyph($r('sys.symbol.ohos_photo'))
            .fontSize(16)
            .fontColor([this.capSupportsVision ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('视觉理解')
            .fontSize(13)
            .fontColor(this.capSupportsVision ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capSupportsVision ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsVision = !this.capSupportsVision
        })

        // 图片生成
        Row() {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(16)
            .fontColor([this.capOutputImage ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('图片生成')
            .fontSize(13)
            .fontColor(this.capOutputImage ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capOutputImage ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capOutputImage = !this.capOutputImage
        })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(getAppUiState().themeSurface)
    .borderRadius(16)
    .margin({ bottom: 12 })
  }
}
