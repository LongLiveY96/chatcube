import { ToolCall, ToolResult } from '../models/ChatModels'
import { getToolRegistry, ToolRegistry } from './ToolRegistry'

// 取消检查回调类型
type CancelCheckCallback = () => boolean

// 工具执行服务 - 负责执行工具调用
export class ToolExecutionService {
  private static instance: ToolExecutionService | null = null
  private registry: ToolRegistry
  // 当前取消检查回调
  private cancelCheckCallback: CancelCheckCallback | null = null

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

    const normalized = functionName.toLowerCase().replace(/[\s\-]+/g, '_')
    if ((normalized === 'exa_search' || normalized === 'websearch' || normalized === 'search_web'
      || normalized === 'internet_search' || normalized === 'web_search_exa')
      && this.registry.isToolRegistered('web_search')) {
      return 'web_search'
    }
    if ((normalized === 'weather' || normalized === 'weather_search' || normalized === 'get_weather'
      || normalized === 'query_weather' || normalized === 'weather_lookup')
      && this.registry.isToolRegistered('weather_query')) {
      return 'weather_query'
    }

    if (this.registry.getToolCount() === 1) {
      const ids = this.registry.getAllToolIds()
      if (ids.length === 1) {
        console.warn('ToolExecutionService', `Fallback to single registered tool: ${ids[0]}, raw function: ${functionName}`)
        return ids[0]
      }
    }
    return undefined
  }

  // 执行单个工具调用
  async executeToolCall(toolCall: ToolCall): Promise<ToolResult> {
    console.info('ToolExecutionService', `Executing tool call: ${toolCall.functionName} (${toolCall.id})`)

    // 检查是否已取消
    if (this.isCancelled()) {
      console.info('ToolExecutionService', `Tool execution cancelled: ${toolCall.functionName}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: '工具执行已取消', cancelled: true })
      )
    }

    const normalizedFunctionName = this.normalizeFunctionName(toolCall.functionName)
    // 通过函数名获取工具 ID
    const toolId = this.resolveToolId(normalizedFunctionName)
    if (toolId === undefined) {
      const displayName = normalizedFunctionName !== '' ? normalizedFunctionName : 'null'
      console.error('ToolExecutionService', `Tool not found: ${displayName}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `未知工具: ${displayName}` })
      )
    }
    if (toolCall.functionName !== toolId && (toolId === 'web_search' || toolId === 'weather_query')) {
      toolCall.functionName = toolId
    }

    // 获取工具执行器
    const executor = this.registry.getToolExecutor(toolId)
    if (executor === undefined) {
      console.error('ToolExecutionService', `Executor not found for tool: ${toolId}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `工具执行器未找到: ${toolId}` })
      )
    }

    try {
      // 执行工具
      const startTime = Date.now()
      const result = await executor.execute(toolCall.arguments)

      // 执行完成后再次检查是否取消（避免返回已取消的结果）
      if (this.isCancelled()) {
        console.info('ToolExecutionService', `Tool execution cancelled after completion: ${toolCall.functionName}`)
        return new ToolResult(
          toolCall.id,
          JSON.stringify({ error: '工具执行已取消', cancelled: true })
        )
      }

      const duration = Date.now() - startTime
      console.info('ToolExecutionService', `Tool ${toolCall.functionName} completed in ${duration}ms`)

      return new ToolResult(toolCall.id, result)
    } catch (error) {
      console.error('ToolExecutionService', `Tool execution error: ${JSON.stringify(error)}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `工具执行失败: ${JSON.stringify(error)}` })
      )
    }
  }

  // 批量执行工具调用（并行）
  async executeToolCalls(toolCalls: ToolCall[]): Promise<ToolResult[]> {
    console.info('ToolExecutionService', `Executing ${toolCalls.length} tool calls`)

    // 检查是否已取消
    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'Tool execution cancelled before batch execution')
      return toolCalls.map(tc => new ToolResult(
        tc.id,
        JSON.stringify({ error: '工具执行已取消', cancelled: true })
      ))
    }

    const promises: Promise<ToolResult>[] = []
    for (let i = 0; i < toolCalls.length; i++) {
      promises.push(this.executeToolCall(toolCalls[i]))
    }

    const results = await Promise.all(promises)
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
