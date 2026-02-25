import { ChatTaskOrchestratorService } from '../../services/ChatTaskOrchestratorService'
import { ChatTaskStatus } from '../../models/ChatTaskModels'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../../utils/ToastUtil'
import {
  getTotalUnreadCountExcludeSession,
  parseInAppTaskAlertPayload,
  parseOpenSessionPayload,
  tryParseUnreadBySessionMap
} from '../../utils/TaskAlertUtils'

export class ChatTaskAlertFlowDependencies {
  chatTaskOrchestrator: ChatTaskOrchestratorService
  getTaskUnreadBySessionJson: () => string
  getCurrentSessionId: () => string
  getLastHandledAlertTimestamp: () => number
  onSetOtherSessionUnreadCount: (count: number) => void
  onSetLastHandledAlertTimestamp: (value: number) => void
  onNavigateToSession: (sessionId: string) => void
  onClearOpenSessionPayloadStorage: () => void
  onClearInAppTaskAlertPayloadStorage: () => void
  getUIContext: () => UIContext

  constructor(
    chatTaskOrchestrator: ChatTaskOrchestratorService,
    getTaskUnreadBySessionJson: () => string,
    getCurrentSessionId: () => string,
    getLastHandledAlertTimestamp: () => number,
    onSetOtherSessionUnreadCount: (count: number) => void,
    onSetLastHandledAlertTimestamp: (value: number) => void,
    onNavigateToSession: (sessionId: string) => void,
    onClearOpenSessionPayloadStorage: () => void,
    onClearInAppTaskAlertPayloadStorage: () => void,
    getUIContext: () => UIContext
  ) {
    this.chatTaskOrchestrator = chatTaskOrchestrator
    this.getTaskUnreadBySessionJson = getTaskUnreadBySessionJson
    this.getCurrentSessionId = getCurrentSessionId
    this.getLastHandledAlertTimestamp = getLastHandledAlertTimestamp
    this.onSetOtherSessionUnreadCount = onSetOtherSessionUnreadCount
    this.onSetLastHandledAlertTimestamp = onSetLastHandledAlertTimestamp
    this.onNavigateToSession = onNavigateToSession
    this.onClearOpenSessionPayloadStorage = onClearOpenSessionPayloadStorage
    this.onClearInAppTaskAlertPayloadStorage = onClearInAppTaskAlertPayloadStorage
    this.getUIContext = getUIContext
  }
}

export class ChatTaskAlertFlow {
  private deps: ChatTaskAlertFlowDependencies

  constructor(deps: ChatTaskAlertFlowDependencies) {
    this.deps = deps
  }

  refreshOtherSessionUnreadCount(): void {
    const taskUnreadBySessionJson = this.deps.getTaskUnreadBySessionJson()
    if (taskUnreadBySessionJson === '') {
      this.deps.onSetOtherSessionUnreadCount(0)
      return
    }

    const currentSessionId = this.deps.getCurrentSessionId()
    const unreadBySession = tryParseUnreadBySessionMap(taskUnreadBySessionJson)
    if (unreadBySession === null) {
      this.deps.onSetOtherSessionUnreadCount(0)
      console.error('ChatTaskAlertFlow', 'Failed to parse unread map')
      return
    }

    this.deps.onSetOtherSessionUnreadCount(getTotalUnreadCountExcludeSession(unreadBySession, currentSessionId))
  }

  handleOpenSessionPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }

    const payload = parseOpenSessionPayload(payloadText)
    if (payload === null) {
      console.error('ChatTaskAlertFlow', 'Failed to parse openSession payload')
      return
    }

    const currentSessionId = this.deps.getCurrentSessionId()
    if (payload.sessionId === currentSessionId) {
      this.deps.chatTaskOrchestrator.markSessionRead(currentSessionId)
      this.refreshOtherSessionUnreadCount()
      this.deps.onClearOpenSessionPayloadStorage()
      return
    }

    this.deps.chatTaskOrchestrator.markSessionRead(payload.sessionId)
    this.deps.onNavigateToSession(payload.sessionId)
    this.deps.onClearOpenSessionPayloadStorage()
  }

  handleInAppTaskAlertPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }

    const payload = parseInAppTaskAlertPayload(payloadText)
    if (payload === null) {
      console.error('ChatTaskAlertFlow', 'Failed to parse in-app alert payload')
      return
    }

    if (payload.timestamp <= this.deps.getLastHandledAlertTimestamp()) {
      return
    }

    const currentSessionId = this.deps.getCurrentSessionId()
    if (payload.sessionId === currentSessionId) {
      this.deps.onClearInAppTaskAlertPayloadStorage()
      return
    }

    this.deps.onSetLastHandledAlertTimestamp(payload.timestamp)

    const opts = new SnackBarDisplayOptions()
    opts.message = payload.message
    opts.duration = 5000
    opts.tone = payload.status === ChatTaskStatus.FAILED ? SnackBarTone.ERROR : SnackBarTone.SUCCESS
    opts.actionText = $r('app.string.task_alert_view')
    opts.onAction = (): void => {
      this.deps.chatTaskOrchestrator.markSessionRead(payload.sessionId)
      this.deps.onNavigateToSession(payload.sessionId)
    }
    showSnackBar(this.deps.getUIContext(), opts)
    this.deps.onClearInAppTaskAlertPayloadStorage()
  }
}
