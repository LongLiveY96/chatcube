/**
 * AskUserCard - ask_user 工具专属 UI
 *
 * 解析 toolCall.arguments 里的 questions, 按 selection_type 渲染:
 *  - 'single': FilterChip 单选(不含自由文本)
 *  - 'multi':  多个 chip 可多选
 *  - 'text' / 其他: 选项 chip(可选) + 自由文本 input
 * 多个问题依次排列, 底部一个提交按钮, 点击后以 JSON 回传 { answers: { qid: answer } }。
 *
 * 本版只做 UI 骨架: onAnswer 回调由 ChatPage/ChatViewModel 接入到 ToolExecutionService 审批流程。
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'

interface AskUserQuestion {
  id: string
  question: string
  options: string[]
  selectionType: string
}

interface AskUserArgs {
  questions?: Object[]
}

@ComponentV2
export struct AskUserCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  // 提交回调, ChatPage 里转发到 ToolExecutionService 的 approval/answer 流程
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  // key: question id -> 已选/已输入答案(单选和 text 用 string, multi 用 "a, b" 逗号拼接)
  @Local textAnswers: Map<string, string> = new Map()
  @Local multiAnswers: Map<string, Set<string>> = new Map()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private parseQuestions(): AskUserQuestion[] {
    const out: AskUserQuestion[] = []
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as AskUserArgs
      const rawQs = parsed.questions
      if (!Array.isArray(rawQs)) {
        return out
      }
      const list = rawQs as Object[]
      for (let i = 0; i < list.length; i++) {
        const obj = list[i] as Record<string, Object>
        if (obj === null || obj === undefined) {
          continue
        }
        const id = (obj['id'] as string | undefined) ?? `q_${i}`
        const question = (obj['question'] as string | undefined) ?? ''
        const selectionType = (obj['selection_type'] as string | undefined) ?? 'text'
        const options: string[] = []
        const rawOpts = obj['options'] as Object
        if (Array.isArray(rawOpts)) {
          const arr = rawOpts as string[]
          for (let j = 0; j < arr.length; j++) {
            const v = arr[j]
            if (typeof v === 'string' && v !== '') {
              options.push(v)
            }
          }
        }
        out.push({ id: id, question: question, options: options, selectionType: selectionType })
      }
    } catch (_e) {}
    return out
  }

  private toggleMulti(qid: string, option: string): void {
    const set = this.multiAnswers.get(qid) ?? new Set<string>()
    if (set.has(option)) {
      set.delete(option)
    } else {
      set.add(option)
    }
    this.multiAnswers.set(qid, set)
  }

  private handleSubmit(questions: AskUserQuestion[]): void {
    const answers: Record<string, string> = {}
    for (let i = 0; i < questions.length; i++) {
      const q = questions[i]
      if (q.selectionType === 'multi') {
        const selected = Array.from(this.multiAnswers.get(q.id) ?? new Set<string>())
        answers[q.id] = selected.join(', ')
      } else {
        answers[q.id] = this.textAnswers.get(q.id) ?? ''
      }
    }
    const payload = JSON.stringify({ answers: answers })
    this.onAnswer(this.toolCall.id, payload)
  }

  private canSubmit(questions: AskUserQuestion[]): boolean {
    for (let i = 0; i < questions.length; i++) {
      const q = questions[i]
      if (q.selectionType === 'multi') {
        const set = this.multiAnswers.get(q.id)
        if (set === undefined || set.size === 0) {
          return false
        }
      } else {
        const v = this.textAnswers.get(q.id)
        if (v === undefined || v.trim() === '') {
          return false
        }
      }
    }
    return true
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(14)
          .fontColor([this.themePrimary])
        Text('我有几个问题想确认一下')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 6 })
        Blank()
        if (this.isAnswered) {
          Text('已回答')
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.status_success'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
        }
      }
      .width('100%')

      ForEach(this.parseQuestions(), (q: AskUserQuestion, index: number) => {
        Column({ space: 6 }) {
          Text(q.question !== '' ? q.question : `问题 ${index + 1}`)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          if (q.options.length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(q.options, (opt: string) => {
                this.OptionChip(q, opt)
              }, (opt: string) => opt)
            }
          }

          if (q.selectionType !== 'single' && q.selectionType !== 'multi') {
            TextInput({
              text: this.textAnswers.get(q.id) ?? '',
              placeholder: '输入你的回答'
            })
              .width('100%')
              .height(36)
              .fontSize(13)
              .backgroundColor($r('app.color.background'))
              .borderRadius(8)
              .enabled(!this.isAnswered)
              .onChange((value: string) => {
                this.textAnswers.set(q.id, value)
              })
          }
        }
        .width('100%')
        .padding(10)
        .backgroundColor($r('app.color.divider'))
        .borderRadius(10)
      }, (q: AskUserQuestion) => q.id)

      if (!this.isAnswered) {
        Row() {
          Blank()
          Button('提交')
            .height(32)
            .padding({ left: 16, right: 16 })
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor(this.themePrimary)
            .enabled(this.canSubmit(this.parseQuestions()))
            .onClick(() => {
              this.handleSubmit(this.parseQuestions())
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.background'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private OptionChip(q: AskUserQuestion, option: string) {
    Row() {
      Text(option)
        .fontSize(12)
        .fontColor(this.isOptionSelected(q, option) ? Color.White : $r('app.color.text_primary'))
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .margin({ right: 6, bottom: 6 })
    .backgroundColor(this.isOptionSelected(q, option) ? this.themePrimary : $r('app.color.background'))
    .borderRadius(12)
    .border({ width: 0.5, color: $r('app.color.divider') })
    .onClick(() => {
      if (this.isAnswered) {
        return
      }
      if (q.selectionType === 'multi') {
        this.toggleMulti(q.id, option)
      } else {
        this.textAnswers.set(q.id, option)
      }
    })
  }

  private isOptionSelected(q: AskUserQuestion, option: string): boolean {
    if (q.selectionType === 'multi') {
      const set = this.multiAnswers.get(q.id)
      return set !== undefined && set.has(option)
    }
    return this.textAnswers.get(q.id) === option
  }
}
