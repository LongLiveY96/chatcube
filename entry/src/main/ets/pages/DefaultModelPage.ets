// 默认模型配置页面
import { DefaultModelService } from '../services/DefaultModelService'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { DefaultModelConfig, ModelRole, ModelProvider } from '../models/ChatModels'
import { DefaultPrompts } from '../config/DefaultPrompts'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { DefaultModelSelectSheetContent } from '../components/defaultmodel/DefaultModelSelectSheetContent'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'

@Entry
@Component
struct DefaultModelPage {
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'

  @State chatModel: DefaultModelConfig = new DefaultModelConfig()
  @State titleModel: DefaultModelConfig = new DefaultModelConfig()
  @State translateModel: DefaultModelConfig = new DefaultModelConfig()
  @State searchOptimizationModel: DefaultModelConfig = new DefaultModelConfig()

  @State providers: ModelProvider[] = []
  @State isProvidersLoaded: boolean = false
  @State showModelSheet: boolean = false
  @State currentEditRole: ModelRole = ModelRole.CHAT
  @State showPromptSheet: boolean = false
  @State currentPromptRole: ModelRole = ModelRole.TITLE
  @State currentPrompt: string = ''
  private defaultModelService: DefaultModelService = ServiceRegistry.defaultModel()
  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()

  aboutToAppear(): void {
    this.loadConfig()
    this.loadProviders()
  }

  async loadConfig(): Promise<void> {
    await this.defaultModelService.loadConfig()
    this.chatModel = this.defaultModelService.getModel(ModelRole.CHAT)
    this.titleModel = this.defaultModelService.getModel(ModelRole.TITLE)
    this.translateModel = this.defaultModelService.getModel(ModelRole.TRANSLATE)
    this.searchOptimizationModel = this.defaultModelService.getModel(ModelRole.SEARCH_OPTIMIZATION)
  }

  async loadProviders(): Promise<void> {
    // 只加载启用的供应商（不包括禁用的）
    this.providers = await this.providerViewModel.loadProviders()
    this.isProvidersLoaded = true
    console.info(`[DefaultModelPage] Loaded ${this.providers.length} enabled providers`)
  }

  build() {
    Column() {
      HdsNavigation() {
        Scroll() {
          Column() {
            // 聊天模型配置
            this.SectionTitle($r('app.string.default_model_section_chat'))
            ModelConfigCard({
              roleName: $r('app.string.default_model_role_chat'),
              description: $r('app.string.default_model_desc_chat'),
              showPromptEdit: false,
              isConfigured: this.chatModel.isConfigured(),
              displayName: this.chatModel.getDisplayName(),
              isDefaultPrompt: true,
              onCardClick: () => {
                this.showPromptSheet = false
                this.currentEditRole = ModelRole.CHAT
                this.showModelSheet = true
              },
              onPromptClick: () => {}
            })

            // 标题生成模型配置
            this.SectionTitle($r('app.string.default_model_section_title_generation'))
            ModelConfigCard({
              roleName: $r('app.string.default_model_role_title_generation'),
              description: $r('app.string.default_model_desc_title_generation'),
              showPromptEdit: true,
              isConfigured: this.titleModel.isConfigured(),
              displayName: this.titleModel.getDisplayName(),
              isDefaultPrompt: this.defaultModelService.isDefaultTitlePrompt(),
              onCardClick: () => {
                this.showPromptSheet = false
                this.currentEditRole = ModelRole.TITLE
                this.showModelSheet = true
              },
              onPromptClick: () => {
                this.showModelSheet = false
                this.currentPromptRole = ModelRole.TITLE
                this.currentPrompt = this.defaultModelService.getTitlePromptTemplate()
                this.showPromptSheet = true
              }
            })

            // 翻译模型配置
            this.SectionTitle($r('app.string.default_model_section_translate'))
            ModelConfigCard({
              roleName: $r('app.string.default_model_role_translate'),
              description: $r('app.string.default_model_desc_translate'),
              showPromptEdit: true,
              isConfigured: this.translateModel.isConfigured(),
              displayName: this.translateModel.getDisplayName(),
              isDefaultPrompt: this.defaultModelService.isDefaultTranslatePrompt(),
              onCardClick: () => {
                this.showPromptSheet = false
                this.currentEditRole = ModelRole.TRANSLATE
                this.showModelSheet = true
              },
              onPromptClick: () => {
                this.showModelSheet = false
                this.currentPromptRole = ModelRole.TRANSLATE
                this.currentPrompt = this.defaultModelService.getTranslatePromptTemplate()
                this.showPromptSheet = true
              }
            })

            // 搜索优化模型配置
            this.SectionTitle($r('app.string.search_optimization_model'))
            ModelConfigCard({
              roleName: $r('app.string.search_optimization_model'),
              description: $r('app.string.search_optimization_desc'),
              showPromptEdit: false,
              isConfigured: this.searchOptimizationModel.isConfigured(),
              displayName: this.searchOptimizationModel.getDisplayName(),
              isDefaultPrompt: true,
              onCardClick: () => {
                this.showPromptSheet = false
                this.currentEditRole = ModelRole.SEARCH_OPTIMIZATION
                this.showModelSheet = true
              },
              onPromptClick: () => {}
            })

            // 底部留白
            Column().height(40)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background'))
      .titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: true,
        content: {
          title: {
            mainTitle: $r('app.string.settings_default_model')
          }
        }
      })
      .bindSheet($$this.showModelSheet, this.ModelSelectSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: true,
        title: { title: this.getSheetTitle() }
      })

      // bindSheet 宿主：每个 bindSheet 必须挂在独立组件上，避免多 bindSheet 冲突
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showPromptSheet, this.PromptEditSheet(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  SectionTitle(title: string | Resource) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .padding({ top: 24, bottom: 8 })
      .width('100%')
  }

  @Builder
  ModelSelectSheet() {
    DefaultModelSelectSheetContent({
      currentSelectionText: this.getCurrentModelDisplayName(),
      isProvidersLoaded: this.isProvidersLoaded,
      providers: this.providers,
      currentModelId: this.getCurrentModelId(),
      onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
        this.selectModel(providerId, modelId, modelName)
      },
      onClearSelection: () => {
        this.clearModelSelection()
      }
    })
  }

  @Builder
  PromptEditSheet() {
    Column() {
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
          this.showPromptSheet = false
        })

        Text(this.currentPromptRole === ModelRole.TITLE ?
          $r('app.string.default_model_prompt_edit_title_title') :
          $r('app.string.default_model_prompt_edit_title_translate'))
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
        .onClick(() => {
          this.savePrompt()
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })

      // 变量提示
      Column() {
        Text($r('app.string.default_model_prompt_variables'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        if (this.currentPromptRole === ModelRole.TITLE) {
          Text($r('app.string.default_model_prompt_title_variables_hint'))
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .margin({ top: 4 })
        } else {
          Text($r('app.string.default_model_prompt_translate_variables_hint'))
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .margin({ top: 4 })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(12)
      .margin({ left: 16, right: 16, top: 16 })

      // 编辑区域
      TextArea({ text: this.currentPrompt })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface'))
        .borderRadius(12)
        .margin({ left: 16, right: 16, top: 16 })
        .layoutWeight(1)
        .onChange((value: string) => {
          this.currentPrompt = value
        })

      // 按钮区域
      Row() {
        Button($r('app.string.default_model_reset_prompt'))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius(24)
          .height(44)
          .width('100%')
          .onClick(() => {
            this.resetPrompt()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 32 })
    }
    .width('100%')
    .height('100%')
  }

  private getSheetTitle(): Resource {
    if (this.currentEditRole === ModelRole.CHAT) {
      return $r('app.string.default_model_select_chat_model')
    } else if (this.currentEditRole === ModelRole.TITLE) {
      return $r('app.string.default_model_select_title_model')
    } else if (this.currentEditRole === ModelRole.SEARCH_OPTIMIZATION) {
      return $r('app.string.default_model_select_search_model')
    }
    return $r('app.string.default_model_select_translate_model')
  }

  // 获取当前选择的模型显示名称
  private getCurrentModelDisplayName(): string | Resource {
    let config: DefaultModelConfig
    if (this.currentEditRole === ModelRole.CHAT) {
      config = this.chatModel
    } else if (this.currentEditRole === ModelRole.TITLE) {
      config = this.titleModel
    } else if (this.currentEditRole === ModelRole.SEARCH_OPTIMIZATION) {
      config = this.searchOptimizationModel
    } else {
      config = this.translateModel
    }

    if (config.isConfigured()) {
      return config.getDisplayName()
    }
    return $r('app.string.default_model_unconfigured')
  }

  private getCurrentModelId(): string {
    let config: DefaultModelConfig
    if (this.currentEditRole === ModelRole.CHAT) {
      config = this.chatModel
    } else if (this.currentEditRole === ModelRole.TITLE) {
      config = this.titleModel
    } else if (this.currentEditRole === ModelRole.SEARCH_OPTIMIZATION) {
      config = this.searchOptimizationModel
    } else {
      config = this.translateModel
    }
    return config.modelId
  }

  private getProviderNameById(providerId: string): string {
    for (let i = 0; i < this.providers.length; i++) {
      if (this.providers[i].id === providerId) {
        return this.providers[i].name
      }
    }
    return ''
  }

  private async selectModel(providerId: string, modelId: string, modelName: string): Promise<void> {
    console.info(`[DefaultModelPage] Selecting model: ${modelId} from provider: ${providerId} for role: ${this.currentEditRole}`)
    const resolvedModelName = modelName !== '' ? modelName : modelId
    const providerName = this.getProviderNameById(providerId)
    const config = new DefaultModelConfig(modelId, providerId, resolvedModelName, providerName)
    await this.defaultModelService.setModel(this.currentEditRole, config)
    console.info(`[DefaultModelPage] Model saved, updating UI...`)

    // 立即更新状态变量
    if (this.currentEditRole === ModelRole.CHAT) {
      this.chatModel = new DefaultModelConfig(config.modelId, config.providerId, config.modelName, config.providerName)
    } else if (this.currentEditRole === ModelRole.TITLE) {
      this.titleModel = new DefaultModelConfig(config.modelId, config.providerId, config.modelName, config.providerName)
    } else if (this.currentEditRole === ModelRole.SEARCH_OPTIMIZATION) {
      this.searchOptimizationModel = new DefaultModelConfig(config.modelId, config.providerId, config.modelName, config.providerName)
    } else {
      this.translateModel = new DefaultModelConfig(config.modelId, config.providerId, config.modelName, config.providerName)
    }

    // 关闭 sheet
    this.showModelSheet = false
    console.info(`[DefaultModelPage] Model selection complete`)
  }

  private async clearModelSelection(): Promise<void> {
    console.info(`[DefaultModelPage] Clearing model selection for role: ${this.currentEditRole}`)
    const config = new DefaultModelConfig()
    await this.defaultModelService.setModel(this.currentEditRole, config)

    // 立即更新状态变量
    if (this.currentEditRole === ModelRole.CHAT) {
      this.chatModel = new DefaultModelConfig()
    } else if (this.currentEditRole === ModelRole.TITLE) {
      this.titleModel = new DefaultModelConfig()
    } else if (this.currentEditRole === ModelRole.SEARCH_OPTIMIZATION) {
      this.searchOptimizationModel = new DefaultModelConfig()
    } else {
      this.translateModel = new DefaultModelConfig()
    }

    // 关闭 sheet
    this.showModelSheet = false
  }

  private async resetPrompt(): Promise<void> {
    if (this.currentPromptRole === ModelRole.TITLE) {
      await this.defaultModelService.resetTitlePrompt()
      this.currentPrompt = DefaultPrompts.TITLE_PROMPT
    } else {
      await this.defaultModelService.resetTranslatePrompt()
      this.currentPrompt = DefaultPrompts.TRANSLATE_PROMPT
    }
  }

  private async savePrompt(): Promise<void> {
    if (this.currentPromptRole === ModelRole.TITLE) {
      await this.defaultModelService.setTitlePromptTemplate(this.currentPrompt)
    } else {
      await this.defaultModelService.setTranslatePromptTemplate(this.currentPrompt)
    }
    this.showPromptSheet = false
  }

}

// 独立的模型配置卡片组件，解决 @Builder 响应式问题
@Component
struct ModelConfigCard {
  @Prop roleName: string | Resource = ''
  @Prop description: string | Resource = ''
  @Prop showPromptEdit: boolean = false
  @Prop isDefaultPrompt: boolean = true

  // 使用基本类型避免对象响应式问题
  @Prop isConfigured: boolean = false
  @Prop displayName: string = ''
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'

  onCardClick: () => void = () => {}
  onPromptClick: () => void = () => {}

  build() {
    Column() {
      Row() {
        Column() {
          Row() {
            Text(this.roleName)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))

            if (this.isConfigured) {
              Text(this.displayName)
                .fontSize(13)
                .fontColor(this.themePrimary)
                .margin({ left: 8 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            } else {
              Text($r('app.string.default_model_unconfigured'))
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ left: 8 })
            }
          }
          .width('100%')

          Text(this.description)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
      .padding(16)
      .onClick(() => {
        this.onCardClick()
      })

      if (this.showPromptEdit) {
        Divider().color($r('app.color.divider')).margin({ left: 16 })

        Row() {
          Text($r('app.string.default_model_prompt_template'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))

          Blank()

          Text(this.isDefaultPrompt ?
            $r('app.string.default_model_prompt_template_default') :
            $r('app.string.default_model_prompt_template_custom'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))

          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(16)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ left: 8 })
        }
        .width('100%')
        .padding(16)
        .onClick(() => {
          this.onPromptClick()
        })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
  }
}
