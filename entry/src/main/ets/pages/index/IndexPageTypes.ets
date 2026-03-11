import { ChatSession } from '../../models/ChatModels'

export enum SettingsSheetType {
  NONE = 0,
  THEME = 1,
  LANGUAGE = 2,
  NOTIFICATION = 3,
  HAND_ADAPTIVE = 4
}

export enum SessionFilterType {
  ALL = 0,
  FAVORITE = 1
}

@ObservedV2
export class SessionGroupData {
  @Trace key: string
  @Trace sessions: ChatSession[]

  constructor(key: string, sessions: ChatSession[]) {
    this.key = key
    this.sessions = sessions
  }
}
