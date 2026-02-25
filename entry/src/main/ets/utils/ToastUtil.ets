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

export function showSnackBar(context: UIContext, options: SnackBarDisplayOptions): void {
  try {
    if (options.message === '') {
      return
    }

    const snackBar: HdsSnackBar = new HdsSnackBar(context)
    const icon: SnackBarIconOptions = {
      icon: resolveSnackBarIcon(options.tone),
      iconType: SnackBarIconType.SMALL
    }
    const messageOptions: SnackBarMessageOptions = {
      content: options.message
    }
    const operation: SnackBarOperationOptions = {
      operationType: SnackBarOperationType.CLOSE_BUTTON_ONLY,
      onCloseButtonClick: (): void => {
        snackBar.dismiss()
      }
    }
    if (options.actionText !== '') {
      operation.operationType = SnackBarOperationType.TEXT_WITH_CLOSE
      operation.content = options.actionText
      operation.onContentClick = (): void => {
        options.onAction()
        snackBar.dismiss()
      }
    }
    const style: SnackBarStyleOptions = {
      duration: options.duration
    }
    snackBar.show(icon, messageOptions, operation, style)
  } catch (error) {
    console.error('ToastUtil', 'Failed to show HdsSnackBar: ' + JSON.stringify(error))
    fallbackToast(context, options.message, options.duration)
  }
}

/**
 * 兼容历史调用：默认走 HdsSnackBar，失败时回退 openToast。
 */
export function showToast(context: UIContext, message: string | Resource, duration: number = 2000): void {
  const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
  options.message = message
  options.duration = duration
  showSnackBar(context, options)
}
