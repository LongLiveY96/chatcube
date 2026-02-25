/**
 * 日期分隔符组件
 * 用于在消息列表中显示日期分隔
 */

import { formatDateDivider } from '../utils/DateFormatUtils'

@Component
export struct DateDivider {
  // 时间戳
  timestamp: number = 0

  build() {
    Row() {
      Text(formatDateDivider(this.timestamp))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_tertiary'))
        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        .backgroundColor(Color.Transparent)
        .borderRadius(8)
        .border({ width: 0.5, color: $r('app.color.divider') })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 16, bottom: 10 })
  }
}
