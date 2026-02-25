import { notificationManager } from '@kit.NotificationKit'
import { wantAgent, WantAgent } from '@kit.AbilityKit'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { ChatTaskInfo, ChatTaskStatus, OpenSessionPayload } from '../models/ChatTaskModels'

const DEFAULT_BUNDLE_NAME = 'com.longlive.chatcube'
const DEFAULT_ABILITY_NAME = 'EntryAbility'

interface NotificationBusinessError {
  code?: number
  message?: string
}

export class ChatNotificationService {
  private static instance: ChatNotificationService | null = null
  private slotReady: boolean = false
  private slotPreparing: Promise<void> | null = null

  static getInstance(): ChatNotificationService {
    if (ChatNotificationService.instance === null) {
      ChatNotificationService.instance = new ChatNotificationService()
    }
    return ChatNotificationService.instance
  }

  async publishTaskResult(task: ChatTaskInfo): Promise<void> {
    try {
      await this.ensureNotificationSlot()
      const wantAgentObj = await this.createOpenSessionWantAgent(task)

      const request: notificationManager.NotificationRequest = {

        id: this.buildNotificationId(task.id),
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: task.status === ChatTaskStatus.FAILED ? '回复失败' : '回复完成',
            text: this.buildMessage(task),
            additionalText: 'ChatCube'
          }

        },
        wantAgent: wantAgentObj
      }
      await notificationManager.publish(request)
    } catch (error) {
      console.error('ChatNotificationService', `Failed to publish notification: ${JSON.stringify(error)}`)
    }
  }

  private async ensureNotificationSlot(): Promise<void> {
    if (this.slotReady) {
      return
    }
    if (this.slotPreparing !== null) {
      await this.slotPreparing
      return
    }
    this.slotPreparing = this.ensureNotificationSlotInternal()
    try {
      await this.slotPreparing
    } finally {
      this.slotPreparing = null
    }
  }

  private async ensureNotificationSlotInternal(): Promise<void> {
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION)
      this.slotReady = true
      console.info('ChatNotificationService', 'Service slot ensured')
    } catch (error) {
      if (this.isSlotAlreadyExistsError(error)) {
        this.slotReady = true
        return
      }
      this.slotReady = false
      console.warn('ChatNotificationService', `Failed to add service slot: ${JSON.stringify(error)}`)
    }
  }

  private isSlotAlreadyExistsError(error: Object): boolean {
    const err = error as NotificationBusinessError
    if (err.code !== undefined && err.code === 1600009) {
      return true
    }
    if (err.message !== undefined) {
      const lowerMessage = err.message.toLowerCase()
      if (lowerMessage.includes('already') && lowerMessage.includes('exist')) {
        return true
      }
    }
    return false
  }

  private async createOpenSessionWantAgent(task: ChatTaskInfo): Promise<WantAgent> {
    const payload = new OpenSessionPayload(task.sessionId, task.id, 'notification')
    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: DEFAULT_BUNDLE_NAME,
          abilityName: DEFAULT_ABILITY_NAME,
          parameters: {
            action: 'openSession',
            payload: JSON.stringify(payload)
          }
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.buildNotificationId(task.id),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    return await wantAgent.getWantAgent(info)
  }

  private buildNotificationId(taskId: string): number {
    let hash = 0
    for (let i = 0; i < taskId.length; i++) {
      hash = (hash * 31 + taskId.charCodeAt(i)) % 2000000000
    }
    return hash + 1000
  }

  private buildMessage(task: ChatTaskInfo): string {
    if (task.status === ChatTaskStatus.FAILED) {
      return `会话「${task.sessionTitle}」回复失败，点击查看详情`
    }
    return `会话「${task.sessionTitle}」回复已完成，点击查看`
  }

  handleOpenSessionPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }
    AppStorage.setOrCreate(AppStorageKeys.OPEN_SESSION_PAYLOAD, payloadText)
  }
}

export function getChatNotificationService(): ChatNotificationService {
  return ChatNotificationService.getInstance()
}
