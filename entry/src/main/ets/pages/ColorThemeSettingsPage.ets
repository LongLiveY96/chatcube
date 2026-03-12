import { ThemeAppearanceSettingsView } from './ThemeModeSettingsPage'

let colorThemeSettingsPathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct ColorThemeSettingsPage {
  private handleBack(): void {
    if (colorThemeSettingsPathStack !== null && colorThemeSettingsPathStack.size() > 0) {
      colorThemeSettingsPathStack.pop()
    }
  }

  build() {
    Column() {
      ThemeAppearanceSettingsView({
        compactTitle: $r('app.string.settings_appearance'),
        onCompactBack: () => {
          this.handleBack()
        }
      })
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
  .onReady((context: NavDestinationContext) => {
    colorThemeSettingsPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (colorThemeSettingsPathStack !== null && colorThemeSettingsPathStack.size() > 0) {
      colorThemeSettingsPathStack.pop()
    }
    return true
  })
}
