import { loginComponentManager, LoginWithHuaweiIDButton } from '@kit.AccountKit'
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit'
import { bundleManager, common, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { getAppUiState } from '../state/AppUiState'
import { showToast } from '../utils/ToastUtil'

const DOMAIN = 0x0000
const LOG_TAG = 'LoginPage'

// ChatCube 隐私政策（复用 PrivacyPolicyPage 的 AppGallery 托管地址）
const PRIVACY_POLICY_URL: string =
  'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1906111586003597632'
// 华为账号用户认证协议（官方）
const HUAWEI_AUTH_AGREEMENT_URL: string =
  'https://privacy.consumer.huawei.com/legal/id/authentication-terms.htm?code=CN&language=zh-CN'

// Account Kit 官方错误码（摘自一键登录最佳实践 QA）
const ERROR_CODE_NETWORK_ERROR: number = 1001502001
const ERROR_CODE_NETWORK_ERROR_ALT: number = 1001502005
const ERROR_CODE_AGREEMENT_NOT_ACCEPTED: number = 1001502010
// HarmonyOS 6 / API 23 上 LoginWithHuaweiIDButtonController 抛出的"用户未同意协议"错误码
const ERROR_CODE_AGREEMENT_NOT_ACCEPTED_V2: number = 1005300001
const ERROR_CODE_LOGIN_OUT: number = 1001502009
const ERROR_CODE_USER_CANCEL: number = 1001502012

@Entry
@ComponentV2
struct LoginPage {
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get bottomAvoidHeight(): number {
    return getAppUiState().bottomAvoidHeight
  }

  // 正在登录中（给按钮 loading 态）
  @Local submitting: boolean = false

  private loginButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED)
      .onClickLoginWithHuaweiIDButton(
        (error: BusinessError | undefined, response: loginComponentManager.HuaweiIDCredential): void => {
          this.handleLoginResult(error, response)
        })
      .onClickEvent((error: BusinessError, clickEvent: loginComponentManager.ClickEvent): void => {
        if (error !== null && error !== undefined) {
          this.handleBusinessError(error)
          return
        }
        hilog.info(DOMAIN, LOG_TAG, 'LoginWithHuaweiIDButton clickEvent=%{public}d', clickEvent as number)
      })

  private agreementDialog: CustomDialogController = new CustomDialogController({
    builder: AgreementConfirmDialog({
      onAgree: (): void => {
        this.loginButtonController.setAgreementStatus(loginComponentManager.AgreementStatus.ACCEPTED)
        this.agreementDialog.close()
        this.submitting = true
        this.loginButtonController.continueLogin((err: BusinessError): void => {
          if (err !== null && err !== undefined) {
            hilog.error(DOMAIN, LOG_TAG, 'continueLogin failed: %{public}s', JSON.stringify(err))
            this.handleBusinessError(err)
            this.submitting = false
          }
        })
      },
      onCancel: (): void => {
        this.agreementDialog.close()
        this.submitting = false
      }
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    customStyle: true
  })

  aboutToAppear(): void {
    this.tryAutoSkipForDevEmulator()
  }

  /**
   * Debug 构建 + DevEco 模拟器场景下，Account Kit 无法真登录。
   * 这里用一个占位账号静默跳过，让开发者能直接看到主页 UI。
   * 真机 debug 构建 **不** 触发，Release 构建也不会触发。
   * 通过 HW_PREVENT_AUTO_SKIP_ONCE flag 避免"退出登录 → 自动跳回主页"循环。
   */
  private tryAutoSkipForDevEmulator(): boolean {
    if (!isDevEmulatorBypassEnabled()) {
      return false
    }
    const preventFlag: boolean = AppStorage.get<boolean>(AppStorageKeys.HW_PREVENT_AUTO_SKIP_ONCE) === true
    if (preventFlag) {
      AppStorage.setOrCreate(AppStorageKeys.HW_PREVENT_AUTO_SKIP_ONCE, false)
      hilog.info(DOMAIN, LOG_TAG, 'Auto-skip disabled once by logout flag.')
      return false
    }
    hilog.warn(DOMAIN, LOG_TAG, 'DEV emulator detected. Auto-skipping Huawei ID login.')
    ServiceRegistry.account().saveLoginState('dev-openid', 'dev-unionid', '开发者（模拟器）', '').then((): void => {
      this.switchToMainContent()
    }).catch((error: Object): void => {
      hilog.error(DOMAIN, LOG_TAG, 'Auto-skip saveLoginState failed: %{public}s', JSON.stringify(error))
    })
    return true
  }

  private handleLoginResult(error: BusinessError | undefined,
    response: loginComponentManager.HuaweiIDCredential): void {
    if (error !== null && error !== undefined) {
      if (error.code === ERROR_CODE_AGREEMENT_NOT_ACCEPTED
        || error.code === ERROR_CODE_AGREEMENT_NOT_ACCEPTED_V2) {
        this.agreementDialog.open()
        return
      }
      this.handleBusinessError(error)
      this.submitting = false
      return
    }

    const openId: string = response.openID ?? ''
    const unionId: string = response.unionID ?? ''
    hilog.info(DOMAIN, LOG_TAG, 'Huawei ID login ok. hasOpenId=%{public}s, hasUnionId=%{public}s',
      openId !== '' ? 'true' : 'false',
      unionId !== '' ? 'true' : 'false')

    this.submitting = true
    this.finishLogin(openId, unionId)
  }

  /**
   * 个人开发者账号无法申请 profile / email / quickLoginAnonymousPhone 权限，
   * 直接以空 nickName/avatarUri 登录；设置页有默认兜底。
   */
  private finishLogin(openId: string, unionId: string): void {
    ServiceRegistry.account().saveLoginState(openId, unionId, '', '').then((): void => {
      this.switchToMainContent()
    }).catch((error: Object): void => {
      hilog.error(DOMAIN, LOG_TAG, 'Save login state failed: %{public}s', JSON.stringify(error))
      this.submitting = false
      showToast(this.getUIContext(), $r('app.string.hw_login_error_generic'))
    })
  }

  private switchToMainContent(): void {
    const stage: window.WindowStage | undefined =
      AppStorage.get<window.WindowStage>(AppStorageKeys.MAIN_WINDOW_STAGE)
    if (stage === undefined) {
      hilog.error(DOMAIN, LOG_TAG, 'MainWindowStage not found; cannot switch to Index.')
      this.submitting = false
      return
    }
    stage.loadContent('pages/Index', (err: BusinessError): void => {
      if (err !== null && err !== undefined && err.code !== 0) {
        hilog.error(DOMAIN, LOG_TAG, 'loadContent Index failed: %{public}s', JSON.stringify(err))
        this.submitting = false
        return
      }
      hilog.info(DOMAIN, LOG_TAG, 'Switched to Index after login.')
    })
  }

  private handleBusinessError(error: BusinessError): void {
    hilog.error(DOMAIN, LOG_TAG, 'AccountKit error. code=%{public}d, message=%{public}s', error.code, error.message)
    if (error.code === ERROR_CODE_USER_CANCEL) {
      return
    }
    let messageRes: Resource = $r('app.string.hw_login_error_generic')
    if (error.code === ERROR_CODE_NETWORK_ERROR || error.code === ERROR_CODE_NETWORK_ERROR_ALT) {
      messageRes = $r('app.string.hw_login_error_network')
    } else if (error.code === ERROR_CODE_LOGIN_OUT) {
      messageRes = $r('app.string.hw_login_error_not_logged_in')
    }
    showToast(this.getUIContext(), messageRes)
  }

  private openBrowsableUri(url: string): void {
    const hostContext = this.getUIContext().getHostContext()
    if (hostContext === null || hostContext === undefined) {
      hilog.error(DOMAIN, LOG_TAG, 'HostContext missing, cannot open URL: %{public}s', url)
      return
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    }
    ;(hostContext as common.UIAbilityContext).startAbility(want).catch((error: BusinessError): void => {
      hilog.error(DOMAIN, LOG_TAG, 'Open browsable URL failed: %{public}s, error: %{public}s',
        url, JSON.stringify(error))
      showToast(this.getUIContext(), $r('app.string.hw_login_error_generic'))
    })
  }

  // ================= UI =================

  /** 品牌展示区：App 图标 + 双层光晕 + 标题 + 副标题 */
  @Builder
  private BrandBlock() {
    Column() {
      // 外层光晕 + 图标
      Stack({ alignContent: Alignment.Center }) {
        // 最外圈：主题色柔光
        Column()
          .width(184)
          .height(184)
          .borderRadius(92)
          .backgroundColor(this.themePrimary)
          .opacity(0.06)

        // 中圈：主题色稍强光
        Column()
          .width(136)
          .height(136)
          .borderRadius(68)
          .backgroundColor(this.themePrimary)
          .opacity(0.12)

        // App 图标
        Image($r('app.media.app_icon'))
          .width(104)
          .height(104)
          .borderRadius(28)
          .objectFit(ImageFit.Contain)
          .shadow({
            radius: 24,
            color: '#1F000000',
            offsetX: 0,
            offsetY: 8
          })
      }
      .margin({ bottom: 28 })

      Text($r('app.string.hw_login_welcome_title'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .letterSpacing(0.5)
        .margin({ bottom: 10 })

      Text($r('app.string.hw_login_welcome_subtitle'))
        .fontSize(14)
        .lineHeight(22)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .padding({ left: 40, right: 40 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 登录按钮 + 隐私协议 */
  @Builder
  private LoginBlock() {
    Column() {
      LoginWithHuaweiIDButton({
        params: {
          style: loginComponentManager.Style.BUTTON_RED,
          borderRadius: 24,
          loginType: loginComponentManager.LoginType.ID,
          supportDarkMode: true,
          extraStyle: {
            buttonStyle: new loginComponentManager.ButtonStyle().loadingStyle({ show: this.submitting })
          }
        },
        controller: this.loginButtonController
      })
        .width('100%')
        .height(48)

      this.PrivacyHintBlock()
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
  }

  @Builder
  private PrivacyHintBlock() {
    Column() {
      Text() {
        Span($r('app.string.hw_login_privacy_prefix'))
          .fontColor($r('app.color.text_secondary'))
        Span($r('app.string.hw_login_privacy_policy'))
          .fontColor(this.themePrimary)
          .onClick((): void => {
            this.openBrowsableUri(PRIVACY_POLICY_URL)
          })
        Span($r('app.string.hw_login_privacy_conj'))
          .fontColor($r('app.color.text_secondary'))
        Span($r('app.string.hw_login_privacy_huawei'))
          .fontColor(this.themePrimary)
          .onClick((): void => {
            this.openBrowsableUri(HUAWEI_AUTH_AGREEMENT_URL)
          })
        Span($r('app.string.hw_login_privacy_suffix'))
          .fontColor($r('app.color.text_secondary'))
      }
      .fontSize(12)
      .lineHeight(18)
      .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 16 })
  }

  build() {
    Column() {
      Column()
        .width('100%')
        .height(this.px2vp(this.topAvoidHeight))

      Column() {
        Blank().layoutWeight(1)

        this.BrandBlock()

        Blank().layoutWeight(2)

        this.LoginBlock()
      }
      .width('100%')
      .layoutWeight(1)

      Column()
        .width('100%')
        .height(this.px2vp(this.bottomAvoidHeight) + 24)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  private px2vp(px: number): number {
    const density: number =
      this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3
    return px / density * 160
  }
}

let cachedDevEmulatorBypass: boolean | null = null

/**
 * 是否启用"debug 构建 + 模拟器自动跳过登录"。
 * - debug 判断：bundleManager.getBundleInfoForSelfSync 得到的 appProvisionType === 'debug'
 * - 模拟器判断：deviceInfo.productModel === 'emulator'
 * 只有两个条件都满足才返回 true，release 包永不触发。
 * 结果缓存一次，避免重复查询。
 */
function isDevEmulatorBypassEnabled(): boolean {
  if (cachedDevEmulatorBypass !== null) {
    return cachedDevEmulatorBypass
  }
  let isDebug: boolean = false
  try {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
    isDebug = info.appInfo.appProvisionType === 'debug'
  } catch (error) {
    hilog.error(DOMAIN, LOG_TAG, 'Failed to resolve appProvisionType: %{public}s', JSON.stringify(error))
  }
  let isEmulator: boolean = false
  try {
    isEmulator = deviceInfo.productModel === 'emulator'
  } catch (error) {
    hilog.error(DOMAIN, LOG_TAG, 'Failed to resolve productModel: %{public}s', JSON.stringify(error))
  }
  cachedDevEmulatorBypass = isDebug && isEmulator
  if (cachedDevEmulatorBypass) {
    hilog.warn(DOMAIN, LOG_TAG, 'Dev emulator bypass enabled (debug=%{public}s, emulator=%{public}s).',
      isDebug ? 'true' : 'false', isEmulator ? 'true' : 'false')
  }
  return cachedDevEmulatorBypass
}

@CustomDialog
struct AgreementConfirmDialog {
  controller: CustomDialogController
  onAgree: () => void = (): void => {}
  onCancel: () => void = (): void => {}

  build() {
    Column() {
      Column() {
        Text($r('app.string.hw_login_agreement_dialog_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 12 })

        Text($r('app.string.hw_login_agreement_dialog_desc'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 24, bottom: 20 })
      .alignItems(HorizontalAlign.Start)

      Row() {
        Button($r('app.string.hw_login_agreement_cancel'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.divider'))
          .fontColor($r('app.color.text_primary'))
          .onClick((): void => {
            this.onCancel()
          })

        Button($r('app.string.hw_login_agreement_agree'))
          .layoutWeight(1)
          .height(44)
          .margin({ left: 12 })
          .onClick((): void => {
            this.onAgree()
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 20 })
    }
    .width('86%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(24)
  }
}
