import { ToolDefinition, ToolConfig, ToolParameters } from '../models/ChatModels'

// 工具执行器接口
export interface ToolExecutor {
  execute(args: string): Promise<string>
}

// 已注册工具
export class RegisteredTool {
  id: string = ''                    // 工具 ID
  config: ToolConfig                 // 工具配置（UI 显示用）
  definition: ToolDefinition         // 工具定义（API 请求用）
  executor: ToolExecutor             // 工具执行器

  constructor(
    id: string,
    config: ToolConfig,
    definition: ToolDefinition,
    executor: ToolExecutor
  ) {
    this.id = id
    this.config = config
    this.definition = definition
    this.executor = executor
  }
}

// 工具注册表 - 管理所有可用工具
export class ToolRegistry {
  private static instance: ToolRegistry | null = null
  private tools: Map<string, RegisteredTool> = new Map()

  private constructor() {}

  static getInstance(): ToolRegistry {
    if (ToolRegistry.instance === null) {
      ToolRegistry.instance = new ToolRegistry()
    }
    return ToolRegistry.instance
  }

  // 注册工具
  registerTool(tool: RegisteredTool): void {
    this.tools.set(tool.id, tool)
    console.info('ToolRegistry', `Registered tool: ${tool.id}`)
  }

  // 注销工具
  unregisterTool(toolId: string): void {
    this.tools.delete(toolId)
    console.info('ToolRegistry', `Unregistered tool: ${toolId}`)
  }

  // 获取工具
  getTool(toolId: string): RegisteredTool | undefined {
    return this.tools.get(toolId)
  }

  // 获取工具定义（用于 API 请求）
  getToolDefinition(toolId: string): ToolDefinition | undefined {
    const tool = this.tools.get(toolId)
    if (tool !== undefined) {
      return tool.definition
    }
    return undefined
  }

  // 获取工具执行器
  getToolExecutor(toolId: string): ToolExecutor | undefined {
    const tool = this.tools.get(toolId)
    if (tool !== undefined) {
      return tool.executor
    }
    return undefined
  }

  // 获取所有已注册工具的配置（用于 UI 显示）
  getAllToolConfigs(): ToolConfig[] {
    const configs: ToolConfig[] = []
    this.tools.forEach((tool) => {
      configs.push(tool.config)
    })
    return configs
  }

  // 获取所有已注册工具的 ID
  getAllToolIds(): string[] {
    const ids: string[] = []
    this.tools.forEach((tool) => {
      ids.push(tool.id)
    })
    return ids
  }

  // 根据启用状态获取工具定义列表
  getEnabledToolDefinitions(enabledToolIds: string[]): ToolDefinition[] {
    const definitions: ToolDefinition[] = []
    for (let i = 0; i < enabledToolIds.length; i++) {
      const toolId = enabledToolIds[i]
      const tool = this.tools.get(toolId)
      if (tool !== undefined) {
        definitions.push(tool.definition)
      }
    }
    return definitions
  }

  // 检查工具是否已注册
  isToolRegistered(toolId: string): boolean {
    return this.tools.has(toolId)
  }

  // 获取已注册工具数量
  getToolCount(): number {
    return this.tools.size
  }

  // 通过函数名获取工具 ID
  getToolIdByFunctionName(functionName: string): string | undefined {
    let foundId: string | undefined = undefined
    this.tools.forEach((tool, id) => {
      if (tool.definition.function.name === functionName) {
        foundId = id
      }
    })
    return foundId
  }
}

// 导出单例实例获取方法
export function getToolRegistry(): ToolRegistry {
  return ToolRegistry.getInstance()
}
