import { ToolConfig, SearchEngine, ToolSourceType } from '../models/ChatModels'
import { McpAuthType, McpServerConfig } from '../models/McpModels'
import { ToolRegistry } from '../services/ToolRegistry'
import { McpService } from '../services/McpService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { registerBuiltinTools } from '../config/BuiltinTools'
import { getPreferencesService, PreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { HdsListItemCard } from '@kit.UIDesignKit'
import { getAppUiState } from '../state/AppUiState'
import { formatLocalizedCount, pickLocalizedText } from '../utils/LocalizedTextUtils'
import {
  buildCustomHeadersJson,
  isSensitiveCustomHeaderName,
  normalizeCustomHeaderName,
  parseCustomHeaderEntries,
  validateCustomHeaderEntries
} from '../utils/CustomHeaderUtils'

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
  @Local builtinTools: ToolConfig[] = []
  @Local searchServiceEnabled: boolean = false
  @Local searchEngine: SearchEngine = SearchEngine.BING
  @Local searchEngineSelectedIndex: number = 0
  @Local searchEngineDisplayValue: string = 'Bing(local)'
  @Local searchBraveApiKey: string = ''
  @Local searchTavilyApiKey: string = ''
  @Local searchExaApiKey: string = ''
  @Local searchExaBaseUrl: string = 'https://api.exa.ai'
  @Local searchQueryOptimizationEnabled: boolean = false
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
  @Local isSavingMcpServer: boolean = false

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get secondaryTextHex(): string {
    return this.isDarkMode ? '#999999' : '#666666'
  }

  private get backgroundHex(): string {
    return this.isDarkMode ? '#121212' : '#F1F3F5'
  }

  private get dividerHex(): string {
    return this.isDarkMode ? '#2A2A2A' : '#E5E5E5'
  }

  private toolRegistry: ToolRegistry = ServiceRegistry.toolRegistry()
  private mcpService: McpService = ServiceRegistry.mcp()
  private preferencesService: PreferencesService = getPreferencesService()
  private readonly searchToolId: string = 'web_search'
  private readonly searchEngineOptions: Array<SelectOption> = [
    { value: 'Bing(local)' },
    { value: 'Brave Search' },
    { value: 'Tavily' },
    { value: 'Exa' }
  ]
  private readonly mcpAuthTypeOptions: Array<SelectOption> = [
    { value: 'None' },
    { value: 'Bearer' }
  ]
  private readonly reservedMcpHeaderNames: string[] = [
    'content-type',
    'accept',
    'mcp-protocol-version',
    'mcp-session-id',
    'authorization'
  ]
  private originalSearchEngine: SearchEngine = SearchEngine.BING
  private originalSearchBraveApiKey: string = ''
  private originalSearchTavilyApiKey: string = ''
  private originalSearchExaApiKey: string = ''
  private originalSearchExaBaseUrl: string = 'https://api.exa.ai'
  private originalSearchQueryOptimizationEnabled: boolean = false

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

  private syncBuiltinToolsFromRegistry(): void {
    const allTools = this.toolRegistry.getAllToolConfigs()
    const builtin: ToolConfig[] = []
    for (let i = 0; i < allTools.length; i++) {
      if (allTools[i].sourceType === ToolSourceType.BUILTIN && allTools[i].id !== this.searchToolId) {
        builtin.push(allTools[i])
      }
    }
    this.builtinTools = builtin
  }

  private async loadData(): Promise<void> {
    this.isLoading = true

    registerBuiltinTools()
    this.syncBuiltinToolsFromRegistry()
    try {
      await this.loadToolEnabledStates()
      await this.loadSearchSettings()
      await this.loadMcpServers()
      this.syncBuiltinToolsFromRegistry()
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
    } finally {
      this.syncBuiltinToolsFromRegistry()
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
      total += this.getServerTools(this.mcpServers[i].id).length
    }
    return total
  }

  private parseSearchEngine(raw: string): SearchEngine {
    if (raw === SearchEngine.BRAVE) {
      return SearchEngine.BRAVE
    }
    if (raw === SearchEngine.TAVILY) {
      return SearchEngine.TAVILY
    }
    if (raw === SearchEngine.EXA) {
      return SearchEngine.EXA
    }
    return SearchEngine.BING
  }

  private getSearchEngineLabel(engine: SearchEngine): string {
    if (engine === SearchEngine.BRAVE) {
      return 'Brave Search'
    }
    if (engine === SearchEngine.TAVILY) {
      return 'Tavily'
    }
    if (engine === SearchEngine.EXA) {
      return 'Exa'
    }
    return 'Bing(local)'
  }

  private getSearchEngineByIndex(index: number): SearchEngine {
    if (index === 1) {
      return SearchEngine.BRAVE
    }
    if (index === 2) {
      return SearchEngine.TAVILY
    }
    if (index === 3) {
      return SearchEngine.EXA
    }
    return SearchEngine.BING
  }

  private getSearchEngineSelectedIndex(engine: SearchEngine): number {
    if (engine === SearchEngine.BRAVE) {
      return 1
    }
    if (engine === SearchEngine.TAVILY) {
      return 2
    }
    if (engine === SearchEngine.EXA) {
      return 3
    }
    return 0
  }

  private applySearchServiceEnabledState(enabled: boolean): void {
    this.searchServiceEnabled = enabled
    const registeredTool = this.toolRegistry.getTool(this.searchToolId)
    if (registeredTool !== undefined) {
      registeredTool.config.enabled = enabled
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
    }
  }

  private async loadSearchSettings(): Promise<void> {
    const searchServiceEnabled = await this.preferencesService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    const engineRaw = await this.preferencesService.getString(PreferenceKeys.SEARCH_ENGINE, SearchEngine.BING)
    const braveApiKey = await this.preferencesService.getString(PreferenceKeys.SEARCH_BRAVE_API_KEY, '')
    const tavilyApiKey = await this.preferencesService.getString(PreferenceKeys.SEARCH_TAVILY_API_KEY, '')
    const exaApiKey = await this.preferencesService.getString(PreferenceKeys.SEARCH_EXA_API_KEY, '')
    const exaBaseUrl = await this.preferencesService.getString(PreferenceKeys.SEARCH_EXA_BASE_URL, 'https://api.exa.ai')
    const optimizationEnabled = await this.preferencesService.getBoolean(
      PreferenceKeys.SEARCH_QUERY_OPTIMIZATION_ENABLED,
      false
    )

    this.searchServiceEnabled = searchServiceEnabled
    this.searchEngine = this.parseSearchEngine(engineRaw)
    this.searchEngineSelectedIndex = this.getSearchEngineSelectedIndex(this.searchEngine)
    this.searchEngineDisplayValue = this.getSearchEngineLabel(this.searchEngine)
    this.searchBraveApiKey = braveApiKey.trim()
    this.searchTavilyApiKey = tavilyApiKey.trim()
    this.searchExaApiKey = exaApiKey
    this.searchExaBaseUrl = exaBaseUrl.trim() !== '' ? exaBaseUrl.trim() : 'https://api.exa.ai'
    this.searchQueryOptimizationEnabled = optimizationEnabled
    this.syncOriginalSearchSettings()
  }

  private normalizeSearchBaseUrl(raw: string): string {
    const trimmed = raw.trim()
    if (trimmed === '') {
      return 'https://api.exa.ai'
    }
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1)
    }
    return trimmed
  }

  private syncOriginalSearchSettings(): void {
    this.originalSearchEngine = this.searchEngine
    this.originalSearchBraveApiKey = this.searchBraveApiKey.trim()
    this.originalSearchTavilyApiKey = this.searchTavilyApiKey.trim()
    this.originalSearchExaApiKey = this.searchExaApiKey.trim()
    this.originalSearchExaBaseUrl = this.normalizeSearchBaseUrl(this.searchExaBaseUrl)
    this.originalSearchQueryOptimizationEnabled = this.searchQueryOptimizationEnabled
  }

  private hasPendingSearchConfigChanges(): boolean {
    if (this.searchEngine !== this.originalSearchEngine) {
      return true
    }
    if (this.searchBraveApiKey.trim() !== this.originalSearchBraveApiKey) {
      return true
    }
    if (this.searchTavilyApiKey.trim() !== this.originalSearchTavilyApiKey) {
      return true
    }
    if (this.searchExaApiKey.trim() !== this.originalSearchExaApiKey) {
      return true
    }
    if (this.normalizeSearchBaseUrl(this.searchExaBaseUrl) !== this.originalSearchExaBaseUrl) {
      return true
    }
    if (this.searchQueryOptimizationEnabled !== this.originalSearchQueryOptimizationEnabled) {
      return true
    }
    return false
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
    const braveKey = this.searchBraveApiKey.trim()
    const tavilyKey = this.searchTavilyApiKey.trim()
    const exaKey = this.searchExaApiKey.trim()
    if (this.searchEngine === SearchEngine.BRAVE && braveKey === '') {
      this.showToolsSnack(pickLocalizedText(
        '请选择 Brave Search 时先填写 API Key',
        'Enter the API key before selecting Brave Search'
      ), 2000, SnackBarTone.ERROR)
      return false
    }
    if (this.searchEngine === SearchEngine.TAVILY && tavilyKey === '') {
      this.showToolsSnack(pickLocalizedText(
        '请选择 Tavily 时先填写 API Key',
        'Enter the API key before selecting Tavily'
      ), 2000, SnackBarTone.ERROR)
      return false
    }
    if (this.searchEngine === SearchEngine.EXA && exaKey === '') {
      this.showToolsSnack($r('app.string.search_exa_key_required'), 2000, SnackBarTone.ERROR)
      return false
    }

    const baseUrl = this.normalizeSearchBaseUrl(this.searchExaBaseUrl)
    const shouldValidateExaBaseUrl = this.searchEngine === SearchEngine.EXA
    if (shouldValidateExaBaseUrl && !baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      this.showToolsSnack($r('app.string.search_base_url_invalid'), 2000, SnackBarTone.ERROR)
      return false
    }

    await this.preferencesService.setString(PreferenceKeys.SEARCH_ENGINE, this.searchEngine)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_BRAVE_API_KEY, braveKey)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_TAVILY_API_KEY, tavilyKey)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_EXA_API_KEY, exaKey)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_EXA_BASE_URL, baseUrl)
    await this.preferencesService.setBoolean(
      PreferenceKeys.SEARCH_QUERY_OPTIMIZATION_ENABLED,
      this.searchQueryOptimizationEnabled
    )
    this.searchBraveApiKey = braveKey
    this.searchTavilyApiKey = tavilyKey
    this.searchExaApiKey = exaKey
    this.searchExaBaseUrl = baseUrl
    this.syncOriginalSearchSettings()

    this.showToolsSnack($r('app.string.search_config_saved'), 2000, SnackBarTone.SUCCESS)
    return true
  }

  private handleSaveAndCloseSearchSettings(): void {
    this.handleSaveSearchSettings().then((saved: boolean) => {
      if (saved) {
        this.showSearchConfigSheet = false
      }
    })
  }

  private handleSearchEngineSelect(index: number, value: string): void {
    this.searchEngineSelectedIndex = index
    const nextEngine = this.getSearchEngineByIndex(index)
    const displayValue = value.trim() === '' ? this.getSearchEngineLabel(nextEngine) : value
    this.searchEngineDisplayValue = displayValue
    this.searchEngine = nextEngine
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
    this.showMcpServerSheet = true
  }

  private handleMcpAuthTypeSelect(index: number): void {
    this.mcpAuthTypeSelectedIndex = index
    this.mcpFormAuthType = index === 1 ? McpAuthType.BEARER : McpAuthType.NONE
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

  private getServerTools(serverId: string): ToolConfig[] {
    const configs: ToolConfig[] = []
    const tools = this.toolRegistry.getToolsBySource(ToolSourceType.MCP, serverId)
    for (let i = 0; i < tools.length; i++) {
      configs.push(tools[i].config)
    }
    return configs
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

  @Builder
  SearchConfigSheetBuilder() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
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
        Column() {
          Text($r('app.string.search_service_config_desc'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .margin({ bottom: 10 })

          Column() {
            Text($r('app.string.search_engine'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ bottom: 6 })

            Select(this.searchEngineOptions)
              .selected(this.searchEngineSelectedIndex)
              .value(this.searchEngineDisplayValue)
              .onSelect((index: number, value: string) => {
                this.handleSearchEngineSelect(index, value)
              })
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .height(40)
              .backgroundColor($r('app.color.background'))
              .borderRadius(10)
              .padding({ left: 8, right: 8 })

            if (this.searchEngine === SearchEngine.BRAVE) {
              TextInput({ text: this.searchBraveApiKey, placeholder: 'Brave Search API Key' })
                .onChange((value: string) => {
                  this.searchBraveApiKey = value
                })
                .type(InputType.Password)
                .enableAutoFill(false)
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor($r('app.color.background'))
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })
            }

            if (this.searchEngine === SearchEngine.TAVILY) {
              TextInput({ text: this.searchTavilyApiKey, placeholder: 'Tavily API Key' })
                .onChange((value: string) => {
                  this.searchTavilyApiKey = value
                })
                .type(InputType.Password)
                .enableAutoFill(false)
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor($r('app.color.background'))
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })
            }

            if (this.searchEngine === SearchEngine.EXA) {
              TextInput({ text: this.searchExaApiKey, placeholder: $r('app.string.search_exa_api_key') })
                .onChange((value: string) => {
                  this.searchExaApiKey = value
                })
                .type(InputType.Password)
                .enableAutoFill(false)
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor($r('app.color.background'))
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })

              TextInput({ text: this.searchExaBaseUrl, placeholder: $r('app.string.search_exa_base_url') })
                .onChange((value: string) => {
                  this.searchExaBaseUrl = value
                })
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor($r('app.color.background'))
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })
            }

            Text($r('app.string.search_engine_runtime_hint'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .margin({ top: 8 })

            if (this.searchEngine === SearchEngine.BING) {
              Row() {
                Column() {
                  Text($r('app.string.search_query_optimization'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')

                  Text($r('app.string.search_query_optimization_hint'))
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                    .width('100%')
                    .margin({ top: 2, right: 8 })
                }
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.searchQueryOptimizationEnabled })
                  .onChange((value: boolean) => {
                    this.searchQueryOptimizationEnabled = value
                  })
              }
              .width('100%')
              .margin({ top: 10 })
            }
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.surface'))
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
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  McpServerSheetBuilder() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
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
            .fontSize(18)
            .fontColor([Color.White])
        }
        .type(ButtonType.Circle)
        .stateEffect(false)
        .width(36)
        .height(36)
        .backgroundColor(this.isSavingMcpServer ? `${this.themePrimary}99` : this.themePrimary)
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
                  .fontSize(22)
                  .fontColor([this.themePrimary])
              }
              .width(46)
              .height(46)
              .borderRadius(16)
              .backgroundColor(`${this.themePrimary}${this.isDarkMode ? '26' : '12'}`)
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
                    .backgroundColor(`${this.themePrimary}${this.isDarkMode ? '20' : '10'}`)
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
                .backgroundColor(`${this.themePrimary}${this.isDarkMode ? '20' : '10'}`)

              Text(this.getMcpFormEnableLabel())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(999)
                .backgroundColor($r('app.color.background'))
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))
          .border({ width: 1, color: `${this.themePrimary}${this.isDarkMode ? '20' : '10'}` })

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
                .backgroundColor($r('app.color.background'))
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
                .backgroundColor($r('app.color.background'))
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
          .backgroundColor($r('app.color.surface'))

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
                .backgroundColor($r('app.color.background'))
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
                  .backgroundColor($r('app.color.background'))
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
                    .fontSize(16)
                    .fontColor([this.themePrimary])
                }
                .width(28)
                .height(28)
                .borderRadius(14)
                .backgroundColor(`${this.themePrimary}${this.isDarkMode ? '20' : '10'}`)
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
              .backgroundColor($r('app.color.background'))
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))

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
                        .fontColor('#D97757')
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .borderRadius(999)
                        .backgroundColor(this.isDarkMode ? '#4A2D1A' : '#FFF1E8')
                        .margin({ right: 8 })
                    }

                    Button($r('app.string.delete'))
                      .height(28)
                      .fontSize(11)
                      .type(ButtonType.Capsule)
                      .stateEffect(false)
                      .backgroundColor($r('app.color.surface'))
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
                      .backgroundColor($r('app.color.background'))
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
                        .backgroundColor($r('app.color.background'))
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
                        .backgroundColor($r('app.color.background'))
                        .border({ width: 1, color: $r('app.color.divider') })
                        .padding({ left: 14, right: 14 })
                    }
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(14)
                .borderRadius(18)
                .backgroundColor($r('app.color.background'))
                .border({ width: 1, color: $r('app.color.divider') })
              }, (entry: McpHeaderEntry) => entry.id)
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))

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
              .onChange((value: boolean) => {
                this.mcpFormEnabled = value
              })
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))
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
    .backgroundColor($r('app.color.background'))
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
        } else {
          Scroll() {
            Column({ space: 20 }) {
              SearchServiceCardItem({
                searchEnabled: this.searchServiceEnabled,
                searchEngineDisplayValue: this.searchEngineDisplayValue,
                onToggle: (enabled: boolean) => {
                  this.handleSearchServiceEnabledChanged(enabled)
                },
                onOpenConfig: () => {
                  this.showSearchConfigSheet = true
                }
              })

              if (this.builtinTools.length > 0) {
                Text($r('app.string.tools_builtin_section'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')

                ForEach(this.builtinTools, (tool: ToolConfig) => {
                  BuiltinToolCardItem({
                    tool: tool
                  })
                }, (tool: ToolConfig) => tool.id)
              }

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
                      .fontSize(22)
                      .fontColor([this.themePrimary])
                  }
                  .width(42)
                  .height(42)
                  .borderRadius(16)
                  .backgroundColor(`${this.themePrimary}${this.isDarkMode ? '24' : '10'}`)
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
                .backgroundColor($r('app.color.surface'))
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
                    tools: this.getServerTools(server.id),
                    authLabel: this.getMcpServerAuthLabel(server),
                    customHeaderCount: this.getServerCustomHeaderCount(server),
                    onToggleEnabled: (value: boolean) => {
                      this.handleMcpServerEnabledChanged(server.id, value)
                    },
                    onRefresh: () => {
                      this.refreshMcpServer(server.id)
                    },
                    onEdit: () => {
                      this.openEditMcpServer(server)
                    },
                    onDelete: () => {
                      this.handleDeleteMcpServer(server.id)
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
      .backgroundColor($r('app.color.background'))

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
          onWillAppear: () => {
            this.loadSearchSettings()
          },
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

@ComponentV2
struct SearchServiceCardItem {
  @Param searchEnabled: boolean = false
  @Param searchEngineDisplayValue: string = ''
  @Event onToggle: (enabled: boolean) => void = (enabled: boolean) => {}
  @Event onOpenConfig: () => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get backgroundHex(): string {
    return this.isDarkMode ? '#121212' : '#F1F3F5'
  }

  private get dividerHex(): string {
    return this.isDarkMode ? '#2A2A2A' : '#E5E5E5'
  }

  private getDisabledText(): string {
    return pickLocalizedText('未启用', 'Disabled')
  }

  private getConfigureText(): string {
    return pickLocalizedText('配置', 'Configure')
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([this.searchEnabled ? this.themePrimary : $r('app.color.text_secondary')])
        }
        .width(44)
        .height(44)
        .borderRadius(16)
        .backgroundColor(this.backgroundHex)
        .border({ width: 1, color: this.searchEnabled ? this.themePrimary : this.dividerHex })
        .justifyContent(FlexAlign.Center)

        Column({ space: 6 }) {
          Text($r('app.string.search_service_card_title'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Text(this.searchEnabled ? this.searchEngineDisplayValue : this.getDisabledText())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.searchEnabled })
          .onChange((value: boolean) => {
            this.onToggle(value)
          })
      }
      .width('100%')

      Row({ space: 4 }) {
        Blank()

        Text(this.getConfigureText())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([this.themePrimary])
      }
      .width('100%')
      .onClick(() => {
        this.onOpenConfig()
      })
    }
    .width('100%')
    .padding(16)
    .margin({ bottom: 8 })
    .borderRadius(20)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: this.searchEnabled ? this.themePrimary : this.dividerHex })
    .shadow({
      radius: 16,
      color: this.isDarkMode ? 'rgba(0, 0, 0, 0.20)' : 'rgba(15, 23, 42, 0.05)',
      offsetX: 0,
      offsetY: 6
    })
    .onClick(() => {
      this.onOpenConfig()
    })
  }
}

@ComponentV2
struct BuiltinToolCardItem {
  @Param tool: ToolConfig = new ToolConfig()

  @Builder
  ToolCardText() {
    Column() {
      Text(this.tool.name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Text(this.tool.description)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })

      Text(this.tool.id)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsListItemCard({
      textItem: {
        customBuilder: (): void => { this.ToolCardText() }
      },
      cardBackgroundColor: $r('app.color.surface'),
      cardBorderRadius: 12,
      accessibilityOptions: {
        accessibilityText: this.tool.name,
        accessibilityDescription: this.tool.description,
        accessibilityGroup: {
          isGroup: true
        }
      }
    })
    .margin({ bottom: 8 })
  }
}

@ComponentV2
struct McpServerCardItem {
  @Param serverName: string = ''
  @Param serverBaseUrl: string = ''
  @Param serverEnabled: boolean = false
  @Param tools: ToolConfig[] = []
  @Param authLabel: string = 'None'
  @Param customHeaderCount: number = 0
  @Event onToggleEnabled: (enabled: boolean) => void = (_enabled: boolean) => {}
  @Event onRefresh: () => void = () => {}
  @Event onEdit: () => void = () => {}
  @Event onDelete: () => void = () => {}
  @Local isToolsExpanded: boolean = false

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get secondaryTextHex(): string {
    return this.isDarkMode ? '#999999' : '#666666'
  }

  private get backgroundHex(): string {
    return this.isDarkMode ? '#121212' : '#F1F3F5'
  }

  private get dividerHex(): string {
    return this.isDarkMode ? '#2A2A2A' : '#E5E5E5'
  }

  private getWriteToolCount(): number {
    let count = 0
    for (let i = 0; i < this.tools.length; i++) {
      if (this.tools[i].permissionLevel === 'write') {
        count += 1
      }
    }
    return count
  }

  private getToolPreviewText(): string {
    if (this.tools.length === 0) {
      return pickLocalizedText('暂未发现工具。', 'No tools discovered yet.')
    }
    const names: string[] = []
    const maxVisible = Math.min(this.tools.length, 5)
    for (let i = 0; i < maxVisible; i++) {
      names.push(this.tools[i].name)
    }
    const suffix = this.tools.length > maxVisible
      ? pickLocalizedText(` 等 ${this.tools.length} 个`, ` and ${this.tools.length} total`)
      : ''
    return `${names.join(' · ')}${suffix}`
  }

  private getStatusText(): string {
    return this.serverEnabled ? pickLocalizedText('已启用', 'Enabled') : pickLocalizedText('已停用', 'Disabled')
  }

  private getStatusBackgroundColor(): string {
    return this.serverEnabled ? (this.isDarkMode ? '#183722' : '#EAF7EE') : (this.isDarkMode ? '#2D3138' : '#EEF1F5')
  }

  private getStatusFontColor(): string {
    return this.serverEnabled ? '#2E8B57' : '#667085'
  }

  private getToolToggleText(): string {
    return this.isToolsExpanded ? pickLocalizedText('收起工具', 'Collapse') : pickLocalizedText('展开工具', 'Expand')
  }

  private getToolCountText(): string {
    return this.tools.length > 0
      ? formatLocalizedCount(this.tools.length, '个工具', 'tool', 'tools')
      : pickLocalizedText('尚未发现工具', 'No tools discovered')
  }

  private getCustomHeaderCountText(): string {
    return formatLocalizedCount(this.customHeaderCount, '个请求头', 'header', 'headers')
  }

  private getWriteToolCountText(): string {
    return formatLocalizedCount(this.getWriteToolCount(), '个需确认', 'tool needs approval', 'tools need approval')
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.cloud'))
            .fontSize(22)
            .fontColor([this.serverEnabled ? this.themePrimary : this.secondaryTextHex])
        }
        .width(46)
        .height(46)
        .borderRadius(16)
        .backgroundColor(this.backgroundHex)
        .border({ width: 1, color: this.serverEnabled ? this.themePrimary : this.dividerHex })
        .justifyContent(FlexAlign.Center)

        Column({ space: 6 }) {
          Row() {
            Text(this.serverName)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.getStatusText())
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getStatusFontColor())
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(999)
              .backgroundColor(this.getStatusBackgroundColor())
              .margin({ left: 8 })
          }
          .width('100%')

          Text(this.serverBaseUrl)
            .fontSize(11)
            .lineHeight(16)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.serverEnabled })
          .onChange((value: boolean) => {
            this.onToggleEnabled(value)
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(this.getToolCountText())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(999)
          .backgroundColor($r('app.color.background'))

        if (this.authLabel !== 'None') {
          Text(this.authLabel)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor(this.backgroundHex)
            .border({ width: 1, color: this.themePrimary })
        }

        if (this.customHeaderCount > 0) {
          Text(this.getCustomHeaderCountText())
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor($r('app.color.background'))
        }

        if (this.getWriteToolCount() > 0) {
          Text(this.getWriteToolCountText())
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#D9485F')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor(this.isDarkMode ? '#4B1D24' : '#FDECEF')
        }
      }
      .width('100%')

      Column({ space: 10 }) {
        Row() {
          Text(this.tools.length > 0 ? this.getToolPreviewText() : pickLocalizedText('暂未发现工具', 'No tools discovered'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .maxLines(this.isToolsExpanded ? 10 : 3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.tools.length > 0) {
            Row({ space: 4 }) {
              Text(this.getToolToggleText())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)

              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(12)
                .fontColor([this.themePrimary])
                .rotate({ angle: this.isToolsExpanded ? 180 : 0 })
                .animation({ duration: 180, curve: Curve.EaseOut })
            }
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor(this.backgroundHex)
            .border({ width: 1, color: this.themePrimary })
            .onClick(() => {
              this.isToolsExpanded = !this.isToolsExpanded
            })
          }
        }
        .width('100%')

        if (this.isToolsExpanded && this.tools.length > 0) {
          Column({ space: 8 }) {
            ForEach(this.tools, (tool: ToolConfig) => {
              Row({ space: 8 }) {
                Column({ space: 3 }) {
                  Text(tool.name)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))

                  Text(tool.description.length > 0 ? tool.description : tool.id)
                    .fontSize(11)
                    .lineHeight(16)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                if (tool.permissionLevel === 'write') {
                  Text(pickLocalizedText('需确认', 'Approval'))
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#D9485F')
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(999)
                    .backgroundColor(this.isDarkMode ? '#4B1D24' : '#FDECEF')
                }
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor(this.isDarkMode ? '#23262D' : Color.White)
              .border({ width: 1, color: this.isDarkMode ? '#2E323A' : '#EEF2F6' })
            }, (tool: ToolConfig) => tool.id)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor(this.backgroundHex)
      .border({ width: 1, color: this.serverEnabled ? this.themePrimary : this.dividerHex })

      Row({ space: 8 }) {
        Button(pickLocalizedText('刷新', 'Refresh'))
          .height(32)
          .fontSize(12)
          .type(ButtonType.Capsule)
          .stateEffect(false)
          .backgroundColor(this.backgroundHex)
          .border({ width: 1, color: this.themePrimary })
          .fontColor(this.themePrimary)
          .onClick(() => {
            this.onRefresh()
          })

        Button(pickLocalizedText('编辑', 'Edit'))
          .height(32)
          .fontSize(12)
          .type(ButtonType.Capsule)
          .stateEffect(false)
          .backgroundColor(this.backgroundHex)
          .border({ width: 1, color: this.dividerHex })
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.onEdit()
          })

        Blank()

        Button($r('app.string.delete'))
          .height(32)
          .fontSize(12)
          .type(ButtonType.Capsule)
          .stateEffect(false)
          .backgroundColor(this.backgroundHex)
          .border({ width: 1, color: this.isDarkMode ? '#6A3139' : '#F2CBD2' })
          .fontColor('#D9485F')
          .onClick(() => {
            this.onDelete()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .margin({ bottom: 10 })
    .borderRadius(20)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: this.serverEnabled ? this.themePrimary : this.dividerHex })
    .shadow({
      radius: 16,
      color: this.isDarkMode ? 'rgba(0, 0, 0, 0.20)' : 'rgba(15, 23, 42, 0.05)',
      offsetX: 0,
      offsetY: 6
    })
  }
}
