import { LengthMetrics } from '@kit.ArkUI'
import { HdsActionBar, ActionBarButton, ActionBarStyle } from '@kit.UIDesignKit'

/**
 * 多选工具栏组件
 * 用于消息/会话多选模式下的批量操作
 */
@ComponentV2
export struct MultiSelectToolbar {
  @Param selectedCount: number = 0
  @Param totalCount: number = 0
  @Event onSelectAll: () => void = () => {}
  @Event onDelete: () => void = () => {}
  @Event onShare: () => void = () => {}
  @Event onCancel: () => void = () => {}

  private isAllSelected(): boolean {
    return this.totalCount > 0 && this.selectedCount === this.totalCount
  }

  private buildStartButtons(): Array<ActionBarButton> {
    const buttons: Array<ActionBarButton> = []
    buttons.push(new ActionBarButton({
      baseIcon: $r('sys.symbol.xmark'),
      onClick: (): void => {
        this.onCancel()
      }
    }))
    buttons.push(new ActionBarButton({
      baseIcon: this.isAllSelected() ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'),
      enabled: this.totalCount > 0,
      onClick: (): void => {
        this.onSelectAll()
      }
    }))
    return buttons
  }

  private buildEndButtons(): Array<ActionBarButton> {
    const buttons: Array<ActionBarButton> = []
    buttons.push(new ActionBarButton({
      baseIcon: $r('sys.symbol.share'),
      enabled: this.selectedCount > 0,
      onClick: (): void => {
        this.onShare()
      }
    }))
    buttons.push(new ActionBarButton({
      baseIcon: $r('sys.symbol.trash'),
      enabled: this.selectedCount > 0,
      onClick: (): void => {
        this.onDelete()
      }
    }))
    return buttons
  }

  private buildActionBarStyle(): ActionBarStyle {
    return new ActionBarStyle({
      margin: LengthMetrics.vp(16)
    })
  }

  build() {
    Column() {
      Text(`已选 ${this.selectedCount} 条`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 16, right: 16, bottom: 6 })

      HdsActionBar({
        startButtons: this.buildStartButtons(),
        endButtons: this.buildEndButtons(),
        actionBarStyle: this.buildActionBarStyle()
      })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .backgroundColor($r('app.color.background'))
    .shadow({
      radius: 8,
      color: 'rgba(0, 0, 0, 0.08)',
      offsetX: 0,
      offsetY: -2
    })
  }
}
