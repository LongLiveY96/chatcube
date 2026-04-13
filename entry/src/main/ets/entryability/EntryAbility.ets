import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { getPreferencesService, PreferenceKeys, ThemeMode, AppLanguage } from '../services/PreferencesService';
import { SettingsChangeCallback } from '../viewmodels/SettingsManager';
import { WindowManager } from '@kit.SpeechKit';
import { AppStorageKeys } from '../config/AppStorageKeys';
import { AppError } from '../models/AppError';
import { ServiceRegistry } from '../services/ServiceRegistry';
import { IconDownloadCache } from '../services/IconDownloadCache';
import { ModelCapabilityMatcher } from '../services/ModelCapabilityMatcher';
import { isExpandedLayoutClass, resolveLayoutSizeClass } from '../config/LayoutProfile';
import { setAppUiStateValue } from '../state/AppUiState';

const DOMAIN = 0x0000;

// Surface 颜色常量，需要与 color.json 保持一致（用于沉浸式效果）
const SURFACE_COLOR_LIGHT = '#FFFFFF';
const SURFACE_COLOR_DARK = '#1C1C1E';
const STATUS_BAR_CONTENT_LIGHT = '#1F2329';
const STATUS_BAR_CONTENT_DARK = '#F5F7FA';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private settingsCallback: SettingsChangeCallback | null = null;
  private pendingNewChat: boolean = false;
  private pendingOpenSessionPayload: string = '';
  private readonly windowSizeChangeCallback = (size: window.Size): void => {
    this.updateLayoutProfile(size.width, size.height);
  };
  // 启动时的关键初始化任务（偏好/数据库/主题等）。
  // 必须在 loadContent 之前完成，否则会出现“先默认主题后切换”的闪屏与设置项状态不同步。
  private servicesInitPromise: Promise<void> | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');

    // 检查是否从卡片点击进入
    if (want.parameters !== undefined && want.parameters !== null) {
      const action = want.parameters.action as string;
      if (action === 'newChat') {
        this.pendingNewChat = true;
      } else if (action === 'openSession') {
        const payload = want.parameters.payload as string
        const sessionId = want.parameters.sessionId as string
        if (payload !== undefined && payload !== '') {
          this.pendingOpenSessionPayload = payload
        } else if (sessionId !== undefined && sessionId !== '') {
          this.pendingOpenSessionPayload = JSON.stringify({
            sessionId: sessionId,
            taskId: '',
            source: 'notification',
            timestamp: Date.now()
          })
        }
      }
    }

    // 初始化服务
    this.servicesInitPromise = this.initializeServices();
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', 'Ability onNewWant');

    // 处理卡片点击跳转
    if (want.parameters !== undefined && want.parameters !== null) {
      const action = want.parameters.action as string;
      if (action === 'newChat') {
        // 通过 AppStorage 通知应用打开新聊天
        setAppUiStateValue(AppStorageKeys.OPEN_NEW_CHAT, Date.now());
      } else if (action === 'openSession') {
        const payload = want.parameters.payload as string
        const sessionId = want.parameters.sessionId as string
        if (payload !== undefined && payload !== '') {
          setAppUiStateValue(AppStorageKeys.OPEN_SESSION_PAYLOAD, payload)
        } else if (sessionId !== undefined && sessionId !== '') {
          setAppUiStateValue(AppStorageKeys.OPEN_SESSION_PAYLOAD, JSON.stringify({
            sessionId: sessionId,
            taskId: '',
            source: 'notification',
            timestamp: Date.now()
          }))
        }
      }
    }
  }

  private async initializeServices(): Promise<void> {
    try {
      // 初始化偏好设置服务
      await ServiceRegistry.preferences().initialize(this.context);
      hilog.info(DOMAIN, 'testTag', 'PreferencesService initialized successfully');

      await ServiceRegistry.language().migrateStoredLanguagePreference();
      hilog.info(DOMAIN, 'testTag', 'Language preference migrated successfully');

      // 预加载模型图标持久化索引（用于冷启动恢复图标）
      await ModelCapabilityMatcher.getInstance().loadPersistedLogoIndex();
      hilog.info(DOMAIN, 'testTag', 'Model logo index loaded successfully');

      // 初始化数据库服务
      await ServiceRegistry.database().initialize(this.context);
      hilog.info(DOMAIN, 'testTag', 'DatabaseService initialized successfully');

      // 初始化附件存储服务
      await ServiceRegistry.attachmentStorage().initialize(this.context);
      hilog.info(DOMAIN, 'testTag', 'AttachmentStorageService initialized successfully');

      // 初始化图标下载缓存服务
      await IconDownloadCache.getInstance().initialize(this.context);
      hilog.info(DOMAIN, 'testTag', 'IconDownloadCache initialized successfully');

      // 初始化设置管理器
      await ServiceRegistry.settings().initialize();
      hilog.info(DOMAIN, 'testTag', 'SettingsManager initialized successfully');

      // 初始化默认模型服务
      await ServiceRegistry.defaultModel().initialize();
      hilog.info(DOMAIN, 'testTag', 'DefaultModelService initialized successfully');

      // 助手模块暂缓，启动阶段不再初始化相关服务

      // 应用保存的主题设置
      void this.persistSystemDarkMode(this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      const themeMode = ServiceRegistry.settings().getThemeMode();
      const targetColorMode = ServiceRegistry.settings().getColorModeFromTheme(themeMode);
      this.setAppColorMode(targetColorMode);

      // 初始化主题配色服务（需要在主题设置应用后，获取当前深浅模式）
      const isDarkMode = targetColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        ? true
        : targetColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          ? false
          : this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      await ServiceRegistry.theme().initialize(isDarkMode);
      hilog.info(DOMAIN, 'testTag', 'ThemeService initialized successfully');

      // 提前同步深浅模式到 AppStorage，避免页面首次 build 时读到默认值
      setAppUiStateValue(AppStorageKeys.IS_DARK_MODE, isDarkMode);

      // 应用保存的语言设置
      await this.applyLanguageSettings();

      // 注册设置变化回调
      this.registerSettingsCallback();

      // 初始化后台任务守护与通知服务
      ServiceRegistry.backgroundGuard().initialize(this.context)
      ServiceRegistry.backgroundGuard().onAppBackgroundChanged(false)
    } catch (error) {
      if (error instanceof AppError) {
        hilog.error(
          DOMAIN,
          'testTag',
          'Failed to initialize services. code=%{public}s, message=%{public}s, cause=%{public}s',
          error.code,
          error.message,
          error.causeDetail
        );
      } else {
        hilog.error(DOMAIN, 'testTag', 'Failed to initialize services: %{public}s', JSON.stringify(error));
      }
    }
  }

  // 应用语言设置
  private async applyLanguageSettings(): Promise<void> {
    await ServiceRegistry.language().applyStoredLanguage(this.context);
  }

  // 设置应用颜色模式
  private setAppColorMode(colorMode: ConfigurationConstant.ColorMode): void {
    try {
      this.context.getApplicationContext().setColorMode(colorMode);
      hilog.info(DOMAIN, 'testTag', 'Color mode set to: %{public}s', colorMode.toString());
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  // 注册设置变化回调
  private registerSettingsCallback(): void {
    this.settingsCallback = {
      onThemeModeChanged: (mode: ThemeMode, colorMode: ConfigurationConstant.ColorMode): void => {
        this.setAppColorMode(colorMode);
        // 立即同步深浅模式与主题服务，避免等待系统配置回调导致的短暂闪动/状态不同步
        const isDarkMode = mode === ThemeMode.DARK
          ? true
          : mode === ThemeMode.LIGHT
            ? false
            : this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        this.updateColorModeStorage(colorMode);
        ServiceRegistry.theme().updateDarkMode(isDarkMode);
        this.updateWindowAppearance(colorMode);
      },
      onLanguageChanged: (language: AppLanguage): void => {
        ServiceRegistry.language().applyLanguage(this.context, language);
      }
    };
    ServiceRegistry.settings().registerCallback(this.settingsCallback);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    // 取消注册回调
    if (this.settingsCallback !== null) {
      ServiceRegistry.settings().unregisterCallback(this.settingsCallback);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 初始化 WindowManager（TextReader 需要）
    WindowManager.setWindowStage(windowStage);

    // ChatPage 已迁移为 NavDestination，始终加载 Index
    // 如果从卡片进入需要新建对话，通过 AppStorage 通知 Index
    if (this.pendingNewChat) {
      setAppUiStateValue(AppStorageKeys.OPEN_NEW_CHAT, Date.now())
    }
    this.pendingNewChat = false;
    const pagePath = 'pages/Index';

    // 等待关键初始化完成后再 loadContent，避免冷启动时主题闪烁与设置项状态不同步
    const loadAfterInit = async (): Promise<void> => {
      if (this.servicesInitPromise !== null) {
        try {
          await this.servicesInitPromise;
        } catch (error) {
          if (error instanceof AppError) {
            hilog.error(
              DOMAIN,
              'testTag',
              'Services init failed before loadContent. code=%{public}s, message=%{public}s, cause=%{public}s',
              error.code,
              error.message,
              error.causeDetail
            );
          } else {
            hilog.error(DOMAIN, 'testTag', 'Services init failed before loadContent: %{public}s', JSON.stringify(error));
          }
          // 初始化失败时仍然尝试进入页面，避免卡死在启动窗口
        }
      }

      windowStage.loadContent(pagePath, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      this.mainWindow = windowStage.getMainWindowSync();

      // 设置窗口全屏布局，实现完全沉浸式效果
      this.mainWindow.setWindowLayoutFullScreen(true).then(() => {
        hilog.info(DOMAIN, 'testTag', 'Window layout set to full screen');
      }).catch((error: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to set full screen: %{public}s', JSON.stringify(error));
      });

      // 获取避让区域高度并存储到 AppStorage
      this.updateAvoidAreaHeight();
      this.updateLayoutProfileFromWindow();

      // 监听避让区域变化
      this.mainWindow.on('avoidAreaChange', (data) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          const topHeight = data.area.topRect.height;
          setAppUiStateValue(AppStorageKeys.TOP_AVOID_HEIGHT, topHeight);
          hilog.info(DOMAIN, 'testTag', 'Top avoid area updated: %{public}d', topHeight);
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          const bottomHeight = data.area.bottomRect.height;
          setAppUiStateValue(AppStorageKeys.BOTTOM_AVOID_HEIGHT, bottomHeight);
          hilog.info(DOMAIN, 'testTag', 'Bottom avoid area updated: %{public}d', bottomHeight);
        }
      });
      this.mainWindow.on('windowSizeChange', this.windowSizeChangeCallback);

      // 设置窗口背景色与系统栏样式，确保冷启动时状态栏图标颜色与当前主题一致
      this.updateWindowAppearance();

      // 初始化颜色模式到 AppStorage
      this.updateColorModeStorage();
      // 初始化后台状态到 AppStorage
      setAppUiStateValue(AppStorageKeys.APP_IN_BACKGROUND, false);
      setAppUiStateValue(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, '')
      setAppUiStateValue(AppStorageKeys.SPEAKING_MESSAGE_ID, '')

      if (this.pendingOpenSessionPayload !== '') {
        setAppUiStateValue(AppStorageKeys.OPEN_SESSION_PAYLOAD, this.pendingOpenSessionPayload)
        this.pendingOpenSessionPayload = ''
      }
      });
    };
    loadAfterInit();
  }

  // 获取并更新避让区域高度
  private updateAvoidAreaHeight(): void {
    if (this.mainWindow === null) {
      return;
    }

    // 获取状态栏高度
    try {
      const systemAvoidArea = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const topHeight = systemAvoidArea.topRect.height;
      setAppUiStateValue(AppStorageKeys.TOP_AVOID_HEIGHT, topHeight);
      hilog.info(DOMAIN, 'testTag', 'Top avoid area height: %{public}d', topHeight);
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'Failed to get system avoid area: %{public}s', JSON.stringify(error));
      setAppUiStateValue(AppStorageKeys.TOP_AVOID_HEIGHT, 0);
    }

    // 获取导航条高度
    try {
      const navAvoidArea = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const bottomHeight = navAvoidArea.bottomRect.height;
      setAppUiStateValue(AppStorageKeys.BOTTOM_AVOID_HEIGHT, bottomHeight);
      hilog.info(DOMAIN, 'testTag', 'Bottom avoid area height: %{public}d', bottomHeight);
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'Failed to get navigation avoid area: %{public}s', JSON.stringify(error));
      setAppUiStateValue(AppStorageKeys.BOTTOM_AVOID_HEIGHT, 0);
    }
  }

  private updateLayoutProfileFromWindow(): void {
    if (this.mainWindow === null) {
      return;
    }
    try {
      const properties = this.mainWindow.getWindowProperties();
      this.updateLayoutProfile(properties.windowRect.width, properties.windowRect.height);
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'Failed to get window properties: %{public}s', JSON.stringify(error));
    }
  }

  private updateLayoutProfile(widthPx: number, heightPx: number): void {
    const widthVp = Math.round(this.pxToVp(widthPx));
    const heightVp = Math.round(this.pxToVp(heightPx));
    const sizeClass = resolveLayoutSizeClass(widthVp);
    setAppUiStateValue(AppStorageKeys.WINDOW_WIDTH_VP, widthVp);
    setAppUiStateValue(AppStorageKeys.WINDOW_HEIGHT_VP, heightVp);
    setAppUiStateValue(AppStorageKeys.LAYOUT_SIZE_CLASS, sizeClass);
    AppStorage.setOrCreate(AppStorageKeys.IS_EXPANDED_LAYOUT, isExpandedLayoutClass(sizeClass));
    hilog.info(
      DOMAIN,
      'testTag',
      'Layout profile updated. widthVp=%{public}d, heightVp=%{public}d, sizeClass=%{public}s',
      widthVp,
      heightVp,
      sizeClass
    );
  }

  private pxToVp(px: number): number {
    const density = this.context.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3;
    return px / density * 160;
  }

  // 监听配置变化（包括主题切换）
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, 'testTag', 'Configuration updated: %{public}s', JSON.stringify(newConfig));
    // 使用 newConfig.colorMode 获取最新系统深浅色，this.context.config 在回调时可能尚未更新
    const latestColorMode = newConfig.colorMode ?? this.context.config.colorMode;
    void this.persistSystemDarkMode(latestColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    this.updateWindowAppearance(latestColorMode);
    this.updateColorModeStorage(latestColorMode);

    void ServiceRegistry.language().handleSystemConfigurationUpdate(this.context);

    // 更新主题服务的深浅模式
    const themeMode = ServiceRegistry.settings().getThemeMode();
    const isDarkMode = themeMode === ThemeMode.DARK
      ? true
      : themeMode === ThemeMode.LIGHT
        ? false
        : latestColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    ServiceRegistry.theme().updateDarkMode(isDarkMode);
  }

  // 更新颜色模式到 AppStorage
  private updateColorModeStorage(colorMode?: ConfigurationConstant.ColorMode): void {
    const isDarkMode = this.resolveIsDarkMode(colorMode);
    setAppUiStateValue(AppStorageKeys.IS_DARK_MODE, isDarkMode);
    hilog.info(DOMAIN, 'testTag', 'isDarkMode updated: %{public}s', isDarkMode.toString());
  }

  private resolveIsDarkMode(colorMode?: ConfigurationConstant.ColorMode): boolean {
    const themeMode = ServiceRegistry.settings().getThemeMode();
    const effectiveColorMode = colorMode ?? this.context.config.colorMode;
    return themeMode === ThemeMode.DARK
      ? true
      : themeMode === ThemeMode.LIGHT
        ? false
        : effectiveColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  // 根据当前主题更新窗口背景色与系统栏样式
  private updateWindowAppearance(colorMode?: ConfigurationConstant.ColorMode): void {
    if (this.mainWindow === null) {
      return;
    }
    const isDarkMode = this.resolveIsDarkMode(colorMode);
    const backgroundColor = isDarkMode ? SURFACE_COLOR_DARK : SURFACE_COLOR_LIGHT;
    const statusBarContentColor = isDarkMode ? STATUS_BAR_CONTENT_DARK : STATUS_BAR_CONTENT_LIGHT;
    try {
      this.mainWindow.setWindowBackgroundColor(backgroundColor);
      hilog.info(DOMAIN, 'testTag', 'Window background color set to: %{public}s', backgroundColor);
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set window background color: %{public}s', JSON.stringify(error));
    }
    this.mainWindow.setWindowSystemBarProperties({
      statusBarContentColor: statusBarContentColor
    }).then(() => {
      hilog.info(
        DOMAIN,
        'testTag',
        'Window system bar updated. statusContent=%{public}s',
        statusBarContentColor
      );
    }).catch((error: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to set window system bar properties: %{public}s', JSON.stringify(error));
    });
  }

  private async persistSystemDarkMode(isDarkMode: boolean): Promise<void> {
    await getPreferencesService().setBoolean(PreferenceKeys.SYSTEM_DARK_MODE, isDarkMode)
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    if (this.mainWindow !== null) {
      try {
        this.mainWindow.off('windowSizeChange', this.windowSizeChangeCallback);
      } catch (error) {
        hilog.error(DOMAIN, 'testTag', 'Failed to unregister windowSizeChange: %{public}s', JSON.stringify(error));
      }
    }
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    setAppUiStateValue(AppStorageKeys.APP_IN_BACKGROUND, false);
    this.updateWindowAppearance();
    ServiceRegistry.backgroundGuard().onAppBackgroundChanged(false)
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    setAppUiStateValue(AppStorageKeys.APP_IN_BACKGROUND, true);
    ServiceRegistry.backgroundGuard().onAppBackgroundChanged(true)
  }
}
