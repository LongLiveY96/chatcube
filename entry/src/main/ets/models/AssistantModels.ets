import { DEFAULT_PRIMARY_COLOR } from '../config/ThemeDefaults'

export const DEFAULT_ASSISTANT_ID: string = 'default'

@ObservedV2
export class Assistant {
  @Trace id: string = ''
  @Trace name: string = ''
  @Trace avatarSymbol: string = ''
  @Trace color: string = ''
  @Trace systemPrompt: string = ''
  @Trace defaultProviderId: string = ''
  @Trace defaultModelId: string = ''
  @Trace defaultModelName: string = ''
  @Trace temperatureEnabled: boolean = false
  @Trace temperature: number = 0.7
  @Trace topPEnabled: boolean = false
  @Trace topP: number = 1.0
  @Trace presencePenaltyEnabled: boolean = false
  @Trace presencePenalty: number = 0
  @Trace frequencyPenaltyEnabled: boolean = false
  @Trace frequencyPenalty: number = 0
  // 上下文消息数量限制。0 = 不限制,发送全部历史;>0 = 仅发送最近 N 条消息
  @Trace contextMessageCount: number = 0
  // 最大输出 token 数。
  // 0 = "无限制",请求时不下发对应字段(max_tokens / max_output_tokens / maxOutputTokens),
  //   让模型按自身上限输出;Anthropic Claude 强制要求该字段时会在 AIApiService 内兜底 64_000。
  // >0 = 限制模型输出长度,请求时显式下发该值。
  @Trace maxOutputTokens: number = 0
  // 助手专属工具白名单。空数组 = 不设边界(继承全局所有工具);
  // 非空 = 仅允许列出的 toolId。搜索工具不在此白名单内(走独立 webSearch 通道)。
  @Trace enabledToolIds: string[] = []
  @Trace isDefault: boolean = false
  @Trace createdAt: number = 0
  @Trace updatedAt: number = 0
  @Trace sortOrder: number = 0

  constructor(id: string = '', name: string = '') {
    const now = Date.now()
    this.id = id
    this.name = name
    this.avatarSymbol = 'AI'
    this.color = DEFAULT_PRIMARY_COLOR
    this.systemPrompt = ''
    this.defaultProviderId = ''
    this.defaultModelId = ''
    this.defaultModelName = ''
    this.temperatureEnabled = false
    this.temperature = 0.7
    this.topPEnabled = false
    this.topP = 1.0
    this.presencePenaltyEnabled = false
    this.presencePenalty = 0
    this.frequencyPenaltyEnabled = false
    this.frequencyPenalty = 0
    this.contextMessageCount = 0
    this.maxOutputTokens = 0
    this.enabledToolIds = []
    this.isDefault = id === DEFAULT_ASSISTANT_ID
    this.createdAt = now
    this.updatedAt = now
    this.sortOrder = this.isDefault ? 0 : now
  }
}

export function createDefaultAssistant(): Assistant {
  const assistant = new Assistant(DEFAULT_ASSISTANT_ID, '默认助手')
  assistant.avatarSymbol = 'AI'
  assistant.color = DEFAULT_PRIMARY_COLOR
  assistant.isDefault = true
  assistant.sortOrder = 0
  return assistant
}
