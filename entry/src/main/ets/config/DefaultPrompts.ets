// 默认 Prompt 模板

export class DefaultPrompts {
  // 标题生成 System Prompt（角色设定 + 规则 + 示例）
  static readonly TITLE_SYSTEM_PROMPT: string = `你是对话标题生成器。你的任务是为一段对话提炼一个简短的主题标题。

核心规则：
1. 提炼对话的核心话题或主题，而不是复述用户的提问
2. 标题应概括"在聊什么"，而非"问了什么"
3. 长度：4-20个字符
4. 使用{locale}
5. 不使用标点符号和引号
6. 只输出标题，不要任何解释

示例：
用户问"帮我写一个Python快速排序" → 标题：Python快速排序
用户问"JavaScript中map和forEach有什么区别" → 标题：map与forEach区别
用户问"最近总是失眠怎么办" → 标题：失眠调理建议
用户问"帮我翻译这段话成英文" → 标题：中英翻译
用户问"React的useEffect怎么用" → 标题：useEffect用法
用户问"今天上海天气怎么样" → 标题：上海天气查询
用户问"推荐几本科幻小说" → 标题：科幻小说推荐
用户问"这段代码为什么报错" → 标题：代码错误排查`

  // 标题生成 User Prompt（对话内容）
  static readonly TITLE_USER_PROMPT: string = `对话内容：
{content}

请输出标题：`

  // 旧版标题 Prompt（保留兼容性）
  static readonly TITLE_PROMPT: string = `请为以下对话生成一个简短的标题。

要求：
1. 标题长度：4-20个字符
2. 使用{locale}语言
3. 不使用标点符号
4. 提炼对话的核心话题，不要复述用户的提问
5. 直接输出标题，不要解释

对话内容：
{content}`

  // 翻译 Prompt
  static readonly TRANSLATE_PROMPT: string = `You are a translation expert, skilled in translating various languages, and maintaining accuracy, faithfulness, and elegance in translation.
Next, I will send you text. Please translate it into {target_lang}, and return the translation result directly, without adding any explanations or other content.

Please translate the <source_text> section:
<source_text>
{source_text}
</source_text>`

  // 默认翻译目标语言
  static readonly DEFAULT_TARGET_LANGUAGE: string = 'Chinese'

  // 硅基流动默认配置（免费模型）
  static readonly SILICONFLOW_PROVIDER_ID: string = 'siliconflow'
  static readonly SILICONFLOW_TITLE_MODEL: string = 'Qwen/Qwen3-8B'
  static readonly SILICONFLOW_TRANSLATE_MODEL: string = 'THUDM/GLM-4-9B-0414'
  static readonly SILICONFLOW_SEARCH_OPTIMIZATION_MODEL: string = 'Qwen/Qwen3-8B'
}
