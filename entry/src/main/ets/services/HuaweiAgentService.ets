import { common, Want } from '@kit.AbilityKit'
import { HuaweiAgentEntry } from '../models/ChatModels'
import { getPreferencesService, PreferencesService, PreferenceKeys } from './PreferencesService'

interface HuaweiAgentEntryData {
  id: string
  name: string
  bundleName: string
  abilityName: string
  uri: string
  enabled: boolean
  lastLaunchAt: number
}

export class HuaweiAgentService {
  private static instance: HuaweiAgentService | null = null
  private preferencesService: PreferencesService
  private entries: HuaweiAgentEntry[] = []
  private featureEnabled: boolean = true
  private initialized: boolean = false

  private constructor() {
    this.preferencesService = getPreferencesService()
  }

  static getInstance(): HuaweiAgentService {
    if (HuaweiAgentService.instance === null) {
      HuaweiAgentService.instance = new HuaweiAgentService()
    }
    return HuaweiAgentService.instance
  }

  async initialize(): Promise<void> {
    if (this.initialized) {
      return
    }
    await this.loadFeatureFlag()
    await this.loadEntries()
    this.initialized = true
  }

  async isFeatureEnabled(): Promise<boolean> {
    if (!this.initialized) {
      await this.initialize()
    }
    return this.featureEnabled
  }

  async setFeatureEnabled(enabled: boolean): Promise<void> {
    if (!this.initialized) {
      await this.initialize()
    }
    this.featureEnabled = enabled
    await this.preferencesService.setBoolean(PreferenceKeys.HUAWEI_AGENT_FEATURE_FLAG, enabled)
  }

  async getEntries(): Promise<HuaweiAgentEntry[]> {
    if (!this.initialized) {
      await this.initialize()
    }
    return this.cloneEntries()
  }

  async addOrUpdateEntry(entry: HuaweiAgentEntry): Promise<void> {
    if (!this.initialized) {
      await this.initialize()
    }

    const normalized = this.normalizeEntry(entry)
    let found = false
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].id === normalized.id) {
        this.entries[i] = normalized
        found = true
        break
      }
    }

    if (!found) {
      this.entries.push(normalized)
    }

    await this.saveEntries()
  }

  async deleteEntry(entryId: string): Promise<void> {
    if (!this.initialized) {
      await this.initialize()
    }

    const list: HuaweiAgentEntry[] = []
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].id !== entryId) {
        list.push(this.entries[i])
      }
    }
    this.entries = list
    await this.saveEntries()
  }

  async launchEntry(entryId: string, context: common.UIAbilityContext): Promise<boolean> {
    if (!this.initialized) {
      await this.initialize()
    }

    if (!this.featureEnabled) {
      return false
    }

    let target: HuaweiAgentEntry | null = null
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].id === entryId && this.entries[i].enabled) {
        target = this.entries[i]
        break
      }
    }

    if (target === null) {
      return false
    }

    const want: Want = {
      bundleName: target.bundleName,
      abilityName: target.abilityName
    }

    if (target.uri !== '') {
      want.uri = target.uri
    }

    try {
      await context.startAbility(want)
      target.lastLaunchAt = Date.now()
      await this.saveEntries()
      return true
    } catch (error) {
      console.error('HuaweiAgentService', `Failed to launch agent entry: ${JSON.stringify(error)}`)
      return false
    }
  }

  private normalizeEntry(entry: HuaweiAgentEntry): HuaweiAgentEntry {
    const normalized = new HuaweiAgentEntry(entry.id !== '' ? entry.id : this.buildEntryId(entry.name), entry.name)
    normalized.bundleName = entry.bundleName
    normalized.abilityName = entry.abilityName
    normalized.uri = entry.uri
    normalized.enabled = entry.enabled
    normalized.lastLaunchAt = entry.lastLaunchAt
    return normalized
  }

  private buildEntryId(name: string): string {
    const base = name !== '' ? name : `huawei_agent_${Date.now()}`
    return base.toLowerCase().replace(/[^a-z0-9_]+/g, '_')
  }

  private async loadFeatureFlag(): Promise<void> {
    this.featureEnabled = await this.preferencesService.getBoolean(PreferenceKeys.HUAWEI_AGENT_FEATURE_FLAG, true)
  }

  private async loadEntries(): Promise<void> {
    const json = await this.preferencesService.getString(PreferenceKeys.HUAWEI_AGENT_ENTRIES, '')
    if (json === '') {
      this.entries = this.getDefaultEntries()
      await this.saveEntries()
      return
    }

    try {
      const parsed = JSON.parse(json) as HuaweiAgentEntryData[]
      const list: HuaweiAgentEntry[] = []
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i]
        const entry = new HuaweiAgentEntry(item.id, item.name)
        entry.bundleName = item.bundleName
        entry.abilityName = item.abilityName
        entry.uri = item.uri
        entry.enabled = item.enabled
        entry.lastLaunchAt = item.lastLaunchAt
        if (entry.id !== '' && entry.name !== '') {
          list.push(entry)
        }
      }
      this.entries = list
    } catch (error) {
      console.error('HuaweiAgentService', `Failed to parse entries: ${JSON.stringify(error)}`)
      this.entries = this.getDefaultEntries()
      await this.saveEntries()
    }
  }

  private async saveEntries(): Promise<void> {
    const data: HuaweiAgentEntryData[] = []
    for (let i = 0; i < this.entries.length; i++) {
      const entry = this.entries[i]
      data.push({
        id: entry.id,
        name: entry.name,
        bundleName: entry.bundleName,
        abilityName: entry.abilityName,
        uri: entry.uri,
        enabled: entry.enabled,
        lastLaunchAt: entry.lastLaunchAt
      })
    }
    await this.preferencesService.setString(PreferenceKeys.HUAWEI_AGENT_ENTRIES, JSON.stringify(data))
  }

  private getDefaultEntries(): HuaweiAgentEntry[] {
    const list: HuaweiAgentEntry[] = []
    const xiaoyi = new HuaweiAgentEntry('xiaoyi_agent', '小艺智能体')
    xiaoyi.bundleName = 'com.huawei.yoyo'
    xiaoyi.abilityName = 'com.huawei.yoyo.MainAbility'
    xiaoyi.enabled = true
    list.push(xiaoyi)
    return list
  }

  private cloneEntries(): HuaweiAgentEntry[] {
    const list: HuaweiAgentEntry[] = []
    for (let i = 0; i < this.entries.length; i++) {
      const src = this.entries[i]
      const copied = new HuaweiAgentEntry(src.id, src.name)
      copied.bundleName = src.bundleName
      copied.abilityName = src.abilityName
      copied.uri = src.uri
      copied.enabled = src.enabled
      copied.lastLaunchAt = src.lastLaunchAt
      list.push(copied)
    }
    return list
  }
}

export function getHuaweiAgentService(): HuaweiAgentService {
  return HuaweiAgentService.getInstance()
}
