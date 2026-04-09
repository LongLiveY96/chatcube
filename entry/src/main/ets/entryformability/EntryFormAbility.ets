import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import resourceManager from '@ohos.resourceManager';
import {
  createNewChatFormBindingData,
  readFormIdFromWant,
  refreshThemeAwareFormWithStoredTheme,
  registerThemeAwareFormId,
  unregisterThemeAwareFormId
} from '../utils/FormThemeSyncUtils';
import { ColorTheme, getThemeColors } from '../models/ThemeColors';

const DOMAIN = 0x0000;

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onAddForm called');
    void this.registerAndRefreshForm(want);
    const darkMode = this.isSystemDarkMode()
    return createNewChatFormBindingData(getThemeColors(ColorTheme.DEFAULT, darkMode), darkMode);
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onCastToNormalForm: %{public}s', formId);
  }

  onUpdateForm(formId: string, _wantParams?: Record<string, Object>): void {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onUpdateForm: %{public}s', formId);
    void this.refreshRegisteredForm(formId);
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onFormEvent: %{public}s, message: %{public}s', formId, message);
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onRemoveForm: %{public}s', formId);
    void unregisterThemeAwareFormId(this.context, formId).catch((error: Object) => {
      hilog.error(DOMAIN, 'EntryFormAbility', 'Failed to unregister form: %{public}s', JSON.stringify(error));
    });
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onAcquireFormState called');
    return formInfo.FormState.READY;
  }

  private isSystemDarkMode(): boolean {
    try {
      const config = this.context.resourceManager.getConfigurationSync()
      return config.colorMode === resourceManager.ColorMode.DARK
    } catch (_) {
      return false
    }
  }

  private async registerAndRefreshForm(want: Want): Promise<void> {
    try {
      const formId = readFormIdFromWant(want);
      if (formId === '') {
        return;
      }
      await registerThemeAwareFormId(this.context, formId);
      await this.refreshRegisteredForm(formId);
    } catch (error) {
      hilog.error(DOMAIN, 'EntryFormAbility', 'Failed to register form: %{public}s', JSON.stringify(error));
    }
  }

  private async refreshRegisteredForm(formId: string): Promise<void> {
    try {
      await refreshThemeAwareFormWithStoredTheme(this.context, formId);
    } catch (error) {
      hilog.error(DOMAIN, 'EntryFormAbility', 'Failed to update form: %{public}s', JSON.stringify(error));
    }
  }
}
