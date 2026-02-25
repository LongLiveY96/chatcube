import { getPreferencesService, PreferencesService } from './PreferencesService'
import { getDatabaseService, DatabaseService } from './DatabaseService'
import { getAttachmentStorageService, AttachmentStorageService } from './AttachmentStorageService'
import { getDefaultModelService, DefaultModelService } from './DefaultModelService'
import { getThemeService, ThemeService } from './ThemeService'
import { getAIApiService, AIApiService } from './AIApiService'
import { getAITaskService, AITaskService } from './AITaskService'
import { getToolExecutionService, ToolExecutionService } from './ToolExecutionService'
import { getWebSearchService, WebSearchService } from './WebSearchService'
import { getShareService, ShareService } from './ShareService'
import { getToolRegistry, ToolRegistry } from './ToolRegistry'
import { getHuaweiAgentService, HuaweiAgentService } from './HuaweiAgentService'
import { getChatTaskOrchestratorService, ChatTaskOrchestratorService } from './ChatTaskOrchestratorService'
import { getBackgroundRunGuardService, BackgroundRunGuardService } from './BackgroundRunGuardService'
import { getChatNotificationService, ChatNotificationService } from './ChatNotificationService'
import { getInAppAlertService, InAppAlertService } from './InAppAlertService'
import { getSettingsManager, SettingsManager } from '../viewmodels/SettingsManager'
import { getAppStateManager, AppStateManager } from '../viewmodels/AppStateManager'
import { getProviderViewModel, ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { createChatViewModel, ChatViewModel } from '../viewmodels/ChatViewModel'

// 统一服务装配入口（过渡层），降低上层对具体单例实现的直接耦合
export class ServiceRegistry {
  static preferences(): PreferencesService {
    return getPreferencesService()
  }

  static database(): DatabaseService {
    return getDatabaseService()
  }

  static attachmentStorage(): AttachmentStorageService {
    return getAttachmentStorageService()
  }

  static defaultModel(): DefaultModelService {
    return getDefaultModelService()
  }

  static settings(): SettingsManager {
    return getSettingsManager()
  }

  static theme(): ThemeService {
    return getThemeService()
  }

  static aiApi(): AIApiService {
    return getAIApiService()
  }

  static aiTask(): AITaskService {
    return getAITaskService()
  }

  static toolExecution(): ToolExecutionService {
    return getToolExecutionService()
  }

  static webSearch(): WebSearchService {
    return getWebSearchService()
  }

  static toolRegistry(): ToolRegistry {
    return getToolRegistry()
  }

  static share(): ShareService {
    return getShareService()
  }

  static appState(): AppStateManager {
    return getAppStateManager()
  }

  static provider(): ProviderViewModel {
    return getProviderViewModel()
  }

  static huaweiAgent(): HuaweiAgentService {
    return getHuaweiAgentService()
  }

  static chatTaskOrchestrator(): ChatTaskOrchestratorService {
    return getChatTaskOrchestratorService()
  }

  static backgroundGuard(): BackgroundRunGuardService {
    return getBackgroundRunGuardService()
  }

  static chatNotification(): ChatNotificationService {
    return getChatNotificationService()
  }

  static inAppAlert(): InAppAlertService {
    return getInAppAlertService()
  }

  static chat(): ChatViewModel {
    return createChatViewModel()
  }
}
