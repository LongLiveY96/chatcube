import { ChatSession } from '../../models/ChatModels'
import { SessionGroupData } from './IndexPageTypes'
import { buildSessionRenderKeyForIndex } from './IndexSessionGroupHelper'

export function buildSessionListItemRenderKey(session: ChatSession, isSelected: boolean, isActive: boolean): string {
  return `${buildSessionRenderKeyForIndex(session)}_${isSelected ? '1' : '0'}_${isActive ? '1' : '0'}`
}

export class SessionListItemData {
  session: ChatSession
  isSelected: boolean
  isActive: boolean
  private readonly renderKey: string

  constructor(session: ChatSession, isSelected: boolean, isActive: boolean) {
    this.session = session
    this.isSelected = isSelected
    this.isActive = isActive
    this.renderKey = buildSessionListItemRenderKey(session, isSelected, isActive)
  }

  get key(): string {
    return this.renderKey
  }

  get stableId(): string {
    return this.session.id
  }
}

export class IndexSessionListDataSource implements IDataSource {
  private items: SessionListItemData[] = []
  private listeners: DataChangeListener[] = []

  constructor(items: SessionListItemData[] = []) {
    this.items = items
  }

  totalCount(): number {
    return this.items.length
  }

  getData(index: number): SessionListItemData {
    return this.items[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.includes(listener)) {
      return
    }
    this.listeners.push(listener)
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener)
  }

  setItems(items: SessionListItemData[]): void {
    const previousItems = this.items
    this.items = items
    if (previousItems.length !== items.length) {
      this.notifyDataReloaded()
      return
    }

    for (let i = 0; i < items.length; i++) {
      if (previousItems[i].key !== items[i].key) {
        this.notifyDataReloaded()
        return
      }
    }

    const changedIndexes: number[] = []
    for (let i = 0; i < items.length; i++) {
      if (this.hasItemStateChanged(previousItems[i], items[i])) {
        changedIndexes.push(i)
      }
    }

    if (changedIndexes.length > 0) {
      this.notifyDataChanged(changedIndexes)
    }
  }

  private notifyDataReloaded(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }

  private notifyDataChanged(indexes: number[]): void {
    for (let listenerIndex = 0; listenerIndex < this.listeners.length; listenerIndex++) {
      const listener = this.listeners[listenerIndex]
      for (let index = 0; index < indexes.length; index++) {
        listener.onDataChange(indexes[index])
      }
    }
  }

  private hasItemStateChanged(previousItem: SessionListItemData, nextItem: SessionListItemData): boolean {
    return previousItem.key !== nextItem.key ||
      previousItem.session !== nextItem.session ||
      previousItem.isSelected !== nextItem.isSelected ||
      previousItem.isActive !== nextItem.isActive
  }
}

export class SessionListGroupViewModel {
  key: string
  count: number
  dataSource: IndexSessionListDataSource

  constructor(key: string, items: SessionListItemData[] = []) {
    this.key = key
    this.count = items.length
    this.dataSource = new IndexSessionListDataSource(items)
  }

  setItems(items: SessionListItemData[]): void {
    this.count = items.length
    this.dataSource.setItems(items)
  }
}

function buildSessionListItems(group: SessionGroupData, selectedSessionIds: string[],
  isMultiSelectMode: boolean, activeSessionId: string): SessionListItemData[] {
  const items: SessionListItemData[] = []
  for (let i = 0; i < group.sessions.length; i++) {
    const session = group.sessions[i]
    items.push(new SessionListItemData(
      session,
      isMultiSelectMode && selectedSessionIds.includes(session.id),
      !isMultiSelectMode && activeSessionId === session.id
    ))
  }
  return items
}

export function rebuildSessionListGroupViewModels(existingGroups: SessionListGroupViewModel[], sessionGroups: SessionGroupData[],
  selectedSessionIds: string[], isMultiSelectMode: boolean, activeSessionId: string): SessionListGroupViewModel[] {
  const existingGroupMap: Map<string, SessionListGroupViewModel> = new Map()
  for (let i = 0; i < existingGroups.length; i++) {
    existingGroupMap.set(existingGroups[i].key, existingGroups[i])
  }

  const nextGroups: SessionListGroupViewModel[] = []
  for (let i = 0; i < sessionGroups.length; i++) {
    const group = sessionGroups[i]
    const items = buildSessionListItems(group, selectedSessionIds, isMultiSelectMode, activeSessionId)
    const existingGroup = existingGroupMap.get(group.key)
    if (existingGroup !== undefined) {
      existingGroup.setItems(items)
      nextGroups.push(existingGroup)
      continue
    }
    nextGroups.push(new SessionListGroupViewModel(group.key, items))
  }
  return nextGroups
}
