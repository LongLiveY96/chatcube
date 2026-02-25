import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';
import { ColorTheme, getThemeColors } from '../models/ThemeColors';
import { AppStorageKeys } from '../config/AppStorageKeys';

const DOMAIN = 0x0000;

// 表单数据接口
class FormData {
  title: string = '';
  subtitle: string = '';
  themePrimary: string = '#0A59F7';
}

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onAddForm called');

    const formData = new FormData();
    formData.title = '新对话';
    formData.subtitle = '点击开始聊天';

    // 同步获取主题色（异步加载后更新）
    this.loadThemeColorAndUpdate(want);

    return formBindingData.createFormBindingData(formData);
  }

  // 异步加载主题色并更新卡片
  private async loadThemeColorAndUpdate(want: Want): Promise<void> {
    try {
      const color = await this.loadThemeColor();
      const formId = want.parameters?.['ohos.extra.param.key.form_identity'] as string;
      if (formId) {
        const formData = new FormData();
        formData.title = '新对话';
        formData.subtitle = '点击开始聊天';
        formData.themePrimary = color;

        const bindingData = formBindingData.createFormBindingData(formData);
        formProvider.updateForm(formId, bindingData);
      }
    } catch (e) {
      hilog.error(DOMAIN, 'EntryFormAbility', 'Failed to update form: %{public}s', JSON.stringify(e));
    }
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onCastToNormalForm: %{public}s', formId);
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onUpdateForm: %{public}s', formId);

    // 更新卡片时重新获取主题色
    this.loadThemeColor().then((color: string) => {
      const formData = new FormData();
      formData.title = '新对话';
      formData.subtitle = '点击开始聊天';
      formData.themePrimary = color;

      const bindingData = formBindingData.createFormBindingData(formData);
      formProvider.updateForm(formId, bindingData);
    });
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onFormEvent: %{public}s, message: %{public}s', formId, message);
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onRemoveForm: %{public}s', formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    hilog.info(DOMAIN, 'EntryFormAbility', 'onAcquireFormState called');
    return formInfo.FormState.READY;
  }

  // 从偏好设置加载主题色
  private async loadThemeColor(): Promise<string> {
    try {
      const store = await preferences.getPreferences(this.context, 'chatbox_preferences');
      const themeId = await store.get(AppStorageKeys.COLOR_THEME, ColorTheme.DEFAULT) as string;
      const colors = getThemeColors(themeId as ColorTheme, false);
      return colors.primary;
    } catch (e) {
      hilog.error(DOMAIN, 'EntryFormAbility', 'Failed to load theme color: %{public}s', JSON.stringify(e));
      return '#0A59F7';
    }
  }
}
