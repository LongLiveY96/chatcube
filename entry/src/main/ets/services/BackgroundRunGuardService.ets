import { Context, wantAgent, WantAgent } from '@kit.AbilityKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'

const DEFAULT_BUNDLE_NAME = 'com.longlive.chatcube'
const DEFAULT_ABILITY_NAME = 'EntryAbility'

export class BackgroundRunGuardService {
  private static instance: BackgroundRunGuardService | null = null
  private context: Context | null = null
  private appInBackground: boolean = false
  private runningTaskCount: number = 0
  private continuousTaskActive: boolean = false
  private syncInProgress: boolean = false

  static getInstance(): BackgroundRunGuardService {
    if (BackgroundRunGuardService.instance === null) {
      BackgroundRunGuardService.instance = new BackgroundRunGuardService()
    }
    return BackgroundRunGuardService.instance
  }

  initialize(context: Context): void {
    this.context = context
  }

  onAppBackgroundChanged(inBackground: boolean): void {
    this.appInBackground = inBackground
    this.syncContinuousTaskState()
  }

  updateRunningTaskCount(count: number): void {
    this.runningTaskCount = count
    this.syncContinuousTaskState()
  }

  private async syncContinuousTaskState(): Promise<void> {
    if (this.syncInProgress) {
      return
    }
    this.syncInProgress = true

    try {
      if (this.context === null) {
        return
      }

      if (this.appInBackground && this.runningTaskCount > 0) {
        await this.startContinuousTaskIfNeeded()
      } else {
        await this.stopContinuousTaskIfNeeded()
      }
    } finally {
      this.syncInProgress = false
    }
  }

  private async startContinuousTaskIfNeeded(): Promise<void> {
    if (this.context === null || this.continuousTaskActive) {
      return
    }

    try {
      const wantAgentObj = await this.createWantAgent()
      const modes: Array<string> = ['dataTransfer']
      await backgroundTaskManager.startBackgroundRunning(this.context, modes, wantAgentObj)
      this.continuousTaskActive = true
      console.info('BackgroundRunGuardService', 'Background running started (dataTransfer)')
    } catch (error) {
      console.error('BackgroundRunGuardService', `Failed to start background running: ${JSON.stringify(error)}`)
    }
  }

  private async stopContinuousTaskIfNeeded(): Promise<void> {
    if (this.context === null || !this.continuousTaskActive) {
      return
    }

    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context)
      this.continuousTaskActive = false
      console.info('BackgroundRunGuardService', 'Background running stopped')
    } catch (error) {
      console.error('BackgroundRunGuardService', `Failed to stop background running: ${JSON.stringify(error)}`)
    }
  }

  private async createWantAgent(): Promise<WantAgent> {
    const wantInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: DEFAULT_BUNDLE_NAME,
          abilityName: DEFAULT_ABILITY_NAME
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 100,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    return await wantAgent.getWantAgent(wantInfo)
  }
}

export function getBackgroundRunGuardService(): BackgroundRunGuardService {
  return BackgroundRunGuardService.getInstance()
}
