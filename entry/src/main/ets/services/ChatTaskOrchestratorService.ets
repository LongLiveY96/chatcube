import { AppStorageKeys } from '../config/AppStorageKeys'
import { ChatTaskInfo, ChatTaskStatus } from '../models/ChatTaskModels'
import { ChatViewModel } from '../viewmodels/ChatViewModel'
import { getSettingsManager, SettingsManager } from '../viewmodels/SettingsManager'
import { getBackgroundRunGuardService, BackgroundRunGuardService } from './BackgroundRunGuardService'
import { getChatNotificationService, ChatNotificationService } from './ChatNotificationService'
import { getInAppAlertService, InAppAlertService } from './InAppAlertService'

class ChatTaskRuntime {
  info: ChatTaskInfo
  stopAction: () => void
  finalized: boolean

  constructor(info: ChatTaskInfo, stopAction: () => void) {
    this.info = info
    this.stopAction = stopAction
    this.finalized = false
  }
}

export class ChatTaskOrchestratorService {
  private static instance: ChatTaskOrchestratorService | null = null
  private readonly MAX_CONCURRENT_TASKS: number = 3
  private tasks: Map<string, ChatTaskRuntime> = new Map()
  private unreadBySession: Map<string, number> = new Map()
  private settingsManager: SettingsManager = getSettingsManager()
  private backgroundGuard: BackgroundRunGuardService = getBackgroundRunGuardService()
  private notificationService: ChatNotificationService = getChatNotificationService()
  private inAppAlertService: InAppAlertService = getInAppAlertService()

  static getInstance(): ChatTaskOrchestratorService {
    if (ChatTaskOrchestratorService.instance === null) {
      ChatTaskOrchestratorService.instance = new ChatTaskOrchestratorService()
    }
    return ChatTaskOrchestratorService.instance
  }

  getMaxConcurrentTasks(): number {
    return this.MAX_CONCURRENT_TASKS
  }

  canStartNewTask(): boolean {
    return this.getRunningTaskCount() < this.MAX_CONCURRENT_TASKS
  }

  getRunningTaskCount(): number {
    let count = 0
    this.tasks.forEach((runtime) => {
      if (runtime.info.status === ChatTaskStatus.RUNNING && !runtime.finalized) {
        count = count + 1
      }
    })
    return count
  }

  startTask(sessionId: string, sessionTitle: string, prompt: string, chatViewModel: ChatViewModel): string {
    if (!this.canStartNewTask()) {
      return ''
    }

    const taskId = this.buildTaskId()
    const title = sessionTitle !== '' ? sessionTitle : '新对话'
    const preview = this.buildPromptPreview(prompt)
    const info = new ChatTaskInfo(taskId, sessionId, title, preview)
    const runtime = new ChatTaskRuntime(info, () => {
      chatViewModel.stopGeneration()
    })
    this.tasks.set(taskId, runtime)
    this.syncTaskCountAndStorage()
    this.bumpTaskEventTick()
    return taskId
  }

  completeTask(taskId: string): void {
    this.finishTaskInternal(taskId, ChatTaskStatus.COMPLETED, '')
  }

  failTask(taskId: string, errorMessage: string): void {
    this.finishTaskInternal(taskId, ChatTaskStatus.FAILED, errorMessage)
  }

  cancelTask(taskId: string): void {
    const runtime = this.tasks.get(taskId)
    if (runtime === undefined || runtime.finalized) {
      return
    }

    try {
      runtime.stopAction()
    } catch (error) {
      console.error('ChatTaskOrchestratorService', `Stop task failed: ${JSON.stringify(error)}`)
    }
    this.finishTaskInternal(taskId, ChatTaskStatus.CANCELLED, '')
  }

  markSessionRead(sessionId: string): void {
    if (sessionId === '') {
      return
    }
    this.dismissInAppAlertForSession(sessionId)
    const count = this.unreadBySession.get(sessionId)
    if (count === undefined || count <= 0) {
      return
    }
    this.unreadBySession.delete(sessionId)
    this.syncUnreadStorage()
    this.bumpTaskEventTick()
  }

  getUnreadCountForSession(sessionId: string): number {
    const value = this.unreadBySession.get(sessionId)
    if (value === undefined) {
      return 0
    }
    return value
  }

  private finishTaskInternal(taskId: string, status: ChatTaskStatus, errorMessage: string): void {
    const runtime = this.tasks.get(taskId)
    if (runtime === undefined || runtime.finalized) {
      return
    }

    runtime.finalized = true
    runtime.info.status = status
    runtime.info.finishedAt = Date.now()
    runtime.info.errorMessage = errorMessage

    if (status === ChatTaskStatus.COMPLETED || status === ChatTaskStatus.FAILED) {
      this.handleTaskResult(runtime.info)
    }

    this.syncTaskCountAndStorage()
    this.cleanupFinishedTasksIfNeeded()
    this.bumpTaskEventTick()
  }

  private handleTaskResult(task: ChatTaskInfo): void {
    const appInBackground = this.getAppInBackground()
    const activeSessionId = this.getActiveSessionId()
    const shouldMarkUnread = appInBackground || activeSessionId !== task.sessionId

    if (shouldMarkUnread) {
      this.increaseUnreadCount(task.sessionId)
    }

    if (!this.settingsManager.getNotificationEnabled()) {
      return
    }
    if (task.status === ChatTaskStatus.COMPLETED && !this.settingsManager.getNotifyOnCompleteEnabled()) {
      return
    }
    if (task.status === ChatTaskStatus.FAILED && !this.settingsManager.getNotifyOnFailedEnabled()) {
      return
    }

    if (shouldMarkUnread) {
      this.inAppAlertService.publishTaskAlert(task)
    }

    if (appInBackground) {
      this.notificationService.publishTaskResult(task)
    }
  }

  private increaseUnreadCount(sessionId: string): void {
    const current = this.unreadBySession.get(sessionId)
    if (current === undefined) {
      this.unreadBySession.set(sessionId, 1)
    } else {
      this.unreadBySession.set(sessionId, current + 1)
    }
    this.syncUnreadStorage()
  }

  private syncTaskCountAndStorage(): void {
    const runningCount = this.getRunningTaskCount()
    AppStorage.setOrCreate(AppStorageKeys.RUNNING_CHAT_TASK_COUNT, runningCount)
    this.backgroundGuard.updateRunningTaskCount(runningCount)
  }

  private syncUnreadStorage(): void {
    const data: Record<string, number> = {}
    let total = 0
    this.unreadBySession.forEach((value: number, key: string) => {
      data[key] = value
      total = total + value
    })
    AppStorage.setOrCreate(AppStorageKeys.TASK_UNREAD_BY_SESSION, JSON.stringify(data))
    AppStorage.setOrCreate(AppStorageKeys.TASK_UNREAD_TOTAL, total)
  }

  private dismissInAppAlertForSession(sessionId: string): void {
    const payloadText = AppStorage.get<string>(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD)
    if (payloadText === undefined || payloadText === '') {
      return
    }

    try {
      const payload = JSON.parse(payloadText) as Record<string, string>
      if (payload.sessionId === sessionId) {
        AppStorage.setOrCreate(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, '')
      }
    } catch (error) {
      console.error('ChatTaskOrchestratorService', `Failed to parse in-app alert payload: ${JSON.stringify(error)}`)
    }
  }

  private bumpTaskEventTick(): void {
    AppStorage.setOrCreate(AppStorageKeys.TASK_EVENT_TICK, Date.now())
  }

  private getAppInBackground(): boolean {
    const value = AppStorage.get<boolean>(AppStorageKeys.APP_IN_BACKGROUND)
    if (value === undefined) {
      return false
    }
    return value
  }

  private getActiveSessionId(): string {
    const value = AppStorage.get<string>(AppStorageKeys.ACTIVE_CHAT_SESSION_ID)
    if (value === undefined) {
      return ''
    }
    return value
  }

  private buildTaskId(): string {
    return `task_${Date.now()}_${Math.floor(Math.random() * 10000)}`
  }

  private buildPromptPreview(prompt: string): string {
    const trimmed = prompt.trim()
    if (trimmed.length <= 24) {
      return trimmed
    }
    return `${trimmed.substring(0, 24)}...`
  }

  private cleanupFinishedTasksIfNeeded(): void {
    if (this.tasks.size <= 120) {
      return
    }

    const completedTaskIds: string[] = []
    this.tasks.forEach((runtime: ChatTaskRuntime, key: string) => {
      if (runtime.finalized) {
        completedTaskIds.push(key)
      }
    })

    const maxRemove = completedTaskIds.length - 80
    if (maxRemove <= 0) {
      return
    }

    for (let i = 0; i < maxRemove; i++) {
      this.tasks.delete(completedTaskIds[i])
    }
  }
}

export function getChatTaskOrchestratorService(): ChatTaskOrchestratorService {
  return ChatTaskOrchestratorService.getInstance()
}
