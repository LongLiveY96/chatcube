import { ModelProvider, ModelInfo, ProviderType } from '../models/ChatModels'
import { ProviderIcon } from './ProviderIcon'

class ModelTagGroup {
  tagId: string
  tagLabel: Resource
  models: ModelInfo[]

  constructor(tagId: string, tagLabel: Resource) {
    this.tagId = tagId
    this.tagLabel = tagLabel
    this.models = []
  }
}

@Component
export struct ProviderCard {
  @ObjectLink provider: ModelProvider
  @State searchKeywords: string = ''
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  @StorageProp('theme_primary_light') themePrimaryLight: string = '#E6F2FF'
  onToggleExpand: () => void = () => {}
  onTestConnection: () => Promise<void> = async (): Promise<void> => {}
  onSaveConfig: () => Promise<void> = async (): Promise<void> => {}
  onRefreshModels: () => Promise<void> = async (): Promise<void> => {}

  build() {
    Column() {
      Row() {
        Row() {
          // 使用新的 ProviderIcon 组件
          ProviderIcon({
            iconType: this.provider.iconType,
            iconPath: this.provider.iconPath,
            textIcon: this.provider.textIcon,
            textIconBgColor: this.provider.textIconBgColor,
            customImagePath: this.provider.customImagePath,
            iconSize: 40,
            bgColor: this.provider.brandColor,
            radius: 12,
            brandColor: this.provider.brandColor,
            fallbackSymbol: this.getProviderFallbackSymbol(this.provider.type),
            fallbackColor: Color.White
          })

          Column() {
            Text(this.provider.name)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))

            Row() {
              if (this.provider.isConnected) {
                Circle()
                  .width(6)
                  .height(6)
                  .fill($r('app.color.status_success'))
                  .margin({ right: 4 })

                Text($r('app.string.connected'))
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              } else {
                Text(this.provider.baseUrl || this.provider.type)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }
            }
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 16 })
        }

        Blank()

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(20)
          .fontColor([this.themePrimary])
          .rotate({ angle: this.provider.isExpanded ? 180 : 0 })
          .animation({ duration: 200 })
      }
      .width('100%')
      .padding(16)
      .onClick(() => {
        this.onToggleExpand()
      })

      if (this.provider.isExpanded) {
        this.ExpandedContent()
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }

  // 获取供应商回退图标符号
  private getProviderFallbackSymbol(type: ProviderType): Resource {
    if (type === ProviderType.OPENAI) {
      return $r('sys.symbol.ai_edit')
    } else if (type === ProviderType.ANTHROPIC) {
      return $r('sys.symbol.star_message')
    } else if (type === ProviderType.OLLAMA) {
      return $r('sys.symbol.message')
    } else if (type === ProviderType.DEEPSEEK) {
      return $r('sys.symbol.plus_magnifyingglass')
    } else if (type === ProviderType.AZURE) {
      return $r('sys.symbol.message_on_message')
    } else if (type === ProviderType.CUSTOM) {
      return $r('sys.symbol.message')
    }
    return $r('sys.symbol.message_fill')
  }

  @Builder
  ExpandedContent() {
    Column() {
      Column() {
        Text($r('app.string.api_key'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 8 })

        Row() {
          TextInput({ text: this.provider.apiKey, placeholder: 'sk-...' })
            .type(InputType.Password)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.provider.apiKey = value
            })
        }
        .width('100%')
        .padding({ left: 16, right: 8, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .border({
          width: 1,
          color: $r('app.color.divider')
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 12 })

      Column() {
        Text($r('app.string.base_url'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 8 })

        TextInput({ text: this.provider.baseUrl, placeholder: 'https://api.openai.com/v1' })
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius(16)
          .border({
            width: 1,
            color: $r('app.color.divider')
          })
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onChange((value: string) => {
            this.provider.baseUrl = value
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      Column() {
        Row() {
          Text($r('app.string.available_models'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))

          Blank()

          Row() {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(14)
              .fontColor([this.themePrimary])
            Text($r('app.string.refresh_list'))
              .fontSize(12)
              .fontColor(this.themePrimary)
              .fontWeight(FontWeight.Medium)
              .margin({ left: 4 })
          }
          .onClick(() => {
            this.onRefreshModels()
          })
        }
        .width('100%')
        .margin({ bottom: 8 })

        // 搜索框
        Search({ value: this.searchKeywords, placeholder: '搜索模型...' })
          .width('100%')
          .height(40)
          .backgroundColor($r('app.color.background'))
          .margin({ bottom: 12 })
          .onChange((value: string) => {
            this.searchKeywords = value
          })

        // 检查是否有模型数据，若存在则进行分组展示
        if (this.provider.models.length > 0) {
          // 创建垂直布局容器
          Column() {
            // 遍历每个分组
            ForEach(this.groupModelsByTag(this.provider.models), (group: ModelTagGroup) => {
              // 为每个分组创建垂直布局容器
              Column() {

                this.ModelTagHeader(group.tagLabel)

                Column() {
                  ForEach(group.models, (model: ModelInfo, index: number) => {
                    Row() {
                      Checkbox()
                        .select(model.isEnabled)
                        .selectedColor(this.themePrimary)
                        .onChange((value: boolean) => {
                          model.isEnabled = value
                        })

                      Column() {
                        Text(model.name)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))

                        if (model.isRecommended) {
                          Text($r('app.string.recommended'))
                            .fontSize(11)
                            .fontColor(this.themePrimary)
                            .fontWeight(FontWeight.Medium)
                        }
                      }
                      .alignItems(HorizontalAlign.Start)
                      .margin({ left: 12 })

                      Blank()

                      Text(this.formatContextLength(model.contextLength))
                        .fontSize(12)
                        .fontColor($r('app.color.text_tertiary'))
                    }
                    .width('100%')
                    .padding(14)
                    .border({
                      width: { bottom: index < group.models.length - 1 ? 0.5 : 0 },
                      color: $r('app.color.divider')
                    })
                  })
                }
                .width('100%')
                .backgroundColor($r('app.color.surface'))
                .borderRadius(16)
                .border({
                  width: 1,
                  color: $r('app.color.divider')
                })
              }
              .width('100%')
              .margin({ bottom: 12 })
            })
          }
          .width('100%')
        } else {
          Column() {
            Text('暂无模型，点击刷新获取')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(16)
          .border({
            width: 1,
            color: $r('app.color.divider')
          })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      Row() {
        Button($r('app.string.test_connection'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor('rgba(0,0,0,0.05)')
          .borderRadius(24)
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.onTestConnection()
          })

        Button($r('app.string.save_config'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(this.themePrimary)
          .borderRadius(24)
          .layoutWeight(1)
          .height(44)
          .margin({ left: 12 })
          .shadow({
            radius: 12,
            color: 'rgba(0, 125, 255, 0.3)',
            offsetX: 0,
            offsetY: 4
          })
          .onClick(() => {
            this.onSaveConfig()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor('rgba(0,0,0,0.02)')
    .border({
      width: { top: 0.5 },
      color: $r('app.color.divider')
    })
  }

  @Builder
  ModelTagHeader(label: Resource) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.themePrimary)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .backgroundColor(this.themePrimaryLight)
        .borderRadius(12)
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  private groupModelsByTag(models: ModelInfo[]): ModelTagGroup[] {
    const groups: ModelTagGroup[] = []
    const keywords = this.searchKeywords.toLowerCase().trim()

    for (let i = 0; i < models.length; i++) {
      const model = models[i]

      // 搜索过滤
      if (keywords && model.name.toLowerCase().indexOf(keywords) === -1) {
        continue
      }

      const tagId = this.getModelTagId(model.id)
      const tagLabel = this.getModelTagLabel(tagId)
      let targetGroup: ModelTagGroup | null = null

      for (let j = 0; j < groups.length; j++) {
        if (groups[j].tagId === tagId) {
          targetGroup = groups[j]
          break
        }
      }

      if (targetGroup === null) {
        const newGroup = new ModelTagGroup(tagId, tagLabel)
        groups.push(newGroup)
        targetGroup = newGroup
      }

      targetGroup.models.push(model)
    }

    return this.sortModelGroups(groups)
  }

  private getModelTagId(modelId: string): string {
    const lowerId = modelId.toLowerCase()
    if (lowerId.indexOf('claude') >= 0 || lowerId.indexOf('anthropic') >= 0) {
      return 'claude'
    }
    if (lowerId.indexOf('gemini') >= 0 || lowerId.indexOf('google') >= 0) {
      return 'gemini'
    }
    if (lowerId.indexOf('gpt') >= 0 || lowerId.indexOf('openai') >= 0 || lowerId.indexOf('o1') >= 0) {
      return 'openai'
    }
    return 'other'
  }

  private getModelTagLabel(tagId: string): Resource {
    if (tagId === 'openai') {
      return $r('app.string.model_tag_openai')
    } else if (tagId === 'claude') {
      return $r('app.string.model_tag_claude')
    } else if (tagId === 'gemini') {
      return $r('app.string.model_tag_gemini')
    }
    return $r('app.string.model_tag_other')
  }

  private sortModelGroups(groups: ModelTagGroup[]): ModelTagGroup[] {
    const order: string[] = ['openai', 'claude', 'gemini', 'other']
    const sorted: ModelTagGroup[] = []

    for (let i = 0; i < order.length; i++) {
      const tagId = order[i]
      for (let j = 0; j < groups.length; j++) {
        if (groups[j].tagId === tagId) {
          sorted.push(groups[j])
          break
        }
      }
    }

    for (let i = 0; i < groups.length; i++) {
      const group = groups[i]
      let exists = false
      for (let j = 0; j < sorted.length; j++) {
        if (sorted[j].tagId === group.tagId) {
          exists = true
          break
        }
      }
      if (!exists) {
        sorted.push(group)
      }
    }

    return sorted
  }

  formatContextLength(length: number): string {
    if (length >= 1000) {
      return `${Math.floor(length / 1000)}k`
    }
    return length.toString()
  }
}

@Component
export struct AddProviderCard {
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'
  private provider: ModelProvider = new ModelProvider('', '', ProviderType.OPENAI, '', $r('app.color.primary'))
  onAdd: () => void = () => {}

  build() {
    Row() {
      Row() {
        // 使用新的 ProviderIcon 组件
        ProviderIcon({
          iconPath: this.provider.iconPath,
          iconSize: 40,
          bgColor: this.provider.brandColor,
          radius: 12,
          brandColor: this.provider.brandColor,
          fallbackSymbol: this.getProviderFallbackSymbol(this.provider.type),
          fallbackColor: Color.White
        })

        Column() {
          Text(this.provider.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text(this.provider.baseUrl || this.provider.type)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 16 })
      }

      Blank()

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(20)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .backgroundColor('rgba(0,0,0,0.05)')
      .onClick(() => {
        this.onAdd()
      })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
  }

  // 获取供应商回退图标符号
  private getProviderFallbackSymbol(type: ProviderType): Resource {
    if (type === ProviderType.OPENAI) {
      return $r('sys.symbol.ai_edit')
    } else if (type === ProviderType.ANTHROPIC) {
      return $r('sys.symbol.star_message')
    } else if (type === ProviderType.OLLAMA) {
      return $r('sys.symbol.message')
    } else if (type === ProviderType.DEEPSEEK) {
      return $r('sys.symbol.plus_magnifyingglass')
    } else if (type === ProviderType.AZURE) {
      return $r('sys.symbol.message_on_message')
    } else if (type === ProviderType.CUSTOM) {
      return $r('sys.symbol.message')
    }
    return $r('sys.symbol.message_fill')
  }
}
