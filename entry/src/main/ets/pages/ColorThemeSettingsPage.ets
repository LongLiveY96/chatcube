import { ThemeAppearanceSettingsView } from './ThemeModeSettingsPage'

@Entry
@ComponentV2
struct ColorThemeSettingsPage {
  build() {
    Column() {
      ThemeAppearanceSettingsView()
    }
    .width('100%')
    .height('100%')
  }
}

@Builder
export function ColorThemeSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    ColorThemeSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
}
