import { describe, it, expect } from '@ohos/hypium'
import { ModelInfo, ChatSession, ModelProvider, ProviderType, ApiStyle } from '../main/ets/models/ChatModels'
import {
  buildProviderModelGroups,
  filterProviderModelsByKeyword
} from '../main/ets/config/ProviderDetailShared'
import {
  buildModelSelectorRows,
  buildModelPickerRows,
  ModelRowGroupPosition,
  ModelSelectorModelRow,
  ModelSelectorRowType,
  ModelPickerModelRow,
  ModelPickerRowType
} from '../main/ets/config/ModelListProjection'
import { SessionFilterType, SessionGroupData } from '../main/ets/pages/index/IndexPageTypes'
import { buildSessionGroupRenderKey, buildSessionRenderKeyForIndex } from '../main/ets/pages/index/IndexSessionGroupHelper'
import { AppError, AppErrorCode, Result } from '../main/ets/models/AppError'
import {
  setAllModelsEnabled,
  isAllModelsEnabled,
  setGroupModelsEnabled,
  isGroupAllEnabled,
  getGroupEnabledCount,
  removeModelById,
  buildSelectedModelsWithPreservedConfig
} from '../main/ets/config/ProviderModelActions'
import { ServiceRegistry } from '../main/ets/services/ServiceRegistry'

export default function refactorGuardTest() {
  describe('refactorGuardTest', () => {
    it('buildProviderModelGroups_should_keep_brand_order', 0, () => {
      const models: ModelInfo[] = [
        new ModelInfo('deepseek-r1', 'deepseek-r1', 4096, true, false),
        new ModelInfo('gpt-4o', 'gpt-4o', 4096, true, false),
        new ModelInfo('claude-3-5-sonnet', 'claude-3-5-sonnet', 4096, true, false),
        new ModelInfo('my-custom-model', 'my-custom-model', 4096, true, false)
      ]

      const groups = buildProviderModelGroups(models)

      expect(groups.length).assertEqual(4)
      expect(groups[0].name).assertEqual('OpenAI')
      expect(groups[1].name).assertEqual('Claude')
      expect(groups[2].name).assertEqual('DeepSeek')
      expect(groups[3].name).assertEqual('其他模型')
    })

    it('filterProviderModelsByKeyword_should_match_name_and_id', 0, () => {
      const models: ModelInfo[] = [
        new ModelInfo('gpt-4o', 'GPT-4o', 4096, true, false),
        new ModelInfo('claude-3-5-sonnet', 'Claude Sonnet', 4096, true, false)
      ]

      const byName = filterProviderModelsByKeyword(models, 'sonnet')
      const byId = filterProviderModelsByKeyword(models, 'gpt-4o')

      expect(byName.length).assertEqual(1)
      expect(byName[0].id).assertEqual('claude-3-5-sonnet')
      expect(byId.length).assertEqual(1)
      expect(byId[0].id).assertEqual('gpt-4o')
    })

    it('buildModelSelectorRows_should_filter_enabled_models_and_keep_provider_order', 0, () => {
      const providerA = new ModelProvider('openai', 'OpenAI', ProviderType.CUSTOM, 'message', '' as Resource, '',
        ApiStyle.OPENAI)
      providerA.models = [
        new ModelInfo('gpt-4o', 'GPT-4o', 4096, true, false),
        new ModelInfo('gpt-4.1', 'GPT-4.1', 4096, false, false)
      ]

      const providerB = new ModelProvider('anthropic', 'Anthropic', ProviderType.CUSTOM, 'message', '' as Resource, '',
        ApiStyle.OPENAI)
      providerB.models = [
        new ModelInfo('claude-3-5-sonnet', 'Claude Sonnet', 4096, true, false)
      ]

      const result = buildModelSelectorRows([providerA, providerB], '', new Set<string>(), false, false)

      expect(result.enabledModelCount).assertEqual(2)
      expect(result.matchedModelCount).assertEqual(2)
      expect(result.rows.length).assertEqual(4)
      expect(result.rows[0].type).assertEqual(ModelSelectorRowType.PROVIDER_HEADER)
      expect(result.rows[1].type).assertEqual(ModelSelectorRowType.MODEL_ITEM)
      expect(result.rows[2].type).assertEqual(ModelSelectorRowType.PROVIDER_HEADER)
      expect(result.rows[3].type).assertEqual(ModelSelectorRowType.MODEL_ITEM)
      expect((result.rows[1] as ModelSelectorModelRow).groupPosition).assertEqual(ModelRowGroupPosition.SINGLE)
    })

    it('buildModelSelectorRows_should_support_favorite_and_model_id_search', 0, () => {
      const provider = new ModelProvider('gateway', 'Gateway', ProviderType.CUSTOM, 'message', '' as Resource, '',
        ApiStyle.OPENAI)
      provider.models = [
        new ModelInfo('gpt-4o', 'GPT Four', 4096, true, false),
        new ModelInfo('claude-3-5-sonnet', 'Claude Sonnet', 4096, true, false)
      ]

      const favorites = new Set<string>(['gateway::gpt-4o'])
      const favoriteOnly = buildModelSelectorRows([provider], '', favorites, true, false)
      const byId = buildModelSelectorRows([provider], 'gpt-4o', favorites, false, true)

      expect(favoriteOnly.rows.length).assertEqual(2)
      expect(favoriteOnly.favoriteEnabledCount).assertEqual(1)
      expect(byId.rows.length).assertEqual(2)
      expect((byId.rows[1] as ModelSelectorModelRow).model.id).assertEqual('gpt-4o')
    })

    it('buildModelPickerRows_should_flatten_groups_with_expansion_state', 0, () => {
      const expansionState = new Map<string, boolean>()
      expansionState.set('Claude', false)

      const result = buildModelPickerRows(
        ['gpt-4o', 'gpt-4.1', 'claude-3-5-sonnet'],
        new Set<string>(['gpt-4o']),
        '',
        expansionState
      )

      expect(result.filteredModelIds.length).assertEqual(3)
      expect(result.rows.length).assertEqual(4)
      expect(result.rows[0].type).assertEqual(ModelPickerRowType.GROUP_HEADER)
      expect(result.rows[1].type).assertEqual(ModelPickerRowType.MODEL_ITEM)
      expect(result.rows[3].type).assertEqual(ModelPickerRowType.GROUP_HEADER)
      expect((result.rows[1] as ModelPickerModelRow).isExisting).assertEqual(true)
    })

    it('result_should_wrap_app_error', 0, () => {
      const error = new AppError(AppErrorCode.DATABASE_INIT_FAILED, '数据库初始化失败', 'cause')
      const result = Result.failure<string>(error)

      expect(result.ok).assertEqual(false)
      expect(result.error !== null).assertEqual(true)
      if (result.error !== null) {
        expect(result.error.code).assertEqual(AppErrorCode.DATABASE_INIT_FAILED)
      }
    })

    it('providerModelActions_should_toggle_and_filter_models', 0, () => {
      const models: ModelInfo[] = [
        new ModelInfo('gpt-4o', 'GPT-4o', 4096, false, false),
        new ModelInfo('claude-3-5-sonnet', 'Claude Sonnet', 4096, true, false)
      ]

      const enabledModels = setAllModelsEnabled(models, true)
      expect(isAllModelsEnabled(enabledModels)).assertEqual(true)

      const removed = removeModelById(enabledModels, 'claude-3-5-sonnet')
      expect(removed.length).assertEqual(1)
      expect(removed[0].id).assertEqual('gpt-4o')
    })

    it('providerModelActions_setAllModelsEnabled_should_return_new_array_reference', 0, () => {
      const models: ModelInfo[] = [
        new ModelInfo('gpt-4o', 'GPT-4o', 4096, false, false)
      ]

      const enabledModels = setAllModelsEnabled(models, true)
      expect(enabledModels === models).assertEqual(false)
      expect(enabledModels.length).assertEqual(1)
      expect(enabledModels[0].isEnabled).assertEqual(true)
    })

    it('providerModelActions_should_handle_empty_group', 0, () => {
      const emptyModels: ModelInfo[] = []
      const emptyGroup = {
        name: 'Empty',
        models: emptyModels,
        isExpanded: true
      }

      setGroupModelsEnabled(emptyGroup, true)
      expect(getGroupEnabledCount(emptyGroup)).assertEqual(0)
      expect(isGroupAllEnabled(emptyGroup)).assertEqual(true)
    })

    it('buildSelectedModelsWithPreservedConfig_should_keep_existing', 0, () => {
      const existing: ModelInfo[] = [
        new ModelInfo('gpt-4o', 'GPT-4o', 8192, false, true),
        new ModelInfo('claude-3-5-sonnet', 'Claude Sonnet', 4096, true, false)
      ]

      const selectedIds: string[] = ['gpt-4o', 'gemini-2.0-flash']
      const rebuilt = buildSelectedModelsWithPreservedConfig(existing, selectedIds)

      expect(rebuilt.length).assertEqual(2)
      expect(rebuilt[0].id).assertEqual('gpt-4o')
      expect(rebuilt[0].contextLength).assertEqual(8192)
      expect(rebuilt[0].isEnabled).assertEqual(false)
      expect(rebuilt[1].id).assertEqual('gemini-2.0-flash')
    })

    it('serviceRegistry_should_return_stable_instances', 0, () => {
      const preferences = ServiceRegistry.preferences()
      const database = ServiceRegistry.database()
      const toolRegistry = ServiceRegistry.toolRegistry()
      const settings = ServiceRegistry.settings()
      const share = ServiceRegistry.share()
      const appState = ServiceRegistry.appState()
      const provider = ServiceRegistry.provider()

      expect(preferences !== null).assertEqual(true)
      expect(database !== null).assertEqual(true)
      expect(toolRegistry !== null).assertEqual(true)
      expect(settings !== null).assertEqual(true)
      expect(share !== null).assertEqual(true)
      expect(appState !== null).assertEqual(true)
      expect(provider !== null).assertEqual(true)
      expect(ServiceRegistry.preferences() === preferences).assertEqual(true)
      expect(ServiceRegistry.database() === database).assertEqual(true)
      expect(ServiceRegistry.toolRegistry() === toolRegistry).assertEqual(true)
      expect(ServiceRegistry.settings() === settings).assertEqual(true)
      expect(ServiceRegistry.share() === share).assertEqual(true)
      expect(ServiceRegistry.appState() === appState).assertEqual(true)
      expect(ServiceRegistry.provider() === provider).assertEqual(true)
    })

    it('indexSessionRenderKey_should_change_on_title_update', 0, () => {
      const session = new ChatSession('s1', '旧标题', 'm1', 'p1')
      session.updatedAt = 1710000000000
      session.messageCount = 12
      session.lastMessagePreview = 'preview'
      const keyBefore = buildSessionRenderKeyForIndex(session)
      session.title = '新标题'
      const keyAfter = buildSessionRenderKeyForIndex(session)
      expect(keyBefore === keyAfter).assertEqual(false)
    })

    it('indexSessionGroupRenderKey_should_change_on_title_update', 0, () => {
      const session = new ChatSession('s1', '旧标题', 'm1', 'p1')
      session.updatedAt = 1710000000000
      session.messageCount = 1
      session.lastMessagePreview = 'preview'
      const group = new SessionGroupData('today', [session])
      const keyBefore = buildSessionGroupRenderKey(group, SessionFilterType.ALL, '')
      session.title = '新标题'
      const keyAfter = buildSessionGroupRenderKey(group, SessionFilterType.ALL, '')
      expect(keyBefore === keyAfter).assertEqual(false)
    })
  })
}
