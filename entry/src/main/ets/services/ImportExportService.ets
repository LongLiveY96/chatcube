/**
 * 导入导出服务
 * 支持将对话、附件、供应商配置等数据导出为 ZIP 文件
 * 支持从 ZIP 文件导入数据
 */

import { zlib } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'
import { Context } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import {
  ChatSession,
  ChatMessage,
  ModelProvider,
  ModelInfo,
  ModelInfoExtendedJson,
  ProviderType,
  ApiStyle,
  OpenAITransport,
  ProviderIconType,
  MessageAttachment,
  AttachmentType,
  MessageRole,
  SearchReference,
  ToolCall,
  ToolResult
} from '../models/ChatModels'
import { Assistant, DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'
import { DatabaseService } from './DatabaseService'
import { AttachmentStorageService } from './AttachmentStorageService'
import { getPreferencesService, PreferenceKeys } from './PreferencesService'
import { getThemeService } from './ThemeService'
import { getSettingsManager } from '../viewmodels/SettingsManager'
import { getAppStateManager } from '../viewmodels/AppStateManager'
import { getProviderViewModel } from '../viewmodels/ProviderViewModel'
import { buildProviderImportOrder } from '../config/ProviderOrderUtils'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { setAppUiStateValue } from '../state/AppUiState'

const ASSISTANT_AVATAR_EXPORT_DIR: string = 'assistant_avatars'

// 导出选项
export interface ExportOptions {
  sessionIds?: string[]
  includeAttachments: boolean
  includeProviders: boolean
  includeApiKeys: boolean
  includePreferences: boolean
}

// 导入选项
export interface ImportOptions {
  conflictStrategy: 'skip' | 'rename' | 'overwrite' | 'ask'
  importProviders: boolean
  importPreferences: boolean
}

// 统计信息
export interface StatisticsData {
  sessionsCount: number
  messagesCount: number
  attachmentsCount: number
  totalSize: number
  preferencesCount?: number
}

// 同步元数据
export interface SyncMetadata {
  lastSyncTime: number
  syncVersion: number
  deviceId: string
}

// 清单数据
export interface ManifestData {
  version: string
  exportTime: number
  appVersion: string
  exportType: string
  options: ExportOptions
  statistics: StatisticsData
  sessions: SessionSummary[]
  syncMetadata: SyncMetadata
  providersCount?: number
  assistantsCount?: number
  preferencesCount?: number
}

// 供应商导出数据
export interface ProviderExportData {
  id: string
  name: string
  type: string
  apiStyle: string
  openaiTransport: string
  apiKey: string
  requiresApiKey: boolean
  baseUrl: string
  isEnabled: boolean
  modelsJson: string
  iconSymbol: string
  sortOrder: number
  isPreset: boolean
  iconPath: string
  apiPath: string
  customHeadersJson: string
  iconType: string
  textIcon: string
  textIconBgColor: string
  customImagePath: string
}

export interface AssistantExportData {
  id: string
  name: string
  avatarSymbol: string
  avatarFileName?: string
  color: string
  systemPrompt: string
  defaultProviderId: string
  defaultModelId: string
  defaultModelName: string
  temperatureEnabled: boolean
  temperature: number
  isDefault: boolean
  createdAt: number
  updatedAt: number
  sortOrder: number
}

// 会话摘要
export interface SessionSummary {
  id: string
  title: string
  messageCount: number
  hasAttachments: boolean
  createdAt: number
  updatedAt: number
}

// 冲突信息
export interface ConflictInfo {
  type: 'session' | 'provider'
  id: string
  title: string
  localUpdatedAt: number
  importUpdatedAt: number
}

// 导入预览信息
export interface ImportPreview {
  sessionsCount: number
  messagesCount: number
  attachmentsCount: number
  providersCount: number
  preferencesCount: number
  conflicts: ConflictInfo[]
  manifest: ManifestData
}

// 导入结果
export interface ImportResult {
  imported: number
  skipped: number
  overwritten: number
  preferencesRestored: number
}

// 偏好设置条目
export interface PreferenceEntry {
  key: string
  value: string | number | boolean
  type: 'string' | 'number' | 'boolean'
}

// 敏感偏好键（不含 API 密钥时需跳过）
const SENSITIVE_PREFERENCE_KEYS: string[] = [
  PreferenceKeys.SEARCH_EXA_API_KEY
]

// 会话数据
interface SessionData {
  id: string
  title: string
  modelId: string
  providerId: string
  assistantId?: string
  createdAt: number
  updatedAt: number
  isFavorite: boolean
  lastMessagePreview: string
  messageCount: number
  syncVersion: number
  lastModified: number
  syncStatus: string
  deviceId: string
}

// 消息数据
interface MessageData {
  id: string
  role: string
  content: string
  timestamp: number
  modelName: string
  reasoningContent: string
  searchQuery: string
  searchEngine: string
  searchSource?: string
  searchReferences: SearchReferenceData[]
  attachmentIds: string[]
  toolCalls: ToolCallData[]
  toolResults: ToolResultData[]
}

// 搜索引用数据
interface SearchReferenceData {
  id: string
  title: string
  url: string
  snippet: string
  timestamp: number
}

// 工具调用数据
interface ToolCallData {
  id: string
  type: string
  functionName: string
  arguments: string
  toolId?: string
  displayName?: string
  sourceType?: string
  sourceLabel?: string
  permissionLevel?: string
}

// 工具结果数据
interface ToolResultData {
  toolCallId: string
  content: string
  isError?: boolean
  displayName?: string
  sourceLabel?: string
}

// 附件元数据
interface AttachmentMetadata {
  id: string
  type: string
  name: string
  mimeType: string
  size: number
}

// 导入文件数据
interface ImportFileData {
  manifest: ManifestData
  sessions: SessionData[]
  messages: Map<string, MessageData[]>
  attachmentsMetadata: Record<string, AttachmentMetadata[]>
  providers: ProviderExportData[]
  assistants: AssistantExportData[]
  preferences: PreferenceEntry[]
  tempDir: string
}

export class ImportExportService {
  private static instance: ImportExportService | null = null
  private context: Context | null = null
  private dbService: DatabaseService
  private attachmentService: AttachmentStorageService

  private constructor() {
    this.dbService = DatabaseService.getInstance()
    this.attachmentService = AttachmentStorageService.getInstance()
  }

  static getInstance(): ImportExportService {
    if (ImportExportService.instance === null) {
      ImportExportService.instance = new ImportExportService()
    }
    return ImportExportService.instance
  }

  async initialize(context: Context): Promise<void> {
    this.context = context
  }

  // ============ 导出功能 ============

  async exportData(options: ExportOptions, onProgress?: (progress: number) => void): Promise<string> {
    if (this.context === null) {
      throw new Error('Service not initialized')
    }

    try {
      let lastProgress = -1
      const emitProgress = (progress: number): void => {
        if (onProgress && progress !== lastProgress) {
          lastProgress = progress
          onProgress(progress)
        }
      }

      emitProgress(10)

      const sessions = await this.collectSessions(options)
      emitProgress(15)
      const messages = await this.collectMessages(sessions, emitProgress)
      const attachments = this.collectAttachments(messages, options)
      const providers = options.includeProviders ? await this.collectProviders(options) : []
      const assistants = await this.collectAssistants()
      const preferences = options.includePreferences ? await this.collectPreferences(options) : []

      emitProgress(30)

      const manifest = this.generateManifest(sessions, messages, attachments, providers, assistants, preferences, options)

      const timestamp = Date.now()
      const tempDir = `${this.context.cacheDir}/export_temp_${timestamp}`
      fileIo.mkdirSync(tempDir)

      await this.writeExportFiles(tempDir, manifest, sessions, messages, attachments, providers, assistants, preferences, options)

      emitProgress(60)

      const zipPath = `${this.context.cacheDir}/chatcube_export_${timestamp}.zip`
      const zlibOptions: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
        memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
        strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
      }
      await zlib.compressFile(tempDir, zipPath, zlibOptions)

      emitProgress(90)

      this.deleteDirectory(tempDir)

      emitProgress(100)

      return zipPath
    } catch (error) {
      console.error('ImportExportService', `Export failed: ${JSON.stringify(error)}`)
      throw new Error('Export failed')
    }
  }

  private async collectSessions(options: ExportOptions): Promise<ChatSession[]> {
    const allSessions = await this.dbService.getAllSessions(false)
    if (options.sessionIds && options.sessionIds.length > 0) {
      const result: ChatSession[] = []
      for (const session of allSessions) {
        if (options.sessionIds.includes(session.id)) {
          result.push(session)
        }
      }
      return result
    }
    return allSessions
  }

  private async collectMessages(
    sessions: ChatSession[],
    onProgress?: (progress: number) => void
  ): Promise<Map<string, ChatMessage[]>> {
    const messages = new Map<string, ChatMessage[]>()
    if (sessions.length === 0) {
      if (onProgress) {
        onProgress(25)
      }
      return messages
    }

    for (let i = 0; i < sessions.length; i++) {
      const session = sessions[i]
      const sessionMessages = await this.dbService.getMessages(session.id)
      messages.set(session.id, sessionMessages)
      if (onProgress) {
        const progress = 15 + Math.floor(((i + 1) / sessions.length) * 10)
        onProgress(progress > 25 ? 25 : progress)
      }
    }
    return messages
  }

  private collectAttachments(
    messages: Map<string, ChatMessage[]>,
    options: ExportOptions
  ): Map<string, MessageAttachment[]> {
    const attachments = new Map<string, MessageAttachment[]>()
    if (!options.includeAttachments) {
      return attachments
    }

    const keys = Array.from(messages.keys())
    for (const key of keys) {
      const msgs = messages.get(key)
      if (msgs) {
        for (const msg of msgs) {
          if (msg.attachments.length > 0) {
            attachments.set(msg.id, msg.attachments)
          }
        }
      }
    }
    return attachments
  }

  private async collectProviders(options: ExportOptions): Promise<ProviderExportData[]> {
    const allProviders = await this.dbService.getAllProviders()
    const providers: ProviderExportData[] = []
    for (const p of allProviders) {
      const providerData: ProviderExportData = {
        id: p.id,
        name: p.name,
        type: p.type,
        apiStyle: p.apiStyle,
        openaiTransport: p.openaiTransport,
        apiKey: options.includeApiKeys ? p.apiKey : '',
        requiresApiKey: p.requiresApiKey,
        baseUrl: p.baseUrl,
        isEnabled: p.isEnabled,
        modelsJson: p.modelsJson,
        iconSymbol: p.iconSymbol,
        sortOrder: p.sortOrder,
        isPreset: p.isPreset,
        iconPath: p.iconPath,
        apiPath: p.apiPath,
        customHeadersJson: p.customHeadersJson,
        iconType: p.iconType,
        textIcon: p.textIcon,
        textIconBgColor: p.textIconBgColor,
        customImagePath: p.customImagePath
      }
      providers.push(providerData)
    }
    return providers
  }

  private async collectAssistants(): Promise<AssistantExportData[]> {
    const allAssistants = await this.dbService.getAllAssistants()
    const assistants: AssistantExportData[] = []
    for (const assistant of allAssistants) {
      assistants.push({
        id: assistant.id,
        name: assistant.name,
        avatarSymbol: assistant.avatarSymbol,
        color: assistant.color,
        systemPrompt: assistant.systemPrompt,
        defaultProviderId: assistant.defaultProviderId,
        defaultModelId: assistant.defaultModelId,
        defaultModelName: assistant.defaultModelName,
        temperatureEnabled: assistant.temperatureEnabled,
        temperature: assistant.temperature,
        isDefault: assistant.isDefault,
        createdAt: assistant.createdAt,
        updatedAt: assistant.updatedAt,
        sortOrder: assistant.sortOrder
      })
    }
    return assistants
  }

  private async collectPreferences(options: ExportOptions): Promise<PreferenceEntry[]> {
    const entries: PreferenceEntry[] = []
    try {
      const allData = await getPreferencesService().getAll()
      const keys = Array.from(allData.keys())
      for (const key of keys) {
        // 若不含 API 密钥，跳过敏感键
        if (!options.includeApiKeys && SENSITIVE_PREFERENCE_KEYS.includes(key)) {
          continue
        }
        const value = allData.get(key)
        if (value === undefined) {
          continue
        }
        let entryType: 'string' | 'number' | 'boolean' = 'string'
        if (typeof value === 'number') {
          entryType = 'number'
        } else if (typeof value === 'boolean') {
          entryType = 'boolean'
        }
        const entry: PreferenceEntry = {
          key: key,
          value: value as string | number | boolean,
          type: entryType
        }
        entries.push(entry)
      }
    } catch (error) {
      console.error('ImportExportService', `Failed to collect preferences: ${JSON.stringify(error)}`)
    }
    return entries
  }

  private generateManifest(
    sessions: ChatSession[],
    messages: Map<string, ChatMessage[]>,
    attachments: Map<string, MessageAttachment[]>,
    providers: ProviderExportData[],
    assistants: AssistantExportData[],
    preferences: PreferenceEntry[],
    options: ExportOptions
  ): ManifestData {
    let totalMessages = 0
    let totalAttachments = 0
    const sessionSummaries: SessionSummary[] = []

    for (const session of sessions) {
      const sessionMessages = messages.get(session.id)
      const messageCount = sessionMessages ? sessionMessages.length : 0
      totalMessages += messageCount

      let hasAttachments = false
      if (sessionMessages) {
        for (const msg of sessionMessages) {
          if (attachments.has(msg.id)) {
            hasAttachments = true
            const atts = attachments.get(msg.id)
            if (atts) {
              totalAttachments += atts.length
            }
          }
        }
      }

      const summary: SessionSummary = {
        id: session.id,
        title: session.title,
        messageCount: messageCount,
        hasAttachments: hasAttachments,
        createdAt: session.createdAt,
        updatedAt: session.updatedAt
      }
      sessionSummaries.push(summary)
    }

    const statistics: StatisticsData = {
      sessionsCount: sessions.length,
      messagesCount: totalMessages,
      attachmentsCount: totalAttachments,
      totalSize: 0,
      preferencesCount: preferences.length
    }

    const syncMetadata: SyncMetadata = {
      lastSyncTime: 0,
      syncVersion: 1,
      deviceId: ''
    }

    const manifest: ManifestData = {
      version: '1.0',
      exportTime: Date.now(),
      appVersion: '0.3.0',
      exportType: (options.sessionIds && options.sessionIds.length > 0) ? 'partial' : 'full',
      options: options,
      statistics: statistics,
      sessions: sessionSummaries,
      syncMetadata: syncMetadata,
      providersCount: providers.length,
      assistantsCount: assistants.length,
      preferencesCount: preferences.length
    }

    return manifest
  }

  private async writeExportFiles(
    tempDir: string,
    manifest: ManifestData,
    sessions: ChatSession[],
    messages: Map<string, ChatMessage[]>,
    attachments: Map<string, MessageAttachment[]>,
    providers: ProviderExportData[],
    assistants: AssistantExportData[],
    preferences: PreferenceEntry[],
    options: ExportOptions
  ): Promise<void> {
    this.writeTextFile(`${tempDir}/manifest.json`, JSON.stringify(manifest, null, 2))

    const sessionsData: SessionData[] = []
    for (const s of sessions) {
      const sessionData: SessionData = {
        id: s.id,
        title: s.title,
        modelId: s.modelId,
        providerId: s.providerId,
        assistantId: s.assistantId !== '' ? s.assistantId : DEFAULT_ASSISTANT_ID,
        createdAt: s.createdAt,
        updatedAt: s.updatedAt,
        isFavorite: s.isFavorite,
        lastMessagePreview: s.lastMessagePreview,
        messageCount: s.messageCount,
        syncVersion: s.syncVersion,
        lastModified: s.lastModified,
        syncStatus: s.syncStatus,
        deviceId: s.deviceId
      }
      sessionsData.push(sessionData)
    }
    this.writeTextFile(`${tempDir}/sessions.json`, JSON.stringify(sessionsData, null, 2))

    const messagesDir = `${tempDir}/messages`
    try {
      fileIo.mkdirSync(messagesDir)
    } catch (error) {
      throw new Error(`Failed to create messages directory: ${JSON.stringify(error)}`)
    }

    const messageKeys = Array.from(messages.keys())
    for (const sessionId of messageKeys) {
      const msgs = messages.get(sessionId)
      if (msgs) {
        const messagesData: MessageData[] = []
        for (const m of msgs) {
          const attachmentIds: string[] = []
          for (const a of m.attachments) {
            attachmentIds.push(a.id)
          }

          // 收集搜索引用数据
          const searchReferencesData: SearchReferenceData[] = []
          for (const ref of m.searchReferences) {
            searchReferencesData.push({
              id: ref.id,
              title: ref.title,
              url: ref.url,
              snippet: ref.snippet,
              timestamp: ref.timestamp
            })
          }

          // 收集工具调用数据
          const toolCallsData: ToolCallData[] = []
          for (const tc of m.toolCalls) {
            toolCallsData.push({
              id: tc.id,
              type: tc.type,
              functionName: tc.functionName,
              arguments: tc.arguments,
              toolId: tc.toolId,
              displayName: tc.displayName,
              sourceType: tc.sourceType,
              sourceLabel: tc.sourceLabel,
              permissionLevel: tc.permissionLevel
            })
          }

          // 收集工具结果数据
          const toolResultsData: ToolResultData[] = []
          for (const tr of m.toolResults) {
            toolResultsData.push({
              toolCallId: tr.toolCallId,
              content: tr.content,
              isError: tr.isError,
              displayName: tr.displayName,
              sourceLabel: tr.sourceLabel
            })
          }

          const messageData: MessageData = {
            id: m.id,
            role: m.role,
            content: m.content,
            timestamp: m.timestamp,
            modelName: m.modelName,
            reasoningContent: m.reasoningContent,
            searchQuery: m.searchQuery,
            searchEngine: m.searchEngine,
            searchSource: m.searchSource,
            searchReferences: searchReferencesData,
            attachmentIds: attachmentIds,
            toolCalls: toolCallsData,
            toolResults: toolResultsData
          }
          messagesData.push(messageData)
        }
        this.writeTextFile(`${messagesDir}/${sessionId}.json`, JSON.stringify(messagesData, null, 2))
      }
    }

    if (options.includeAttachments && attachments.size > 0) {
      const attachmentsDir = `${tempDir}/attachments`
      try {
        fileIo.mkdirSync(attachmentsDir)
        fileIo.mkdirSync(`${attachmentsDir}/images`)
        fileIo.mkdirSync(`${attachmentsDir}/files`)
      } catch (error) {
        throw new Error(`Failed to create attachments directory: ${JSON.stringify(error)}`)
      }

      const attachmentsMetadata: Record<string, AttachmentMetadata[]> = {}
      const attachmentKeys = Array.from(attachments.keys())
      for (const messageId of attachmentKeys) {
        const atts = attachments.get(messageId)
        if (atts) {
          const metadataList: AttachmentMetadata[] = []
          for (const a of atts) {
            const metadata: AttachmentMetadata = {
              id: a.id,
              type: a.type,
              name: a.name,
              mimeType: a.mimeType,
              size: a.size
            }
            metadataList.push(metadata)
          }
          attachmentsMetadata[messageId] = metadataList
        }
      }
      this.writeTextFile(`${attachmentsDir}/metadata.json`, JSON.stringify(attachmentsMetadata, null, 2))

      for (const messageId of attachmentKeys) {
        const atts = attachments.get(messageId)
        if (atts) {
          for (const att of atts) {
            if (this.attachmentService.fileExists(att.filePath)) {
              const subDir = att.type === AttachmentType.IMAGE ? 'images' : 'files'
              const ext = this.getExtension(att.name)
              const destPath = `${attachmentsDir}/${subDir}/${att.id}${ext}`
              await this.copyFile(att.filePath, destPath)
            }
          }
        }
      }
    }

    // 写入供应商数据
    if (options.includeProviders && providers.length > 0) {
      this.writeTextFile(`${tempDir}/providers.json`, JSON.stringify(providers, null, 2))
    }

    if (assistants.length > 0) {
      await this.writeAssistantAvatarFiles(tempDir, assistants)
      this.writeTextFile(`${tempDir}/assistants.json`, JSON.stringify(assistants, null, 2))
    }

    // 写入偏好设置数据
    if (options.includePreferences && preferences.length > 0) {
      this.writeTextFile(`${tempDir}/preferences.json`, JSON.stringify(preferences, null, 2))
    }
  }

  // ============ 导入功能 ============

  async previewImport(zipPath: string): Promise<ImportPreview> {
    if (this.context === null) {
      throw new Error('Service not initialized')
    }

    try {
      console.info('ImportExportService', `Starting preview import from: ${zipPath}`)

      const tempDir = `${this.context.cacheDir}/import_preview_${Date.now()}`
      console.info('ImportExportService', `Temp dir: ${tempDir}`)

      // 确保目标目录存在
      try {
        fileIo.mkdirSync(tempDir)
        console.info('ImportExportService', 'Temp directory created')
      } catch (mkdirError) {
        console.error('ImportExportService', `Failed to create temp dir: ${JSON.stringify(mkdirError)}`)
        throw new Error(`Failed to create temp directory: ${mkdirError}`)
      }

      const zlibOptions: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
      }

      console.info('ImportExportService', 'Starting decompression...')
      await zlib.decompressFile(zipPath, tempDir, zlibOptions)
      console.info('ImportExportService', 'Decompression completed')

      console.info('ImportExportService', 'Reading manifest...')
      const manifestText = this.readTextFile(`${tempDir}/manifest.json`)
      console.info('ImportExportService', `Manifest text length: ${manifestText.length}`)

      const manifest = JSON.parse(manifestText) as ManifestData
      console.info('ImportExportService', `Manifest parsed, sessions: ${manifest.sessions.length}`)

      const conflicts = await this.detectConflicts(manifest)
      console.info('ImportExportService', `Conflicts detected: ${conflicts.length}`)

      this.deleteDirectory(tempDir)

      const preview: ImportPreview = {
        sessionsCount: manifest.statistics.sessionsCount,
        messagesCount: manifest.statistics.messagesCount,
        attachmentsCount: manifest.statistics.attachmentsCount,
        providersCount: manifest.providersCount || 0,
        preferencesCount: manifest.preferencesCount || 0,
        conflicts: conflicts,
        manifest: manifest
      }

      return preview
    } catch (error) {
      console.error('ImportExportService', `Preview failed: ${JSON.stringify(error)}`)
      console.error('ImportExportService', `Error details: ${error}`)
      throw new Error(`Preview failed: ${error}`)
    }
  }

  async importData(
    zipPath: string,
    options: ImportOptions,
    onProgress?: (progress: number) => void
  ): Promise<ImportResult> {
    if (this.context === null) {
      throw new Error('Service not initialized')
    }

    try {
      if (onProgress) {
        onProgress(10)
      }

      const tempDir = `${this.context.cacheDir}/import_temp_${Date.now()}`

      // 确保目标目录存在
      fileIo.mkdirSync(tempDir)

      const zlibOptions: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
      }
      await zlib.decompressFile(zipPath, tempDir, zlibOptions)

      if (onProgress) {
        onProgress(30)
      }

      const importData = this.readImportFiles(tempDir)

      if (onProgress) {
        onProgress(50)
      }

      const result = await this.performImport(importData, options)

      if (onProgress) {
        onProgress(90)
      }

      this.deleteDirectory(tempDir)

      if (onProgress) {
        onProgress(100)
      }

      return result
    } catch (error) {
      console.error('ImportExportService', `Import failed: ${JSON.stringify(error)}`)
      throw new Error('Import failed')
    }
  }

  private readImportFiles(tempDir: string): ImportFileData {
    const manifestText = this.readTextFile(`${tempDir}/manifest.json`)
    const manifest = JSON.parse(manifestText) as ManifestData

    const sessionsText = this.readTextFile(`${tempDir}/sessions.json`)
    const sessions = JSON.parse(sessionsText) as SessionData[]

    const messages = new Map<string, MessageData[]>()
    const messagesDir = `${tempDir}/messages`
    for (const session of sessions) {
      try {
        const messageText = this.readTextFile(`${messagesDir}/${session.id}.json`)
        const sessionMessages = JSON.parse(messageText) as MessageData[]
        messages.set(session.id, sessionMessages)
      } catch (e) {
        console.warn('ImportExportService', `Failed to read messages for session ${session.id}`)
      }
    }

    let attachmentsMetadata: Record<string, AttachmentMetadata[]> = {}
    try {
      const metadataText = this.readTextFile(`${tempDir}/attachments/metadata.json`)
      attachmentsMetadata = JSON.parse(metadataText) as Record<string, AttachmentMetadata[]>
    } catch (e) {
      console.info('ImportExportService', 'No attachments metadata found')
    }

    // 读取供应商数据
    let providers: ProviderExportData[] = []
    try {
      const providersText = this.readTextFile(`${tempDir}/providers.json`)
      providers = JSON.parse(providersText) as ProviderExportData[]
    } catch (e) {
      console.info('ImportExportService', 'No providers data found')
    }

    let assistants: AssistantExportData[] = []
    try {
      const assistantsText = this.readTextFile(`${tempDir}/assistants.json`)
      assistants = JSON.parse(assistantsText) as AssistantExportData[]
    } catch (e) {
      console.info('ImportExportService', 'No assistants data found')
    }

    // 读取偏好设置数据
    let preferences: PreferenceEntry[] = []
    try {
      const preferencesText = this.readTextFile(`${tempDir}/preferences.json`)
      preferences = JSON.parse(preferencesText) as PreferenceEntry[]
    } catch (e) {
      console.info('ImportExportService', 'No preferences data found')
    }

    const importData: ImportFileData = {
      manifest: manifest,
      sessions: sessions,
      messages: messages,
      attachmentsMetadata: attachmentsMetadata,
      providers: providers,
      assistants: assistants,
      preferences: preferences,
      tempDir: tempDir
    }

    return importData
  }

  private async performImport(
    importData: ImportFileData,
    options: ImportOptions
  ): Promise<ImportResult> {
    let imported = 0
    let skipped = 0
    let overwritten = 0

    const sessions = importData.sessions
    const messages = importData.messages
    const attachmentsMetadata = importData.attachmentsMetadata
    const tempDir = importData.tempDir

    if (importData.assistants.length > 0) {
      await this.importAssistants(importData.assistants, tempDir)
    }

    for (const sessionData of sessions) {
      const existingSession = await this.dbService.getSession(sessionData.id)

      let finalSessionId = sessionData.id
      let finalTitle = sessionData.title

      if (existingSession !== null) {
        if (options.conflictStrategy === 'skip') {
          skipped++
          continue
        } else if (options.conflictStrategy === 'rename') {
          finalSessionId = `${sessionData.id}_imported_${Date.now()}`
          finalTitle = `${sessionData.title} (导入)`
        } else if (options.conflictStrategy === 'overwrite') {
          await this.dbService.deleteSession(existingSession.id)
          overwritten++
        }
      }

      const assistantId = sessionData.assistantId !== undefined && sessionData.assistantId !== '' ?
        sessionData.assistantId : DEFAULT_ASSISTANT_ID
      const existingAssistant = await this.dbService.getAssistant(assistantId)
      const effectiveAssistantId = existingAssistant !== null ? assistantId : DEFAULT_ASSISTANT_ID
      const session = new ChatSession(
        finalSessionId,
        finalTitle,
        sessionData.modelId,
        sessionData.providerId,
        effectiveAssistantId
      )
      session.createdAt = sessionData.createdAt
      session.updatedAt = sessionData.updatedAt
      session.isFavorite = sessionData.isFavorite || false
      session.lastMessagePreview = sessionData.lastMessagePreview || ''
      session.messageCount = sessionData.messageCount || 0
      session.syncVersion = sessionData.syncVersion
      session.lastModified = sessionData.lastModified
      session.syncStatus = sessionData.syncStatus as 'synced' | 'pending' | 'conflict'
      session.deviceId = sessionData.deviceId
      await this.dbService.createSession(session)

      const sessionMessages = messages.get(sessionData.id)
      if (sessionMessages) {
        for (const msgData of sessionMessages) {
          const message = new ChatMessage(msgData.id, msgData.role as MessageRole, msgData.content, msgData.modelName)
          message.timestamp = msgData.timestamp
          message.reasoningContent = msgData.reasoningContent || ''
          message.searchQuery = msgData.searchQuery || ''
          message.searchEngine = msgData.searchEngine || ''
          message.searchSource = msgData.searchSource || ''

          // 恢复搜索引用
          if (msgData.searchReferences && msgData.searchReferences.length > 0) {
            for (const refData of msgData.searchReferences) {
              const ref = new SearchReference(
                refData.id,
                refData.title,
                refData.url,
                refData.snippet
              )
              ref.timestamp = refData.timestamp
              message.searchReferences.push(ref)
            }
          }

          // 恢复工具调用
          if (msgData.toolCalls && msgData.toolCalls.length > 0) {
            for (const tcData of msgData.toolCalls) {
              const toolCall = new ToolCall(
                tcData.id,
                tcData.functionName,
                tcData.arguments,
                tcData.toolId || tcData.functionName,
                tcData.displayName || tcData.functionName,
                tcData.sourceType || '',
                tcData.sourceLabel || '',
                tcData.permissionLevel || ''
              )
              toolCall.type = tcData.type
              message.toolCalls.push(toolCall)
            }
          }

          // 恢复工具结果
          if (msgData.toolResults && msgData.toolResults.length > 0) {
            for (const trData of msgData.toolResults) {
              const toolResult = new ToolResult(
                trData.toolCallId,
                trData.content,
                trData.isError === true,
                trData.displayName || '',
                trData.sourceLabel || ''
              )
              message.toolResults.push(toolResult)
            }
          }

          if (msgData.attachmentIds && msgData.attachmentIds.length > 0) {
            const attachments = attachmentsMetadata[msgData.id]
            if (attachments) {
              for (const attData of attachments) {
                const subDir = attData.type === 'image' ? 'images' : 'files'
                const ext = this.getExtension(attData.name)
                const srcPath = `${tempDir}/attachments/${subDir}/${attData.id}${ext}`

                let sourceExists = false
                try {
                  sourceExists = fileIo.accessSync(srcPath)
                } catch (error) {
                  console.warn('ImportExportService', `Attachment file access failed: ${JSON.stringify(error)}`)
                  sourceExists = false
                }

                if (sourceExists) {
                  const attachment = new MessageAttachment(
                    attData.id,
                    attData.type === 'image' ? AttachmentType.IMAGE : AttachmentType.FILE,
                    attData.name,
                    '',
                    attData.mimeType,
                    attData.size
                  )

                  const savedPath = await this.attachmentService.importExistingAttachment(srcPath, attachment)
                  attachment.filePath = savedPath

                  message.attachments.push(attachment)
                }
              }
            }
          }

          await this.dbService.addMessage(finalSessionId, message, false)
        }
      }

      await this.dbService.refreshSessionSummaryForSession(finalSessionId)

      // 恢复会话的原始时间戳（addMessage 会将 updated_at 覆盖为 Date.now()）
      await this.dbService.updateSessionTimestamps(finalSessionId, sessionData.createdAt, sessionData.updatedAt)

      if (existingSession === null) {
        imported++
      }
    }

    // 导入供应商数据
    if (options.importProviders && importData.providers.length > 0) {
      const sortedProviders = this.sortImportedProviders(importData.providers)
      for (const providerData of sortedProviders) {
        await this.importProvider(providerData)
      }
      await this.restoreProviderOrder(sortedProviders)
    }

    // 导入偏好设置
    let preferencesRestored = 0
    if (options.importPreferences && importData.preferences.length > 0) {
      preferencesRestored = await this.importPreferences(importData.preferences)
      await this.refreshAfterImport()
    }

    setAppUiStateValue(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())

    const result: ImportResult = {
      imported: imported,
      skipped: skipped,
      overwritten: overwritten,
      preferencesRestored: preferencesRestored
    }

    return result
  }

  private async importAssistants(assistants: AssistantExportData[], tempDir: string): Promise<void> {
    for (const assistantData of assistants) {
      const assistant = new Assistant(
        assistantData.id !== '' ? assistantData.id : DEFAULT_ASSISTANT_ID,
        assistantData.name
      )
      assistant.avatarSymbol = await this.resolveImportedAssistantAvatarSymbol(assistantData, tempDir)
      assistant.color = assistantData.color !== '' ? assistantData.color : '#0A59F7'
      assistant.systemPrompt = assistantData.systemPrompt || ''
      assistant.defaultProviderId = assistantData.defaultProviderId || ''
      assistant.defaultModelId = assistantData.defaultModelId || ''
      assistant.defaultModelName = assistantData.defaultModelName || ''
      assistant.temperatureEnabled = assistantData.temperatureEnabled === true
      assistant.temperature = assistantData.temperature !== undefined ? assistantData.temperature : 0.7
      assistant.isDefault = assistant.id === DEFAULT_ASSISTANT_ID || assistantData.isDefault === true
      assistant.createdAt = assistantData.createdAt
      assistant.updatedAt = assistantData.updatedAt
      assistant.sortOrder = assistant.isDefault ? 0 : assistantData.sortOrder
      await this.dbService.saveAssistant(assistant)
    }
  }

  private async importProvider(providerData: ProviderExportData): Promise<void> {
    // 解析 modelsJson 为 ModelInfo 数组
    let models: ModelInfo[] = []
    try {
      const modelsArray = JSON.parse(providerData.modelsJson) as ModelInfoExtendedJson[]
      for (const m of modelsArray) {
        models.push(ModelInfo.fromExtendedJson(m))
      }
    } catch (e) {
      console.warn('ImportExportService', `Failed to parse models for provider ${providerData.id}`)
    }

    // 解析 apiStyle 枚举
    let apiStyle = ApiStyle.OPENAI
    if (providerData.apiStyle === 'anthropic') {
      apiStyle = ApiStyle.ANTHROPIC
    } else if (providerData.apiStyle === 'google') {
      apiStyle = ApiStyle.GOOGLE
    }

    // 解析 iconType 枚举
    let iconType = ProviderIconType.SVG
    if (providerData.iconType === 'text') {
      iconType = ProviderIconType.TEXT
    } else if (providerData.iconType === 'image') {
      iconType = ProviderIconType.IMAGE
    }

    // 创建 ModelProvider 对象
    const provider = new ModelProvider(
      providerData.id,
      providerData.name,
      providerData.type as ProviderType,
      providerData.iconSymbol,
      $r('app.color.primary'),
      providerData.baseUrl,
      apiStyle
    )
    provider.apiKey = providerData.apiKey
    provider.requiresApiKey = providerData.requiresApiKey !== undefined ? providerData.requiresApiKey :
      (provider.type !== ProviderType.OLLAMA && provider.type !== ProviderType.LMSTUDIO)
    provider.isConnected = providerData.isEnabled
    provider.isPreset = providerData.isPreset
    provider.iconPath = providerData.iconPath
    provider.apiPath = providerData.apiPath
    provider.openaiTransport = providerData.openaiTransport === OpenAITransport.RESPONSES
      ? OpenAITransport.RESPONSES
      : OpenAITransport.CHAT_COMPLETIONS
    provider.customHeadersJson = providerData.customHeadersJson !== undefined ? providerData.customHeadersJson : ''
    provider.iconType = iconType
    provider.textIcon = providerData.textIcon
    provider.textIconBgColor = providerData.textIconBgColor
    provider.customImagePath = providerData.customImagePath
    provider.models = models

    // 保存到数据库
    await this.dbService.saveProvider(provider)
  }

  private sortImportedProviders(providers: ProviderExportData[]): ProviderExportData[] {
    const sortedProviders = [...providers]
    sortedProviders.sort((a: ProviderExportData, b: ProviderExportData) => {
      const leftOrder = a.sortOrder !== undefined ? a.sortOrder : Number.MAX_SAFE_INTEGER
      const rightOrder = b.sortOrder !== undefined ? b.sortOrder : Number.MAX_SAFE_INTEGER
      if (leftOrder !== rightOrder) {
        return leftOrder - rightOrder
      }
      return a.name.localeCompare(b.name)
    })
    return sortedProviders
  }

  private async restoreProviderOrder(importedProviders: ProviderExportData[]): Promise<void> {
    const localProviders = await this.dbService.getAllProviders()
    const importedProviderIds: string[] = []
    const localProviderIds: string[] = []

    for (let i = 0; i < importedProviders.length; i++) {
      importedProviderIds.push(importedProviders[i].id)
    }
    for (let i = 0; i < localProviders.length; i++) {
      localProviderIds.push(localProviders[i].id)
    }

    const orderedProviderIds = buildProviderImportOrder(importedProviderIds, localProviderIds)
    if (orderedProviderIds.length <= 0) {
      return
    }
    await this.dbService.updateProvidersOrder(orderedProviderIds)
    await getProviderViewModel().loadAllProviders()
  }

  private async importPreferences(preferences: PreferenceEntry[]): Promise<number> {
    let restored = 0
    const preferencesService = getPreferencesService()
    for (const entry of preferences) {
      try {
        if (entry.type === 'string') {
          await preferencesService.setString(entry.key, entry.value as string)
        } else if (entry.type === 'number') {
          await preferencesService.setNumber(entry.key, entry.value as number)
        } else if (entry.type === 'boolean') {
          await preferencesService.setBoolean(entry.key, entry.value as boolean)
        }
        restored++
      } catch (error) {
        console.warn('ImportExportService', `Failed to restore preference ${entry.key}: ${JSON.stringify(error)}`)
      }
    }
    console.info('ImportExportService', `Preferences restored: ${restored}/${preferences.length}`)
    return restored
  }

  private async refreshAfterImport(): Promise<void> {
    try {
      // 刷新主题服务缓存
      await getThemeService().reloadTheme()
    } catch (error) {
      console.warn('ImportExportService', `Failed to reload theme: ${JSON.stringify(error)}`)
    }
    try {
      // 刷新设置管理器缓存
      await getSettingsManager().reload()
    } catch (error) {
      console.warn('ImportExportService', `Failed to reload settings: ${JSON.stringify(error)}`)
    }
    try {
      // 刷新应用状态管理器缓存
      await getAppStateManager().loadState()
    } catch (error) {
      console.warn('ImportExportService', `Failed to reload app state: ${JSON.stringify(error)}`)
    }
  }

  private isLocalFileAvatar(value: string): boolean {
    return value.trim().toLowerCase().startsWith('file://')
  }

  private getPathFromFileUri(value: string): string {
    const trimmed = value.trim()
    return trimmed.toLowerCase().startsWith('file://') ? trimmed.substring(7) : trimmed
  }

  private sanitizeFileName(value: string): string {
    const safeName = value.trim().replace(/[^0-9A-Za-z._-]/g, '_').replace(/\.\./g, '_')
    if (safeName === '' || safeName === '.' || safeName === '..') {
      return 'avatar'
    }
    return safeName
  }

  private buildExportedAssistantAvatarFileName(assistant: AssistantExportData): string {
    const sourcePath = this.getPathFromFileUri(assistant.avatarSymbol)
    const ext = this.getExtension(sourcePath.split('?')[0])
    const baseName = this.sanitizeFileName(assistant.id !== '' ? assistant.id : DEFAULT_ASSISTANT_ID)
    return `${baseName}${ext !== '' ? ext : '.jpg'}`
  }

  private ensureDirectory(dirPath: string): void {
    try {
      fileIo.mkdirSync(dirPath, true)
    } catch (error) {
      console.warn('ImportExportService', `Directory may already exist: ${JSON.stringify(error)}`)
    }
  }

  private async writeAssistantAvatarFiles(tempDir: string, assistants: AssistantExportData[]): Promise<void> {
    let avatarDirReady = false
    const avatarDir = `${tempDir}/${ASSISTANT_AVATAR_EXPORT_DIR}`
    for (const assistant of assistants) {
      if (!this.isLocalFileAvatar(assistant.avatarSymbol)) {
        continue
      }
      const sourcePath = this.getPathFromFileUri(assistant.avatarSymbol)
      let sourceExists = false
      try {
        sourceExists = fileIo.accessSync(sourcePath)
      } catch (error) {
        console.warn('ImportExportService', `Assistant avatar access failed: ${JSON.stringify(error)}`)
        sourceExists = false
      }
      if (!sourceExists) {
        continue
      }
      if (!avatarDirReady) {
        this.ensureDirectory(avatarDir)
        avatarDirReady = true
      }
      const fileName = this.buildExportedAssistantAvatarFileName(assistant)
      try {
        await fileIo.copyFile(sourcePath, `${avatarDir}/${fileName}`)
        assistant.avatarFileName = fileName
      } catch (error) {
        console.warn('ImportExportService', `Failed to export assistant avatar: ${JSON.stringify(error)}`)
      }
    }
  }

  private async resolveImportedAssistantAvatarSymbol(assistantData: AssistantExportData, tempDir: string): Promise<string> {
    const fallbackAvatar = assistantData.avatarSymbol !== undefined && assistantData.avatarSymbol !== '' ?
      assistantData.avatarSymbol : 'AI'
    const avatarFileName = assistantData.avatarFileName !== undefined ? this.sanitizeFileName(assistantData.avatarFileName) : ''
    if (avatarFileName === '' || this.context === null) {
      return fallbackAvatar
    }

    const sourcePath = `${tempDir}/${ASSISTANT_AVATAR_EXPORT_DIR}/${avatarFileName}`
    let sourceExists = false
    try {
      sourceExists = fileIo.accessSync(sourcePath)
    } catch (error) {
      console.warn('ImportExportService', `Imported assistant avatar access failed: ${JSON.stringify(error)}`)
      sourceExists = false
    }
    if (!sourceExists) {
      return fallbackAvatar
    }

    const avatarDir = `${this.context.filesDir}/${ASSISTANT_AVATAR_EXPORT_DIR}`
    this.ensureDirectory(avatarDir)
    const ext = this.getExtension(avatarFileName)
    const assistantId = this.sanitizeFileName(assistantData.id !== '' ? assistantData.id : DEFAULT_ASSISTANT_ID)
    const targetPath = `${avatarDir}/avatar_${assistantId}_${Date.now()}${ext !== '' ? ext : '.jpg'}`
    try {
      await fileIo.copyFile(sourcePath, targetPath)
      return `file://${targetPath}`
    } catch (error) {
      console.warn('ImportExportService', `Failed to import assistant avatar: ${JSON.stringify(error)}`)
      return fallbackAvatar
    }
  }

  private async detectConflicts(manifest: ManifestData): Promise<ConflictInfo[]> {
    const conflicts: ConflictInfo[] = []

    for (const sessionSummary of manifest.sessions) {
      const existingSession = await this.dbService.getSession(sessionSummary.id)
      if (existingSession !== null) {
        const conflict: ConflictInfo = {
          type: 'session',
          id: sessionSummary.id,
          title: sessionSummary.title,
          localUpdatedAt: existingSession.updatedAt,
          importUpdatedAt: sessionSummary.updatedAt
        }
        conflicts.push(conflict)
      }
    }

    return conflicts
  }

  // ============ 工具方法 ============

  private writeTextFile(filePath: string, content: string): void {
    try {
      const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE)
      fileIo.writeSync(file.fd, content)
      fileIo.closeSync(file)
    } catch (error) {
      throw new Error(`Write text file failed: ${JSON.stringify(error)}`)
    }
  }

  private readTextFile(filePath: string): string {
    try {
      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      fileIo.closeSync(file)

      const uint8Array = new Uint8Array(buffer)
      const decoder = util.TextDecoder.create('utf-8')
      return decoder.decodeToString(uint8Array, { stream: false })
    } catch (error) {
      throw new Error(`Read text file failed: ${JSON.stringify(error)}`)
    }
  }

  private async copyFile(srcPath: string, destPath: string): Promise<void> {
    try {
      await fileIo.copyFile(srcPath, destPath)
    } catch (error) {
      console.error('ImportExportService', `Failed to copy file: ${JSON.stringify(error)}`)
    }
  }

  private deleteDirectory(dirPath: string): void {
    try {
      if (fileIo.accessSync(dirPath)) {
        this.deleteRecursively(dirPath)
      }
    } catch (error) {
      console.error('ImportExportService', `Failed to delete directory: ${JSON.stringify(error)}`)
    }
  }

  private deleteRecursively(path: string): void {
    try {
      const files = fileIo.listFileSync(path)

      for (const file of files) {
        const fullPath = `${path}/${file}`
        const stats = fileIo.statSync(fullPath)

        if (stats.isDirectory()) {
          this.deleteRecursively(fullPath)
        } else {
          fileIo.unlinkSync(fullPath)
        }
      }

      fileIo.rmdirSync(path)
    } catch (error) {
      console.error('ImportExportService', `Failed to delete recursively: ${JSON.stringify(error)}`)
    }
  }

  private getExtension(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.')
    if (dotIndex > 0) {
      return fileName.substring(dotIndex)
    }
    return ''
  }
}

export function getImportExportService(): ImportExportService {
  return ImportExportService.getInstance()
}
