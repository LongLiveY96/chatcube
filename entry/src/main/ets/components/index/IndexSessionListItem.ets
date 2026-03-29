import { ChatSession } from '../../models/ChatModels'
import { SessionCard } from '../SessionCard'
import { SessionListItemData } from '../../pages/index/IndexSessionListDataSource'
import { getAppUiState } from '../../state/AppUiState'

@ComponentV2
export struct IndexSessionListItem {
  @Param item: SessionListItemData = new SessionListItemData(new ChatSession('', '', ''), false, false)
  @Param isMultiSelectMode: boolean = false
  @Event onToggleSelection: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onOpenSession: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onDeleteSession: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onEnterMultiSelect: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onShareSession: (session: ChatSession) => void = (_session: ChatSession): void => {}
  @Event onToggleFavorite: (session: ChatSession) => void = (_session: ChatSession): void => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private handleTap(): void {
    if (this.isMultiSelectMode) {
      this.onToggleSelection(this.item.session.id)
      return
    }
    this.onOpenSession(this.item.session.id)
  }

  build() {
    SessionCard({
      session: this.item.session,
      enableAnimation: false,
      enableContextMenu: !this.isMultiSelectMode,
      onTap: (): void => {
        this.handleTap()
      },
      onDelete: (): void => {
        this.onDeleteSession(this.item.session.id)
      },
      onMultiSelect: (): void => {
        this.onEnterMultiSelect(this.item.session.id)
      },
      onShare: (): void => {
        this.onShareSession(this.item.session)
      },
      onToggleFavorite: (): void => {
        this.onToggleFavorite(this.item.session)
      }
    })
      .borderRadius(12)
      .clip(true)
      .border({
        width: 2,
        color: this.item.isSelected || this.item.isActive ? this.themePrimary : Color.Transparent
      })
      .opacity(this.isMultiSelectMode && !this.item.isSelected ? 0.5 : 1)
      .animation({ duration: 200 })
  }
}
