import { ThemeAppearanceSettingsView } from './ThemeModeSettingsPage'

@Entry
@Component
struct FontSizeSettingsPage {
  build() {
    Column() {
      ThemeAppearanceSettingsView()
    }
    .width('100%')
    .height('100%')
  }
}

@Builder
export function FontSizeSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    FontSizeSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
}
