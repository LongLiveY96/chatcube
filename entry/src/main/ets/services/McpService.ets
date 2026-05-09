import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import {
  ToolConfig,
  ToolDefinition,
  ToolFunction,
  ToolParameters,
  ToolPermissionLevel,
  ToolSourceType
} from '../models/ChatModels'
import {
  McpAuthType,
  McpDiscoveredTool,
  McpServerConfig,
  McpToolAnnotations,
  McpToolCallResponse,
  McpToolDescriptor
} from '../models/McpModels'
import { HttpService } from './HttpService'
import { getPreferencesService, PreferenceKeys, PreferencesService } from './PreferencesService'
import { getToolRegistry, RegisteredTool, ToolExecutor, ToolRegistry } from './ToolRegistry'

const MCP_PROTOCOL_VERSION = '2025-06-18'
const MCP_DEFAULT_TIMEOUT_MS = 30000
const MCP_CLIENT_NAME = 'ChatBox'
const MCP_CLIENT_VERSION = '1.1.3'

interface McpHttpResponse {
  statusCode: number
  headers: Record<string, string>
  body: string
}

interface JsonRpcErrorPayload {
  code?: number
  message?: string
}

interface JsonRpcResponsePayload {
  id?: string | number
  result?: Record<string, Object>
  error?: JsonRpcErrorPayload
}

class JsonRpcErrorPayloadData {
  code?: number
  message?: string
}

class JsonRpcResponsePayloadData {
  id?: string | number
  result?: Record<string, Object>
  error?: JsonRpcErrorPayload
}

class McpHttpResponseData {
  statusCode: number = 0
  headers: Record<string, string> = JSON.parse('{}') as Record<string, string>
  body: string = ''
}

class JsonRpcEmptyObject {
}

class McpToolAnnotationsData {
  readOnlyHint?: boolean
  destructiveHint?: boolean
  title?: string
}

class McpToolDescriptorData {
  name: string = ''
  title?: string
  description?: string
  inputSchema?: object
  annotations?: McpToolAnnotations
}

class McpServerConfigJson {
  id: string = ''
  name: string = ''
  baseUrl: string = ''
  enabled: boolean = true
  authType: string = McpAuthType.NONE
  authToken: string = ''
  customHeadersJson: string = ''
}

class McpToolCallParams {
  name: string = ''
  arguments: Record<string, Object> = JSON.parse('{}') as Record<string, Object>
}

class JsonRpcClientInfo {
  name: string = ''
  version: string = ''
}

class JsonRpcInitializeParams {
  protocolVersion: string = MCP_PROTOCOL_VERSION
  capabilities: object = new JsonRpcEmptyObject()
  clientInfo: JsonRpcClientInfo = new JsonRpcClientInfo()
}

class JsonRpcNotificationRequest {
  jsonrpc: string = '2.0'
  method: string = ''
  params?: object
}

class JsonRpcRequestEnvelope {
  jsonrpc: string = '2.0'
  id: string = ''
  method: string = ''
  params?: object
}

class JsonRpcResultWithHeaders {
  result: Record<string, Object> = JSON.parse('{}') as Record<string, Object>
  headers: Record<string, string> = JSON.parse('{}') as Record<string, string>
}

class NormalizedMcpToolResult {
  isError: boolean = false
  structuredContent?: object
  content?: Array<Record<string, Object>>
  summary?: string
}

class McpToolExecutor implements ToolExecutor {
  private serverId: string
  private remoteToolName: string
  private service: McpService

  constructor(service: McpService, serverId: string, remoteToolName: string) {
    this.service = service
    this.serverId = serverId
    this.remoteToolName = remoteToolName
  }

  async execute(args: string): Promise<string> {
    return await this.service.callTool(this.serverId, this.remoteToolName, args)
  }
}

export class McpService {
  private static instance: McpService | null = null
  private preferencesService: PreferencesService
  private toolRegistry: ToolRegistry
  private sessionIds: Map<string, string> = new Map()
  private negotiatedProtocolVersions: Map<string, string> = new Map()
  private readonly chatSearchToolId: string = 'web_search'

  private constructor() {
    this.preferencesService = getPreferencesService()
    this.toolRegistry = getToolRegistry()
  }

  static getInstance(): McpService {
    if (McpService.instance === null) {
      McpService.instance = new McpService()
    }
    return McpService.instance
  }

  async loadServerConfigs(): Promise<McpServerConfig[]> {
    const raw = await this.preferencesService.getString(PreferenceKeys.MCP_SERVER_CONFIGS_JSON, '[]')
    if (raw.trim() === '') {
      return []
    }
    try {
      const parsed = JSON.parse(raw) as Array<Record<string, Object>>
      const result: McpServerConfig[] = []
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i]
        result.push(new McpServerConfig(
          this.readString(item, 'id'),
          this.readString(item, 'name'),
          this.readString(item, 'baseUrl'),
          this.readBoolean(item, 'enabled', true),
          this.readString(item, 'authType', McpAuthType.NONE),
          this.readString(item, 'authToken'),
          this.readString(item, 'customHeadersJson')
        ))
      }
      return result
    } catch (error) {
      console.error('McpService', `Failed to parse MCP server configs: ${JSON.stringify(error)}`)
      return []
    }
  }

  async saveServerConfigs(configs: McpServerConfig[]): Promise<void> {
    const serialized: McpServerConfigJson[] = []
    for (let i = 0; i < configs.length; i++) {
      const item = new McpServerConfigJson()
      item.id = configs[i].id
      item.name = configs[i].name
      item.baseUrl = this.normalizeBaseUrl(configs[i].baseUrl)
      item.enabled = configs[i].enabled
      item.authType = configs[i].authType
      item.authToken = configs[i].authToken
      item.customHeadersJson = configs[i].customHeadersJson
      serialized.push(item)
    }
    await this.preferencesService.setString(
      PreferenceKeys.MCP_SERVER_CONFIGS_JSON,
      JSON.stringify(serialized)
    )
  }

  async loadSelectedToolIds(): Promise<string[]> {
    const raw = await this.preferencesService.getString(PreferenceKeys.CHAT_SELECTED_TOOL_IDS_JSON, '')
    return this.normalizeStoredSelectedToolIds(this.parseStringArray(raw))
  }

  async saveSelectedToolIds(toolIds: string[]): Promise<string[]> {
    const sanitized = this.normalizeStoredSelectedToolIds(toolIds)
    await this.preferencesService.setString(
      PreferenceKeys.CHAT_SELECTED_TOOL_IDS_JSON,
      JSON.stringify(sanitized)
    )
    return sanitized
  }

  private normalizeStoredSelectedToolIds(toolIds: string[]): string[] {
    const ids: string[] = []
    for (let i = 0; i < toolIds.length; i++) {
      const toolId = toolIds[i].trim()
      if (toolId === '' || toolId === this.chatSearchToolId) {
        continue
      }
      if (!ids.includes(toolId)) {
        ids.push(toolId)
      }
    }
    return ids
  }

  sanitizeSelectedToolIds(toolIds: string[]): string[] {
    const normalizedToolIds = this.normalizeStoredSelectedToolIds(toolIds)
    const ids: string[] = []
    for (let i = 0; i < normalizedToolIds.length; i++) {
      const toolId = normalizedToolIds[i]
      if (toolId === '' || !this.toolRegistry.isToolRegistered(toolId)) {
        continue
      }
      const tool = this.toolRegistry.getTool(toolId)
      if (tool === undefined || !tool.config.enabled) {
        continue
      }
      if (!ids.includes(toolId)) {
        ids.push(toolId)
      }
    }
    return ids
  }

  async refreshAllServers(): Promise<void> {
    const configs = await this.loadServerConfigs()
    const enabledServerIds: string[] = []
    const failedServers: string[] = []
    for (let i = 0; i < configs.length; i++) {
      const server = configs[i]
      if (!server.enabled) {
        this.toolRegistry.unregisterToolsBySource(ToolSourceType.MCP, server.id)
        this.clearServerRuntime(server.id)
        continue
      }
      enabledServerIds.push(server.id)
      try {
        await this.refreshServer(server.id, configs)
      } catch (error) {
        console.warn('McpService', `Failed to refresh server ${server.id}: ${JSON.stringify(error)}`)
        failedServers.push(server.name !== '' ? server.name : server.id)
      }
    }

    const registeredMcpTools = this.toolRegistry.getToolsBySource(ToolSourceType.MCP)
    for (let i = 0; i < registeredMcpTools.length; i++) {
      const sourceId = registeredMcpTools[i].config.sourceId
      if (!enabledServerIds.includes(sourceId)) {
        this.toolRegistry.unregisterToolsBySource(ToolSourceType.MCP, sourceId)
        this.clearServerRuntime(sourceId)
      }
    }
    if (failedServers.length > 0) {
      throw new Error(`以下 MCP Server 刷新失败: ${failedServers.join(', ')}`)
    }
  }

  async refreshServer(serverId: string, cachedConfigs?: McpServerConfig[]): Promise<McpDiscoveredTool[]> {
    const configs = cachedConfigs !== undefined ? cachedConfigs : await this.loadServerConfigs()
    const server = this.findServerConfig(configs, serverId)
    if (server === null) {
      this.toolRegistry.unregisterToolsBySource(ToolSourceType.MCP, serverId)
      this.clearServerRuntime(serverId)
      return []
    }
    if (!server.enabled) {
      this.toolRegistry.unregisterToolsBySource(ToolSourceType.MCP, serverId)
      this.clearServerRuntime(serverId)
      return []
    }

    try {
      const discovered = await this.discoverTools(server)
      this.toolRegistry.unregisterToolsBySource(ToolSourceType.MCP, server.id)
      for (let i = 0; i < discovered.length; i++) {
        const tool = this.buildRegisteredTool(server, discovered[i])
        this.toolRegistry.registerTool(tool)
      }
      return discovered
    } catch (error) {
      this.toolRegistry.unregisterToolsBySource(ToolSourceType.MCP, server.id)
      this.clearServerRuntime(server.id)
      throw new Error(`${error}`)
    }
  }

  async callTool(serverId: string, remoteToolName: string, args: string): Promise<string> {
    const server = await this.requireServerConfig(serverId)
    return await this.callToolInternal(server, remoteToolName, args, true)
  }

  private async callToolInternal(
    server: McpServerConfig,
    remoteToolName: string,
    args: string,
    allowRetry: boolean
  ): Promise<string> {
    try {
      const params = new McpToolCallParams()
      params.name = remoteToolName
      params.arguments = this.parseArgumentsObject(args)
      const result = await this.sendJsonRpcRequest(server, 'tools/call', params)
      return this.normalizeToolResult(result)
    } catch (error) {
      const message = `${error}`
      if (allowRetry && message.includes('HTTP 404') && this.sessionIds.has(server.id)) {
        this.clearServerRuntime(server.id)
        await this.initializeSession(server)
        return await this.callToolInternal(server, remoteToolName, args, false)
      }
      throw new Error(message)
    }
  }

  async terminateServerSession(serverId: string): Promise<void> {
    const sessionId = this.sessionIds.get(serverId)
    const server = await this.requireServerConfig(serverId)
    if (sessionId === undefined || sessionId === '') {
      return
    }

    const httpRequest = http.createHttp()
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.DELETE,
        header: this.buildHeaders(server, true),
        connectTimeout: 10000,
        readTimeout: 10000
      }
      await httpRequest.request(server.baseUrl, options)
    } catch (error) {
      console.info('McpService', `Terminate session ignored: ${JSON.stringify(error)}`)
    } finally {
      try {
        httpRequest.destroy()
      } catch (_error) {}
      this.clearServerRuntime(serverId)
    }
  }

  private async discoverTools(server: McpServerConfig): Promise<McpDiscoveredTool[]> {
    await this.initializeSession(server)
    const tools: McpDiscoveredTool[] = []
    let cursor = ''
    do {
      const params = JSON.parse('{}') as Record<string, Object>
      if (cursor !== '') {
        params.cursor = cursor
      }
      const result = await this.sendJsonRpcRequest(server, 'tools/list', params)
      const toolArray = this.readObjectArray(result, 'tools')
      for (let i = 0; i < toolArray.length; i++) {
        const descriptor = this.toToolDescriptor(toolArray[i])
        tools.push(this.toDiscoveredTool(server, descriptor))
      }
      cursor = this.readString(result, 'nextCursor')
    } while (cursor !== '')
    return tools
  }

  private async initializeSession(server: McpServerConfig): Promise<void> {
    if (this.sessionIds.has(server.id)) {
      return
    }

    const initializeParams = new JsonRpcInitializeParams()
    initializeParams.protocolVersion = MCP_PROTOCOL_VERSION
    initializeParams.capabilities = new JsonRpcEmptyObject()
    initializeParams.clientInfo = new JsonRpcClientInfo()
    initializeParams.clientInfo.name = MCP_CLIENT_NAME
    initializeParams.clientInfo.version = MCP_CLIENT_VERSION
    const response = await this.sendJsonRpcRequestWithMeta(server, 'initialize', initializeParams, false)
    const negotiatedVersion = this.readString(response.result, 'protocolVersion', MCP_PROTOCOL_VERSION)
    this.negotiatedProtocolVersions.set(server.id, negotiatedVersion)
    const sessionId = this.readHeader(response.headers, 'mcp-session-id')
    if (sessionId !== '') {
      this.sessionIds.set(server.id, sessionId)
    }
    await this.sendJsonRpcNotification(server, 'notifications/initialized')
  }

  private buildRegisteredTool(server: McpServerConfig, discovered: McpDiscoveredTool): RegisteredTool {
    const parameters = new ToolParameters()
    parameters.setRawSchema(discovered.inputSchema)
    const func = new ToolFunction(
      discovered.functionName,
      discovered.description,
      parameters
    )
    const definition = new ToolDefinition(func)
    const config = new ToolConfig(
      discovered.toolId,
      discovered.displayName,
      discovered.description,
      null,
      true,
      false,
      ToolSourceType.MCP,
      server.id,
      discovered.functionName,
      server.name,
      discovered.permissionLevel
    )
    return new RegisteredTool(
      discovered.toolId,
      config,
      definition,
      new McpToolExecutor(this, server.id, discovered.remoteName)
    )
  }

  private toDiscoveredTool(server: McpServerConfig, descriptor: McpToolDescriptor): McpDiscoveredTool {
    const remoteName = descriptor.name.trim()
    const toolId = `mcp:${server.id}:${remoteName}`
    const functionName = this.buildFunctionName(server.id, remoteName)
    const displayName = this.resolveToolDisplayName(descriptor)
    const description = descriptor.description !== undefined && descriptor.description.trim() !== '' ?
      descriptor.description.trim() : `${displayName} (${server.name})`
    const inputSchema = descriptor.inputSchema !== undefined ? descriptor.inputSchema : this.createEmptyObject()
    return new McpDiscoveredTool(
      toolId,
      functionName,
      remoteName,
      displayName,
      description,
      inputSchema,
      this.inferPermissionLevel(descriptor)
    )
  }

  private inferPermissionLevel(descriptor: McpToolDescriptor): string {
    const annotations = descriptor.annotations
    if (annotations?.destructiveHint === true) {
      return ToolPermissionLevel.WRITE
    }
    if (annotations?.readOnlyHint === true) {
      return ToolPermissionLevel.READ
    }
    const text = `${descriptor.name} ${descriptor.title || ''} ${descriptor.description || ''}`.toLowerCase()
    if (/(^|[^a-z])(create|update|delete|write|edit|modify|save|append|commit|push|publish|upload|insert|remove|rename|move|patch|set|sync)([^a-z]|$)/.test(text)) {
      return ToolPermissionLevel.WRITE
    }
    if (/(^|[^a-z])(get|list|read|search|find|query|fetch|lookup|open|show)([^a-z]|$)/.test(text)) {
      return ToolPermissionLevel.READ
    }
    return ToolPermissionLevel.WRITE
  }

  private buildFunctionName(serverId: string, remoteName: string): string {
    return `mcp__${this.sanitizeFunctionSegment(serverId)}__${this.sanitizeFunctionSegment(remoteName)}__${this.buildStableFunctionSuffix(serverId, remoteName)}`
  }

  private buildStableFunctionSuffix(serverId: string, remoteName: string): string {
    const raw = `${serverId}:${remoteName}`
    let hash = 2166136261
    for (let i = 0; i < raw.length; i++) {
      hash ^= raw.charCodeAt(i)
      hash = Math.imul(hash, 16777619) >>> 0
    }
    return hash.toString(36)
  }

  private resolveToolDisplayName(descriptor: McpToolDescriptor): string {
    if (descriptor.title !== undefined && descriptor.title.trim() !== '') {
      return descriptor.title.trim()
    }
    if (descriptor.annotations?.title !== undefined && descriptor.annotations.title.trim() !== '') {
      return descriptor.annotations.title.trim()
    }
    return descriptor.name
  }

  private sanitizeFunctionSegment(raw: string): string {
    const normalized = raw.toLowerCase().replace(/[^a-z0-9_]+/g, '_').replace(/_+/g, '_').replace(/^_+|_+$/g, '')
    if (normalized === '') {
      return 'tool'
    }
    if (normalized[0] >= '0' && normalized[0] <= '9') {
      return `n_${normalized}`
    }
    return normalized
  }

  private normalizeToolResult(result: Record<string, Object>): string {
    const normalized = new NormalizedMcpToolResult()
    normalized.isError = this.readBoolean(result, 'isError', false)
    const structuredContent = this.readOptionalObject(result, 'structuredContent')
    if (structuredContent !== undefined) {
      normalized.structuredContent = structuredContent
    }
    const content = this.readObjectArray(result, 'content')
    if (content.length > 0) {
      normalized.content = content
      const summary = this.extractTextSummary(content)
      if (summary !== '') {
        normalized.summary = summary
      }
    }
    return JSON.stringify(normalized)
  }

  private extractTextSummary(content: Array<Record<string, Object>>): string {
    const parts: string[] = []
    for (let i = 0; i < content.length; i++) {
      const block = content[i]
      const blockType = this.readString(block, 'type')
      if (blockType === 'text') {
        const text = this.readString(block, 'text')
        if (text !== '') {
          parts.push(text)
        }
      }
    }
    const summary = parts.join('\n').trim()
    if (summary.length <= 400) {
      return summary
    }
    return summary.substring(0, 400) + '...'
  }

  private parseArgumentsObject(args: string): Record<string, Object> {
    if (args.trim() === '') {
      return this.createEmptyRecord()
    }
    try {
      const parsed = JSON.parse(args) as Record<string, Object>
      return parsed
    } catch (error) {
      throw new Error(`工具参数不是合法 JSON: ${JSON.stringify(error)}`)
    }
  }

  private async sendJsonRpcNotification(
    server: McpServerConfig,
    method: string,
    params?: object
  ): Promise<void> {
    const payload = new JsonRpcNotificationRequest()
    payload.jsonrpc = '2.0'
    payload.method = method
    if (params !== undefined) {
      payload.params = params
    }
    const response = await this.sendHttpRequest(server, JSON.stringify(payload), true)
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw new Error(this.buildHttpErrorMessage(response))
    }
  }

  private async sendJsonRpcRequest(
    server: McpServerConfig,
    method: string,
    params?: object
  ): Promise<Record<string, Object>> {
    const response = await this.sendJsonRpcRequestWithMeta(server, method, params, true)
    return response.result
  }

  private async sendJsonRpcRequestWithMeta(
    server: McpServerConfig,
    method: string,
    params?: object,
    includeSessionHeader: boolean = true
  ): Promise<JsonRpcResultWithHeaders> {
    const requestId = `${Date.now()}_${Math.floor(Math.random() * 100000)}`
    const payload = new JsonRpcRequestEnvelope()
    payload.jsonrpc = '2.0'
    payload.id = requestId
    payload.method = method
    if (params !== undefined) {
      payload.params = params
    }

    const response = await this.sendHttpRequest(server, JSON.stringify(payload), includeSessionHeader)
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw new Error(this.buildHttpErrorMessage(response))
    }

    const rpcResponse = this.parseJsonRpcResponse(response, requestId)
    if (rpcResponse.error !== undefined) {
      const code = rpcResponse.error.code !== undefined ? rpcResponse.error.code : 0
      const message = rpcResponse.error.message !== undefined ? rpcResponse.error.message : 'Unknown MCP error'
      throw new Error(`MCP ${method} failed (${code}): ${message}`)
    }
    if (rpcResponse.result === undefined) {
      throw new Error(`MCP ${method} missing result`)
    }
    const result = new JsonRpcResultWithHeaders()
    result.result = rpcResponse.result
    result.headers = response.headers
    return result
  }

  private parseJsonRpcResponse(response: McpHttpResponse, expectedId: string): JsonRpcResponsePayload {
    const contentType = this.readHeader(response.headers, 'content-type')
    if (contentType.includes('text/event-stream') || response.body.includes('\ndata:')) {
      const events = this.parseSsePayloads(response.body)
      for (let i = 0; i < events.length; i++) {
        if (events[i].id === expectedId) {
          return events[i]
        }
      }
      if (events.length > 0) {
        return events[events.length - 1]
      }
      throw new Error('MCP SSE response missing JSON payload')
    }

    return this.parseJsonRpcBody(response.body)
  }

  private parseSsePayloads(body: string): JsonRpcResponsePayload[] {
    const events: JsonRpcResponsePayload[] = []
    const blocks = body.split(/\r?\n\r?\n/)
    for (let i = 0; i < blocks.length; i++) {
      const lines = blocks[i].split(/\r?\n/)
      const dataLines: string[] = []
      for (let j = 0; j < lines.length; j++) {
        if (lines[j].startsWith('data:')) {
          dataLines.push(lines[j].substring(5).trimStart())
        }
      }
      if (dataLines.length === 0) {
        continue
      }
      const payload = dataLines.join('\n').trim()
      if (payload === '') {
        continue
      }
      try {
        events.push(this.parseJsonRpcBody(payload))
      } catch (error) {
        console.warn('McpService', `Failed to parse SSE payload: ${JSON.stringify(error)}`)
      }
    }
    return events
  }

  private parseJsonRpcBody(body: string): JsonRpcResponsePayload {
    const trimmed = body.trim()
    if (trimmed === '') {
      throw new Error('MCP response body is empty')
    }
    const parsed = JSON.parse(trimmed) as Record<string, Object>
    const payload = new JsonRpcResponsePayloadData()
    const idValue = parsed['id']
    if (typeof idValue === 'string' || typeof idValue === 'number') {
      payload.id = idValue
    }
    const result = this.readOptionalRecord(parsed, 'result')
    if (result !== undefined) {
      payload.result = result
    }
    const errorPayload = this.readOptionalJsonRpcError(parsed, 'error')
    if (errorPayload !== undefined) {
      payload.error = errorPayload
    }
    return payload
  }

  private async sendHttpRequest(
    server: McpServerConfig,
    body: string,
    includeSessionHeader: boolean
  ): Promise<McpHttpResponse> {
    const httpRequest = http.createHttp()
    const chunks: Uint8Array[] = []
    let responseHeaders: Record<string, string> = this.createEmptyStringMap()
    let responseCode = -1
    let dataEnded = false

    const finalizeBody = (): string => {
      if (chunks.length === 0) {
        return ''
      }
      let totalLength = 0
      for (let i = 0; i < chunks.length; i++) {
        totalLength += chunks[i].length
      }
      const merged = new Uint8Array(totalLength)
      let offset = 0
      for (let i = 0; i < chunks.length; i++) {
        merged.set(chunks[i], offset)
        offset += chunks[i].length
      }
      const decoder = util.TextDecoder.create('utf-8')
      return decoder.decodeToString(merged, { stream: false })
    }

    try {
      const response = await new Promise<McpHttpResponse>((resolve, reject) => {
        const tryResolve = (): void => {
          if (!dataEnded || responseCode < 0) {
            return
          }
          const result = new McpHttpResponseData()
          result.statusCode = responseCode
          result.headers = responseHeaders
          result.body = finalizeBody()
          resolve(result)
        }

        httpRequest.on('headersReceive', (header: Object) => {
          responseHeaders = this.normalizeHeaders(header)
        })
        httpRequest.on('dataReceive', (chunk: ArrayBuffer) => {
          chunks.push(new Uint8Array(chunk))
        })
        httpRequest.on('dataEnd', () => {
          dataEnded = true
          tryResolve()
        })

        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.POST,
          header: this.buildHeaders(server, includeSessionHeader),
          extraData: body,
          connectTimeout: 15000,
          readTimeout: MCP_DEFAULT_TIMEOUT_MS,
          expectDataType: http.HttpDataType.ARRAY_BUFFER
        }

        httpRequest.requestInStream(server.baseUrl, options).then((code: number) => {
          responseCode = code
          tryResolve()
        }).catch((error: Error) => {
          reject(new Error(HttpService.formatHttpError(error)))
        })
      })
      return response
    } finally {
      try {
        httpRequest.destroy()
      } catch (_error) {}
    }
  }

  private buildHeaders(server: McpServerConfig, includeSessionHeader: boolean): Record<string, string> {
    const headers = this.createEmptyStringMap()
    headers['Content-Type'] = 'application/json'
    headers['Accept'] = 'application/json, text/event-stream'
    headers['MCP-Protocol-Version'] = this.negotiatedProtocolVersions.get(server.id) || MCP_PROTOCOL_VERSION
    if (server.authType === McpAuthType.BEARER && server.authToken.trim() !== '') {
      headers['Authorization'] = `Bearer ${server.authToken.trim()}`
    }
    const customHeaders = this.parseCustomHeaders(server.customHeadersJson)
    const customKeys = Object.keys(customHeaders)
    for (let i = 0; i < customKeys.length; i++) {
      if (this.isManagedHeaderName(customKeys[i])) {
        continue
      }
      headers[customKeys[i]] = customHeaders[customKeys[i]]
    }
    if (includeSessionHeader) {
      const sessionId = this.sessionIds.get(server.id)
      if (sessionId !== undefined && sessionId !== '') {
        headers['Mcp-Session-Id'] = sessionId
      }
    }
    return headers
  }

  private parseCustomHeaders(raw: string): Record<string, string> {
    if (raw.trim() === '') {
      return this.createEmptyStringMap()
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>
      const result = this.createEmptyStringMap()
      const keys = Object.keys(parsed)
      for (let i = 0; i < keys.length; i++) {
        result[keys[i]] = `${parsed[keys[i]]}`
      }
      return result
    } catch (error) {
      console.warn('McpService', `Invalid custom headers JSON ignored: ${JSON.stringify(error)}`)
      return this.createEmptyStringMap()
    }
  }

  private isManagedHeaderName(name: string): boolean {
    const normalizedName = name.trim().toLowerCase()
    return normalizedName === 'content-type' ||
      normalizedName === 'accept' ||
      normalizedName === 'mcp-protocol-version' ||
      normalizedName === 'mcp-session-id' ||
      normalizedName === 'authorization'
  }

  private normalizeHeaders(rawHeaders: Object): Record<string, string> {
    const normalized = this.createEmptyStringMap()
    try {
      const parsed = JSON.parse(JSON.stringify(rawHeaders)) as Record<string, Object>
      const keys = Object.keys(parsed)
      for (let i = 0; i < keys.length; i++) {
        normalized[keys[i].toLowerCase()] = `${parsed[keys[i]]}`
      }
    } catch (_error) {}
    return normalized
  }

  private readHeader(headers: Record<string, string>, key: string): string {
    const lower = key.toLowerCase()
    return headers[lower] !== undefined ? headers[lower] : ''
  }

  private buildHttpErrorMessage(response: McpHttpResponse): string {
    const body = response.body.trim()
    if (body !== '') {
      return `HTTP ${response.statusCode}: ${body}`
    }
    return `HTTP ${response.statusCode}`
  }

  private async requireServerConfig(serverId: string): Promise<McpServerConfig> {
    const configs = await this.loadServerConfigs()
    const server = this.findServerConfig(configs, serverId)
    if (server === null) {
      throw new Error(`MCP server not found: ${serverId}`)
    }
    return server
  }

  private findServerConfig(configs: McpServerConfig[], serverId: string): McpServerConfig | null {
    for (let i = 0; i < configs.length; i++) {
      if (configs[i].id === serverId) {
        configs[i].baseUrl = this.normalizeBaseUrl(configs[i].baseUrl)
        return configs[i]
      }
    }
    return null
  }

  private normalizeBaseUrl(raw: string): string {
    const trimmed = raw.trim()
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1)
    }
    return trimmed
  }

  private clearServerRuntime(serverId: string): void {
    this.sessionIds.delete(serverId)
    this.negotiatedProtocolVersions.delete(serverId)
  }

  private createEmptyObject(): object {
    return JSON.parse('{}') as object
  }

  private createEmptyRecord(): Record<string, Object> {
    return JSON.parse('{}') as Record<string, Object>
  }

  private createEmptyStringMap(): Record<string, string> {
    return JSON.parse('{}') as Record<string, string>
  }

  private parseStringArray(raw: string): string[] {
    if (raw.trim() === '') {
      return []
    }
    try {
      const parsed = JSON.parse(raw) as Object[]
      const result: string[] = []
      for (let i = 0; i < parsed.length; i++) {
        if (typeof parsed[i] === 'string') {
          result.push(parsed[i] as string)
        }
      }
      return result
    } catch (_error) {
      return []
    }
  }

  private toToolDescriptor(raw: Record<string, Object>): McpToolDescriptor {
    const descriptor = new McpToolDescriptorData()
    descriptor.name = this.readString(raw, 'name')
    descriptor.title = this.readString(raw, 'title')
    descriptor.description = this.readString(raw, 'description')
    descriptor.inputSchema = this.readObject(raw, 'inputSchema')
    const annotations = this.readToolAnnotations(raw, 'annotations')
    if (annotations !== undefined) {
      descriptor.annotations = annotations
    }
    return descriptor
  }

  private readToolAnnotations(
    data: Record<string, Object>,
    key: string
  ): McpToolAnnotations | undefined {
    const raw = this.readOptionalRecord(data, key)
    if (raw === undefined) {
      return undefined
    }
    const annotations = new McpToolAnnotationsData()
    if (raw['readOnlyHint'] !== undefined) {
      annotations.readOnlyHint = this.readBoolean(raw, 'readOnlyHint', false)
    }
    if (raw['destructiveHint'] !== undefined) {
      annotations.destructiveHint = this.readBoolean(raw, 'destructiveHint', false)
    }
    const title = this.readString(raw, 'title')
    if (title !== '') {
      annotations.title = title
    }
    return annotations
  }

  private readString(data: Record<string, Object>, key: string, defaultValue: string = ''): string {
    const value = data[key]
    return typeof value === 'string' ? value : defaultValue
  }

  private readBoolean(data: Record<string, Object>, key: string, defaultValue: boolean = false): boolean {
    const value = data[key]
    return typeof value === 'boolean' ? value : defaultValue
  }

  private readObject(data: Record<string, Object>, key: string): object {
    const value = data[key]
    if (value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)) {
      return value as object
    }
    return this.createEmptyObject()
  }

  private readOptionalObject(data: Record<string, Object>, key: string): object | undefined {
    const value = data[key]
    if (value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)) {
      return value as object
    }
    return undefined
  }

  private readOptionalRecord(
    data: Record<string, Object>,
    key: string
  ): Record<string, Object> | undefined {
    const value = data[key]
    if (value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, Object>
    }
    return undefined
  }

  private readOptionalJsonRpcError(
    data: Record<string, Object>,
    key: string
  ): JsonRpcErrorPayload | undefined {
    const raw = this.readOptionalRecord(data, key)
    if (raw === undefined) {
      return undefined
    }
    const error = new JsonRpcErrorPayloadData()
    if (raw['code'] !== undefined && typeof raw['code'] === 'number') {
      error.code = raw['code'] as number
    }
    const message = this.readString(raw, 'message')
    if (message !== '') {
      error.message = message
    }
    return error
  }

  private readObjectArray(data: Record<string, Object>, key: string): Array<Record<string, Object>> {
    const value = data[key]
    if (!Array.isArray(value)) {
      return []
    }
    const result: Array<Record<string, Object>> = []
    for (let i = 0; i < value.length; i++) {
      if (value[i] !== null && typeof value[i] === 'object' && !Array.isArray(value[i])) {
        result.push(value[i] as Record<string, Object>)
      }
    }
    return result
  }
}

export function getMcpService(): McpService {
  return McpService.getInstance()
}
