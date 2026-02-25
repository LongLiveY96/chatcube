import { relationalStore } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import {
  ChatMessage,
  ChatSession,
  MessageRole,
  ModelProvider,
  ModelInfo,
  ProviderType,
  ModelInfoExtendedJson,
  MessageAttachment,
  AttachmentType,
  SearchReference
} from '../models/ChatModels'
import { generateDefaultTextIcon } from '../utils/IconGeneratorUtils'
import { isPresetProvider, getPresetProviderById } from '../config/PresetProviders'
import { AppError, AppErrorCode, toErrorDetail } from '../models/AppError'
import { AppStorageKeys } from '../config/AppStorageKeys'

// 数据库配置
const DB_CONFIG: relationalStore.StoreConfig = {
  name: 'chatbox.db',
  securityLevel: relationalStore.SecurityLevel.S1
}

// 表名常量
export class TableNames {
  static readonly SESSIONS: string = 'chat_sessions'
  static readonly MESSAGES: string = 'messages'
  static readonly PROVIDERS: string = 'providers'
  static readonly ATTACHMENTS: string = 'message_attachments'
  static readonly TOOL_EVENTS: string = 'tool_events'
}

// 模型数据接口（用于 JSON 序列化，兼容扩展格式）
interface ModelJsonData {
  id: string
  name: string
  contextLength: number
  isEnabled: boolean
  isRecommended: boolean
  // 扩展字段（可选，用于向后兼容）
  modelType?: string
  inputMode?: string
  outputMode?: string
  capabilities?: CapabilitiesJsonData
  parameters?: ParametersJsonData
}

// 能力配置 JSON 数据
interface CapabilitiesJsonData {
  supportsTools: boolean
  supportsReasoning: boolean
  supportsWebSearch: boolean
  supportsVision: boolean
  supportsStreaming: boolean
}

// 参数配置 JSON 数据
interface ParametersJsonData {
  temperature: number
  topP: number
  maxTokens: number
  presencePenalty: number
  frequencyPenalty: number
}

// 搜索引用 JSON 数据接口（用于序列化）
interface SearchReferenceJsonData {
  id: string
  title: string
  url: string
  snippet: string
  timestamp: number
}

// 数据库服务 - 单例模式
export class DatabaseService {
  private static instance: DatabaseService | null = null
  private rdbStore: relationalStore.RdbStore | null = null
  private isInitialized: boolean = false
  private initPromise: Promise<void> | null = null

  private constructor() {
  }

  static getInstance(): DatabaseService {
    if (DatabaseService.instance === null) {
      DatabaseService.instance = new DatabaseService()
    }
    return DatabaseService.instance
  }

  async initialize(context: Context): Promise<void> {
    if (this.isInitialized) {
      return
    }
    if (this.initPromise !== null) {
      await this.initPromise
      return
    }
    this.initPromise = this.doInitialize(context)
    try {
      await this.initPromise
    } finally {
      this.initPromise = null
    }
  }

  private async doInitialize(context: Context): Promise<void> {
    try {
      this.rdbStore = await relationalStore.getRdbStore(context, DB_CONFIG)
      await this.createTables()
      this.isInitialized = true
    } catch (error) {
      console.error('DatabaseService', `Failed to initialize database: ${JSON.stringify(error)}`)
      throw new AppError(
        AppErrorCode.DATABASE_INIT_FAILED,
        '数据库初始化失败',
        toErrorDetail(error as Object),
        false
      )
    }
  }

  private async waitForInitialization(): Promise<void> {
    // 如果已经初始化完成，直接返回
    if (this.isInitialized) {
      return
    }
    // 如果正在初始化，等待初始化完成
    if (this.initPromise !== null) {
      await this.initPromise
      return
    }
    // 如果 initPromise 为 null 但 isInitialized 为 false，说明初始化还未开始
    // 使用轮询等待机制，最长等待 5 秒
    const maxWaitTime = 5000
    const pollInterval = 50
    let waited = 0
    while (!this.isInitialized && waited < maxWaitTime) {
      await new Promise<void>((resolve) => setTimeout(resolve, pollInterval))
      waited += pollInterval
      // 如果初始化已经开始，直接等待其完成
      if (this.initPromise !== null) {
        await this.initPromise
        return
      }
    }
    if (!this.isInitialized) {
      console.warn('DatabaseService', '等待数据库初始化超时，数据加载可能失败')
    }
  }

  private async createTables(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }

    // 创建会话表
    const createSessionsTable = `
      CREATE TABLE IF NOT EXISTS ${TableNames.SESSIONS} (
        id TEXT PRIMARY KEY,
        title TEXT,
        model_id TEXT,
        provider_id TEXT,
        created_at INTEGER,
        updated_at INTEGER,
        is_favorite INTEGER DEFAULT 0,
        last_message_preview TEXT DEFAULT '',
        message_count INTEGER DEFAULT 0,
        sync_version INTEGER DEFAULT 0,
        last_modified INTEGER DEFAULT 0,
        sync_status TEXT DEFAULT 'synced',
        device_id TEXT DEFAULT ''
      )
    `

    // 创建消息表
    const createMessagesTable = `
      CREATE TABLE IF NOT EXISTS ${TableNames.MESSAGES} (
        id TEXT PRIMARY KEY,
        session_id TEXT,
        role TEXT,
        content TEXT,
        model_name TEXT,
        timestamp INTEGER,
        reasoning_content TEXT,
        FOREIGN KEY (session_id) REFERENCES ${TableNames.SESSIONS}(id)
      )
    `

    // 创建服务商配置表
    const createProvidersTable = `
      CREATE TABLE IF NOT EXISTS ${TableNames.PROVIDERS} (
        id TEXT PRIMARY KEY,
        name TEXT,
        type TEXT,
        api_style TEXT,
        api_key TEXT,
        base_url TEXT,
        is_enabled INTEGER,
        models_json TEXT,
        icon_symbol TEXT,
        brand_color TEXT,
        sort_order INTEGER DEFAULT 0,
        is_preset INTEGER DEFAULT 0,
        icon_path TEXT DEFAULT ''
      )
    `

    // 创建附件表
    const createAttachmentsTable = `
      CREATE TABLE IF NOT EXISTS ${TableNames.ATTACHMENTS} (
        id TEXT PRIMARY KEY,
        message_id TEXT,
        type TEXT,
        name TEXT,
        file_path TEXT,
        mime_type TEXT,
        size INTEGER,
        FOREIGN KEY (message_id) REFERENCES ${TableNames.MESSAGES}(id)
      )
    `

    // 创建工具事件表
    const createToolEventsTable = `
      CREATE TABLE IF NOT EXISTS ${TableNames.TOOL_EVENTS} (
        id TEXT PRIMARY KEY,
        session_id TEXT,
        message_id TEXT,
        tool_call_id TEXT,
        tool_name TEXT,
        tool_arguments TEXT,
        tool_result TEXT,
        status TEXT DEFAULT 'pending',
        created_at INTEGER,
        completed_at INTEGER,
        FOREIGN KEY (session_id) REFERENCES ${TableNames.SESSIONS}(id),
        FOREIGN KEY (message_id) REFERENCES ${TableNames.MESSAGES}(id)
      )
    `

    try {
      await this.rdbStore.executeSql(createSessionsTable)
      await this.rdbStore.executeSql(createMessagesTable)
      await this.rdbStore.executeSql(createProvidersTable)
      await this.rdbStore.executeSql(createAttachmentsTable)
      await this.rdbStore.executeSql(createToolEventsTable)
      // 尝试添加 sort_order 字段（如果表已存在但没有该字段）
      await this.addSortOrderColumnIfNeeded()
      // 尝试添加 reasoning_content 字段（用于推理模型）
      await this.addReasoningContentColumnIfNeeded()
      // 尝试添加 is_preset 和 icon_path 字段（用于供应商图标管理）
      await this.addProviderIconColumnsIfNeeded()
      await this.addApiPathColumnIfNeeded()
      // 尝试添加同步相关字段（为 WebDAV 同步预留）
      await this.addSyncColumnsIfNeeded()
      // 尝试添加会话元信息字段（用于会话列表增强）
      await this.addSessionMetaColumnsIfNeeded()
      // 尝试添加搜索引用相关字段（用于联网搜索）
      await this.addSearchColumnsIfNeeded()
      // 尝试添加消息 model_id 字段（用于图标匹配）
      await this.addMessageModelIdColumnIfNeeded()
      // 迁移现有供应商数据
      await this.migrateExistingProviders()
    } catch (error) {
      console.error('DatabaseService', `Failed to create tables: ${JSON.stringify(error)}`)
      throw new AppError(
        AppErrorCode.DATABASE_SCHEMA_INIT_FAILED,
        '数据库表结构初始化失败',
        toErrorDetail(error as Object),
        false
      )
    }
  }

  // 添加 sort_order 字段（用于数据库升级）
  private async addSortOrderColumnIfNeeded(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.PROVIDERS} ADD COLUMN sort_order INTEGER DEFAULT 0`)
    } catch (error) {
      // 如果字段已存在，会抛出错误，忽略即可
      console.info('DatabaseService', 'sort_order column may already exist')
    }
  }

  // 添加 reasoning_content 字段（用于推理模型）
  private async addReasoningContentColumnIfNeeded(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.MESSAGES} ADD COLUMN reasoning_content TEXT DEFAULT ''`)
    } catch (error) {
      // 如果字段已存在，会抛出错误，忽略即可
      console.info('DatabaseService', 'reasoning_content column may already exist')
    }
  }

  // 添加 is_preset 和 icon_path 字段（用于供应商图标管理）
  private async addProviderIconColumnsIfNeeded(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.PROVIDERS} ADD COLUMN is_preset INTEGER DEFAULT 0`)
    } catch (error) {
      console.info('DatabaseService', 'is_preset column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.PROVIDERS} ADD COLUMN icon_path TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'icon_path column may already exist')
    }
    // 添加图标类型相关字段
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.PROVIDERS} ADD COLUMN icon_type TEXT DEFAULT 'svg'`)
    } catch (error) {
      console.info('DatabaseService', 'icon_type column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.PROVIDERS} ADD COLUMN text_icon TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'text_icon column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.PROVIDERS} ADD COLUMN text_icon_bg_color TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'text_icon_bg_color column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.PROVIDERS} ADD COLUMN custom_image_path TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'custom_image_path column may already exist')
    }
  }

  // 迁移现有供应商数据（为图标类型字段设置默认值）
  private async migrateExistingProviders(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    try {
      // 查询所有供应商
      const predicates = new relationalStore.RdbPredicates(TableNames.PROVIDERS)
      const resultSet = await this.rdbStore.query(predicates)

      while (resultSet.goToNextRow()) {
        const id = resultSet.getString(resultSet.getColumnIndex('id'))
        let iconType = ''
        try {
          iconType = resultSet.getString(resultSet.getColumnIndex('icon_type'))
        } catch (e) {
          iconType = ''
        }

        // 预设供应商：强制迁移为 TEXT 类型
        if (isPresetProvider(id)) {
          const preset = getPresetProviderById(id)
          if (preset !== null && (iconType === '' || iconType === 'svg')) {
            const updatePredicates = new relationalStore.RdbPredicates(TableNames.PROVIDERS)
            updatePredicates.equalTo('id', id)
            const valueBucket: relationalStore.ValuesBucket = {
              'icon_type': 'text',
              'icon_path': '',
              'text_icon': preset.textIcon,
              'text_icon_bg_color': preset.textIconBgColor
            }
            await this.rdbStore.update(valueBucket, updatePredicates)
          }
          continue
        }

        // 非预设供应商：保持原有逻辑
        if (iconType === '' || iconType === 'svg') {
          const iconPath = resultSet.getString(resultSet.getColumnIndex('icon_path'))
          const name = resultSet.getString(resultSet.getColumnIndex('name'))

          if (iconPath !== '' && iconPath !== null) {
            const updatePredicates = new relationalStore.RdbPredicates(TableNames.PROVIDERS)
            updatePredicates.equalTo('id', id)
            const valueBucket: relationalStore.ValuesBucket = {
              'icon_type': 'svg'
            }
            await this.rdbStore.update(valueBucket, updatePredicates)
          } else {
            const config = generateDefaultTextIcon(name)
            const updatePredicates = new relationalStore.RdbPredicates(TableNames.PROVIDERS)
            updatePredicates.equalTo('id', id)
            const valueBucket: relationalStore.ValuesBucket = {
              'icon_type': 'text',
              'text_icon': config.text,
              'text_icon_bg_color': config.bgColor
            }
            await this.rdbStore.update(valueBucket, updatePredicates)
          }
        }
      }

      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to migrate providers: ${JSON.stringify(error)}`)
    }
  }

  // 添加 api_path 字段（用于自定义 API 路径）
  private async addApiPathColumnIfNeeded(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.PROVIDERS} ADD COLUMN api_path TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'api_path column may already exist')
    }
  }

  // 添加同步相关字段（为 WebDAV 同步预留）
  private async addSyncColumnsIfNeeded(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.SESSIONS} ADD COLUMN sync_version INTEGER DEFAULT 0`)
    } catch (error) {
      console.info('DatabaseService', 'sync_version column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.SESSIONS} ADD COLUMN last_modified INTEGER DEFAULT 0`)
    } catch (error) {
      console.info('DatabaseService', 'last_modified column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.SESSIONS} ADD COLUMN sync_status TEXT DEFAULT 'synced'`)
    } catch (error) {
      console.info('DatabaseService', 'sync_status column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.SESSIONS} ADD COLUMN device_id TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'device_id column may already exist')
    }
  }

  // 添加会话元信息字段（用于会话列表增强）
  private async addSessionMetaColumnsIfNeeded(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.SESSIONS} ADD COLUMN is_favorite INTEGER DEFAULT 0`)
    } catch (error) {
      console.info('DatabaseService', 'is_favorite column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.SESSIONS} ADD COLUMN last_message_preview TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'last_message_preview column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.SESSIONS} ADD COLUMN message_count INTEGER DEFAULT 0`)
    } catch (error) {
      console.info('DatabaseService', 'message_count column may already exist')
    }
  }

  // 添加搜索引用相关字段（用于联网搜索）
  private async addSearchColumnsIfNeeded(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.MESSAGES} ADD COLUMN search_query TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'search_query column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.MESSAGES} ADD COLUMN search_engine TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'search_engine column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.MESSAGES} ADD COLUMN search_source TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'search_source column may already exist')
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.MESSAGES} ADD COLUMN search_references TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'search_references column may already exist')
    }
  }

  // 添加 model_id 字段到消息表（用于图标匹配）
  private async addMessageModelIdColumnIfNeeded(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${TableNames.MESSAGES} ADD COLUMN model_id TEXT DEFAULT ''`)
    } catch (error) {
      console.info('DatabaseService', 'messages model_id column may already exist')
    }
  }

  private normalizePreview(content: string): string {
    if (content === '') {
      return ''
    }
    const normalized = content.replace(/\s+/g, ' ').trim()
    if (normalized.length === 0) {
      return ''
    }
    if (normalized.length <= 48) {
      return normalized
    }
    return normalized.substring(0, 48) + '...'
  }

  private async getMessageSessionId(messageId: string): Promise<string> {
    if (this.rdbStore === null) {
      return ''
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.MESSAGES)
    predicates.equalTo('id', messageId)
    try {
      const resultSet = await this.rdbStore.query(predicates)
      if (resultSet.goToNextRow()) {
        const sessionId = resultSet.getString(resultSet.getColumnIndex('session_id'))
        resultSet.close()
        return sessionId
      }
      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to get message session id: ${JSON.stringify(error)}`)
    }
    return ''
  }

  private async refreshSessionSummary(sessionId: string): Promise<void> {
    if (this.rdbStore === null || sessionId === '') {
      return
    }

    let messageCount = 0
    let latestTimestamp = 0
    let latestPreview = ''

    const predicates = new relationalStore.RdbPredicates(TableNames.MESSAGES)
    predicates.equalTo('session_id', sessionId)
    predicates.orderByDesc('timestamp')
    try {
      const resultSet = await this.rdbStore.query(predicates)
      while (resultSet.goToNextRow()) {
        messageCount = messageCount + 1
        if (messageCount === 1) {
          latestTimestamp = resultSet.getLong(resultSet.getColumnIndex('timestamp'))
          latestPreview = this.normalizePreview(resultSet.getString(resultSet.getColumnIndex('content')) || '')
        }
      }
      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to refresh session summary: ${JSON.stringify(error)}`)
      return
    }

    let valueBucket: relationalStore.ValuesBucket
    if (latestTimestamp > 0) {
      valueBucket = {
        message_count: messageCount,
        last_message_preview: latestPreview,
        updated_at: latestTimestamp
      }
    } else {
      valueBucket = {
        message_count: messageCount,
        last_message_preview: latestPreview
      }
    }
    const updatePredicates = new relationalStore.RdbPredicates(TableNames.SESSIONS)
    updatePredicates.equalTo('id', sessionId)
    try {
      await this.rdbStore.update(valueBucket, updatePredicates)
      AppStorage.setOrCreate<number>(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())
    } catch (error) {
      console.error('DatabaseService', `Failed to update session summary: ${JSON.stringify(error)}`)
    }
  }

  private addUniqueSessionId(list: string[], sessionId: string): void {
    if (sessionId === '') {
      return
    }
    for (let i = 0; i < list.length; i++) {
      if (list[i] === sessionId) {
        return
      }
    }
    list.push(sessionId)
  }

  // ============ 会话操作 ============

  // 创建新会话
  async createSession(session: ChatSession): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    const valueBucket: relationalStore.ValuesBucket = {
      id: session.id,
      title: session.title,
      model_id: session.modelId,
      provider_id: session.providerId,  // 使用会话的 providerId 字段
      created_at: session.createdAt,
      updated_at: session.updatedAt,
      is_favorite: session.isFavorite ? 1 : 0,
      last_message_preview: session.lastMessagePreview,
      message_count: session.messageCount
    }
    try {
      await this.rdbStore.insert(TableNames.SESSIONS, valueBucket)
    } catch (error) {
      console.error('DatabaseService', `Failed to create session: ${JSON.stringify(error)}`)
    }
  }

  // 更新会话
  async updateSession(session: ChatSession): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    const valueBucket: relationalStore.ValuesBucket = {
      title: session.title,
      model_id: session.modelId,
      updated_at: Date.now()
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.SESSIONS)
    predicates.equalTo('id', session.id)
    try {
      await this.rdbStore.update(valueBucket, predicates)
    } catch (error) {
      console.error('DatabaseService', `Failed to update session: ${JSON.stringify(error)}`)
    }
  }

  // 仅更新会话标题（不修改 updated_at，避免改变会话时间排序）
  async updateSessionTitle(sessionId: string, title: string): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    const valueBucket: relationalStore.ValuesBucket = {
      title: title
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.SESSIONS)
    predicates.equalTo('id', sessionId)
    try {
      await this.rdbStore.update(valueBucket, predicates)
    } catch (error) {
      console.error('DatabaseService', `Failed to update session title: ${JSON.stringify(error)}`)
    }
  }
  async toggleSessionFavorite(sessionId: string): Promise<boolean> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return false
    }

    const predicates = new relationalStore.RdbPredicates(TableNames.SESSIONS)
    predicates.equalTo('id', sessionId)
    try {
      const resultSet = await this.rdbStore.query(predicates)
      if (!resultSet.goToNextRow()) {
        resultSet.close()
        return false
      }
      let currentValue = false
      try {
        currentValue = resultSet.getLong(resultSet.getColumnIndex('is_favorite')) === 1
      } catch (e) {
        currentValue = false
      }
      resultSet.close()

      const nextValue = !currentValue
      const valueBucket: relationalStore.ValuesBucket = {
        is_favorite: nextValue ? 1 : 0
      }
      await this.rdbStore.update(valueBucket, predicates)
      return nextValue
    } catch (error) {
      console.error('DatabaseService', `Failed to toggle session favorite: ${JSON.stringify(error)}`)
      return false
    }
  }

  // 更新会话时间戳（用于导入时恢复原始时间）
  async updateSessionTimestamps(sessionId: string, createdAt: number, updatedAt: number): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    const valueBucket: relationalStore.ValuesBucket = {
      created_at: createdAt,
      updated_at: updatedAt
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.SESSIONS)
    predicates.equalTo('id', sessionId)
    try {
      await this.rdbStore.update(valueBucket, predicates)
    } catch (error) {
      console.error('DatabaseService', `Failed to update session timestamps: ${JSON.stringify(error)}`)
    }
  }

  // 删除会话及其消息
  async deleteSession(sessionId: string): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    try {
      // 删除消息
      const messagePredicates = new relationalStore.RdbPredicates(TableNames.MESSAGES)
      messagePredicates.equalTo('session_id', sessionId)
      await this.rdbStore.delete(messagePredicates)

      // 删除会话
      const sessionPredicates = new relationalStore.RdbPredicates(TableNames.SESSIONS)
      sessionPredicates.equalTo('id', sessionId)
      await this.rdbStore.delete(sessionPredicates)
    } catch (error) {
      console.error('DatabaseService', `Failed to delete session: ${JSON.stringify(error)}`)
    }
  }

  // 获取所有会话
  async getAllSessions(): Promise<ChatSession[]> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return []
    }
    const sessions: ChatSession[] = []
    const predicates = new relationalStore.RdbPredicates(TableNames.SESSIONS)
    predicates.orderByDesc('updated_at')
    try {
      const resultSet = await this.rdbStore.query(predicates)
      while (resultSet.goToNextRow()) {
        // 获取 provider_id 列索引，兼容旧数据库（可能不存在该列）
        let providerId = ''
        try {
          const providerIdIndex = resultSet.getColumnIndex('provider_id')
          if (providerIdIndex >= 0) {
            providerId = resultSet.getString(providerIdIndex)
          }
        } catch (e) {
          // 列不存在，使用默认值
        }

        const session = new ChatSession(
          resultSet.getString(resultSet.getColumnIndex('id')),
          resultSet.getString(resultSet.getColumnIndex('title')),
          resultSet.getString(resultSet.getColumnIndex('model_id')),
          providerId  // 传递 providerId
        )
        session.createdAt = resultSet.getLong(resultSet.getColumnIndex('created_at'))
        session.updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'))
        try {
          session.isFavorite = resultSet.getLong(resultSet.getColumnIndex('is_favorite')) === 1
        } catch (e) {
          session.isFavorite = false
        }
        try {
          session.lastMessagePreview = resultSet.getString(resultSet.getColumnIndex('last_message_preview')) || ''
        } catch (e) {
          session.lastMessagePreview = ''
        }
        try {
          session.messageCount = resultSet.getLong(resultSet.getColumnIndex('message_count'))
        } catch (e) {
          session.messageCount = 0
        }
        sessions.push(session)
      }
      resultSet.close()

      // 兼容旧数据：首次加载时回填会话摘要和计数
      for (let i = 0; i < sessions.length; i++) {
        if (sessions[i].messageCount === 0 &&
          sessions[i].lastMessagePreview === '' &&
          sessions[i].updatedAt > sessions[i].createdAt) {
          await this.refreshSessionSummary(sessions[i].id)
          const summaryPredicates = new relationalStore.RdbPredicates(TableNames.SESSIONS)
          summaryPredicates.equalTo('id', sessions[i].id)
          const summaryResult = await this.rdbStore.query(summaryPredicates)
          if (summaryResult.goToNextRow()) {
            try {
              sessions[i].lastMessagePreview = summaryResult.getString(summaryResult.getColumnIndex('last_message_preview')) || ''
            } catch (e) {
              sessions[i].lastMessagePreview = ''
            }
            try {
              sessions[i].messageCount = summaryResult.getLong(summaryResult.getColumnIndex('message_count'))
            } catch (e) {
              sessions[i].messageCount = 0
            }
            try {
              sessions[i].updatedAt = summaryResult.getLong(summaryResult.getColumnIndex('updated_at'))
            } catch (e) {
              // ignore
            }
          }
          summaryResult.close()
        }
      }
    } catch (error) {
      console.error('DatabaseService', `Failed to get sessions: ${JSON.stringify(error)}`)
    }
    return sessions
  }

  // 获取单个会话
  async getSession(sessionId: string): Promise<ChatSession | null> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return null
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.SESSIONS)
    predicates.equalTo('id', sessionId)
    try {
      const resultSet = await this.rdbStore.query(predicates)
      if (resultSet.goToNextRow()) {
        // 获取 provider_id 列索引，兼容旧数据库（可能不存在该列）
        let providerId = ''
        try {
          const providerIdIndex = resultSet.getColumnIndex('provider_id')
          if (providerIdIndex >= 0) {
            providerId = resultSet.getString(providerIdIndex)
          }
        } catch (e) {
          // 列不存在，使用默认值
        }

        const session = new ChatSession(
          resultSet.getString(resultSet.getColumnIndex('id')),
          resultSet.getString(resultSet.getColumnIndex('title')),
          resultSet.getString(resultSet.getColumnIndex('model_id')),
          providerId  // 传递 providerId
        )
        session.createdAt = resultSet.getLong(resultSet.getColumnIndex('created_at'))
        session.updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'))
        try {
          session.isFavorite = resultSet.getLong(resultSet.getColumnIndex('is_favorite')) === 1
        } catch (e) {
          session.isFavorite = false
        }
        try {
          session.lastMessagePreview = resultSet.getString(resultSet.getColumnIndex('last_message_preview')) || ''
        } catch (e) {
          session.lastMessagePreview = ''
        }
        try {
          session.messageCount = resultSet.getLong(resultSet.getColumnIndex('message_count'))
        } catch (e) {
          session.messageCount = 0
        }
        resultSet.close()
        return session
      }
      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to get session: ${JSON.stringify(error)}`)
    }
    return null
  }

  // ============ 消息操作 ============

  // 添加消息
  async addMessage(sessionId: string, message: ChatMessage): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }

    // 将 searchReferences 数组序列化为 JSON 字符串
    let searchReferencesJson = ''
    if (message.searchReferences.length > 0) {
      const refsArray: SearchReferenceJsonData[] = []
      for (let i = 0; i < message.searchReferences.length; i++) {
        const ref = message.searchReferences[i]
        refsArray.push({
          id: ref.id,
          title: ref.title,
          url: ref.url,
          snippet: ref.snippet,
          timestamp: ref.timestamp
        })
      }
      searchReferencesJson = JSON.stringify(refsArray)
    }

    const valueBucket: relationalStore.ValuesBucket = {
      id: message.id,
      session_id: sessionId,
      role: message.role,
      content: message.content,
      model_name: message.modelName,
      model_id: message.modelId || '',
      timestamp: message.timestamp,
      reasoning_content: message.reasoningContent,
      // 保存搜索引用数据
      search_query: message.searchQuery || '',
      search_engine: message.searchEngine || '',
      search_source: message.searchSource || '',
      search_references: searchReferencesJson
    }
    try {
      await this.rdbStore.insert(TableNames.MESSAGES, valueBucket)

      // 保存附件
      if (message.attachments.length > 0) {
        for (let i = 0; i < message.attachments.length; i++) {
          const attachment = message.attachments[i]
          await this.addAttachment(message.id, attachment)
        }
      }

      // 同步会话摘要、计数和更新时间
      await this.refreshSessionSummary(sessionId)
    } catch (error) {
      console.error('DatabaseService', `Failed to add message: ${JSON.stringify(error)}`)
    }
  }

  // 添加附件
  private async addAttachment(messageId: string, attachment: MessageAttachment): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    const valueBucket: relationalStore.ValuesBucket = {
      id: attachment.id,
      message_id: messageId,
      type: attachment.type,
      name: attachment.name,
      file_path: attachment.filePath,
      mime_type: attachment.mimeType,
      size: attachment.size
    }
    try {
      await this.rdbStore.insert(TableNames.ATTACHMENTS, valueBucket)
    } catch (error) {
      console.error('DatabaseService', `Failed to add attachment: ${JSON.stringify(error)}`)
    }
  }

  // 获取消息的附件
  private async getAttachments(messageId: string): Promise<MessageAttachment[]> {
    if (this.rdbStore === null) {
      return []
    }
    const attachments: MessageAttachment[] = []
    const predicates = new relationalStore.RdbPredicates(TableNames.ATTACHMENTS)
    predicates.equalTo('message_id', messageId)
    try {
      const resultSet = await this.rdbStore.query(predicates)
      while (resultSet.goToNextRow()) {
        const typeStr = resultSet.getString(resultSet.getColumnIndex('type'))
        const attachmentType = typeStr === 'image' ? AttachmentType.IMAGE : AttachmentType.FILE
        const attachment = new MessageAttachment(
          resultSet.getString(resultSet.getColumnIndex('id')),
          attachmentType,
          resultSet.getString(resultSet.getColumnIndex('name')),
          resultSet.getString(resultSet.getColumnIndex('file_path')),
          resultSet.getString(resultSet.getColumnIndex('mime_type')),
          resultSet.getLong(resultSet.getColumnIndex('size'))
        )
        attachments.push(attachment)
      }
      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to get attachments: ${JSON.stringify(error)}`)
    }
    return attachments
  }

  // 获取会话的所有消息
  async getMessages(sessionId: string): Promise<ChatMessage[]> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return []
    }
    const messages: ChatMessage[] = []
    const predicates = new relationalStore.RdbPredicates(TableNames.MESSAGES)
    predicates.equalTo('session_id', sessionId)
    predicates.orderByAsc('timestamp')
    try {
      const resultSet = await this.rdbStore.query(predicates)
      while (resultSet.goToNextRow()) {
        const roleStr = resultSet.getString(resultSet.getColumnIndex('role'))
        let role: MessageRole = MessageRole.USER
        if (roleStr === 'assistant') {
          role = MessageRole.ASSISTANT
        } else if (roleStr === 'system') {
          role = MessageRole.SYSTEM
        }
        const messageId = resultSet.getString(resultSet.getColumnIndex('id'))
        const message = new ChatMessage(
          messageId,
          role,
          resultSet.getString(resultSet.getColumnIndex('content')),
          resultSet.getString(resultSet.getColumnIndex('model_name'))
        )
        // 读取 model_id（历史消息可能没有该字段）
        try {
          message.modelId = resultSet.getString(resultSet.getColumnIndex('model_id')) || ''
        } catch (e) {
          message.modelId = ''
        }
        message.timestamp = resultSet.getLong(resultSet.getColumnIndex('timestamp'))
        // 读取推理内容
        try {
          const reasoningContent = resultSet.getString(resultSet.getColumnIndex('reasoning_content'))
          message.reasoningContent = reasoningContent || ''
        } catch (e) {
          // 如果字段不存在，使用默认值
          message.reasoningContent = ''
        }
        // 恢复搜索引用数据
        try {
          message.searchQuery = resultSet.getString(resultSet.getColumnIndex('search_query')) || ''
        } catch (e) {
          message.searchQuery = ''
        }
        try {
          message.searchEngine = resultSet.getString(resultSet.getColumnIndex('search_engine')) || ''
        } catch (e) {
          message.searchEngine = ''
        }
        try {
          message.searchSource = resultSet.getString(resultSet.getColumnIndex('search_source')) || ''
        } catch (e) {
          message.searchSource = ''
        }
        try {
          const searchReferencesJson = resultSet.getString(resultSet.getColumnIndex('search_references')) || ''
          if (searchReferencesJson.length > 0) {
            const refsArray = JSON.parse(searchReferencesJson) as SearchReferenceJsonData[]
            for (let i = 0; i < refsArray.length; i++) {
              const refData = refsArray[i]
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
        } catch (e) {
          console.error('DatabaseService', `Failed to parse search references: ${JSON.stringify(e)}`)
        }
        messages.push(message)
      }
      resultSet.close()

      // 加载每条消息的附件
      for (let i = 0; i < messages.length; i++) {
        const attachments = await this.getAttachments(messages[i].id)
        messages[i].attachments = attachments
      }
    } catch (error) {
      console.error('DatabaseService', `Failed to get messages: ${JSON.stringify(error)}`)
    }
    return messages
  }

  // 删除消息
  async deleteMessage(messageId: string): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    const sessionId = await this.getMessageSessionId(messageId)
    try {
      // 先删除附件记录（不删除文件，可能被重新生成复用）
      const attachmentPredicates = new relationalStore.RdbPredicates(TableNames.ATTACHMENTS)
      attachmentPredicates.equalTo('message_id', messageId)
      await this.rdbStore.delete(attachmentPredicates)

      const predicates = new relationalStore.RdbPredicates(TableNames.MESSAGES)
      predicates.equalTo('id', messageId)
      await this.rdbStore.delete(predicates)

      if (sessionId !== '') {
        await this.refreshSessionSummary(sessionId)
      }
    } catch (error) {
      console.error('DatabaseService', `Failed to delete message: ${JSON.stringify(error)}`)
    }
  }

  // 批量删除消息
  async deleteMessagesByIds(messageIds: string[]): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    if (messageIds.length === 0) {
      return
    }
    try {
      const touchedSessionIds: string[] = []
      for (let i = 0; i < messageIds.length; i++) {
        const sessionId = await this.getMessageSessionId(messageIds[i])
        this.addUniqueSessionId(touchedSessionIds, sessionId)

        // 先删除附件记录（不删除文件，可能被重新生成复用）
        const attachmentPredicates = new relationalStore.RdbPredicates(TableNames.ATTACHMENTS)
        attachmentPredicates.equalTo('message_id', messageIds[i])
        await this.rdbStore.delete(attachmentPredicates)

        const predicates = new relationalStore.RdbPredicates(TableNames.MESSAGES)
        predicates.equalTo('id', messageIds[i])
        await this.rdbStore.delete(predicates)
      }
      for (let i = 0; i < touchedSessionIds.length; i++) {
        await this.refreshSessionSummary(touchedSessionIds[i])
      }
      console.info('DatabaseService', `Deleted ${messageIds.length} messages with attachments`)
    } catch (error) {
      console.error('DatabaseService', `Failed to delete messages: ${JSON.stringify(error)}`)
    }
  }

  // 更新消息内容
  async updateMessageContent(messageId: string, content: string): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    const valueBucket: relationalStore.ValuesBucket = {
      content: content
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.MESSAGES)
    predicates.equalTo('id', messageId)
    try {
      await this.rdbStore.update(valueBucket, predicates)

      const sessionId = await this.getMessageSessionId(messageId)
      if (sessionId !== '') {
        await this.refreshSessionSummary(sessionId)
      }
    } catch (error) {
      console.error('DatabaseService', `Failed to update message: ${JSON.stringify(error)}`)
    }
  }

  // 更新消息附件
  async updateMessageAttachments(messageId: string, attachments: MessageAttachment[]): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    try {
      // 1. 先删除该消息的所有附件
      const deletePredicates = new relationalStore.RdbPredicates(TableNames.ATTACHMENTS)
      deletePredicates.equalTo('message_id', messageId)
      await this.rdbStore.delete(deletePredicates)

      // 2. 插入新的附件
      for (let i = 0; i < attachments.length; i++) {
        const attachment = attachments[i]
        const valueBucket: relationalStore.ValuesBucket = {
          id: attachment.id,
          message_id: messageId,
          type: attachment.type,
          name: attachment.name,
          file_path: attachment.filePath,
          mime_type: attachment.mimeType,
          size: attachment.size
        }
        await this.rdbStore.insert(TableNames.ATTACHMENTS, valueBucket)
      }
      console.info('DatabaseService', `Updated attachments for message ${messageId}: ${attachments.length} attachments`)
    } catch (error) {
      console.error('DatabaseService', `Failed to update message attachments: ${JSON.stringify(error)}`)
    }
  }

  // ============ 服务商操作 ============

  // 保存服务商配置
  async saveProvider(provider: ModelProvider): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }

    // 将 models 数组转换为 JSON 字符串（使用扩展格式）
    const modelsArray: ModelJsonData[] = []
    for (let i = 0; i < provider.models.length; i++) {
      const model = provider.models[i]

      // 构建能力配置对象
      const capabilitiesData: CapabilitiesJsonData = {
        supportsTools: model.capabilities.supportsTools,
        supportsReasoning: model.capabilities.supportsReasoning,
        supportsWebSearch: model.capabilities.supportsWebSearch,
        supportsVision: model.capabilities.supportsVision,
        supportsStreaming: model.capabilities.supportsStreaming
      }

      // 构建参数配置对象
      const parametersData: ParametersJsonData = {
        temperature: model.parameters.temperature,
        topP: model.parameters.topP,
        maxTokens: model.parameters.maxTokens,
        presencePenalty: model.parameters.presencePenalty,
        frequencyPenalty: model.parameters.frequencyPenalty
      }

      // 构建模型数据对象
      const modelObj: ModelJsonData = {
        id: model.id,
        name: model.name,
        contextLength: model.contextLength,
        isEnabled: model.isEnabled,
        isRecommended: model.isRecommended,
        modelType: model.modelType,
        inputMode: model.inputMode,
        outputMode: model.outputMode,
        capabilities: capabilitiesData,
        parameters: parametersData
      }
      modelsArray.push(modelObj)
    }
    const modelsJson = JSON.stringify(modelsArray)

    const valueBucket: relationalStore.ValuesBucket = {
      id: provider.id,
      name: provider.name,
      type: provider.type,
      api_style: provider.apiStyle,
      api_key: provider.apiKey,
      base_url: provider.baseUrl,
      is_enabled: provider.isConnected ? 1 : 0,
      models_json: modelsJson,
      icon_symbol: provider.iconSymbol,
      brand_color: '',
      is_preset: provider.isPreset ? 1 : 0,
      icon_path: provider.iconPath,
      api_path: provider.apiPath,
      icon_type: provider.iconType,
      text_icon: provider.textIcon,
      text_icon_bg_color: provider.textIconBgColor,
      custom_image_path: provider.customImagePath
    }

    try {
      // 先检查是否存在
      const predicates = new relationalStore.RdbPredicates(TableNames.PROVIDERS)
      predicates.equalTo('id', provider.id)
      const resultSet = await this.rdbStore.query(predicates)
      const exists = resultSet.goToNextRow()
      resultSet.close()

      if (exists) {
        await this.rdbStore.update(valueBucket, predicates)
      } else {
        await this.rdbStore.insert(TableNames.PROVIDERS, valueBucket)
      }
    } catch (error) {
      console.error('DatabaseService', `Failed to save provider: ${JSON.stringify(error)}`)
    }
  }

  // 获取所有服务商配置
  async getAllProviders(): Promise<ProviderConfig[]> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return []
    }
    const providers: ProviderConfig[] = []
    const predicates = new relationalStore.RdbPredicates(TableNames.PROVIDERS)
    predicates.orderByAsc('sort_order')
    try {
      const resultSet = await this.rdbStore.query(predicates)
      while (resultSet.goToNextRow()) {
        // 安全读取 is_preset 字段
        let isPreset = false
        try {
          isPreset = resultSet.getLong(resultSet.getColumnIndex('is_preset')) === 1
        } catch (e) {
          isPreset = false
        }
        // 安全读取 icon_path 字段
        let iconPath = ''
        try {
          iconPath = resultSet.getString(resultSet.getColumnIndex('icon_path'))
        } catch (e) {
          iconPath = ''
        }
        // 安全读取 api_path 字段
        let apiPath = ''
        try {
          apiPath = resultSet.getString(resultSet.getColumnIndex('api_path'))
        } catch (e) {
          apiPath = ''
        }
        // 安全读取图标类型相关字段
        let iconType = 'svg'
        try {
          iconType = resultSet.getString(resultSet.getColumnIndex('icon_type'))
        } catch (e) {
          iconType = 'svg'
        }
        let textIcon = ''
        try {
          textIcon = resultSet.getString(resultSet.getColumnIndex('text_icon'))
        } catch (e) {
          textIcon = ''
        }
        let textIconBgColor = ''
        try {
          textIconBgColor = resultSet.getString(resultSet.getColumnIndex('text_icon_bg_color'))
        } catch (e) {
          textIconBgColor = ''
        }
        let customImagePath = ''
        try {
          customImagePath = resultSet.getString(resultSet.getColumnIndex('custom_image_path'))
        } catch (e) {
          customImagePath = ''
        }

        const config: ProviderConfig = {
          id: resultSet.getString(resultSet.getColumnIndex('id')),
          name: resultSet.getString(resultSet.getColumnIndex('name')),
          type: resultSet.getString(resultSet.getColumnIndex('type')),
          apiStyle: resultSet.getString(resultSet.getColumnIndex('api_style')),
          apiKey: resultSet.getString(resultSet.getColumnIndex('api_key')),
          baseUrl: resultSet.getString(resultSet.getColumnIndex('base_url')),
          isEnabled: resultSet.getLong(resultSet.getColumnIndex('is_enabled')) === 1,
          modelsJson: resultSet.getString(resultSet.getColumnIndex('models_json')),
          iconSymbol: resultSet.getString(resultSet.getColumnIndex('icon_symbol')),
          sortOrder: resultSet.getLong(resultSet.getColumnIndex('sort_order')),
          isPreset: isPreset,
          iconPath: iconPath,
          apiPath: apiPath,
          iconType: iconType,
          textIcon: textIcon,
          textIconBgColor: textIconBgColor,
          customImagePath: customImagePath
        }
        providers.push(config)
      }
      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to get providers: ${JSON.stringify(error)}`)
    }
    return providers
  }

  // 删除服务商配置
  async deleteProvider(providerId: string): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.PROVIDERS)
    predicates.equalTo('id', providerId)
    try {
      await this.rdbStore.delete(predicates)
    } catch (error) {
      console.error('DatabaseService', `Failed to delete provider: ${JSON.stringify(error)}`)
    }
  }

  // 更新服务商启用状态
  async updateProviderEnabled(providerId: string, isEnabled: boolean): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    const valueBucket: relationalStore.ValuesBucket = {
      is_enabled: isEnabled ? 1 : 0
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.PROVIDERS)
    predicates.equalTo('id', providerId)
    try {
      await this.rdbStore.update(valueBucket, predicates)
    } catch (error) {
      console.error('DatabaseService', `Failed to update provider enabled status: ${JSON.stringify(error)}`)
    }
  }

  // 获取单个服务商的 API Key
  async getProviderApiKey(providerId: string): Promise<string> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return ''
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.PROVIDERS)
    predicates.equalTo('id', providerId)
    try {
      const resultSet = await this.rdbStore.query(predicates)
      if (resultSet.goToNextRow()) {
        const apiKey = resultSet.getString(resultSet.getColumnIndex('api_key'))
        resultSet.close()
        return apiKey
      }
      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to get API key: ${JSON.stringify(error)}`)
    }
    return ''
  }

  // 更新供应商排序顺序
  async updateProviderSortOrder(providerId: string, sortOrder: number): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    const valueBucket: relationalStore.ValuesBucket = {
      sort_order: sortOrder
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.PROVIDERS)
    predicates.equalTo('id', providerId)
    try {
      await this.rdbStore.update(valueBucket, predicates)
    } catch (error) {
      console.error('DatabaseService', `Failed to update provider sort order: ${JSON.stringify(error)}`)
    }
  }

  // 批量更新供应商排序顺序
  async updateProvidersOrder(providerIds: string[]): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }
    try {
      for (let i = 0; i < providerIds.length; i++) {
        const valueBucket: relationalStore.ValuesBucket = {
          sort_order: i
        }
        const predicates = new relationalStore.RdbPredicates(TableNames.PROVIDERS)
        predicates.equalTo('id', providerIds[i])
        await this.rdbStore.update(valueBucket, predicates)
      }
    } catch (error) {
      console.error('DatabaseService', `Failed to update providers order: ${JSON.stringify(error)}`)
    }
  }

  // ============ 工具事件操作 ============

  // 保存工具事件
  async saveToolEvent(
    sessionId: string,
    messageId: string,
    toolCallId: string,
    toolName: string,
    toolArguments: string,
    toolResult: string,
    status: string
  ): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }

    const eventId = `${toolCallId}_${Date.now()}`
    const now = Date.now()

    const valueBucket: relationalStore.ValuesBucket = {
      id: eventId,
      session_id: sessionId,
      message_id: messageId,
      tool_call_id: toolCallId,
      tool_name: toolName,
      tool_arguments: toolArguments,
      tool_result: toolResult,
      status: status,
      created_at: now,
      completed_at: status === 'completed' ? now : 0
    }

    try {
      await this.rdbStore.insert(TableNames.TOOL_EVENTS, valueBucket)
      console.info('DatabaseService', `Tool event saved: ${eventId}`)
    } catch (error) {
      console.error('DatabaseService', `Failed to save tool event: ${JSON.stringify(error)}`)
    }
  }

  // 获取消息相关的工具事件
  async getToolEvents(messageId: string): Promise<ToolEventData[]> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return []
    }

    const events: ToolEventData[] = []
    const predicates = new relationalStore.RdbPredicates(TableNames.TOOL_EVENTS)
    predicates.equalTo('message_id', messageId)
    predicates.orderByAsc('created_at')

    try {
      const resultSet = await this.rdbStore.query(predicates)
      while (resultSet.goToNextRow()) {
        const eventData: ToolEventData = {
          id: resultSet.getString(resultSet.getColumnIndex('id')),
          sessionId: resultSet.getString(resultSet.getColumnIndex('session_id')),
          messageId: resultSet.getString(resultSet.getColumnIndex('message_id')),
          toolCallId: resultSet.getString(resultSet.getColumnIndex('tool_call_id')),
          toolName: resultSet.getString(resultSet.getColumnIndex('tool_name')),
          toolArguments: resultSet.getString(resultSet.getColumnIndex('tool_arguments')),
          toolResult: resultSet.getString(resultSet.getColumnIndex('tool_result')),
          status: resultSet.getString(resultSet.getColumnIndex('status')),
          createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
          completedAt: resultSet.getLong(resultSet.getColumnIndex('completed_at'))
        }
        events.push(eventData)
      }
      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to get tool events: ${JSON.stringify(error)}`)
    }

    return events
  }

  // 获取会话的所有工具事件
  async getToolEventsBySession(sessionId: string): Promise<ToolEventData[]> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return []
    }

    const events: ToolEventData[] = []
    const predicates = new relationalStore.RdbPredicates(TableNames.TOOL_EVENTS)
    predicates.equalTo('session_id', sessionId)
    predicates.orderByAsc('created_at')

    try {
      const resultSet = await this.rdbStore.query(predicates)
      while (resultSet.goToNextRow()) {
        const eventData: ToolEventData = {
          id: resultSet.getString(resultSet.getColumnIndex('id')),
          sessionId: resultSet.getString(resultSet.getColumnIndex('session_id')),
          messageId: resultSet.getString(resultSet.getColumnIndex('message_id')),
          toolCallId: resultSet.getString(resultSet.getColumnIndex('tool_call_id')),
          toolName: resultSet.getString(resultSet.getColumnIndex('tool_name')),
          toolArguments: resultSet.getString(resultSet.getColumnIndex('tool_arguments')),
          toolResult: resultSet.getString(resultSet.getColumnIndex('tool_result')),
          status: resultSet.getString(resultSet.getColumnIndex('status')),
          createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
          completedAt: resultSet.getLong(resultSet.getColumnIndex('completed_at'))
        }
        events.push(eventData)
      }
      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to get tool events by session: ${JSON.stringify(error)}`)
    }

    return events
  }

  // 获取最近的工具事件（按时间倒序）
  async getRecentToolEvents(limit: number = 20): Promise<ToolEventData[]> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return []
    }

    const events: ToolEventData[] = []
    const predicates = new relationalStore.RdbPredicates(TableNames.TOOL_EVENTS)
    predicates.orderByDesc('created_at')

    try {
      const resultSet = await this.rdbStore.query(predicates)
      let count = 0
      while (resultSet.goToNextRow()) {
        if (count >= limit) {
          break
        }
        const eventData: ToolEventData = {
          id: resultSet.getString(resultSet.getColumnIndex('id')),
          sessionId: resultSet.getString(resultSet.getColumnIndex('session_id')),
          messageId: resultSet.getString(resultSet.getColumnIndex('message_id')),
          toolCallId: resultSet.getString(resultSet.getColumnIndex('tool_call_id')),
          toolName: resultSet.getString(resultSet.getColumnIndex('tool_name')),
          toolArguments: resultSet.getString(resultSet.getColumnIndex('tool_arguments')),
          toolResult: resultSet.getString(resultSet.getColumnIndex('tool_result')),
          status: resultSet.getString(resultSet.getColumnIndex('status')),
          createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
          completedAt: resultSet.getLong(resultSet.getColumnIndex('completed_at'))
        }
        events.push(eventData)
        count = count + 1
      }
      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to get recent tool events: ${JSON.stringify(error)}`)
    }

    return events
  }

  // 删除消息相关的工具事件
  async deleteToolEvents(messageId: string): Promise<void> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return
    }

    const predicates = new relationalStore.RdbPredicates(TableNames.TOOL_EVENTS)
    predicates.equalTo('message_id', messageId)

    try {
      await this.rdbStore.delete(predicates)
      console.info('DatabaseService', `Tool events deleted for message: ${messageId}`)
    } catch (error) {
      console.error('DatabaseService', `Failed to delete tool events: ${JSON.stringify(error)}`)
    }
  }
}

// 工具事件数据接口
export interface ToolEventData {
  id: string
  sessionId: string
  messageId: string
  toolCallId: string
  toolName: string
  toolArguments: string
  toolResult: string
  status: string
  createdAt: number
  completedAt: number
}

// 服务商配置接口
export interface ProviderConfig {
  id: string
  name: string
  type: string
  apiStyle: string
  apiKey: string
  baseUrl: string
  isEnabled: boolean
  modelsJson: string
  iconSymbol: string
  sortOrder: number
  isPreset: boolean   // 是否为预设供应商
  iconPath: string    // 图标文件路径
  apiPath: string     // API 路径（可选）
  iconType: string    // 图标类型
  textIcon: string    // 文字图标内容
  textIconBgColor: string  // 文字图标背景色
  customImagePath: string  // 自定义图片路径
}

// 导出单例实例获取方法
export function getDatabaseService(): DatabaseService {
  return DatabaseService.getInstance()
}
