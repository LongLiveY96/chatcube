import { Context } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { getPreferencesService, PreferenceKeys, PreferencesService } from './PreferencesService'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { setAppUiStateValue } from '../state/AppUiState'

const DOMAIN = 0x0000
const LOG_TAG = 'AccountService'

/**
 * 华为账号登录态最小数据模型。
 * avatarUri / nickName 可选：一键登录回调只给 openID/unionID，
 * profile 需要再次 createAuthorizationWithHuaweiIDRequest 静默获取，
 * 静默失败时 avatar/nickName 可能为空。
 */
export class HuaweiAccountInfo {
  loggedIn: boolean = false
  openId: string = ''
  unionId: string = ''
  nickName: string = ''
  avatarUri: string = ''
}

/**
 * AccountService：应用层的华为账号登录态管理。
 * - 持久化：PreferencesService（chatbox_preferences）
 * - UI 响应：AppStorage（hwAccountLoggedIn / hwAccountNickName / hwAccountAvatarUri）
 * - 不触达 Account Kit 的登出/取消授权接口；退出登录只清本地态。
 */
export class AccountService {
  private static instance: AccountService | null = null
  private isInitialized: boolean = false
  private cachedAccount: HuaweiAccountInfo = new HuaweiAccountInfo()

  private constructor() {
  }

  static getInstance(): AccountService {
    if (AccountService.instance === null) {
      AccountService.instance = new AccountService()
    }
    return AccountService.instance
  }

  /**
   * 从 Preferences 读取登录态到内存，同步一份到 AppStorage。
   * 在 EntryAbility.initializeServices 的 PreferencesService 初始化之后调用。
   */
  async initialize(_context: Context): Promise<void> {
    if (this.isInitialized) {
      return
    }
    try {
      const preferences: PreferencesService = getPreferencesService()
      const loggedIn: boolean = await preferences.getBoolean(PreferenceKeys.HW_ACCOUNT_LOGGED_IN, false)
      const openId: string = await preferences.getString(PreferenceKeys.HW_ACCOUNT_OPEN_ID, '')
      const unionId: string = await preferences.getString(PreferenceKeys.HW_ACCOUNT_UNION_ID, '')
      const nickName: string = await preferences.getString(PreferenceKeys.HW_ACCOUNT_NICK_NAME, '')
      const avatarUri: string = await preferences.getString(PreferenceKeys.HW_ACCOUNT_AVATAR_URI, '')

      const account = new HuaweiAccountInfo()
      account.loggedIn = loggedIn
      account.openId = openId
      account.unionId = unionId
      account.nickName = nickName
      account.avatarUri = avatarUri

      this.cachedAccount = account
      this.syncToAppStorage(account)
      this.isInitialized = true

      hilog.info(DOMAIN, LOG_TAG, 'Account loaded. loggedIn=%{public}s, hasNick=%{public}s, hasAvatar=%{public}s',
        loggedIn ? 'true' : 'false',
        nickName !== '' ? 'true' : 'false',
        avatarUri !== '' ? 'true' : 'false')
    } catch (error) {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to load account: %{public}s', JSON.stringify(error))
      // 读失败也当作未登录，避免卡在启动阶段
      this.cachedAccount = new HuaweiAccountInfo()
      this.syncToAppStorage(this.cachedAccount)
      this.isInitialized = true
    }
  }

  isLoggedIn(): boolean {
    return this.cachedAccount.loggedIn
  }

  getAccount(): HuaweiAccountInfo {
    return this.cachedAccount
  }

  /**
   * 登录成功时调用：写 Preferences + 同步 AppStorage。
   * openId / unionId 至少一个必须有值；nickName / avatarUri 可能为空。
   */
  async saveLoginState(openId: string, unionId: string, nickName: string, avatarUri: string): Promise<void> {
    const normalizedOpenId: string = openId !== '' ? openId : ''
    const normalizedUnionId: string = unionId !== '' ? unionId : ''
    const normalizedNickName: string = nickName !== '' ? nickName : ''
    const normalizedAvatarUri: string = avatarUri !== '' ? avatarUri : ''

    const account = new HuaweiAccountInfo()
    account.loggedIn = true
    account.openId = normalizedOpenId
    account.unionId = normalizedUnionId
    account.nickName = normalizedNickName
    account.avatarUri = normalizedAvatarUri

    try {
      const preferences: PreferencesService = getPreferencesService()
      await preferences.setBoolean(PreferenceKeys.HW_ACCOUNT_LOGGED_IN, true)
      await preferences.setString(PreferenceKeys.HW_ACCOUNT_OPEN_ID, normalizedOpenId)
      await preferences.setString(PreferenceKeys.HW_ACCOUNT_UNION_ID, normalizedUnionId)
      await preferences.setString(PreferenceKeys.HW_ACCOUNT_NICK_NAME, normalizedNickName)
      await preferences.setString(PreferenceKeys.HW_ACCOUNT_AVATAR_URI, normalizedAvatarUri)
      this.cachedAccount = account
      this.syncToAppStorage(account)
      hilog.info(DOMAIN, LOG_TAG, 'Login state saved. hasNick=%{public}s, hasAvatar=%{public}s',
        normalizedNickName !== '' ? 'true' : 'false',
        normalizedAvatarUri !== '' ? 'true' : 'false')
    } catch (error) {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to save login state: %{public}s', JSON.stringify(error))
      throw error as Error
    }
  }

  /**
   * 仅在登录成功后 profile 授权拿到新头像/昵称时调用，补齐展示数据。
   * 不改变 loggedIn 状态。
   */
  async updateProfile(nickName: string, avatarUri: string): Promise<void> {
    if (!this.cachedAccount.loggedIn) {
      return
    }
    const preferences: PreferencesService = getPreferencesService()
    try {
      await preferences.setString(PreferenceKeys.HW_ACCOUNT_NICK_NAME, nickName)
      await preferences.setString(PreferenceKeys.HW_ACCOUNT_AVATAR_URI, avatarUri)
      this.cachedAccount.nickName = nickName
      this.cachedAccount.avatarUri = avatarUri
      setAppUiStateValue<string>(AppStorageKeys.HW_ACCOUNT_NICK_NAME, nickName)
      setAppUiStateValue<string>(AppStorageKeys.HW_ACCOUNT_AVATAR_URI, avatarUri)
    } catch (error) {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to update profile: %{public}s', JSON.stringify(error))
    }
  }

  /**
   * 退出登录：仅清本地登录态，不调 Account Kit 的 cancelAuthorization。
   * 这样下次再点一键登录依然是静默体验。
   */
  async clearLoginState(): Promise<void> {
    try {
      const preferences: PreferencesService = getPreferencesService()
      await preferences.setBoolean(PreferenceKeys.HW_ACCOUNT_LOGGED_IN, false)
      await preferences.remove(PreferenceKeys.HW_ACCOUNT_OPEN_ID)
      await preferences.remove(PreferenceKeys.HW_ACCOUNT_UNION_ID)
      await preferences.remove(PreferenceKeys.HW_ACCOUNT_NICK_NAME)
      await preferences.remove(PreferenceKeys.HW_ACCOUNT_AVATAR_URI)
    } catch (error) {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to clear login state: %{public}s', JSON.stringify(error))
    }
    this.cachedAccount = new HuaweiAccountInfo()
    this.syncToAppStorage(this.cachedAccount)
    hilog.info(DOMAIN, LOG_TAG, 'Login state cleared.')
  }

  private syncToAppStorage(account: HuaweiAccountInfo): void {
    setAppUiStateValue<boolean>(AppStorageKeys.HW_ACCOUNT_LOGGED_IN, account.loggedIn)
    setAppUiStateValue<string>(AppStorageKeys.HW_ACCOUNT_NICK_NAME, account.nickName)
    setAppUiStateValue<string>(AppStorageKeys.HW_ACCOUNT_AVATAR_URI, account.avatarUri)
  }
}

export function getAccountService(): AccountService {
  return AccountService.getInstance()
}
