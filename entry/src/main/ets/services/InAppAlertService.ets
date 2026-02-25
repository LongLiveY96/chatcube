import { AppStorageKeys } from '../config/AppStorageKeys'
import { ChatTaskInfo, ChatTaskStatus, InAppTaskAlertPayload } from '../models/ChatTaskModels'

export class InAppAlertService {
  private static instance: InAppAlertService | null = null

  static getInstance(): InAppAlertService {
    if (InAppAlertService.instance === null) {
      InAppAlertService.instance = new InAppAlertService()
    }
    return InAppAlertService.instance
  }

  publishTaskAlert(task: ChatTaskInfo): void {
    const message = this.buildMessage(task)
    const payload = new InAppTaskAlertPayload(
      task.id,
      task.sessionId,
      task.sessionTitle,
      task.status,
      message,
      Date.now()
    )
    AppStorage.setOrCreate(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, JSON.stringify(payload))
  }

  private buildMessage(task: ChatTaskInfo): string {
    if (task.status === ChatTaskStatus.FAILED) {
      return `会话「${task.sessionTitle}」回复失败，点击查看`
    }
    return `会话「${task.sessionTitle}」回复已完成，点击查看`
  }
}

export function getInAppAlertService(): InAppAlertService {
  return InAppAlertService.getInstance()
}
