import { ChatSession } from '../../models/ChatModels'

export enum SettingsSheetType {
  NONE = 0,
  THEME = 1,
  LANGUAGE = 2,
  COLOR_THEME = 3,
  NOTIFICATION = 4,
  HAND_ADAPTIVE = 5
}

export enum SessionFilterType {
  ALL = 0,
  FAVORITE = 1
}

export class SessionGroupData {
  key: string
  sessions: ChatSession[]

  constructor(key: string, sessions: ChatSession[]) {
    this.key = key
    this.sessions = sessions
  }
}
