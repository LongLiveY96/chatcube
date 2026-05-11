import { AppStorageV2, UIUtils } from '@kit.ArkUI'
import { ModelProvider, DefaultModelConfig } from '../models/ChatModels'
import { Assistant, DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'

/**
 * 应用配置状态（跟 AppUiState 并列）
 *
 * 相较于 AppUiState：
 * - AppUiState 装 UI 临时态 / 主题 / 账号 / 系统状态等 primitive（string/number/boolean），通过 AppStorage 自动持久化
 * - AppSettingsState 装“应用配置”类对象（providers / assistants / favorites 等），由对应 Store 负责 SQLite 持久化
 *
 * 已覆盖：providers / assistants
 * 计划：defaultModels / favoriteModels 等
 */
const APP_SETTINGS_STATE_KEY = 'chatbox_app_settings_state'

@ObservedV2
export class AppSettingsState {
  // ===== providers =====
  @Trace providers: ModelProvider[] = []
  @Trace providersInitialized: boolean = false
  @Trace providersVersion: number = 0

  // ===== assistants =====
  @Trace assistants: Assistant[] = []
  @Trace assistantsInitialized: boolean = false
  @Trace assistantsVersion: number = 0
  @Trace currentAssistantId: string = DEFAULT_ASSISTANT_ID

  // ===== default models（chat / title / translate / search optimization 四个 role）=====
  @Trace defaultChatModel: DefaultModelConfig = new DefaultModelConfig()
  @Trace defaultTitleModel: DefaultModelConfig = new DefaultModelConfig()
  @Trace defaultTranslateModel: DefaultModelConfig = new DefaultModelConfig()
  @Trace defaultSearchOptimizationModel: DefaultModelConfig = new DefaultModelConfig()
  @Trace defaultModelsInitialized: boolean = false
  @Trace defaultModelsVersion: number = 0

  // ===== 生成类 Prompt 模板（标题 / 翻译）=====
  @Trace titlePromptTemplate: string = ''
  @Trace translatePromptTemplate: string = ''
  @Trace translateTargetLanguage: string = ''
  @Trace promptsInitialized: boolean = false
  @Trace promptsVersion: number = 0
}

function createAppSettingsState(): AppSettingsState {
  return new AppSettingsState()
}

/**
 * 取得 AppSettingsState 全局单例。内部通过 AppStorageV2.connect 绑定到固定 key，与 AppUiState 同源一致
 */
export function getAppSettingsState(): AppSettingsState {
  return AppStorageV2.connect(AppSettingsState, APP_SETTINGS_STATE_KEY, createAppSettingsState)
    ?? createAppSettingsState()
}

/**
 * path 解析器：入参支持字段名（providers / providersVersion / providersInitialized）
 * 未命中则原样返回，让 UIUtils.addMonitor 自己决定要不要监听
 */
function resolveAppSettingsStatePath(path: string): string {
  switch (path) {
    case 'providers':
      return 'providers'
    case 'providersInitialized':
      return 'providersInitialized'
    case 'providersVersion':
      return 'providersVersion'
    case 'assistants':
      return 'assistants'
    case 'assistantsInitialized':
      return 'assistantsInitialized'
    case 'assistantsVersion':
      return 'assistantsVersion'
    case 'currentAssistantId':
      return 'currentAssistantId'
    case 'defaultChatModel':
      return 'defaultChatModel'
    case 'defaultTitleModel':
      return 'defaultTitleModel'
    case 'defaultTranslateModel':
      return 'defaultTranslateModel'
    case 'defaultSearchOptimizationModel':
      return 'defaultSearchOptimizationModel'
    case 'defaultModelsInitialized':
      return 'defaultModelsInitialized'
    case 'defaultModelsVersion':
      return 'defaultModelsVersion'
    case 'titlePromptTemplate':
      return 'titlePromptTemplate'
    case 'translatePromptTemplate':
      return 'translatePromptTemplate'
    case 'translateTargetLanguage':
      return 'translateTargetLanguage'
    case 'promptsInitialized':
      return 'promptsInitialized'
    case 'promptsVersion':
      return 'promptsVersion'
    default:
      return path
  }
}

/**
 * 订阅 AppSettingsState 指定字段变化。与 observeAppUiState 保持同风格，返回“解绑函数”
 *
 * 典型用法：订阅 providersVersion 即可在任意 provider 写操作后收到通知
 */
export function observeAppSettingsState(paths: string | string[], callback: () => void): () => void {
  const monitorPaths = Array.isArray(paths)
    ? paths.map((path: string): string => resolveAppSettingsStatePath(path))
    : resolveAppSettingsStatePath(paths)
  const monitorCallback = (_monitorValue: Object): void => {
    callback()
  }
  UIUtils.addMonitor(getAppSettingsState(), monitorPaths, monitorCallback)
  return (): void => {
    UIUtils.clearMonitor(getAppSettingsState(), monitorPaths, monitorCallback)
  }
}
