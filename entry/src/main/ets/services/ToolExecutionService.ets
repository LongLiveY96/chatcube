import {
  ToolApprovalPolicy,
  ToolCall,
  ToolPermissionLevel,
  ToolResult,
  ToolSourceType
} from '../models/ChatModels'
import { getToolRegistry, RegisteredTool, ToolRegistry } from './ToolRegistry'
import {
  ASK_USER_TOOL_ID,
  LEGACY_WEB_SEARCH_TOOL_ID,
  SCRAPE_WEB_TOOL_ID,
  SEARCH_WEB_TOOL_ID,
  isAskUserFunctionName,
  isScrapeWebFunctionName,
  isSearchWebFunctionName
} from '../utils/SearchToolIdentityUtils'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { setAppUiStateValue } from '../state/AppUiState'

// 取消检查回调类型
type CancelCheckCallback = () => boolean
export type PendingToolInteractionChangeCallback = () => void

export enum PendingToolInteractionKind {
  APPROVAL = 'approval',
  ASK_USER = 'ask_user'
}

export class ToolExecutionContext {
  sessionId: string
  sessionTitle: string

  constructor(sessionId: string = '', sessionTitle: string = '') {
    this.sessionId = sessionId
    this.sessionTitle = sessionTitle
  }
}

// 待确认/待答复的工具交互快照。
//
// 注意:
// - 这些快照只存在内存里 (pendingApprovals / pendingAnswers Map)。
// - App 进程被系统杀死或主动 kill 后, 内存里的 Promise resolver 与 HTTP 流都会一起丢失,
//   下次冷启动只能依赖 ChatPage.fixInconsistentState + RUNNING_CHAT_TASK_COUNT 把残留的
//   isGenerating / isSearching 状态重置, 从用户视角等同于"任务中断"。
// - 不要试图用 Preferences 持久化这里的 resolver, resolver 跨进程没有意义。
// - sourceType / permissionLevel 之所以写成 string 而不是 enum, 是因为 ChatModels.ToolCall /
//   ToolConfig 里这两个字段就是 string 类型(历史选择, 整改要触及全工程, 这里跟随上游)。
//   通过 ToolSourceType / ToolPermissionLevel 比较时仍然是字符串相等, 不影响语义。
export class PendingToolInteractionSnapshot {
  id: string = ''
  kind: PendingToolInteractionKind = PendingToolInteractionKind.APPROVAL
  sessionId: string = ''
  sessionTitle: string = ''
  toolId: string = ''
  toolName: string = ''
  sourceLabel: string = ''
  sourceType: string = ToolSourceType.BUILTIN
  sourceId: string = ''
  permissionLevel: string = ToolPermissionLevel.READ
  argumentsJson: string = ''
  createdAt: number = 0
}

// 工具结果是否被取消的语义化判定结果, 取代裸 JSON 检查。
export class CancelledToolResultInfo {
  cancelled: boolean = false
  // 取消时希望透传给用户的简短文案, 取消标志为 false 时无意义。
  reason: string = ''
}

// 解析单条 ToolResult 是否被取消, 取消时同时透出原因字符串。
//
// 之前是用 `content.includes('"cancelled":true')` 这种字符串子串匹配, 模型把 cancelled 拼到
// 普通业务字段里就会误判。这里改走 JSON.parse + Object 索引访问, 失败时按"未取消"处理。
export function isCancelledToolResult(result: ToolResult): CancelledToolResultInfo {
  const info = new CancelledToolResultInfo()
  const content = result.content.trim()
  if (content === '') {
    return info
  }
  let parsed: Object | null = null
  try {
    parsed = JSON.parse(content) as Object
  } catch (_error) {
    return info
  }
  if (parsed === null || typeof parsed !== 'object') {
    return info
  }
  const record = parsed as Record<string, Object>
  const cancelledRaw = record['cancelled']
  if (cancelledRaw !== true) {
    return info
  }
  info.cancelled = true
  const errorRaw = record['error']
  if (typeof errorRaw === 'string') {
    info.reason = (errorRaw as string).trim()
  }
  return info
}

class PendingToolApprovalRuntime {
  snapshot: PendingToolInteractionSnapshot
  resolve: (approved: boolean) => void

  constructor(snapshot: PendingToolInteractionSnapshot, resolve: (approved: boolean) => void) {
    this.snapshot = snapshot
    this.resolve = resolve
  }
}

class PendingToolAnswerRuntime {
  snapshot: PendingToolInteractionSnapshot
  resolve: (answerJson: string | null) => void

  constructor(snapshot: PendingToolInteractionSnapshot, resolve: (answerJson: string | null) => void) {
    this.snapshot = snapshot
    this.resolve = resolve
  }
}

// 工具执行服务 - 负责执行工具调用
export class ToolExecutionService {
  private static instance: ToolExecutionService | null = null
  private registry: ToolRegistry
  // 当前取消检查回调
  private cancelCheckCallback: CancelCheckCallback | null = null
  private pendingApprovals: Map<string, PendingToolApprovalRuntime> = new Map()
  private pendingAnswers: Map<string, PendingToolAnswerRuntime> = new Map()
  private pendingInteractionChangeCallbacks: PendingToolInteractionChangeCallback[] = []

  private constructor() {
    this.registry = getToolRegistry()
  }

  static getInstance(): ToolExecutionService {
    if (ToolExecutionService.instance === null) {
      ToolExecutionService.instance = new ToolExecutionService()
    }
    return ToolExecutionService.instance
  }

  // 设置取消检查回调
  setCancelCheckCallback(callback: CancelCheckCallback | null): void {
    this.cancelCheckCallback = callback
  }

  // 清除取消检查回调
  clearCancelCheckCallback(): void {
    this.cancelCheckCallback = null
  }

  // 检查是否已取消
  private isCancelled(): boolean {
    if (this.cancelCheckCallback !== null) {
      return this.cancelCheckCallback()
    }
    return false
  }

  private publishPendingInteractionChanged(): void {
    setAppUiStateValue(AppStorageKeys.PENDING_TOOL_INTERACTION_TICK, Date.now())
    const callbacks = this.pendingInteractionChangeCallbacks.slice()
    for (let i = 0; i < callbacks.length; i++) {
      callbacks[i]()
    }
  }

  addPendingInteractionChangeCallback(callback: PendingToolInteractionChangeCallback): () => void {
    this.pendingInteractionChangeCallbacks.push(callback)
    return (): void => {
      const index = this.pendingInteractionChangeCallbacks.indexOf(callback)
      if (index >= 0) {
        this.pendingInteractionChangeCallbacks.splice(index, 1)
      }
    }
  }

  private clonePendingSnapshot(snapshot: PendingToolInteractionSnapshot): PendingToolInteractionSnapshot {
    const cloned = new PendingToolInteractionSnapshot()
    cloned.id = snapshot.id
    cloned.kind = snapshot.kind
    cloned.sessionId = snapshot.sessionId
    cloned.sessionTitle = snapshot.sessionTitle
    cloned.toolId = snapshot.toolId
    cloned.toolName = snapshot.toolName
    cloned.sourceLabel = snapshot.sourceLabel
    cloned.sourceType = snapshot.sourceType
    cloned.sourceId = snapshot.sourceId
    cloned.permissionLevel = snapshot.permissionLevel
    cloned.argumentsJson = snapshot.argumentsJson
    cloned.createdAt = snapshot.createdAt
    return cloned
  }

  private buildApprovalSnapshot(
    toolCall: ToolCall,
    tool: RegisteredTool,
    context: ToolExecutionContext
  ): PendingToolInteractionSnapshot {
    const snapshot = new PendingToolInteractionSnapshot()
    snapshot.id = toolCall.id
    snapshot.kind = PendingToolInteractionKind.APPROVAL
    snapshot.sessionId = context.sessionId
    snapshot.sessionTitle = context.sessionTitle
    snapshot.toolId = tool.config.id
    snapshot.toolName = tool.config.name
    snapshot.sourceLabel = tool.config.sourceLabel
    snapshot.sourceType = tool.config.sourceType
    snapshot.sourceId = tool.config.sourceId
    snapshot.permissionLevel = tool.config.permissionLevel
    snapshot.argumentsJson = toolCall.arguments
    snapshot.createdAt = Date.now()
    return snapshot
  }

  private buildAskUserSnapshot(toolCall: ToolCall, context: ToolExecutionContext): PendingToolInteractionSnapshot {
    const snapshot = new PendingToolInteractionSnapshot()
    snapshot.id = toolCall.id
    snapshot.kind = PendingToolInteractionKind.ASK_USER
    snapshot.sessionId = context.sessionId
    snapshot.sessionTitle = context.sessionTitle
    snapshot.toolId = ASK_USER_TOOL_ID
    snapshot.toolName = toolCall.displayName
    snapshot.sourceLabel = toolCall.sourceLabel
    snapshot.sourceType = toolCall.sourceType
    snapshot.sourceId = ''
    snapshot.permissionLevel = toolCall.permissionLevel
    snapshot.argumentsJson = toolCall.arguments
    snapshot.createdAt = Date.now()
    return snapshot
  }

  getPendingInteractionForSession(sessionId: string): PendingToolInteractionSnapshot | null {
    if (sessionId === '') {
      return null
    }
    let found: PendingToolInteractionSnapshot | null = null
    this.pendingApprovals.forEach((runtime: PendingToolApprovalRuntime) => {
      if (found === null && runtime.snapshot.sessionId === sessionId) {
        found = this.clonePendingSnapshot(runtime.snapshot)
      }
    })
    if (found !== null) {
      return found
    }
    this.pendingAnswers.forEach((runtime: PendingToolAnswerRuntime) => {
      if (found === null && runtime.snapshot.sessionId === sessionId) {
        found = this.clonePendingSnapshot(runtime.snapshot)
      }
    })
    return found
  }

  getFirstPendingInteraction(): PendingToolInteractionSnapshot | null {
    const snapshots = this.getPendingInteractions()
    return snapshots.length > 0 ? snapshots[0] : null
  }

  getPendingInteractions(): PendingToolInteractionSnapshot[] {
    const interactions: PendingToolInteractionSnapshot[] = []
    this.pendingApprovals.forEach((runtime: PendingToolApprovalRuntime) => {
      interactions.push(this.clonePendingSnapshot(runtime.snapshot))
    })
    this.pendingAnswers.forEach((runtime: PendingToolAnswerRuntime) => {
      interactions.push(this.clonePendingSnapshot(runtime.snapshot))
    })
    return interactions
  }

  hasPendingInteractionForSession(sessionId: string): boolean {
    return this.getPendingInteractionForSession(sessionId) !== null
  }

  resolvePendingApproval(toolCallId: string, approved: boolean): boolean {
    const runtime = this.pendingApprovals.get(toolCallId)
    if (runtime === undefined) {
      return false
    }
    this.pendingApprovals.delete(toolCallId)
    runtime.resolve(approved)
    this.publishPendingInteractionChanged()
    return true
  }

  resolvePendingAnswer(toolCallId: string, answerJson: string | null): boolean {
    const runtime = this.pendingAnswers.get(toolCallId)
    if (runtime === undefined) {
      return false
    }
    this.pendingAnswers.delete(toolCallId)
    runtime.resolve(answerJson)
    this.publishPendingInteractionChanged()
    return true
  }

  cancelPendingInteractionsForSession(sessionId: string): void {
    if (sessionId === '') {
      return
    }
    const approvalIds: string[] = []
    this.pendingApprovals.forEach((runtime: PendingToolApprovalRuntime, key: string) => {
      if (runtime.snapshot.sessionId === sessionId) {
        approvalIds.push(key)
      }
    })
    for (let i = 0; i < approvalIds.length; i++) {
      this.resolvePendingApproval(approvalIds[i], false)
    }

    const answerIds: string[] = []
    this.pendingAnswers.forEach((runtime: PendingToolAnswerRuntime, key: string) => {
      if (runtime.snapshot.sessionId === sessionId) {
        answerIds.push(key)
      }
    })
    for (let i = 0; i < answerIds.length; i++) {
      this.resolvePendingAnswer(answerIds[i], null)
    }
  }

  // 全局拒绝并清空所有 pending 工具交互。
  // 仅在 ChatViewModel.stopGeneration() 全局停止路径里调用, 与逐 session 调用相比少一次
  // 通过 activeRequests 反推 sessionId 的间接路径, 也避免漏掉 activeRequests 已被清空但
  // pending 还在的边界场景。
  cancelAllPendingInteractions(): void {
    const approvalIds: string[] = []
    this.pendingApprovals.forEach((_runtime: PendingToolApprovalRuntime, key: string) => {
      approvalIds.push(key)
    })
    for (let i = 0; i < approvalIds.length; i++) {
      this.resolvePendingApproval(approvalIds[i], false)
    }

    const answerIds: string[] = []
    this.pendingAnswers.forEach((_runtime: PendingToolAnswerRuntime, key: string) => {
      answerIds.push(key)
    })
    for (let i = 0; i < answerIds.length; i++) {
      this.resolvePendingAnswer(answerIds[i], null)
    }
  }

  private normalizeFunctionName(functionName: string): string {
    const rawName = functionName as string | null | undefined
    if (rawName === undefined || rawName === null) {
      return ''
    }
    return rawName.trim()
  }

  private resolveToolId(functionName: string): string | undefined {
    if (functionName !== '') {
      const direct = this.registry.getToolIdByFunctionName(functionName)
      if (direct !== undefined) {
        return direct
      }
    }

    if (isScrapeWebFunctionName(functionName) && this.registry.isToolRegistered(SCRAPE_WEB_TOOL_ID)) {
      return SCRAPE_WEB_TOOL_ID
    }

    if (isSearchWebFunctionName(functionName)) {
      if (this.registry.isToolRegistered(SEARCH_WEB_TOOL_ID)) {
        return SEARCH_WEB_TOOL_ID
      }
      if (this.registry.isToolRegistered(LEGACY_WEB_SEARCH_TOOL_ID)) {
        return LEGACY_WEB_SEARCH_TOOL_ID
      }
    }
    return undefined
  }

  private buildCancelledResult(toolCall: ToolCall, displayName: string, sourceLabel: string): ToolResult {
    return new ToolResult(
      toolCall.id,
      JSON.stringify({ error: '工具执行已取消', cancelled: true }),
      true,
      displayName,
      sourceLabel
    )
  }

  private async requestApprovalIfNeeded(
    toolCall: ToolCall,
    tool: RegisteredTool,
    context: ToolExecutionContext
  ): Promise<boolean> {
    if (tool.config.sourceType === ToolSourceType.MCP) {
      if (tool.config.approvalPolicy === ToolApprovalPolicy.ALWAYS_ALLOW) {
        toolCall.approvalState = 'auto'
        toolCall.approvalReason = 'always_allow'
        return true
      }
      return await this.requestManualApproval(toolCall, tool, context)
    }

    if (tool.config.permissionLevel !== 'write') {
      toolCall.approvalState = 'auto'
      return true
    }

    return await this.requestManualApproval(toolCall, tool, context)
  }

  private async requestManualApproval(
    toolCall: ToolCall,
    tool: RegisteredTool,
    context: ToolExecutionContext
  ): Promise<boolean> {
    toolCall.approvalState = 'pending'
    try {
      const approved = await new Promise<boolean>((resolve) => {
        const existing = this.pendingApprovals.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(false)
          this.pendingApprovals.delete(toolCall.id)
        }
        const snapshot = this.buildApprovalSnapshot(toolCall, tool, context)
        this.pendingApprovals.set(toolCall.id, new PendingToolApprovalRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
      toolCall.approvalState = approved ? 'approved' : 'denied'
      return approved
    } catch (error) {
      console.error('ToolExecutionService', `Approval callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return false
    }
  }

  // ask_user 特殊路径: 不走通用 executor, 挂起等待 UI 层 (AskUserCard) 的回答,
  // 拿到 answerJson 后直接作为 ToolResult 返回; 用户取消/页面销毁则按 denied 处理。
  private async handleAskUser(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    // 用 ASK_USER_TOOL_ID 回填, 保证工具卡片/消息事件按统一 id 识别
    toolCall.toolId = ASK_USER_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '向用户提问'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    // 标记为 pending, UI (AskUserCard) 据此判断是否可交互
    toolCall.approvalState = 'pending'

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `ask_user answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `ask_user 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    // 执行期间被取消 (例如用户在 AskUserCard 外按了停止)
    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'ask_user cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '用户未回答该问题' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    // 标记为已回答, 答案 JSON 既写入 approvalReason (UI 显示)也作为 tool_result 回传给模型
    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `ask_user answered: ${toolCall.id}`)
    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // 执行单个工具调用
  async executeToolCall(
    toolCall: ToolCall,
    context: ToolExecutionContext = new ToolExecutionContext()
  ): Promise<ToolResult> {
    console.info('ToolExecutionService', `Executing tool call: ${toolCall.functionName} (${toolCall.id})`)

    // 检查是否已取消
    if (this.isCancelled()) {
      console.info('ToolExecutionService', `Tool execution cancelled: ${toolCall.functionName}`)
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    const normalizedFunctionName = this.normalizeFunctionName(toolCall.functionName)

    // === ask_user 特殊路径 ===
    // 人机交互工具, 不走通用 executor 和 write 审批 sheet, 由 AskUserCard 直接收集答案。
    if (isAskUserFunctionName(normalizedFunctionName)) {
      return await this.handleAskUser(toolCall, context)
    }

    // 通过函数名获取工具 ID
    const toolId = this.resolveToolId(normalizedFunctionName)
    if (toolId === undefined) {
      const displayName = normalizedFunctionName !== '' ? normalizedFunctionName : 'null'
      console.error('ToolExecutionService', `Tool not found: ${displayName}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `未知工具: ${displayName}` }),
        true,
        displayName,
        toolCall.sourceLabel
      )
    }

    const registeredTool = this.registry.getTool(toolId)
    if (registeredTool === undefined) {
      console.error('ToolExecutionService', `Registered tool not found: ${toolId}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `工具未注册: ${toolId}` }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.toolId = registeredTool.id
    toolCall.displayName = registeredTool.config.name
    toolCall.sourceType = registeredTool.config.sourceType
    toolCall.sourceLabel = registeredTool.config.sourceLabel
    toolCall.permissionLevel = registeredTool.config.permissionLevel
    toolCall.approvalPolicy = registeredTool.config.approvalPolicy

    const approved = await this.requestApprovalIfNeeded(toolCall, registeredTool, context)
    if (!approved) {
      const denialMessage = toolCall.approvalReason.trim() !== '' ? toolCall.approvalReason : '用户拒绝了工具调用'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: denialMessage, cancelled: true }),
        true,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
    }

    // 获取工具执行器
    const executor = this.registry.getToolExecutor(toolId)
    if (executor === undefined) {
      console.error('ToolExecutionService', `Executor not found for tool: ${toolId}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `工具执行器未找到: ${toolId}` }),
        true,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
    }

    try {
      // 执行工具
      const startTime = Date.now()
      const result = await executor.execute(toolCall.arguments)

      // 执行完成后再次检查是否取消（避免返回已取消的结果）
      if (this.isCancelled()) {
        console.info('ToolExecutionService', `Tool execution cancelled after completion: ${toolCall.functionName}`)
        return this.buildCancelledResult(toolCall, registeredTool.config.name, registeredTool.config.sourceLabel)
      }

      const duration = Date.now() - startTime
      console.info('ToolExecutionService', `Tool ${toolCall.functionName} completed in ${duration}ms`)

      let isError = false
      try {
        const parsed = JSON.parse(result) as Record<string, Object>
        isError = parsed.isError === true || parsed.error !== undefined
      } catch (_error) {}

      return new ToolResult(
        toolCall.id,
        result,
        isError,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
    } catch (error) {
      console.error('ToolExecutionService', `Tool execution error: ${JSON.stringify(error)}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `工具执行失败: ${JSON.stringify(error)}` }),
        true,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
    }
  }

  // 批量执行工具调用（串行，避免多个确认框并发弹出）
  async executeToolCalls(
    toolCalls: ToolCall[],
    context: ToolExecutionContext = new ToolExecutionContext()
  ): Promise<ToolResult[]> {
    console.info('ToolExecutionService', `Executing ${toolCalls.length} tool calls`)

    // 检查是否已取消
    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'Tool execution cancelled before batch execution')
      return toolCalls.map(tc => new ToolResult(
        tc.id,
        JSON.stringify({ error: '工具执行已取消', cancelled: true }),
        true,
        tc.displayName,
        tc.sourceLabel
      ))
    }

    const results: ToolResult[] = []
    for (let i = 0; i < toolCalls.length; i++) {
      results.push(await this.executeToolCall(toolCalls[i], context))
    }
    return results
  }

  // 检查工具是否可用
  isToolAvailable(functionName: string): boolean {
    const normalizedFunctionName = this.normalizeFunctionName(functionName)
    const toolId = this.resolveToolId(normalizedFunctionName)
    return toolId !== undefined
  }
}

// 导出单例实例获取方法
export function getToolExecutionService(): ToolExecutionService {
  return ToolExecutionService.getInstance()
}
