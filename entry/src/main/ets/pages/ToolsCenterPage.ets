import { ToolsCenterPanel } from '../components/ToolsCenterPanel'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'

@Entry
@Component
struct ToolsCenterPage {
  build() {
    Column() {
      HdsNavigation() {
        Column() {
          ToolsCenterPanel({ showHeader: false })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background'))
      .titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: true,
        content: {
          title: {
            mainTitle: $r('app.string.tools_center_title')
          }
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
