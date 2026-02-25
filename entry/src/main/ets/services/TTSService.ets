import { TextReader } from '@kit.SpeechKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'

// TTS事件回调接口
export interface TTSCallback {
  onStart: () => void
  onComplete: () => void
  onError: (error: string) => void
}

export class TTSService {
  private isInitialized: boolean = false
  private isReading: boolean = false
  private currentCallback: TTSCallback | null = null
  private currentReadId: string = ''

  // 初始化小艺朗读引擎
  async init(context: common.Context): Promise<void> {
    if (this.isInitialized) {
      return
    }

    const readerParams: TextReader.ReaderParam = {
      isVoiceBrandVisible: true, // 显示品牌信息
      businessBrandInfo: {
        panelName: 'AI 助手朗读'
      },
      // 关键配置：启用在线音色支持
      person: {
        tone: 0,
        style: 'interaction-broadcast'
      }
    }

    try {
      await TextReader.init(context, readerParams)

      // 监听朗读状态变化
      TextReader.on('stateChange', (state: ESObject) => {
        console.info('TTSService', `Read state: ${JSON.stringify(state)}`)

        const stateCode = state['state'] as number

        // 状态码：0=READY, 1=PLAYING, 2=PAUSED, 3=STOPPED
        if (stateCode === 1) {  // PLAYING
          this.isReading = true
          if (this.currentCallback) {
            this.currentCallback.onStart()
          }
        } else if (stateCode === 2) {  // PAUSED — 系统面板暂停也视为停止，防止用户暂停后直接关闭面板
          this.isReading = false
          const cb = this.currentCallback
          this.currentCallback = null
          if (cb) {
            cb.onComplete()
          }
        } else if (stateCode === 3) {  // STOPPED（包括用户关闭面板、朗读完成、主动stop）
          this.isReading = false
          const cb = this.currentCallback
          this.currentCallback = null
          if (cb) {
            cb.onComplete()
          }
        }
      })

      // 兜底：监听 stop 事件，确保系统面板关闭时能恢复图标状态
      TextReader.on('stop', () => {
        console.info('TTSService', 'TextReader stop event received')
        this.isReading = false
        const cb = this.currentCallback
        this.currentCallback = null
        if (cb) {
          cb.onComplete()
        }
      })

      this.isInitialized = true
      console.info('TTSService', 'TextReader initialized successfully')
    } catch (error) {
      const err = error as BusinessError
      console.error('TTSService', `TextReader init failed: ${err.code}, ${err.message}`)
      throw new Error(`朗读服务初始化失败: ${err.message}`)
    }
  }

  // 朗读文本
  async speak(text: string, callback: TTSCallback): Promise<void> {
    if (!this.isInitialized) {
      callback.onError('朗读服务未初始化')
      return
    }

    // 如果正在朗读，先停止
    if (this.isReading) {
      this.stop()
    }

    // 预处理文本（移除代码块、清理Markdown符号等）
    const processedText = this.preprocessTextForTTS(text)

    if (processedText === '') {
      callback.onError('没有可朗读的内容')
      return
    }

    // 保存当前回调
    this.currentCallback = callback
    this.currentReadId = Date.now().toString()

    // 构造朗读内容
    const readInfoList: TextReader.ReadInfo[] = [{
      id: this.currentReadId,
      title: { text: 'AI 回复', isClickable: false },
      bodyInfo: processedText
    }]

    console.info('TTSService', `Starting read, id: ${this.currentReadId}, text length: ${processedText.length}`)

    try {
      // 启动朗读（第二个参数传 undefined，从头开始播放）
      // 注意：不调用 showPanel() 可保持悬浮窗模式，系统会自动显示小悬浮窗
      await TextReader.start(readInfoList, undefined)

      console.info('TTSService', 'TextReader start called successfully')
    } catch (error) {
      const err = error as BusinessError
      console.error('TTSService', `TextReader start failed: ${err.code}, ${err.message}`)
      this.isReading = false
      callback.onError(`朗读失败: ${err.message}`)
    }
  }

  // 停止朗读
  stop(): void {
    try {
      TextReader.stop()
      this.isReading = false
      console.info('TTSService', 'TextReader stopped')
    } catch (error) {
      console.error('TTSService', `TextReader stop failed: ${error}`)
      this.isReading = false
    }
  }

  // 检查是否正在朗读
  getReadingStatus(): boolean {
    return this.isReading
  }

  // 释放资源
  destroy(): void {
    try {
      TextReader.off('stateChange')
      TextReader.off('stop')
      TextReader.release()
      this.isInitialized = false
      this.isReading = false
      console.info('TTSService', 'TextReader released')
    } catch (error) {
      console.error('TTSService', `TextReader release failed: ${error}`)
    }
  }

  // 文本预处理：移除代码块、清理Markdown符号等
  private preprocessTextForTTS(markdown: string): string {
    if (markdown === '') {
      return ''
    }

    let text = markdown

    // 移除代码块（```code```）
    text = text.replace(/```[\s\S]*?```/g, '')

    // 移除行内代码（`code`）
    text = text.replace(/`[^`]*`/g, '')

    // 清理Markdown符号
    text = text.replace(/\*\*\*([^*]+)\*\*\*/g, '$1')  // ***bold italic***
    text = text.replace(/\*\*([^*]+)\*\*/g, '$1')     // **bold**
    text = text.replace(/\*([^*]+)\*/g, '$1')         // *italic*
    text = text.replace(/___([^_]+)___/g, '$1')      // ___bold italic___
    text = text.replace(/__([^_]+)__/g, '$1')        // __bold__
    text = text.replace(/_([^_]+)_/g, '$1')          // _italic_
    text = text.replace(/~~([^~]+)~~/g, '')          // ~~strikethrough~~

    // 清理标题符号
    text = text.replace(/^#{1,6}\s+/gm, '')

    // 清理引用符号
    text = text.replace(/^>\s+/gm, '')

    // 清理链接语法 [text](url) -> text
    text = text.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')

    // 清理图片语法 ![alt](url)
    text = text.replace(/!\[[^\]]*\]\([^)]+\)/g, '')

    // 清理无序列表符号
    text = text.replace(/^[-*+]\s+/gm, '')

    // 清理有序列表符号
    text = text.replace(/^\d+\.\s+/gm, '')

    // 清理水平线
    text = text.replace(/^[-*_]{3,}\s*$/gm, '')

    // 清理LaTeX公式（简单处理）
    text = text.replace(/\$\$[\s\S]*?\$\$/g, '公式')
    text = text.replace(/\$[^$]*\$/g, '公式')

    // 清理多余空行
    text = text.replace(/\n{3,}/g, '\n\n')

    // 限制长度（TextReader 支持长文本，但建议合理分段）
    if (text.length > 50000) {
      text = text.substring(0, 50000) + '...'
    }

    return text.trim()
  }
}
