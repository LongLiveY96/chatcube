import { PromptAction } from '@kit.ArkUI'
import {
  HdsSnackBar,
  SnackBarIconOptions,
  SnackBarIconType,
  SnackBarMessageOptions,
  SnackBarOperationOptions,
  SnackBarOperationType,
  SnackBarStyleOptions
} from '@kit.UIDesignKit'

export enum SnackBarTone {
  DEFAULT = 0,
  SUCCESS = 1,
  ERROR = 2
}

export class SnackBarDisplayOptions {
  message: string | Resource = ''
  duration: number = 2000
  tone: SnackBarTone = SnackBarTone.DEFAULT
  actionText: string | Resource = ''
  onAction: () => void = (): void => {}
}

let activeSnackBar: HdsSnackBar | null = null
let activeSnackBarToken: number = 0
let activeSnackBarTimerId: number = -1

function resolveSnackBarIcon(tone: SnackBarTone): Resource {
  if (tone === SnackBarTone.SUCCESS) {
    return $r('sys.symbol.checkmark_circle')
  }
  if (tone === SnackBarTone.ERROR) {
    return $r('sys.symbol.exclamationmark_circle')
  }
  return $r('sys.symbol.message')
}

function fallbackToast(context: UIContext, message: string | Resource, duration: number): void {
  const promptAction: PromptAction = context.getPromptAction()
  promptAction.openToast({
    message: message,
    duration: duration
  })
}

function clearActiveSnackBarTimer(): void {
  if (activeSnackBarTimerId === -1) {
    return
  }
  clearTimeout(activeSnackBarTimerId)
  activeSnackBarTimerId = -1
}

function clearActiveSnackBar(token: number): void {
  if (token !== activeSnackBarToken) {
    return
  }
  activeSnackBar = null
  clearActiveSnackBarTimer()
}

function dismissSnackBarInstance(snackBar: HdsSnackBar, token: number): void {
  clearActiveSnackBar(token)
  try {
    snackBar.dismiss()
  } catch (error) {
    console.error('ToastUtil', 'Failed to dismiss HdsSnackBar: ' + JSON.stringify(error))
  }
}

function dismissActiveSnackBar(): void {
  if (activeSnackBar === null) {
    return
  }
  const snackBar = activeSnackBar
  const token = activeSnackBarToken
  dismissSnackBarInstance(snackBar, token)
}

function scheduleActiveSnackBarClear(token: number, duration: number): void {
  clearActiveSnackBarTimer()
  if (duration <= 0) {
    return
  }
  activeSnackBarTimerId = setTimeout((): void => {
    if (token !== activeSnackBarToken) {
      return
    }
    activeSnackBar = null
    activeSnackBarTimerId = -1
  }, duration)
}

export function dismissActiveSnackBarOnBack(): boolean {
  if (activeSnackBar === null) {
    return false
  }
  dismissActiveSnackBar()
  return true
}

export function showSnackBar(context: UIContext, options: SnackBarDisplayOptions): void {
  try {
    if (options.message === '') {
      return
    }

    if (options.actionText === '') {
      fallbackToast(context, options.message, options.duration)
      return
    }

    dismissActiveSnackBar()

    const snackBar: HdsSnackBar = new HdsSnackBar(context)
    activeSnackBarToken += 1
    const token: number = activeSnackBarToken
    activeSnackBar = snackBar
    const dismissCurrentSnackBar = (): void => {
      dismissSnackBarInstance(snackBar, token)
    }
    const icon: SnackBarIconOptions = {
      icon: resolveSnackBarIcon(options.tone),
      iconType: SnackBarIconType.SMALL
    }
    const messageOptions: SnackBarMessageOptions = {
      content: options.message
    }
    const operation: SnackBarOperationOptions = {
      operationType: SnackBarOperationType.CLOSE_BUTTON_ONLY,
      onCloseButtonClick: dismissCurrentSnackBar
    }
    operation.operationType = SnackBarOperationType.TEXT_WITH_CLOSE
    operation.content = options.actionText
    operation.onContentClick = (): void => {
      dismissCurrentSnackBar()
      options.onAction()
    }
    const style: SnackBarStyleOptions = {
      duration: options.duration,
      pressBackCallback: dismissCurrentSnackBar
    }
    snackBar.show(icon, messageOptions, operation, style)
    scheduleActiveSnackBarClear(token, options.duration)
  } catch (error) {
    clearActiveSnackBar(activeSnackBarToken)
    console.error('ToastUtil', 'Failed to show HdsSnackBar: ' + JSON.stringify(error))
    fallbackToast(context, options.message, options.duration)
  }
}

/**
 * 普通状态提示统一走 openToast。
 */
export function showToast(context: UIContext, message: string | Resource, duration: number = 2000): void {
  try {
    const promptAction: PromptAction = context.getPromptAction()
    promptAction.openToast({
      message: message,
      duration: duration
    })
  } catch (error) {
    console.error('ToastUtil', 'Failed to show toast: ' + JSON.stringify(error))
  }
}
