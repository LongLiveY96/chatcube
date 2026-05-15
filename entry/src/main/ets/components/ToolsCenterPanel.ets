import {
  ToolApprovalPolicy,
  SearchEngine,
  normalizeToolApprovalPolicy
} from '../models/ChatModels'
import { McpAuthType, McpServerConfig, McpToolEntry } from '../models/McpModels'
import { ToolRegistry } from '../services/ToolRegistry'
import { McpService } from '../services/McpService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { registerBuiltinTools } from '../config/BuiltinTools'
import { getPreferencesService, PreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { HdsListItemCard } from '@kit.UIDesignKit'
import { getAppUiState } from '../state/AppUiState'
import { formatLocalizedCount, pickLocalizedText } from '../utils/LocalizedTextUtils'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getSearchToolIds, isSearchToolId } from '../utils/SearchToolIdentityUtils'
import {
  buildCustomHeadersJson,
  isSensitiveCustomHeaderName,
  normalizeCustomHeaderName,
  parseCustomHeaderEntries,
  validateCustomHeaderEntries
} from '../utils/CustomHeaderUtils'
import {
  getSearchEngineRegistry,
  registerAllSearchEngines,
  SearchEngineDescriptor
} from '../services/search/Index'
import {
  asSearchEngine,
  parseSearchEngineIdListJson,
  stringifySearchEngineIdList
} from '../utils/SearchEnginePreferenceUtils'

@ObservedV2
class McpHeaderEntry {
  @Trace id: string = ''
  @Trace name: string = ''
  @Trace value: string = ''

  constructor(id: string = '', name: string = '', value: string = '') {
    this.id = id
    this.name = name
    this.value = value
  }
}

@ComponentV2
export struct ToolsCenterPanel {
  @Param showHeader: boolean = true
  @Param contentBottomPadding: number = 24
  @Param contentTopPadding: number = 0
  @Param contentScroller: Scroller = new Scroller()
  @Local searchServiceEnabled: boolean = false
  @Local searchEngine: SearchEngine = SearchEngine.BING
  @Local searchEnabledEngineIds: string[] = []
  @Local searchBraveApiKey: string = ''
  @Local searchTavilyApiKey: string = ''
  @Local searchTavilyBaseUrl: string = 'https://api.tavily.com'
  @Local searchExaApiKey: string = ''
  @Local searchExaBaseUrl: string = 'https://api.exa.ai'
  @Local searchMetasoApiKey: string = ''
  @Local searchFirecrawlApiKey: string = ''
  @Local searchFirecrawlBaseUrl: string = 'https://api.firecrawl.dev'
  @Local isLoading: boolean = false
  @Local isRefreshingMcpServers: boolean = false
  @Local showSearchConfigSheet: boolean = false
  @Local mcpServers: McpServerConfig[] = []
  @Local showMcpServerSheet: boolean = false
  @Local editingMcpServerId: string = ''
  @Local mcpFormName: string = ''
  @Local mcpFormBaseUrl: string = ''
  @Local mcpFormAuthToken: string = ''
  @Local mcpFormCustomHeadersJson: string = ''
  @Local mcpFormCustomHeaderEntries: McpHeaderEntry[] = []
  @Local showMcpCustomHeadersEditor: boolean = false
  @Local mcpFormEnabled: boolean = true
  @Local mcpFormAuthType: string = McpAuthType.NONE
  @Local mcpAuthTypeSelectedIndex: number = 0
  @Local mcpFormToolApprovalPolicy: string = ToolApprovalPolicy.UNCONFIGURED
  @Local mcpToolApprovalPolicySelectedIndex: number = 0
  @Local isSavingMcpServer: boolean = false
  @Local showMcpServerDetailSheet: boolean = false
  @Local detailServerId: string = ''

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get sensitiveBadgeColor(): string {
    return '#D9485F'
  }

  private get sensitiveBadgeBackgroundColor(): string {
    return withColorAlpha(this.sensitiveBadgeColor, this.isDarkMode ? '28' : '12')
  }

  private get secondaryTextHex(): string {
    return this.isDarkMode ? '#999999' : '#666666'
  }

  private get backgroundHex(): string {
    return getAppUiState().themeBackground
  }

  private get dividerHex(): string {
    return getAppUiState().themeDivider
  }

  private toolRegistry: ToolRegistry = ServiceRegistry.toolRegistry()
  private mcpService: McpService = ServiceRegistry.mcp()
  private preferencesService: PreferencesService = getPreferencesService()
  private get searchEngineDescriptors(): SearchEngineDescriptor[] {
    registerAllSearchEngines()
    return getSearchEngineRegistry().getAll()
  }
  private readonly mcpAuthTypeOptions: Array<SelectOption> = [
    { value: 'None' },
    { value: 'Bearer' }
  ]
  private readonly mcpToolApprovalPolicyOptions: Array<SelectOption> = [
    { value: pickLocalizedText('未配置', 'Not configured') },
    { value: pickLocalizedText('始终允许', 'Always allow') }
  ]
  private readonly reservedMcpHeaderNames: string[] = [
    'content-type',
    'accept',
    'mcp-protocol-version',
    'mcp-session-id',
    'authorization'
  ]

  private showToolsSnack(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  aboutToAppear(): void {
    this.loadData()
  }

  private async loadData(): Promise<void> {
    this.isLoading = true

    registerBuiltinTools()
    try {
      await this.loadToolEnabledStates()
      await this.loadSearchSettings()
      await this.loadMcpServers()
    } finally {
      this.isLoading = false
    }
    this.refreshMcpServersInBackground(false)
  }

  private async loadMcpServers(): Promise<void> {
    const configs = await this.mcpService.loadServerConfigs()
    this.applyMcpServerConfigsToLocal(configs)
  }

  private syncMcpServerProperties(target: McpServerConfig, source: McpServerConfig): void {
    target.name = source.name
    target.baseUrl = source.baseUrl
    target.enabled = source.enabled
    target.authType = source.authType
    target.authToken = source.authToken
    target.customHeadersJson = source.customHeadersJson
    target.toolApprovalPolicy = normalizeToolApprovalPolicy(source.toolApprovalPolicy)
    target.tools = source.tools
  }

  private applyMcpServerConfigsToLocal(configs: McpServerConfig[]): void {
    if (this.mcpServers.length === 0) {
      this.mcpServers = [...configs]
      return
    }

    const configMap = new Map<string, McpServerConfig>()
    for (let i = 0; i < configs.length; i++) {
      configMap.set(configs[i].id, configs[i])
    }

    for (let i = 0; i < this.mcpServers.length; i++) {
      const existing = this.mcpServers[i]
      const updated = configMap.get(existing.id)
      if (updated !== undefined && updated !== existing) {
        this.syncMcpServerProperties(existing, updated)
      }
    }

    let needsRebuild = configs.length !== this.mcpServers.length
    if (!needsRebuild) {
      for (let i = 0; i < configs.length; i++) {
        if (configs[i].id !== this.mcpServers[i].id) {
          needsRebuild = true
          break
        }
      }
    }

    if (needsRebuild) {
      this.mcpServers = [...configs]
      return
    }

    this.mcpServers = [...this.mcpServers]
  }

  private findLocalMcpServerById(serverId: string): McpServerConfig | null {
    for (let i = 0; i < this.mcpServers.length; i++) {
      if (this.mcpServers[i].id === serverId) {
        return this.mcpServers[i]
      }
    }
    return null
  }

  private updateLocalMcpServerEnabledState(serverId: string, enabled: boolean): void {
    const server = this.findLocalMcpServerById(serverId)
    if (server === null) {
      return
    }
    server.enabled = enabled
    this.mcpServers = [...this.mcpServers]
  }

  private refreshMcpServersInBackground(showErrorSnack: boolean): void {
    if (this.isRefreshingMcpServers) {
      return
    }
    this.isRefreshingMcpServers = true
    this.performRefreshAllMcpServers(showErrorSnack).finally(() => {
      this.isRefreshingMcpServers = false
    })
  }

  private async performRefreshAllMcpServers(showErrorSnack: boolean): Promise<void> {
    try {
      await this.mcpService.refreshAllServers()
      await this.loadMcpServers()
    } catch (error) {
      console.warn('ToolsCenterPanel', `MCP refresh failed during load: ${JSON.stringify(error)}`)
      if (showErrorSnack) {
        this.showToolsSnack(this.getMcpRefreshFailedMessage(error), 2500, SnackBarTone.ERROR)
      }
    }
  }

  private getEnabledMcpServerCount(): number {
    let count = 0
    for (let i = 0; i < this.mcpServers.length; i++) {
      if (this.mcpServers[i].enabled) {
        count += 1
      }
    }
    return count
  }

  private getDiscoveredMcpToolCount(): number {
    let total = 0
    for (let i = 0; i < this.mcpServers.length; i++) {
      total += this.mcpServers[i].tools.length
    }
    return total
  }

  private parseSearchEngine(raw: string): SearchEngine {
    return asSearchEngine(raw)
  }

  private getSearchEngineLabel(engine: SearchEngine): string {
    return getSearchEngineRegistry().getLabel(engine)
  }

  private setCurrentSearchEngine(engine: SearchEngine): void {
    // 该方法只更新"当前正在编辑的引擎"标识(打开配置 sheet 时定位 + ensureDefaultSearchEngineAvailable
    // 内禁用引擎后的 fallback)。SEARCH_ENGINE 偏好仅由聊天页 chip 切换 / fallback 路径直接写入,
    // 设置页不再隐式改默认。
    this.searchEngine = engine
  }

  private isSearchEngineEnabled(engineId: string): boolean {
    return this.searchEnabledEngineIds.includes(engineId)
  }

  private isSearchEngineConfiguredLocal(engineId: SearchEngine): boolean {
    const desc = getSearchEngineRegistry().getById(engineId)
    if (desc === undefined) {
      return false
    }
    let hasPasswordField = false
    for (let i = 0; i < desc.configFields.length; i++) {
      const field = desc.configFields[i]
      if (field.isPassword) {
        hasPasswordField = true
        if (this.getConfigFieldValue(field.key).trim() !== '') {
          return true
        }
      }
    }
    return !hasPasswordField
  }

  private getAvailableEnabledSearchEngineCount(): number {
    let count = 0
    const engines = this.searchEngineDescriptors
    for (let i = 0; i < engines.length; i++) {
      if (this.isSearchEngineEnabled(engines[i].id) && this.isSearchEngineConfiguredLocal(engines[i].id)) {
        count += 1
      }
    }
    return count
  }

  private resolveSearchEnabledEngineIds(raw: string, storedEngine: SearchEngine): string[] {
    if (raw.trim() !== '') {
      return parseSearchEngineIdListJson(raw)
    }

    const defaults: string[] = [SearchEngine.BING]
    const engines = this.searchEngineDescriptors
    for (let i = 0; i < engines.length; i++) {
      const engineId = engines[i].id
      if (engineId !== SearchEngine.BING && this.isSearchEngineConfiguredLocal(engineId) &&
        !defaults.includes(engineId)) {
        defaults.push(engineId)
      }
    }
    if (storedEngine !== SearchEngine.BING && this.isSearchEngineConfiguredLocal(storedEngine) &&
      !defaults.includes(storedEngine)) {
      defaults.push(storedEngine)
    }
    return defaults
  }

  private findFirstAvailableSearchEngine(): SearchEngine | null {
    const engines = this.searchEngineDescriptors
    for (let i = 0; i < engines.length; i++) {
      if (this.isSearchEngineEnabled(engines[i].id) && this.isSearchEngineConfiguredLocal(engines[i].id)) {
        return engines[i].id
      }
    }
    return null
  }

  private async persistEnabledSearchEngineIds(): Promise<void> {
    this.searchEnabledEngineIds = parseSearchEngineIdListJson(stringifySearchEngineIdList(this.searchEnabledEngineIds))
    await this.preferencesService.setString(
      PreferenceKeys.SEARCH_ENABLED_ENGINE_IDS_JSON,
      stringifySearchEngineIdList(this.searchEnabledEngineIds)
    )
  }

  private async ensureDefaultSearchEngineAvailable(): Promise<void> {
    if (this.isSearchEngineEnabled(this.searchEngine) && this.isSearchEngineConfiguredLocal(this.searchEngine)) {
      return
    }

    const fallback = this.findFirstAvailableSearchEngine()
    if (fallback === null) {
      return
    }

    this.setCurrentSearchEngine(fallback)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_ENGINE, fallback)
  }

  private async ensureAtLeastOneSearchEngineEnabled(): Promise<void> {
    if (this.getAvailableEnabledSearchEngineCount() > 0) {
      return
    }
    if (!this.isSearchEngineEnabled(SearchEngine.BING)) {
      this.searchEnabledEngineIds = [...this.searchEnabledEngineIds, SearchEngine.BING]
      await this.persistEnabledSearchEngineIds()
    }
    await this.ensureDefaultSearchEngineAvailable()
  }

  private handleSearchEngineEnabledChanged(engineId: SearchEngine, enabled: boolean): void {
    this.updateSearchEngineEnabledState(engineId, enabled).catch((error: Object) => {
      console.error('ToolsCenterPanel', `Failed to update search engine enabled state: ${JSON.stringify(error)}`)
      this.showToolsSnack(pickLocalizedText('搜索服务状态保存失败', 'Failed to save search service state'),
        2000, SnackBarTone.ERROR)
    })
  }

  private async updateSearchEngineEnabledState(engineId: SearchEngine, enabled: boolean): Promise<void> {
    if (enabled && !this.isSearchEngineConfiguredLocal(engineId)) {
      this.showToolsSnack(pickLocalizedText('请先完成该搜索服务配置', 'Configure this search service first'),
        2000, SnackBarTone.ERROR)
      this.openSearchEngineConfig(engineId)
      return
    }

    const next = [...this.searchEnabledEngineIds]
    const index = next.indexOf(engineId)
    if (enabled && index < 0) {
      next.push(engineId)
    }
    if (!enabled && index >= 0) {
      next.splice(index, 1)
    }
    this.searchEnabledEngineIds = next
    await this.persistEnabledSearchEngineIds()
    await this.ensureDefaultSearchEngineAvailable()
  }

  private openSearchEngineConfig(engineId: SearchEngine): void {
    this.setCurrentSearchEngine(engineId)
    this.syncOriginalSearchSettings()
    this.showSearchConfigSheet = true
  }

  private applySearchServiceEnabledState(enabled: boolean): void {
    this.searchServiceEnabled = enabled
    const searchToolIds = getSearchToolIds()
    for (let i = 0; i < searchToolIds.length; i++) {
      const registeredTool = this.toolRegistry.getTool(searchToolIds[i])
      if (registeredTool !== undefined) {
        registeredTool.config.enabled = enabled
      }
    }
  }

  private async loadToolEnabledStates(): Promise<void> {
    const webSearchEnabled = await this.preferencesService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    this.applySearchServiceEnabledState(webSearchEnabled)
  }

  private handleSearchServiceEnabledChanged(enabled: boolean): void {
    this.applySearchServiceEnabledState(enabled)
    this.preferencesService.setBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, enabled)
    if (!enabled) {
      this.preferencesService.setBoolean(PreferenceKeys.SEARCH_CONVERSATION_ENABLED, false)
      return
    }
    this.ensureAtLeastOneSearchEngineEnabled().catch((error: Object) => {
      console.error('ToolsCenterPanel', `Failed to prepare search engines: ${JSON.stringify(error)}`)
    })
  }

  private async loadSearchSettings(): Promise<void> {
    registerAllSearchEngines()
    const searchServiceEnabled = await this.preferencesService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    const engineRaw = await this.preferencesService.getString(PreferenceKeys.SEARCH_ENGINE, SearchEngine.BING)
    const enabledEngineIdsRaw = await this.preferencesService.getString(
      PreferenceKeys.SEARCH_ENABLED_ENGINE_IDS_JSON,
      ''
    )
    this.searchServiceEnabled = searchServiceEnabled
    this.searchEngine = this.parseSearchEngine(engineRaw)

    // 动态加载所有引擎的配置字段
    const allEngines = getSearchEngineRegistry().getAll()
    for (const engine of allEngines) {
      for (const field of engine.configFields) {
        const value = await this.preferencesService.getString(field.key, field.defaultValue)
        const normalized = field.isPassword ? value.trim() :
          this.normalizeSearchBaseUrl(value, field.defaultValue)
        this.setConfigFieldValue(field.key, normalized)
      }
    }

    this.searchEnabledEngineIds = this.resolveSearchEnabledEngineIds(enabledEngineIdsRaw, this.searchEngine)
    await this.persistEnabledSearchEngineIds()
    await this.ensureDefaultSearchEngineAvailable()
    this.syncOriginalSearchSettings()
  }

  private normalizeSearchBaseUrl(raw: string, fallback: string): string {
    const trimmed = raw.trim()
    if (trimmed === '') {
      return fallback
    }
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1)
    }
    return trimmed
  }

  private originalSearchConfigSnapshot: string = ''

  private buildSearchConfigSnapshot(): string {
    return JSON.stringify({
      engine: this.searchEngine,
      brave: this.searchBraveApiKey.trim(),
      tavily: this.searchTavilyApiKey.trim(),
      tavilyUrl: this.normalizeSearchBaseUrl(this.searchTavilyBaseUrl, 'https://api.tavily.com'),
      exa: this.searchExaApiKey.trim(),
      exaUrl: this.normalizeSearchBaseUrl(this.searchExaBaseUrl, 'https://api.exa.ai'),
      metaso: this.searchMetasoApiKey.trim(),
      firecrawl: this.searchFirecrawlApiKey.trim(),
      firecrawlUrl: this.normalizeSearchBaseUrl(this.searchFirecrawlBaseUrl, 'https://api.firecrawl.dev')
    })
  }

  private syncOriginalSearchSettings(): void {
    this.originalSearchConfigSnapshot = this.buildSearchConfigSnapshot()
  }

  private hasPendingSearchConfigChanges(): boolean {
    return this.buildSearchConfigSnapshot() !== this.originalSearchConfigSnapshot
  }

  private performCloseSearchConfigSheet(sheetDismiss?: SheetDismiss): void {
    if (sheetDismiss !== undefined) {
      sheetDismiss.dismiss()
      return
    }
    this.showSearchConfigSheet = false
  }

  private requestCloseSearchConfigSheet(sheetDismiss?: SheetDismiss): void {
    if (!this.hasPendingSearchConfigChanges()) {
      this.performCloseSearchConfigSheet(sheetDismiss)
      return
    }

    this.getUIContext().showAlertDialog({
      title: $r('app.string.search_discard_changes_title'),
      message: $r('app.string.search_discard_changes_message'),
      primaryButton: {
        value: $r('app.string.search_continue_editing'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.search_discard_changes'),
        fontColor: Color.Red,
        action: () => {
          this.performCloseSearchConfigSheet(sheetDismiss)
        }
      }
    })
  }

  private async handleSaveSearchSettings(): Promise<boolean> {
    const registry = getSearchEngineRegistry()
    const descriptor = registry.getById(this.searchEngine)

    // 验证当前引擎的必填字段
    if (descriptor !== undefined) {
      for (const field of descriptor.configFields) {
        const value = this.getConfigFieldValue(field.key)
        if (field.isPassword && value.trim() === '') {
          this.showToolsSnack(pickLocalizedText(
            `请选择 ${descriptor.label} 时先填写 API Key`,
            `Enter the API key before selecting ${descriptor.label}`
          ), 2000, SnackBarTone.ERROR)
          return false
        }
        if (!field.isPassword && field.defaultValue !== '') {
          const normalized = this.normalizeSearchBaseUrl(value, field.defaultValue)
          if (normalized !== field.defaultValue && !normalized.startsWith('http://') &&
            !normalized.startsWith('https://')) {
            this.showToolsSnack($r('app.string.search_base_url_invalid'), 2000, SnackBarTone.ERROR)
            return false
          }
        }
      }
    }

    // 保存引擎选择
    await this.preferencesService.setString(PreferenceKeys.SEARCH_ENGINE, this.searchEngine)

    // 保存所有引擎的配置字段
    const allEngines = registry.getAll()
    for (const engine of allEngines) {
      for (const field of engine.configFields) {
        const value = this.getConfigFieldValue(field.key)
        const normalized = field.isPassword ? value.trim() :
          this.normalizeSearchBaseUrl(value, field.defaultValue)
        await this.preferencesService.setString(field.key, normalized)
        this.setConfigFieldValue(field.key, normalized)
      }
    }

    if (!this.isSearchEngineEnabled(this.searchEngine)) {
      this.searchEnabledEngineIds = [...this.searchEnabledEngineIds, this.searchEngine]
      await this.persistEnabledSearchEngineIds()
    }
    this.syncOriginalSearchSettings()
    this.showToolsSnack($r('app.string.search_config_saved'), 2000, SnackBarTone.SUCCESS)
    return true
  }

  // 通过 preference key 获取对应的 UI 状态变量值
  private getConfigFieldValue(key: string): string {
    if (key === PreferenceKeys.SEARCH_BRAVE_API_KEY) return this.searchBraveApiKey
    if (key === PreferenceKeys.SEARCH_TAVILY_API_KEY) return this.searchTavilyApiKey
    if (key === PreferenceKeys.SEARCH_TAVILY_BASE_URL) return this.searchTavilyBaseUrl
    if (key === PreferenceKeys.SEARCH_EXA_API_KEY) return this.searchExaApiKey
    if (key === PreferenceKeys.SEARCH_EXA_BASE_URL) return this.searchExaBaseUrl
    if (key === PreferenceKeys.SEARCH_METASO_API_KEY) return this.searchMetasoApiKey
    if (key === PreferenceKeys.SEARCH_FIRECRAWL_API_KEY) return this.searchFirecrawlApiKey
    if (key === PreferenceKeys.SEARCH_FIRECRAWL_BASE_URL) return this.searchFirecrawlBaseUrl
    return ''
  }

  // 通过 preference key 设置对应的 UI 状态变量值
  private setConfigFieldValue(key: string, value: string): void {
    if (key === PreferenceKeys.SEARCH_BRAVE_API_KEY) this.searchBraveApiKey = value
    else if (key === PreferenceKeys.SEARCH_TAVILY_API_KEY) this.searchTavilyApiKey = value
    else if (key === PreferenceKeys.SEARCH_TAVILY_BASE_URL) this.searchTavilyBaseUrl = value
    else if (key === PreferenceKeys.SEARCH_EXA_API_KEY) this.searchExaApiKey = value
    else if (key === PreferenceKeys.SEARCH_EXA_BASE_URL) this.searchExaBaseUrl = value
    else if (key === PreferenceKeys.SEARCH_METASO_API_KEY) this.searchMetasoApiKey = value
    else if (key === PreferenceKeys.SEARCH_FIRECRAWL_API_KEY) this.searchFirecrawlApiKey = value
    else if (key === PreferenceKeys.SEARCH_FIRECRAWL_BASE_URL) this.searchFirecrawlBaseUrl = value
  }

  private handleSaveAndCloseSearchSettings(): void {
    this.handleSaveSearchSettings().then((saved: boolean) => {
      if (saved) {
        this.showSearchConfigSheet = false
      }
    })
  }

  private resetMcpServerForm(): void {
    this.editingMcpServerId = ''
    this.mcpFormName = ''
    this.mcpFormBaseUrl = ''
    this.mcpFormAuthToken = ''
    this.mcpFormCustomHeadersJson = ''
    this.mcpFormCustomHeaderEntries = []
    this.showMcpCustomHeadersEditor = false
    this.mcpFormEnabled = true
    this.mcpFormAuthType = McpAuthType.NONE
    this.mcpAuthTypeSelectedIndex = 0
    this.mcpFormToolApprovalPolicy = ToolApprovalPolicy.UNCONFIGURED
    this.mcpToolApprovalPolicySelectedIndex = 0
    this.isSavingMcpServer = false
  }

  private openCreateMcpServer(): void {
    this.resetMcpServerForm()
    this.showMcpServerSheet = true
  }

  private openEditMcpServer(server: McpServerConfig): void {
    this.editingMcpServerId = server.id
    this.mcpFormName = server.name
    this.mcpFormBaseUrl = server.baseUrl
    this.mcpFormAuthToken = server.authToken
    this.mcpFormCustomHeadersJson = server.customHeadersJson
    this.mcpFormCustomHeaderEntries = this.parseMcpHeaderEntries(server.customHeadersJson)
    this.showMcpCustomHeadersEditor = this.mcpFormCustomHeaderEntries.length > 0
    this.mcpFormEnabled = server.enabled
    this.mcpFormAuthType = server.authType
    this.mcpAuthTypeSelectedIndex = server.authType === McpAuthType.BEARER ? 1 : 0
    this.mcpFormToolApprovalPolicy = normalizeToolApprovalPolicy(server.toolApprovalPolicy)
    this.mcpToolApprovalPolicySelectedIndex = this.getMcpToolApprovalPolicyIndex(this.mcpFormToolApprovalPolicy)
    this.showMcpServerSheet = true
  }

  private handleMcpAuthTypeSelect(index: number): void {
    this.mcpAuthTypeSelectedIndex = index
    this.mcpFormAuthType = index === 1 ? McpAuthType.BEARER : McpAuthType.NONE
  }

  private handleMcpToolApprovalPolicySelect(index: number): void {
    this.mcpToolApprovalPolicySelectedIndex = index
    if (index === 1) {
      this.mcpFormToolApprovalPolicy = ToolApprovalPolicy.ALWAYS_ALLOW
      return
    }
    this.mcpFormToolApprovalPolicy = ToolApprovalPolicy.UNCONFIGURED
  }

  private getMcpToolApprovalPolicyIndex(policy: string): number {
    const normalized = normalizeToolApprovalPolicy(policy)
    if (normalized === ToolApprovalPolicy.ALWAYS_ALLOW) {
      return 1
    }
    return 0
  }

  private isEditingMcpServer(): boolean {
    return this.editingMcpServerId !== ''
  }

  private getMcpFormTitle(): string {
    return this.isEditingMcpServer()
      ? pickLocalizedText('编辑 MCP Server', 'Edit MCP Server')
      : pickLocalizedText('新增 MCP Server', 'Add MCP Server')
  }

  private getMcpFormModeTag(): string {
    return this.isEditingMcpServer()
      ? pickLocalizedText('编辑', 'Editing')
      : pickLocalizedText('新服务', 'New')
  }

  private getMcpFormHeroTitle(): string {
    const name = this.mcpFormName.trim()
    if (name !== '') {
      return name
    }
    return this.isEditingMcpServer()
      ? pickLocalizedText('未命名服务', 'Unnamed Server')
      : pickLocalizedText('新建 MCP Server', 'New MCP Server')
  }

  private getMcpFormHeroDescription(): string {
    if (this.isEditingMcpServer()) {
      return pickLocalizedText('管理连接、认证和请求头。', 'Manage connection, auth, and headers.')
    }
    return pickLocalizedText('添加一个新的 MCP 服务。', 'Add a new MCP service.')
  }

  private getMcpFormTargetHint(): string {
    const baseUrl = this.normalizeMcpBaseUrl(this.mcpFormBaseUrl)
    if (baseUrl !== '') {
      return baseUrl
    }
    return ''
  }

  private getMcpFormAuthLabel(): string {
    return this.mcpFormAuthType === McpAuthType.BEARER ? 'Bearer' : pickLocalizedText('无认证', 'No auth')
  }

  private getMcpFormEnableLabel(): string {
    return this.mcpFormEnabled ? pickLocalizedText('自动启用', 'Auto enable') : pickLocalizedText('暂不启用', 'Save disabled')
  }

  private getMcpToolApprovalPolicyLabel(policy: string): string {
    const normalized = normalizeToolApprovalPolicy(policy)
    if (normalized === ToolApprovalPolicy.ALWAYS_ALLOW) {
      return pickLocalizedText('始终允许', 'Always allow')
    }
    return pickLocalizedText('未配置', 'Not configured')
  }

  private getMcpToolApprovalPolicyDescription(policy: string): string {
    const normalized = normalizeToolApprovalPolicy(policy)
    if (normalized === ToolApprovalPolicy.ALWAYS_ALLOW) {
      return pickLocalizedText(
        '该服务的工具调用会直接执行，不再弹出确认。',
        'Tool calls from this server run directly without approval prompts.'
      )
    }
    return pickLocalizedText(
      '该服务的工具调用会在聊天中先询问；你也可以在确认时改成始终允许。',
      'Tool calls from this server ask in chat first; you can switch to always allow during approval.'
    )
  }

  private getServerCustomHeaderCount(server: McpServerConfig): number {
    return this.parseMcpHeaderEntries(server.customHeadersJson).length
  }

  private getMcpServerAuthLabel(server: McpServerConfig): string {
    return server.authType === McpAuthType.BEARER ? 'Bearer' : 'None'
  }

  private buildNewMcpServerId(): string {
    return `mcp_${Date.now()}`
  }

  private buildNewMcpHeaderEntryId(): string {
    return `mcp_header_${Date.now()}_${Math.floor(Math.random() * 100000)}`
  }

  private createMcpHeaderEntry(name: string = '', value: string = ''): McpHeaderEntry {
    return new McpHeaderEntry(this.buildNewMcpHeaderEntryId(), name, value)
  }

  private normalizeMcpHeaderName(name: string): string {
    return normalizeCustomHeaderName(name)
  }

  private isReservedMcpHeaderName(name: string): boolean {
    return this.reservedMcpHeaderNames.includes(this.normalizeMcpHeaderName(name))
  }

  private isSensitiveMcpHeaderName(name: string): boolean {
    return isSensitiveCustomHeaderName(name)
  }

  private parseMcpHeaderEntries(raw: string): McpHeaderEntry[] {
    const parsedEntries = parseCustomHeaderEntries(raw)
    const entries: McpHeaderEntry[] = []
    for (let i = 0; i < parsedEntries.length; i++) {
      entries.push(this.createMcpHeaderEntry(parsedEntries[i].name, parsedEntries[i].value))
    }
    return entries
  }

  private syncMcpCustomHeadersJsonFromEntries(): void {
    this.mcpFormCustomHeadersJson = this.buildMcpCustomHeadersJson()
  }

  private buildMcpCustomHeadersJson(): string {
    return buildCustomHeadersJson(this.mcpFormCustomHeaderEntries)
  }

  private validateMcpHeaderEntries(): string {
    return validateCustomHeaderEntries(this.mcpFormCustomHeaderEntries, this.reservedMcpHeaderNames, {
      emptyEntryMessage: pickLocalizedText(
        '自定义请求头的名称和值都不能为空',
        'Custom header name and value are both required'
      ),
      reservedHeaderMessage: (name: string): string => pickLocalizedText(
        `请求头 ${name} 由系统管理，请勿手动填写`,
        `Header ${name} is managed by the system and should not be set manually`
      ),
      duplicateHeaderMessage: (name: string): string => pickLocalizedText(
        `请求头 ${name} 重复，请保留一项`,
        `Header ${name} is duplicated; keep only one entry`
      )
    })
  }

  private getMcpRefreshFailedMessage(error: Object): string {
    return pickLocalizedText(`MCP 刷新失败: ${error}`, `MCP refresh failed: ${error}`)
  }

  private getDuplicateMcpServerMessage(serverName: string): string {
    return pickLocalizedText(
      `相同的 MCP 配置已存在：${serverName}`,
      `An identical MCP configuration already exists: ${serverName}`
    )
  }

  private getSavedMcpServerMessage(): string {
    return pickLocalizedText('MCP Server 已保存', 'MCP server saved')
  }

  private getSavedMcpServerRefreshFailedMessage(error: Object): string {
    return pickLocalizedText(
      `MCP Server 已保存，但刷新失败: ${error}`,
      `MCP server saved, but refresh failed: ${error}`
    )
  }

  private getSavedMcpServerSyncFailedMessage(error: Object): string {
    return pickLocalizedText(
      `MCP Server 已保存，但同步失败: ${error}`,
      `MCP server saved, but sync failed: ${error}`
    )
  }

  private getSaveMcpServerFailedMessage(error: Object): string {
    return pickLocalizedText(`保存 MCP Server 失败: ${error}`, `Failed to save MCP server: ${error}`)
  }

  private getMcpServerConnectedCountText(): string {
    return formatLocalizedCount(this.mcpServers.length, '个服务', 'connected service', 'connected services')
  }

  private addMcpHeaderEntry(): void {
    this.showMcpCustomHeadersEditor = true
    this.mcpFormCustomHeaderEntries = [...this.mcpFormCustomHeaderEntries, this.createMcpHeaderEntry()]
    this.syncMcpCustomHeadersJsonFromEntries()
  }

  private removeMcpHeaderEntry(entryId: string): void {
    const nextEntries: McpHeaderEntry[] = []
    for (let i = 0; i < this.mcpFormCustomHeaderEntries.length; i++) {
      if (this.mcpFormCustomHeaderEntries[i].id !== entryId) {
        nextEntries.push(this.mcpFormCustomHeaderEntries[i])
      }
    }
    this.mcpFormCustomHeaderEntries = nextEntries
    if (this.mcpFormCustomHeaderEntries.length === 0) {
      this.showMcpCustomHeadersEditor = false
    }
    this.syncMcpCustomHeadersJsonFromEntries()
  }

  private updateMcpHeaderEntryName(entryId: string, value: string): void {
    for (let i = 0; i < this.mcpFormCustomHeaderEntries.length; i++) {
      if (this.mcpFormCustomHeaderEntries[i].id === entryId) {
        this.mcpFormCustomHeaderEntries[i].name = value
        break
      }
    }
    this.mcpFormCustomHeaderEntries = [...this.mcpFormCustomHeaderEntries]
    this.syncMcpCustomHeadersJsonFromEntries()
  }

  private updateMcpHeaderEntryValue(entryId: string, value: string): void {
    for (let i = 0; i < this.mcpFormCustomHeaderEntries.length; i++) {
      if (this.mcpFormCustomHeaderEntries[i].id === entryId) {
        this.mcpFormCustomHeaderEntries[i].value = value
        break
      }
    }
    this.mcpFormCustomHeaderEntries = [...this.mcpFormCustomHeaderEntries]
    this.syncMcpCustomHeadersJsonFromEntries()
  }

  private normalizeMcpBaseUrl(raw: string): string {
    const trimmed = raw.trim()
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1)
    }
    return trimmed
  }

  private buildMcpServerSignature(
    baseUrl: string,
    authType: string,
    authToken: string,
    customHeadersJson: string
  ): string {
    return JSON.stringify({
      baseUrl: this.normalizeMcpBaseUrl(baseUrl),
      authType: authType,
      authToken: authToken.trim(),
      customHeadersJson: customHeadersJson.trim()
    })
  }

  private findDuplicateMcpServer(
    configs: McpServerConfig[],
    baseUrl: string,
    authType: string,
    authToken: string,
    customHeadersJson: string,
    ignoreServerId: string
  ): McpServerConfig | null {
    const targetSignature = this.buildMcpServerSignature(baseUrl, authType, authToken, customHeadersJson)
    for (let i = 0; i < configs.length; i++) {
      if (configs[i].id === ignoreServerId) {
        continue
      }
      const configSignature = this.buildMcpServerSignature(
        configs[i].baseUrl,
        configs[i].authType,
        configs[i].authToken,
        configs[i].customHeadersJson
      )
      if (configSignature === targetSignature) {
        return configs[i]
      }
    }
    return null
  }

  private async handleSaveMcpServer(): Promise<void> {
    if (this.isSavingMcpServer) {
      return
    }
    const name = this.mcpFormName.trim()
    const baseUrl = this.normalizeMcpBaseUrl(this.mcpFormBaseUrl)
    const customHeadersError = this.validateMcpHeaderEntries()
    if (name === '') {
      this.showToolsSnack(pickLocalizedText('MCP Server 名称不能为空', 'MCP server name is required'),
        2000, SnackBarTone.ERROR)
      return
    }
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      this.showToolsSnack(
        pickLocalizedText('MCP Server 地址必须是 http/https', 'MCP server URL must use http or https'),
        2000,
        SnackBarTone.ERROR
      )
      return
    }
    if (customHeadersError !== '') {
      this.showToolsSnack(customHeadersError, 2500, SnackBarTone.ERROR)
      return
    }
    const customHeadersJson = this.buildMcpCustomHeadersJson()
    this.isSavingMcpServer = true
    let configSaved = false
    try {
      const configs = await this.mcpService.loadServerConfigs()
      const duplicateServer = this.findDuplicateMcpServer(
        configs,
        baseUrl,
        this.mcpFormAuthType,
        this.mcpFormAuthToken,
        customHeadersJson,
        this.editingMcpServerId
      )
      if (duplicateServer !== null) {
        const duplicateName = duplicateServer.name.trim() !== ''
          ? duplicateServer.name.trim()
          : pickLocalizedText('未命名服务', 'Unnamed Server')
        this.showToolsSnack(this.getDuplicateMcpServerMessage(duplicateName), 2500, SnackBarTone.ERROR)
        return
      }

      let targetServer: McpServerConfig | null = null
      for (let i = 0; i < configs.length; i++) {
        if (configs[i].id === this.editingMcpServerId) {
          targetServer = configs[i]
          break
        }
      }
      if (targetServer === null) {
        targetServer = new McpServerConfig(this.buildNewMcpServerId())
        configs.push(targetServer)
      }

      targetServer.name = name
      targetServer.baseUrl = baseUrl
      targetServer.enabled = this.mcpFormEnabled
      targetServer.authType = this.mcpFormAuthType
      targetServer.authToken = this.mcpFormAuthToken.trim()
      targetServer.customHeadersJson = customHeadersJson
      targetServer.toolApprovalPolicy = normalizeToolApprovalPolicy(this.mcpFormToolApprovalPolicy)
      this.mcpFormBaseUrl = baseUrl
      this.mcpFormAuthToken = targetServer.authToken
      this.mcpFormCustomHeadersJson = customHeadersJson

      await this.mcpService.saveServerConfigs(configs)
      configSaved = true
      this.applyMcpServerConfigsToLocal(configs)
      this.showMcpServerSheet = false

      if (targetServer.enabled) {
        try {
          await this.mcpService.refreshServer(targetServer.id, configs)
          await this.loadMcpServers()
          this.showToolsSnack(this.getSavedMcpServerMessage(), 2000, SnackBarTone.SUCCESS)
        } catch (error) {
          await this.loadMcpServers()
          this.showToolsSnack(this.getSavedMcpServerRefreshFailedMessage(error), 3000, SnackBarTone.ERROR)
        }
      } else {
        await this.mcpService.refreshAllServers()
        await this.loadMcpServers()
        this.showToolsSnack(this.getSavedMcpServerMessage(), 2000, SnackBarTone.SUCCESS)
      }
    } catch (error) {
      console.error('ToolsCenterPanel', `Failed to save MCP server: ${JSON.stringify(error)}`)
      if (configSaved) {
        this.showToolsSnack(this.getSavedMcpServerSyncFailedMessage(error), 3000, SnackBarTone.ERROR)
      } else {
        this.showToolsSnack(this.getSaveMcpServerFailedMessage(error), 3000, SnackBarTone.ERROR)
      }
    } finally {
      this.isSavingMcpServer = false
    }
  }

  private handleDeleteMcpServer(serverId: string): void {
    this.getUIContext().showAlertDialog({
      title: pickLocalizedText('删除 MCP Server', 'Delete MCP Server'),
      message: pickLocalizedText(
        '删除后会同时卸载该 Server 发现的所有工具。',
        'Deleting it also removes every tool discovered from this server.'
      ),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: Color.Red,
        action: () => {
          this.deleteMcpServer(serverId)
        }
      }
    })
  }

  private deleteMcpServer(serverId: string): void {
    this.performDeleteMcpServer(serverId).catch((error: Object) => {
      console.error('ToolsCenterPanel', `Failed to delete MCP server: ${JSON.stringify(error)}`)
      this.showToolsSnack(pickLocalizedText('删除 MCP Server 失败', 'Failed to delete MCP server'),
        2000, SnackBarTone.ERROR)
    })
  }

  private async performDeleteMcpServer(serverId: string): Promise<void> {
    const configs = await this.mcpService.loadServerConfigs()
    const nextConfigs: McpServerConfig[] = []
    for (let i = 0; i < configs.length; i++) {
      if (configs[i].id !== serverId) {
        nextConfigs.push(configs[i])
      }
    }
    await this.mcpService.saveServerConfigs(nextConfigs)
    this.applyMcpServerConfigsToLocal(nextConfigs)
    await this.mcpService.terminateServerSession(serverId)
    await this.mcpService.refreshAllServers()
    await this.loadMcpServers()
    this.showToolsSnack(pickLocalizedText('MCP Server 已删除', 'MCP server deleted'), 2000, SnackBarTone.SUCCESS)
  }

  private handleMcpServerEnabledChanged(serverId: string, enabled: boolean): void {
    this.updateMcpServerEnabled(serverId, enabled).catch((error: Object) => {
      console.error('ToolsCenterPanel', `Failed to update MCP server enabled state: ${JSON.stringify(error)}`)
      this.showToolsSnack(pickLocalizedText('更新 MCP Server 状态失败', 'Failed to update MCP server state'),
        2000, SnackBarTone.ERROR)
    })
  }

  private async updateMcpServerEnabled(serverId: string, enabled: boolean): Promise<void> {
    const localServer = this.findLocalMcpServerById(serverId)
    const previousEnabled = localServer !== null ? localServer.enabled : !enabled
    this.updateLocalMcpServerEnabledState(serverId, enabled)
    const configs = await this.mcpService.loadServerConfigs()
    for (let i = 0; i < configs.length; i++) {
      if (configs[i].id === serverId) {
        configs[i].enabled = enabled
        break
      }
    }
    try {
      await this.mcpService.saveServerConfigs(configs)
    } catch (error) {
      this.updateLocalMcpServerEnabledState(serverId, previousEnabled)
      throw new Error(`${error}`)
    }
    this.applyMcpServerConfigsToLocal(configs)
    try {
      await this.mcpService.refreshAllServers()
    } finally {
      await this.loadMcpServers()
    }
  }

  private refreshMcpServer(serverId: string): void {
    this.performRefreshMcpServer(serverId).catch((error: Object) => {
      console.error('ToolsCenterPanel', `Failed to refresh MCP server: ${JSON.stringify(error)}`)
      this.showToolsSnack(this.getMcpRefreshFailedMessage(error), 2500, SnackBarTone.ERROR)
    })
  }

  private async performRefreshMcpServer(serverId: string): Promise<void> {
    await this.mcpService.refreshServer(serverId)
    await this.loadMcpServers()
    this.showToolsSnack(pickLocalizedText('MCP 工具已刷新', 'MCP tools refreshed'), 2000, SnackBarTone.SUCCESS)
  }

  private openMcpServerDetail(serverId: string): void {
    this.detailServerId = serverId
    this.showMcpServerDetailSheet = true
  }

  private getDetailServer(): McpServerConfig | null {
    return this.findLocalMcpServerById(this.detailServerId)
  }

  private handleToolEnabledChanged(serverId: string, toolName: string, enabled: boolean): void {
    const server = this.findLocalMcpServerById(serverId)
    if (server === null) {
      return
    }
    for (let i = 0; i < server.tools.length; i++) {
      if (server.tools[i].name === toolName) {
        server.tools[i].enabled = enabled
        break
      }
    }
    server.tools = [...server.tools]
    this.persistMcpServerTools(serverId)
  }

  private handleToolPolicyChanged(serverId: string, toolName: string, policy: string): void {
    const server = this.findLocalMcpServerById(serverId)
    if (server === null) {
      return
    }
    for (let i = 0; i < server.tools.length; i++) {
      if (server.tools[i].name === toolName) {
        server.tools[i].toolApprovalPolicy = normalizeToolApprovalPolicy(policy)
        break
      }
    }
    server.tools = [...server.tools]
    this.persistMcpServerTools(serverId)
  }

  private persistMcpServerTools(serverId: string): void {
    this.mcpService.loadServerConfigs().then((configs: McpServerConfig[]) => {
      const localServer = this.findLocalMcpServerById(serverId)
      if (localServer === null) {
        return
      }
      for (let i = 0; i < configs.length; i++) {
        if (configs[i].id === serverId) {
          configs[i].tools = localServer.tools
          break
        }
      }
      this.mcpService.saveServerConfigs(configs)
    })
  }

  @Builder
  McpServerDetailSheetBuilder() {
    Column() {
      if (this.getDetailServer() !== null) {
        this.McpServerDetailContentBuilder()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  McpServerDetailContentBuilder() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Circle)
        .stateEffect(false)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.showMcpServerDetailSheet = false
        })

        Text(this.getDetailServer()!.name)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button(pickLocalizedText('刷新', 'Refresh'))
          .height(32)
          .fontSize(12)
          .type(ButtonType.Capsule)
          .stateEffect(false)
          .backgroundColor(this.themePrimary)
          .fontColor(Color.White)
          .onClick(() => {
            this.refreshMcpServer(this.detailServerId)
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 8 }) {
            Text(this.getDetailServer()!.baseUrl)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Row({ space: 8 }) {
              Text(this.getDetailServer()!.enabled
                ? pickLocalizedText('已启用', 'Enabled') : pickLocalizedText('已停用', 'Disabled'))
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.getDetailServer()!.enabled ? this.themePrimary : $r('app.color.text_secondary'))
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(999)
                .backgroundColor(this.getDetailServer()!.enabled
                  ? withColorAlpha(this.themePrimary, this.isDarkMode ? '28' : '16')
                  : getAppUiState().themeBackground)

              Text(formatLocalizedCount(this.getDetailServer()!.tools.length, '个工具', 'tool', 'tools'))
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(999)
                .backgroundColor(getAppUiState().themeBackground)
            }
            .width('100%')
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor(getAppUiState().themeSurface)

          Column({ space: 4 }) {
            Text(pickLocalizedText('工具列表', 'Tools'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            if (this.getDetailServer()!.tools.length === 0) {
              Text(pickLocalizedText('暂未发现工具，请点击刷新。', 'No tools discovered yet. Tap Refresh.'))
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .margin({ top: 8 })
            }
          }
          .width('100%')

          ForEach(this.getDetailServer()!.tools, (tool: McpToolEntry) => {
            McpToolEntryCard({
              tool: tool,
              serverApprovalPolicy: this.getDetailServer()!.toolApprovalPolicy,
              onEnabledChange: (enabled: boolean) => {
                this.handleToolEnabledChanged(this.detailServerId, tool.name, enabled)
              },
              onPolicyChange: (policy: string) => {
                this.handleToolPolicyChanged(this.detailServerId, tool.name, policy)
              }
            })
          }, (tool: McpToolEntry) => tool.name)

          Row({ space: 8 }) {
            Button(pickLocalizedText('编辑', 'Edit'))
              .height(36)
              .fontSize(13)
              .type(ButtonType.Capsule)
              .stateEffect(false)
              .backgroundColor(getAppUiState().themeBackground)
              .border({ width: 1, color: this.dividerHex })
              .fontColor($r('app.color.text_primary'))
              .onClick(() => {
                this.showMcpServerDetailSheet = false
                this.openEditMcpServer(this.getDetailServer()!)
              })

            Blank()

            Button($r('app.string.delete'))
              .height(36)
              .fontSize(13)
              .type(ButtonType.Capsule)
              .stateEffect(false)
              .backgroundColor(getAppUiState().themeBackground)
              .border({ width: 1, color: this.isDarkMode ? '#6A3139' : '#F2CBD2' })
              .fontColor('#D9485F')
              .onClick(() => {
                this.showMcpServerDetailSheet = false
                this.handleDeleteMcpServer(this.detailServerId)
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SearchConfigSheetBuilder() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Circle)
        .stateEffect(false)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.requestCloseSearchConfigSheet()
        })

        Text($r('app.string.search_service_config'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontSize(18)
            .fontColor([Color.White])
        }
        .type(ButtonType.Circle)
        .stateEffect(false)
        .width(36)
        .height(36)
        .backgroundColor(this.themePrimary)
        .onClick(() => {
          this.handleSaveAndCloseSearchSettings()
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 16 }) {
          // 引擎信息卡片
          Column({ space: 10 }) {
            Text(pickLocalizedText('搜索引擎', 'Search Engine'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            Text(this.getSearchEngineLabel(this.searchEngine))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            // 能力标签
            Row({ space: 8 }) {
              Text(pickLocalizedText('搜索', 'Search'))
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(6)
                .backgroundColor(withColorAlpha(this.themePrimary, '18'))
                .border({ width: 1, color: withColorAlpha(this.themePrimary, '40') })

              if (this.currentEngineSupportsScrape()) {
                Text(pickLocalizedText('网页抓取', 'Scrape'))
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.themePrimary)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(6)
                  .backgroundColor(withColorAlpha(this.themePrimary, '18'))
                  .border({ width: 1, color: withColorAlpha(this.themePrimary, '40') })
              } else {
                Text(pickLocalizedText('网页抓取', 'Scrape'))
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_tertiary'))
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(6)
                  .backgroundColor(getAppUiState().themeBackground)
                  .border({ width: 1, color: $r('app.color.divider') })
              }
            }
            .width('100%')
            .margin({ top: 4 })
          }
          .width('100%')
          .padding(14)
          .borderRadius(14)
          .backgroundColor(getAppUiState().themeSurface)

          // 配置区域（仅需要 API Key 的引擎显示）
          if (this.currentEngineHasConfig()) {
            Column({ space: 10 }) {
              Text(pickLocalizedText('认证配置', 'Authentication'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')

              if (this.searchEngine === SearchEngine.BRAVE) {
                TextInput({ text: this.searchBraveApiKey, placeholder: 'Brave Search API Key' })
                  .onChange((value: string) => { this.searchBraveApiKey = value })
                  .type(InputType.Password)
                  .enableAutoFill(false)
                  .fontSize(13)
                  .width('100%')
                  .height(40)
                  .borderRadius(10)
                  .backgroundColor(getAppUiState().themeBackground)
                  .padding({ left: 12, right: 12 })
              }

              if (this.searchEngine === SearchEngine.TAVILY) {
                TextInput({ text: this.searchTavilyApiKey, placeholder: 'Tavily API Key' })
                  .onChange((value: string) => { this.searchTavilyApiKey = value })
                  .type(InputType.Password)
                  .enableAutoFill(false)
                  .fontSize(13)
                  .width('100%')
                  .height(40)
                  .borderRadius(10)
                  .backgroundColor(getAppUiState().themeBackground)
                  .padding({ left: 12, right: 12 })

                TextInput({ text: this.searchTavilyBaseUrl, placeholder: 'https://api.tavily.com' })
                  .onChange((value: string) => { this.searchTavilyBaseUrl = value })
                  .fontSize(13)
                  .width('100%')
                  .height(40)
                  .borderRadius(10)
                  .backgroundColor(getAppUiState().themeBackground)
                  .padding({ left: 12, right: 12 })
                  .margin({ top: 4 })
              }

              if (this.searchEngine === SearchEngine.EXA) {
                TextInput({ text: this.searchExaApiKey, placeholder: 'Exa API Key' })
                  .onChange((value: string) => { this.searchExaApiKey = value })
                  .type(InputType.Password)
                  .enableAutoFill(false)
                  .fontSize(13)
                  .width('100%')
                  .height(40)
                  .borderRadius(10)
                  .backgroundColor(getAppUiState().themeBackground)
                  .padding({ left: 12, right: 12 })

                TextInput({ text: this.searchExaBaseUrl, placeholder: 'https://api.exa.ai' })
                  .onChange((value: string) => { this.searchExaBaseUrl = value })
                  .fontSize(13)
                  .width('100%')
                  .height(40)
                  .borderRadius(10)
                  .backgroundColor(getAppUiState().themeBackground)
                  .padding({ left: 12, right: 12 })
                  .margin({ top: 4 })
              }

              if (this.searchEngine === SearchEngine.METASO) {
                TextInput({ text: this.searchMetasoApiKey, placeholder: 'Metaso API Key' })
                  .onChange((value: string) => { this.searchMetasoApiKey = value })
                  .type(InputType.Password)
                  .enableAutoFill(false)
                  .fontSize(13)
                  .width('100%')
                  .height(40)
                  .borderRadius(10)
                  .backgroundColor(getAppUiState().themeBackground)
                  .padding({ left: 12, right: 12 })
              }

              if (this.searchEngine === SearchEngine.FIRECRAWL) {
                TextInput({ text: this.searchFirecrawlApiKey, placeholder: 'Firecrawl API Key' })
                  .onChange((value: string) => { this.searchFirecrawlApiKey = value })
                  .type(InputType.Password)
                  .enableAutoFill(false)
                  .fontSize(13)
                  .width('100%')
                  .height(40)
                  .borderRadius(10)
                  .backgroundColor(getAppUiState().themeBackground)
                  .padding({ left: 12, right: 12 })

                TextInput({ text: this.searchFirecrawlBaseUrl, placeholder: 'https://api.firecrawl.dev' })
                  .onChange((value: string) => { this.searchFirecrawlBaseUrl = value })
                  .fontSize(13)
                  .width('100%')
                  .height(40)
                  .borderRadius(10)
                  .backgroundColor(getAppUiState().themeBackground)
                  .padding({ left: 12, right: 12 })
                  .margin({ top: 4 })
              }

              Text(pickLocalizedText(
                '支持自定义 Base URL 的引擎可接入代理或私有部署',
                'Engines with Base URL support can connect to proxies or private deployments'
              ))
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .margin({ top: 2 })
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .backgroundColor(getAppUiState().themeSurface)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  private currentEngineSupportsScrape(): boolean {
    const desc = getSearchEngineRegistry().getById(this.searchEngine)
    return desc !== undefined && desc.supportsScrape
  }

  private currentEngineHasConfig(): boolean {
    const desc = getSearchEngineRegistry().getById(this.searchEngine)
    return desc !== undefined && desc.configFields.length > 0
  }

  @Builder
  McpServerSheetBuilder() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Circle)
        .stateEffect(false)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.showMcpServerSheet = false
        })

        Text(this.getMcpFormTitle())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontSize(18)
            .fontColor([Color.White])
        }
        .type(ButtonType.Circle)
        .stateEffect(false)
        .width(36)
        .height(36)
        .backgroundColor(this.isSavingMcpServer ? withColorAlpha(this.themePrimary, '99') : this.themePrimary)
        .onClick(() => {
          this.handleSaveMcpServer()
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.cloud'))
                  .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                  .fontSize(22)
                  .fontColor([this.themePrimary])
              }
              .width(46)
              .height(46)
              .borderRadius(16)
              .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '26' : '12'))
              .justifyContent(FlexAlign.Center)

              Column({ space: 4 }) {
                Row({ space: 8 }) {
                  Text(this.getMcpFormHeroTitle())
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(this.getMcpFormModeTag())
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.themePrimary)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(999)
                    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '20' : '10'))
                }
                .width('100%')

                Text(this.getMcpFormHeroDescription())
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')

                if (this.getMcpFormTargetHint() !== '') {
                  Text(this.getMcpFormTargetHint())
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                    .width('100%')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')

            Row({ space: 8 }) {
              Text(this.getMcpFormAuthLabel())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(999)
                .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '20' : '10'))

              Text(this.getMcpFormEnableLabel())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(999)
                .backgroundColor(getAppUiState().themeBackground)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor(getAppUiState().themeSurface)
          .border({ width: 1, color: withColorAlpha(this.themePrimary, this.isDarkMode ? '20' : '10') })

          Column({ space: 12 }) {
            Column({ space: 4 }) {
              Text(pickLocalizedText('连接信息', 'Connection'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text(pickLocalizedText('填写名称和服务地址。', 'Set the display name and service URL.'))
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column({ space: 6 }) {
              Text(pickLocalizedText('显示名称', 'Display Name'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')

              TextInput({ text: this.mcpFormName, placeholder: pickLocalizedText(
                '例如 GitHub MCP / Timebook MCP',
                'e.g. GitHub MCP / Timebook MCP'
              ) })
                .onChange((value: string) => {
                  this.mcpFormName = value
                })
                .fontSize(14)
                .width('100%')
                .height(46)
                .borderRadius(14)
                .backgroundColor(getAppUiState().themeBackground)
                .border({ width: 1, color: $r('app.color.divider') })
                .padding({ left: 14, right: 14 })
            }
            .width('100%')

            Column({ space: 6 }) {
              Text(pickLocalizedText('服务地址', 'Service URL'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')

              TextInput({ text: this.mcpFormBaseUrl, placeholder: 'https://your-mcp.example.com/mcp' })
                .onChange((value: string) => {
                  this.mcpFormBaseUrl = value
                })
                .fontSize(14)
                .width('100%')
                .height(46)
                .borderRadius(14)
                .backgroundColor(getAppUiState().themeBackground)
                .border({ width: 1, color: $r('app.color.divider') })
                .padding({ left: 14, right: 14 })

              Text(pickLocalizedText('请输入完整的 HTTP/HTTPS 地址。', 'Enter the full HTTP or HTTPS URL.'))
                .fontSize(11)
                .lineHeight(16)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor(getAppUiState().themeSurface)

          Column({ space: 12 }) {
            Column({ space: 4 }) {
              Text(pickLocalizedText('认证策略', 'Authentication'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text(pickLocalizedText('按服务要求选择认证方式。', 'Choose the auth method required by the server.'))
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column({ space: 6 }) {
              Text(pickLocalizedText('认证类型', 'Auth Type'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')

              Select(this.mcpAuthTypeOptions)
                .selected(this.mcpAuthTypeSelectedIndex)
                .value(this.mcpAuthTypeSelectedIndex === 1 ? 'Bearer' : 'None')
                .onSelect((index: number, _value: string) => {
                  this.handleMcpAuthTypeSelect(index)
                })
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .height(46)
                .backgroundColor(getAppUiState().themeBackground)
                .borderRadius(14)
                .border({ width: 1, color: $r('app.color.divider') })
                .padding({ left: 10, right: 10 })
            }
            .width('100%')

            if (this.mcpFormAuthType === McpAuthType.BEARER) {
              Column({ space: 6 }) {
                Text('Bearer Token')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')

                TextInput({ text: this.mcpFormAuthToken, placeholder: pickLocalizedText(
                  '输入 Bearer Token',
                  'Enter bearer token'
                ) })
                  .onChange((value: string) => {
                    this.mcpFormAuthToken = value
                  })
                  .type(InputType.Password)
                  .enableAutoFill(false)
                  .fontSize(14)
                  .width('100%')
                  .height(46)
                  .borderRadius(14)
                  .backgroundColor(getAppUiState().themeBackground)
                  .border({ width: 1, color: $r('app.color.divider') })
                  .padding({ left: 14, right: 14 })

                Text(pickLocalizedText(
                  '系统会自动附加 Authorization。',
                  'Authorization is added automatically.'
                ))
                  .fontSize(11)
                  .lineHeight(16)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
              }
              .width('100%')
            } else {
              Row({ space: 10 }) {
                Column() {
                  SymbolGlyph($r('sys.symbol.checkmark_circle'))
                    .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                    .fontSize(16)
                    .fontColor([this.themePrimary])
                }
                .width(28)
                .height(28)
                .borderRadius(14)
                .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '20' : '10'))
                .justifyContent(FlexAlign.Center)

                Column({ space: 3 }) {
                  Text(pickLocalizedText('未设置额外认证', 'No extra authentication'))
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))

                  Text(pickLocalizedText(
                    '当前服务将直接使用基础连接信息。',
                    'This server uses the base connection settings directly.'
                  ))
                    .fontSize(11)
                    .lineHeight(16)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor(getAppUiState().themeBackground)
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor(getAppUiState().themeSurface)

          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Text(pickLocalizedText('自定义请求头', 'Custom Headers'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Toggle({ type: ToggleType.Switch, isOn: this.showMcpCustomHeadersEditor })
                .selectedColor(this.themePrimary)
                .onChange((isOn: boolean) => {
                  this.showMcpCustomHeadersEditor = isOn
                })
            }
            .width('100%')

            if (this.showMcpCustomHeadersEditor) {
              Row() {
                Button() {
                  Row({ space: 4 }) {
                    SymbolGlyph($r('sys.symbol.plus'))
                      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                      .fontSize(13)
                      .fontColor([Color.White])
                    Text(pickLocalizedText('新增请求头', 'Add header'))
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Color.White)
                  }
                }
                .height(32)
                .padding({ left: 14, right: 14 })
                .type(ButtonType.Capsule)
                .stateEffect(false)
                .backgroundColor(this.themePrimary)
                .onClick(() => {
                  this.addMcpHeaderEntry()
                })
                Blank()
              }
              .width('100%')
            }

            if (this.showMcpCustomHeadersEditor) {
              ForEach(this.mcpFormCustomHeaderEntries, (entry: McpHeaderEntry, index: number) => {
                Column({ space: 10 }) {
                  Row() {
                    Text(pickLocalizedText(`请求头 ${index + 1}`, `Header ${index + 1}`))
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)

                    if (this.isSensitiveMcpHeaderName(entry.name)) {
                      Text(pickLocalizedText('敏感', 'Sensitive'))
                        .fontSize(10)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.sensitiveBadgeColor)
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .borderRadius(999)
                        .backgroundColor(this.sensitiveBadgeBackgroundColor)
                        .margin({ right: 8 })
                    }

                    Button($r('app.string.delete'))
                      .height(28)
                      .fontSize(11)
                      .type(ButtonType.Capsule)
                      .stateEffect(false)
                      .backgroundColor(getAppUiState().themeSurface)
                      .border({ width: 1, color: this.isDarkMode ? '#6A3139' : '#F2CBD2' })
                      .fontColor('#D9485F')
                      .onClick(() => {
                        this.removeMcpHeaderEntry(entry.id)
                      })
                  }
                  .width('100%')

                  Column({ space: 6 }) {
                    Text(pickLocalizedText('名称', 'Name'))
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                      .width('100%')

                    TextInput({ text: entry.name, placeholder: pickLocalizedText(
                      '例如 timebook-mcp-token',
                      'e.g. timebook-mcp-token'
                    ) })
                      .onChange((value: string) => {
                        this.updateMcpHeaderEntryName(entry.id, value)
                      })
                      .fontSize(14)
                      .width('100%')
                      .height(44)
                      .borderRadius(14)
                      .backgroundColor(getAppUiState().themeBackground)
                      .border({ width: 1, color: $r('app.color.divider') })
                      .padding({ left: 14, right: 14 })
                  }
                  .width('100%')

                  Column({ space: 6 }) {
                    Text(pickLocalizedText('值', 'Value'))
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                      .width('100%')

                    if (this.isSensitiveMcpHeaderName(entry.name)) {
                      TextInput({ text: entry.value, placeholder: pickLocalizedText(
                        '输入 Header Value',
                        'Enter header value'
                      ) })
                        .onChange((value: string) => {
                          this.updateMcpHeaderEntryValue(entry.id, value)
                        })
                        .type(InputType.Password)
                        .enableAutoFill(false)
                        .fontSize(14)
                        .width('100%')
                        .height(44)
                        .borderRadius(14)
                        .backgroundColor(getAppUiState().themeBackground)
                        .border({ width: 1, color: $r('app.color.divider') })
                        .padding({ left: 14, right: 14 })
                    } else {
                      TextInput({ text: entry.value, placeholder: pickLocalizedText(
                        '输入 Header Value',
                        'Enter header value'
                      ) })
                        .onChange((value: string) => {
                          this.updateMcpHeaderEntryValue(entry.id, value)
                        })
                        .fontSize(14)
                        .width('100%')
                        .height(44)
                        .borderRadius(14)
                        .backgroundColor(getAppUiState().themeBackground)
                        .border({ width: 1, color: $r('app.color.divider') })
                        .padding({ left: 14, right: 14 })
                    }
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(14)
                .borderRadius(18)
                .backgroundColor(getAppUiState().themeBackground)
                .border({ width: 1, color: $r('app.color.divider') })
              }, (entry: McpHeaderEntry) => entry.id)
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor(getAppUiState().themeSurface)

          Column({ space: 12 }) {
            Column({ space: 4 }) {
              Text(pickLocalizedText('工具调用策略', 'Tool Call Policy'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text(pickLocalizedText(
                '控制该 MCP Server 的工具执行是否需要你确认。',
                'Control whether tool calls from this MCP server need your approval.'
              ))
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column({ space: 6 }) {
              Text(pickLocalizedText('执行策略', 'Execution Policy'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')

              Select(this.mcpToolApprovalPolicyOptions)
                .selected(this.mcpToolApprovalPolicySelectedIndex)
                .value(this.getMcpToolApprovalPolicyLabel(this.mcpFormToolApprovalPolicy))
                .onSelect((index: number, _value: string) => {
                  this.handleMcpToolApprovalPolicySelect(index)
                })
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .height(46)
                .backgroundColor(getAppUiState().themeBackground)
                .borderRadius(14)
                .border({ width: 1, color: $r('app.color.divider') })
                .padding({ left: 10, right: 10 })

              Text(this.getMcpToolApprovalPolicyDescription(this.mcpFormToolApprovalPolicy))
                .fontSize(11)
                .lineHeight(16)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor(getAppUiState().themeSurface)

          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(pickLocalizedText('启用该 Server', 'Enable This Server'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')

              Text(this.mcpFormEnabled
                ? pickLocalizedText('保存后立即连接并发现工具。', 'Connect and discover tools right after saving.')
                : pickLocalizedText('仅保存当前配置。', 'Only save the current configuration.'))
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.mcpFormEnabled })
              .selectedColor(this.themePrimary)
              .onChange((value: boolean) => {
                this.mcpFormEnabled = value
              })
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor(getAppUiState().themeSurface)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  build() {
    Column() {
      Column() {
        if (this.showHeader) {
          Row() {
            Text($r('app.string.tools_center_title'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            Blank()

            Button($r('app.string.tools_center_refresh'))
              .height(30)
              .fontSize(12)
              .type(ButtonType.Capsule)
              .stateEffect(false)
              .backgroundColor(this.themePrimary)
              .fontColor(Color.White)
              .onClick(() => {
                this.refreshMcpServersInBackground(true)
              })
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
        }

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(42)
              .height(42)
              .color(this.themePrimary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ top: this.contentTopPadding })
        } else {
          Scroll(this.contentScroller) {
            Column({ space: 20 }) {
              if (this.contentTopPadding > 0) {
                Blank()
                  .width('100%')
                  .height(this.contentTopPadding)
              }

              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text($r('app.string.search_service_card_title'))
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')

                  Text(pickLocalizedText(
                    '开启后聊天底栏会出现联网菜单,具体引擎在下方启用并选择。',
                    'Enable to show the web menu in chat. Pick engines below.'
                  ))
                    .fontSize(12)
                    .lineHeight(18)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: this.searchServiceEnabled })
                  .selectedColor(this.themePrimary)
                  .onChange((value: boolean) => {
                    this.handleSearchServiceEnabledChanged(value)
                  })
              }
              .width('100%')
              .padding({ left: 4, right: 4, top: 4, bottom: 4 })

              Column({ space: 10 }) {
                Row() {
                  Text(pickLocalizedText('搜索服务', 'Search Services'))
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)

                  Text(formatLocalizedCount(this.getAvailableEnabledSearchEngineCount(), '个可用',
                    'available service', 'available services'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')

                Text(pickLocalizedText(
                  '启用并配置完成后会出现在聊天联网菜单,聊天页可随时切换当前引擎。',
                  'Configured and enabled engines appear in the chat web menu; switch from there anytime.'
                ))
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              .width('100%')

              ForEach(this.searchEngineDescriptors, (engine: SearchEngineDescriptor) => {
                SearchEngineCardItem({
                  engineName: engine.label,
                  engineEnabled: this.isSearchEngineEnabled(engine.id),
                  engineConfigured: this.isSearchEngineConfiguredLocal(engine.id),
                  supportsScrape: engine.supportsScrape,
                  zeroConfig: engine.configFields.length === 0,
                  onToggleEnabled: (enabled: boolean) => {
                    this.handleSearchEngineEnabledChanged(engine.id, enabled)
                  },
                  onTap: () => {
                    this.openSearchEngineConfig(engine.id)
                  }
                })
              }, (engine: SearchEngineDescriptor) => engine.id)

              Column({ space: 10 }) {
                Row() {
                  Text(pickLocalizedText('MCP 服务', 'MCP Services'))
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)

                  if (this.isRefreshingMcpServers) {
                    LoadingProgress()
                      .width(18)
                      .height(18)
                      .color(this.themePrimary)
                      .margin({ right: 8 })
                  }

                  Button() {
                    Row({ space: 4 }) {
                      SymbolGlyph($r('sys.symbol.plus'))
                        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                        .fontSize(13)
                        .fontColor([Color.White])
                      Text(pickLocalizedText('新增', 'Add'))
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Color.White)
                    }
                  }
                  .height(32)
                  .padding({ left: 14, right: 14 })
                  .type(ButtonType.Capsule)
                  .stateEffect(false)
                  .backgroundColor(this.themePrimary)
                  .onClick(() => {
                    this.openCreateMcpServer()
                  })
                }
                .width('100%')

                if (this.mcpServers.length > 0) {
                  Text(this.getMcpServerConnectedCountText())
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }
              }
              .width('100%')

              if (this.mcpServers.length === 0) {
                Row({ space: 12 }) {
                  Column() {
                    SymbolGlyph($r('sys.symbol.puzzle'))
                      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                      .fontSize(22)
                      .fontColor([this.themePrimary])
                  }
                  .width(42)
                  .height(42)
                  .borderRadius(16)
                  .backgroundColor(this.backgroundHex)
                  .border({ width: 1, color: this.themePrimary })
                  .justifyContent(FlexAlign.Center)

                  Column({ space: 4 }) {
                    Text(pickLocalizedText('还没有 MCP Server', 'No MCP server yet'))
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))

                    Text(pickLocalizedText('点击右上角新增。', 'Tap Add in the top right to create one.'))
                      .fontSize(12)
                      .lineHeight(18)
                      .fontColor($r('app.color.text_secondary'))
                      .width('100%')
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(18)
                .borderRadius(20)
                .backgroundColor(getAppUiState().themeSurface)
                .border({ width: 1, color: $r('app.color.divider') })
                .shadow({
                  radius: 14,
                  color: this.isDarkMode ? 'rgba(0, 0, 0, 0.20)' : 'rgba(15, 23, 42, 0.05)',
                  offsetX: 0,
                  offsetY: 6
                })
              } else {
                ForEach(this.mcpServers, (server: McpServerConfig) => {
                  McpServerCardItem({
                    serverName: server.name,
                    serverBaseUrl: server.baseUrl,
                    serverEnabled: server.enabled,
                    toolCount: server.tools.length,
                    onToggleEnabled: (value: boolean) => {
                      this.handleMcpServerEnabledChanged(server.id, value)
                    },
                    onTap: () => {
                      this.openMcpServerDetail(server.id)
                    }
                  })
                }, (server: McpServerConfig) => server.id)
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: this.contentBottomPadding })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(getAppUiState().themeBackground)

      // bindSheet 宿主分离：布尔状态模式下不要把多个 sheet 链到同一个组件上
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showSearchConfigSheet, this.SearchConfigSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          showClose: false,
          dragBar: true,
          blurStyle: BlurStyle.Regular,
          shouldDismiss: (dismissAction: SheetDismiss) => {
            this.requestCloseSearchConfigSheet(dismissAction)
          },
          onDisappear: () => {
            this.showSearchConfigSheet = false
            this.loadSearchSettings()
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showMcpServerSheet, this.McpServerSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          showClose: false,
          dragBar: true,
          blurStyle: BlurStyle.Regular,
          onDisappear: () => {
            this.showMcpServerSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showMcpServerDetailSheet, this.McpServerDetailSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          showClose: false,
          dragBar: true,
          blurStyle: BlurStyle.Regular,
          onDisappear: () => {
            this.showMcpServerDetailSheet = false
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }
}

@ComponentV2
struct SearchEngineCardItem {
  @Param engineName: string = ''
  @Param engineEnabled: boolean = false
  @Param engineConfigured: boolean = false
  @Param supportsScrape: boolean = false
  @Param zeroConfig: boolean = false
  @Event onToggleEnabled: (enabled: boolean) => void = (_enabled: boolean) => {}
  @Event onTap: () => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get dividerHex(): string {
    return getAppUiState().themeDivider
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private getStatusText(): string {
    if (!this.engineConfigured) {
      return pickLocalizedText('缺少配置', 'Needs config')
    }
    if (this.engineEnabled) {
      return pickLocalizedText('已启用', 'Enabled')
    }
    return pickLocalizedText('未启用', 'Disabled')
  }

  private getSubtitleText(): string {
    if (!this.engineConfigured) {
      return pickLocalizedText('填写 API Key 后可启用', 'Add an API key to enable it')
    }
    if (this.engineEnabled) {
      return pickLocalizedText('可在聊天联网菜单中切换', 'Available in the chat search menu')
    }
    return pickLocalizedText('启用后可在聊天中选择', 'Enable it to use from chat')
  }

  private getStatusColor(): ResourceColor {
    if (!this.engineConfigured) {
      return '#D9485F'
    }
    if (this.engineEnabled) {
      return this.themePrimary
    }
    return $r('app.color.text_secondary')
  }

  private getStatusBackgroundColor(): ResourceColor {
    if (!this.engineConfigured) {
      return this.isDarkMode ? '#3A1D23' : '#FBECEF'
    }
    if (this.engineEnabled) {
      return withColorAlpha(this.themePrimary, this.isDarkMode ? '28' : '16')
    }
    return getAppUiState().themeBackground
  }

  @Builder
  private AbilityTag(label: string, active: boolean) {
    Text(label)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(active ? this.themePrimary : $r('app.color.text_tertiary'))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(999)
      .backgroundColor(active ? withColorAlpha(this.themePrimary, this.isDarkMode ? '24' : '12') :
        getAppUiState().themeBackground)
      .border({ width: 1, color: active ? withColorAlpha(this.themePrimary, '40') : this.dividerHex })
  }

  build() {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontSize(19)
          .fontColor([this.engineEnabled ? this.themePrimary : $r('app.color.text_secondary')])
      }
      .width(42)
      .height(42)
      .borderRadius(14)
      .backgroundColor(getAppUiState().themeBackground)
      .border({ width: 1, color: this.engineEnabled ? this.themePrimary : this.dividerHex })
      .justifyContent(FlexAlign.Center)

      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(this.engineName)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.getStatusText())
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getStatusColor())
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(999)
            .backgroundColor(this.getStatusBackgroundColor())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.getSubtitleText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Row({ space: 6 }) {
          if (this.zeroConfig) {
            this.AbilityTag(pickLocalizedText('零配置', 'No setup'), true)
          }
          this.AbilityTag(pickLocalizedText('网页抓取', 'Scrape'), this.supportsScrape)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.engineEnabled })
        .selectedColor(this.themePrimary)
        .onChange((value: boolean) => {
          this.onToggleEnabled(value)
        })
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor(getAppUiState().themeSurface)
    .border({ width: 1, color: this.engineEnabled ? this.themePrimary : this.dividerHex })
    .onClick(() => {
      this.onTap()
    })
  }
}

@ComponentV2
struct McpServerCardItem {
  @Param serverName: string = ''
  @Param serverBaseUrl: string = ''
  @Param serverEnabled: boolean = false
  @Param toolCount: number = 0
  @Event onToggleEnabled: (enabled: boolean) => void = (_enabled: boolean) => {}
  @Event onTap: () => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get dividerHex(): string {
    return getAppUiState().themeDivider
  }

  build() {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.cloud'))
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontSize(20)
          .fontColor([this.serverEnabled ? this.themePrimary : $r('app.color.text_secondary')])
      }
      .width(42)
      .height(42)
      .borderRadius(14)
      .backgroundColor(getAppUiState().themeBackground)
      .border({ width: 1, color: this.serverEnabled ? this.themePrimary : this.dividerHex })
      .justifyContent(FlexAlign.Center)

      Column({ space: 4 }) {
        Text(this.serverName)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.serverBaseUrl)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(formatLocalizedCount(this.toolCount, '个工具', 'tool', 'tools'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.serverEnabled })
        .selectedColor(this.themePrimary)
        .onChange((value: boolean) => {
          this.onToggleEnabled(value)
        })

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontSize(16)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding(14)
    .margin({ bottom: 8 })
    .borderRadius(18)
    .backgroundColor(getAppUiState().themeSurface)
    .border({ width: 1, color: this.serverEnabled ? this.themePrimary : this.dividerHex })
    .shadow({
      radius: 12,
      color: this.isDarkMode ? 'rgba(0, 0, 0, 0.18)' : 'rgba(15, 23, 42, 0.04)',
      offsetX: 0,
      offsetY: 4
    })
    .onClick(() => {
      this.onTap()
    })
  }
}

@ComponentV2
struct McpToolEntryCard {
  @Param tool: McpToolEntry = new McpToolEntry()
  @Param serverApprovalPolicy: string = ToolApprovalPolicy.UNCONFIGURED
  @Event onEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {}
  @Event onPolicyChange: (policy: string) => void = (_policy: string) => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private getEffectivePolicy(): string {
    const toolPolicy = normalizeToolApprovalPolicy(this.tool.toolApprovalPolicy)
    if (toolPolicy !== ToolApprovalPolicy.UNCONFIGURED) {
      return toolPolicy
    }
    return normalizeToolApprovalPolicy(this.serverApprovalPolicy)
  }

  private getPolicyLabel(): string {
    const effective = this.getEffectivePolicy()
    if (effective === ToolApprovalPolicy.ALWAYS_ALLOW) {
      return pickLocalizedText('始终允许', 'Always')
    }
    return ''
  }

  build() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(this.tool.name)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (this.tool.permissionLevel === 'write') {
            Text(pickLocalizedText('写', 'W'))
              .fontSize(9)
              .fontColor('#D9485F')
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .borderRadius(4)
              .backgroundColor(this.isDarkMode ? '#4B1D24' : '#FDECEF')
          }

          if (this.getPolicyLabel() !== '') {
            Text(this.getPolicyLabel())
              .fontSize(9)
              .fontColor(this.themePrimary)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .borderRadius(4)
              .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '20' : '10'))
          }
        }
        .width('100%')

        if (this.tool.description !== '') {
          Text(this.tool.description)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        const current = normalizeToolApprovalPolicy(this.tool.toolApprovalPolicy)
        const next = current === ToolApprovalPolicy.ALWAYS_ALLOW
          ? ToolApprovalPolicy.UNCONFIGURED : ToolApprovalPolicy.ALWAYS_ALLOW
        this.onPolicyChange(next)
      })

      Toggle({ type: ToggleType.Switch, isOn: this.tool.enabled })
        .selectedColor(this.themePrimary)
        .onChange((value: boolean) => {
          this.onEnabledChange(value)
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(this.isDarkMode ? '#23262D' : Color.White)
  }
}
