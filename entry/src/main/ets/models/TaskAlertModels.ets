export interface OpenSessionPayloadData {
  sessionId: string
  taskId: string
  source: string
  timestamp: number
}

export interface InAppTaskAlertPayloadData {
  id: string
  sessionId: string
  sessionTitle: string
  status: string
  message: string
  timestamp: number
}
