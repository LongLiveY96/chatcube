import { ThemeAppearanceSettingsView } from './ThemeModeSettingsPage'

let fontSizeSettingsPathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct FontSizeSettingsPage {
  private handleBack(): void {
    if (fontSizeSettingsPathStack !== null && fontSizeSettingsPathStack.size() > 0) {
      fontSizeSettingsPathStack.pop()
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
export function FontSizeSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    FontSizeSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    fontSizeSettingsPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (fontSizeSettingsPathStack !== null && fontSizeSettingsPathStack.size() > 0) {
      fontSizeSettingsPathStack.pop()
    }
    return true
  })
}
