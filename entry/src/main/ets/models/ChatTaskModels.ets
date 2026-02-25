export enum ChatTaskStatus {
  RUNNING = 'running',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

export class ChatTaskInfo {
  id: string
  sessionId: string
  sessionTitle: string
  promptPreview: string
  status: ChatTaskStatus
  startedAt: number
  finishedAt: number
  errorMessage: string

  constructor(id: string, sessionId: string, sessionTitle: string, promptPreview: string) {
    this.id = id
    this.sessionId = sessionId
    this.sessionTitle = sessionTitle
    this.promptPreview = promptPreview
    this.status = ChatTaskStatus.RUNNING
    this.startedAt = Date.now()
    this.finishedAt = 0
    this.errorMessage = ''
  }
}

export class InAppTaskAlertPayload {
  id: string
  sessionId: string
  sessionTitle: string
  status: ChatTaskStatus
  message: string
  timestamp: number

  constructor(
    id: string,
    sessionId: string,
    sessionTitle: string,
    status: ChatTaskStatus,
    message: string,
    timestamp: number
  ) {
    this.id = id
    this.sessionId = sessionId
    this.sessionTitle = sessionTitle
    this.status = status
    this.message = message
    this.timestamp = timestamp
  }
}

export class OpenSessionPayload {
  sessionId: string
  taskId: string
  source: string
  timestamp: number

  constructor(sessionId: string, taskId: string, source: string) {
    this.sessionId = sessionId
    this.taskId = taskId
    this.source = source
    this.timestamp = Date.now()
  }
}
