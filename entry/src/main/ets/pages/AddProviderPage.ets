import { ModelProvider, ModelInfo, ProviderType, ApiStyle, ProviderIconType } from '../models/ChatModels'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { showToast } from '../utils/ToastUtil'
import { ModelPickerSheetHost } from '../components/ModelPickerSheetHost'
import { ProviderIconEditor } from '../components/ProviderIconEditor'
import { generateDefaultTextIcon } from '../utils/IconGeneratorUtils'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'

// API 风格选项
interface ApiStyleOption {
  style: ApiStyle
  name: string
  description: string | Resource
}

@Entry
@Component
struct AddProviderPage {
  // 主题颜色
  @StorageProp('theme_primary') themePrimary: string = '#0A59F7'

  @State providerName: string = ''
  @State baseUrl: string = ''
  @State apiPath: string = ''
  @State apiKey: string = ''
  @State selectedApiStyle: ApiStyle = ApiStyle.OPENAI
  @State modelInput: string = ''
  @State models: ModelInfo[] = []
  @State isTesting: boolean = false
  @State isSaving: boolean = false
  // 模型选择器相关状态
  @State showModelPicker: boolean = false
  @State fetchedModels: string[] = []
  // 图标配置相关状态
  @State iconType: string = 'text'
  @State iconPath: string = ''
  @State textIcon: string = ''
  @State textIconBgColor: string = ''

  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()

  // 初始化图标配置
  aboutToAppear(): void {
    const config = generateDefaultTextIcon('')
    this.textIcon = config.text
    this.textIconBgColor = config.bgColor
  }

  private apiStyleOptions: ApiStyleOption[] = [
    {
      style: ApiStyle.OPENAI,
      name: 'OpenAI',
      description: $r('app.string.api_style_openai_desc')
    },
    {
      style: ApiStyle.ANTHROPIC,
      name: 'Claude',
      description: $r('app.string.api_style_anthropic_desc')
    },
    {
      style: ApiStyle.GOOGLE,
      name: 'Google',
      description: $r('app.string.api_style_google_desc')
    }
  ]

  build() {
    Column() {
      HdsNavigation() {
        Column() {
          Scroll() {
            Column() {
              // 自定义配置表单
              Column() {
                this.ConfigFormSection()
              }

              Column().height(40)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 0, bottom: 24 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
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
            mainTitle: $r('app.string.add_custom_provider')
          }
        }
      })
      .bindSheet($$this.showModelPicker, this.ModelPickerSheetBuilder(), {
        height: SheetSize.LARGE,
        showClose: false,
        dragBar: true,
        blurStyle: BlurStyle.Regular,
        onDisappear: () => {
          this.clearPickerState()
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  // 配置表单区域
  @Builder
  ConfigFormSection() {
    Column() {
      // 服务商名称
      this.SectionTitle($r('app.string.provider_name'))
      TextInput({ text: $$this.providerName, placeholder: $r('app.string.provider_name_placeholder') })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.divider') })
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .onChange((value: string) => {
          // 自动生成文字图标
          if (this.iconType === 'text' && (this.textIcon === '' || this.textIcon === 'AI')) {
            const config = generateDefaultTextIcon(value)
            this.textIcon = config.text
            if (this.textIconBgColor === '') {
              this.textIconBgColor = config.bgColor
            }
          }
        })

      // 图标编辑器
      ProviderIconEditor({
        iconType: $iconType,
        iconPath: $iconPath,
        textIcon: $textIcon,
        textIconBgColor: $textIconBgColor,
        providerName: this.providerName,
        isPreset: false
      })

      // API 接口风格
      this.SectionTitle($r('app.string.api_style'))
      Column() {
        ForEach(this.apiStyleOptions, (option: ApiStyleOption, index: number) => {
          Row() {
            Radio({ value: option.style, group: 'apiStyle' })
              .checked(this.selectedApiStyle === option.style)
              .onChange((isChecked: boolean) => {
                if (isChecked) {
                  this.selectedApiStyle = option.style
                }
              })

            Column() {
              Text(option.name)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))

              Text(option.description)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })
            .layoutWeight(1)
          }
          .width('100%')
          .padding(16)
          .onClick(() => {
            this.selectedApiStyle = option.style
          })

          if (index < this.apiStyleOptions.length - 1) {
            Divider().color($r('app.color.divider')).margin({ left: 48 })
          }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(16)
      .margin({ top: 8, bottom: 16 })

      // Base URL
      this.SectionTitle($r('app.string.base_url'))
      TextInput({ text: $$this.baseUrl, placeholder: this.getDefaultBaseUrl() })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.divider') })
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      // API Path
      this.SectionTitle($r('app.string.api_path_optional'))
      TextInput({ text: $$this.apiPath, placeholder: $r('app.string.provider_api_path_placeholder') })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.divider') })
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      // API Key
      this.SectionTitle($r('app.string.api_key'))
      TextInput({ text: $$this.apiKey, placeholder: 'sk-...' })
        .type(InputType.Password)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.divider') })
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      // 模型列表
      this.SectionTitle($r('app.string.model_list'))
      Column() {
        Row() {
          TextInput({ text: this.modelInput, placeholder: $r('app.string.model_input_placeholder') })
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.modelInput = value
            })

          Button($r('app.string.add'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
            .backgroundColor('rgba(0,0,0,0.05)')
            .borderRadius(20)
            .height(36)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.addModel()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .border({
          width: 1,
          color: $r('app.color.divider')
        })

        if (this.models.length > 0) {
          Column() {
            ForEach(this.models, (model: ModelInfo, index: number) => {
              Row() {
                Text(model.name)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.xmark'))
                    .fontSize(14)
                    .fontColor([$r('app.color.text_tertiary')])
                }
                .width(28)
                .height(28)
                .backgroundColor('rgba(0,0,0,0.05)')
                .onClick(() => {
                  this.removeModel(index)
                })
              }
              .width('100%')
              .padding(12)

              if (index < this.models.length - 1) {
                Divider().color($r('app.color.divider'))
              }
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius(16)
          .margin({ top: 8 })
          .border({
            width: 1,
            color: $r('app.color.divider')
          })
        }
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 操作按钮
      Row() {
        Button($r('app.string.test_connection'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor('rgba(0,0,0,0.05)')
          .borderRadius(24)
          .layoutWeight(1)
          .height(48)
          .onClick(() => {
            this.testConnection()
          })

        Button($r('app.string.save'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(this.themePrimary)
          .borderRadius(24)
          .layoutWeight(1)
          .height(48)
          .margin({ left: 12 })
          .shadow({
            radius: 12,
            color: 'rgba(0, 125, 255, 0.3)',
            offsetX: 0,
            offsetY: 4
          })
          .onClick(() => {
            this.saveProvider()
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
  }

  @Builder
  SectionTitle(title: Resource) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 4, top: 16, bottom: 8 })
  }

  @Builder
  ModelPickerSheetBuilder() {
    ModelPickerSheetHost({
      availableModels: this.fetchedModels,
      existingModels: this.models,
      providerId: 'custom',
      onConfirm: (selectedIds: string[]) => {
        this.saveSelectedModels(selectedIds)
      },
      onCancel: () => {
        this.cancelModelPicker()
      }
    })
  }

  // 重置表单
  resetForm(): void {
    this.providerName = ''
    this.baseUrl = ''
    this.apiPath = ''
    this.apiKey = ''
    this.selectedApiStyle = ApiStyle.OPENAI
    this.models = []
    this.modelInput = ''
    // 重置图标配置：生成默认文字图标
    const config = generateDefaultTextIcon('')
    this.iconPath = ''
    this.iconType = 'text'
    this.textIcon = config.text
    this.textIconBgColor = config.bgColor
  }

  private showProviderToast(message: string | Resource, duration: number = 2000): void {
    showToast(this.getUIContext(), message, duration)
  }

  getDefaultBaseUrl(): string {
    if (this.selectedApiStyle === ApiStyle.OPENAI) {
      return 'https://api.openai.com/v1'
    } else if (this.selectedApiStyle === ApiStyle.ANTHROPIC) {
      return 'https://api.anthropic.com'
    } else if (this.selectedApiStyle === ApiStyle.GOOGLE) {
      return 'https://generativelanguage.googleapis.com'
    }
    return ''
  }

  addModel(): void {
    if (this.modelInput.trim() === '') {
      return
    }

    const modelId = this.modelInput.trim()
    const modelInfo = new ModelInfo(modelId, modelId, 4096, true, false)
    this.models.push(modelInfo)
    this.modelInput = ''
  }

  removeModel(index: number): void {
    this.models.splice(index, 1)
  }

  async testConnection(): Promise<void> {
    if (this.isTesting) {
      return
    }

    if (this.baseUrl === '') {
      this.showError($r('app.string.base_url_required'))
      return
    }

    this.isTesting = true
    this.showProviderToast($r('app.string.provider_testing_connection'), 1500)

    // 创建临时 provider 进行测试
    const tempProvider = new ModelProvider(
      'temp',
      this.providerName || 'temp',
      ProviderType.CUSTOM,
      'message',
      $r('app.color.brand_custom'),
      this.baseUrl,
      this.selectedApiStyle
    )
    tempProvider.apiKey = this.apiKey
    tempProvider.apiPath = this.apiPath // 设置 API Path
    tempProvider.models = this.models

    try {
      const result = await this.providerViewModel.refreshModels(tempProvider)
      if (result.success && result.models.length > 0) {
        // 成功获取模型后，打开选择弹窗让用户选择
        this.fetchedModels = result.models
        this.showModelPicker = true
        this.showProviderToast($r('app.string.provider_models_refreshed'), 2000)
      } else if (result.success && result.models.length === 0) {
        this.showProviderToast($r('app.string.provider_no_models'), 2000)
      } else {
        console.error('AddProviderPage', `[testConnection] failed: ${result.errorMessage}`)
        this.showError($r('app.string.connection_failed'))
      }
    } catch (error) {
      console.error('AddProviderPage', `[testConnection] exception: ${JSON.stringify(error)}`)
      this.showError($r('app.string.connection_failed'))
    } finally {
      this.isTesting = false
    }
  }

  async saveProvider(): Promise<void> {
    if (this.providerName.trim() === '') {
      this.showError($r('app.string.provider_name_required'))
      return
    }

    if (this.baseUrl.trim() === '') {
      this.showError($r('app.string.base_url_required'))
      return
    }

    this.isSaving = true

    // 创建新的自定义服务商
    const providerId = `custom_${Date.now()}`

    const provider = new ModelProvider(
      providerId,
      this.providerName.trim(),
      ProviderType.CUSTOM,
      'message',
      $r('app.color.brand_custom'),
      this.baseUrl.trim(),
      this.selectedApiStyle
    )
    provider.apiKey = this.apiKey
    provider.apiPath = this.apiPath // 保存 API Path
    provider.models = this.models
    provider.iconPath = ''
    provider.isPreset = false
    provider.isConnected = true // 保存时自动启用
    // 保存图标配置
    const defaultIconConfig = generateDefaultTextIcon(this.providerName.trim())
    provider.iconType = 'text' as ProviderIconType
    provider.textIcon = this.textIcon !== '' ? this.textIcon : defaultIconConfig.text
    provider.textIconBgColor = this.textIconBgColor !== '' ? this.textIconBgColor : defaultIconConfig.bgColor
    provider.customImagePath = ''

    await this.providerViewModel.saveProvider(provider)
    this.isSaving = false

    this.showProviderToast($r('app.string.provider_added'), 2000)

    this.getUIContext().getRouter().back()
  }

  // 保存用户选中的模型
  saveSelectedModels(selectedIds: string[]): void {
    // 构建已有模型的配置映射（保留配置）
    const existingConfigMap = new Map<string, ModelInfo>()
    for (let i = 0; i < this.models.length; i++) {
      const model = this.models[i]
      existingConfigMap.set(model.id, model)
    }

    // 构建新的模型列表
    const newModels: ModelInfo[] = []
    for (let i = 0; i < selectedIds.length; i++) {
      const modelId = selectedIds[i]
      const existingModel = existingConfigMap.get(modelId)
      if (existingModel !== undefined) {
        // 保留已有模型的配置
        newModels.push(existingModel)
      } else {
        // 新模型使用默认配置
        const modelInfo = new ModelInfo(modelId, modelId, 4096, true, false)
        newModels.push(modelInfo)
      }
    }

    this.models = newModels
    this.showModelPicker = false
    this.fetchedModels = []

    this.showProviderToast($r('app.string.provider_models_selected'), 2000)
  }

  // 取消模型选择
  cancelModelPicker(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.showModelPicker = false
    })
  }

  // 清理弹窗状态
  clearPickerState(): void {
    this.fetchedModels = []
  }

  showError(message: string | Resource): void {
    this.showProviderToast(message, 3000)
  }
}
