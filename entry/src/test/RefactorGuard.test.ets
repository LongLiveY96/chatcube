import { describe, it, expect } from '@ohos/hypium'
import {
  AttachmentType,
  ApiStyle,
  ChatMessage,
  ChatSession,
  MessageAttachment,
  MessageRole,
  ModelInfo,
  ModelProvider,
  ProviderType,
  SearchReference,
  ToolCall,
  ToolResult
} from '../main/ets/models/ChatModels'
import {
  buildProviderModelGroups,
  filterProviderModelsByKeyword,
  ProviderModelGroup
} from '../main/ets/config/ProviderDetailShared'
import {
  buildModelSelectorRows,
  buildModelPickerRows,
  ModelRowGroupPosition,
  ModelSelectorModelRow,
  ModelSelectorRowType
} from '../main/ets/config/ModelListProjection'
import { LayoutSizeClass, resolveLayoutSizeClass } from '../main/ets/config/LayoutProfile'
import { SessionFilterType, SessionGroupData } from '../main/ets/pages/index/IndexPageTypes'
import { buildSessionGroupRenderKey, buildSessionRenderKeyForIndex } from '../main/ets/pages/index/IndexSessionGroupHelper'
import { getCompactTabsBarHeightForIndex } from '../main/ets/utils/SettingsPageLayoutHelper'
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
import { shouldShowScrollToTopButtonForChat } from '../main/ets/pages/chat/ChatPageUiHelper'
import { ChatScrollUiFlow, ChatScrollUiFlowDependencies } from '../main/ets/pages/chat/ChatScrollUiFlow'
import {
  buildChatMessageRowRenderSignature,
  ChatMessageListDataSource,
  ChatMessageRowData
} from '../main/ets/components/chat/ChatMessageListDataSource'
import { SessionListItemData } from '../main/ets/pages/index/IndexSessionListDataSource'

class TestDataChangeListener implements DataChangeListener {
  reloadCount: number = 0
  changedIndexes: number[] = []

  onDataReloaded(): void {
    this.reloadCount++
  }

  onDataAdded(_index: number): void {}

  onDataAdd(_index: number): void {}

  onDataMoved(_from: number, _to: number): void {}

  onDataMove(_from: number, _to: number): void {}

  onDataDeleted(_index: number): void {}

  onDataDelete(_index: number): void {}

  onDataChanged(index: number): void {
    this.changedIndexes.push(index)
  }

  onDataChange(index: number): void {
    this.changedIndexes.push(index)
  }

  onDatasetChange(_operations: DataOperation[]): void {}
}

function createTestMessage(id: string, content: string = ''): ChatMessage {
  const message = new ChatMessage(id, MessageRole.ASSISTANT, content, 'AI', 'model')
  message.timestamp = 1710000000000
  return message
}

function createRow(id: string, signature: string): ChatMessageRowData {
  return new ChatMessageRowData(
    createTestMessage(id, signature),
    false,
    false,
    false,
    false,
    false,
    signature
  )
}

function buildTestChatMessageSignature(
  message: ChatMessage,
  isEditing: boolean = false,
  previewContent: string = '',
  previewAttachments: MessageAttachment[] = []
): string {
  return buildChatMessageRowRenderSignature(
    message,
    false,
    false,
    false,
    isEditing,
    false,
    '',
    15,
    '',
    previewContent,
    previewAttachments
  )
}

interface TestScrollFlowState {
  isScrollerAtEnd: boolean
  scrollerOffset: number
  currentOffset: number
  lastOffset: number
  maxOffset: number
  isAtTop: boolean
  isAtBottom: boolean
  isInputBarVisible: boolean
  scrollProgress: number
  scrollToIndexCalls: number
  scrollEdgeCalls: number
}

function createScrollUiFlow(state: TestScrollFlowState): ChatScrollUiFlow {
  const scroller = {
    scrollToIndex: (_index: number, _smooth: boolean, _align: ScrollAlign): void => {
      state.scrollToIndexCalls++
    },
    scrollEdge: (_edge: Edge): void => {
      state.scrollEdgeCalls++
    }
  } as Scroller

  const deps: ChatScrollUiFlowDependencies = {
    scroller: scroller,
    messages: [],
    getBottomAnchorIndex: (): number => 0,
    getCurrentScrollOffset: (): number => state.currentOffset,
    syncCurrentScrollOffset: (): number => state.scrollerOffset,
    syncIsAtBottomBoundary: (): boolean => state.isScrollerAtEnd,
    getLastScrollOffset: (): number => state.lastOffset,
    setLastScrollOffset: (value: number): void => {
      state.lastOffset = value
    },
    getMaxScrollOffset: (): number => state.maxOffset,
    setMaxScrollOffset: (value: number): void => {
      state.maxOffset = value
    },
    getInputBarShowThreshold: (): number => 24,
    getInputBarHideThreshold: (): number => 24,
    getIsAtTop: (): boolean => state.isAtTop,
    getIsAtBottom: (): boolean => state.isAtBottom,
    getIsInputBarVisible: (): boolean => state.isInputBarVisible,
    getIsSending: (): boolean => false,
    getIsEditingMessage: (): boolean => false,
    getEditingMessageId: (): string => '',
    hasDraftContent: (): boolean => false,
    onSetIsAtTopState: (value: boolean): void => {
      state.isAtTop = value
    },
    onSetIsAtBottomState: (value: boolean): void => {
      state.isAtBottom = value
    },
    onSetInputBarVisibleState: (value: boolean): void => {
      state.isInputBarVisible = value
    },
    onSetCurrentScrollOffsetState: (value: number): void => {
      state.currentOffset = value
    },
    onSetScrollProgressState: (value: number): void => {
      state.scrollProgress = value
    },
    onAnimate: (_duration: number, _curve: Curve, updater: () => void): void => {
      updater()
    }
  }

  return new ChatScrollUiFlow(deps)
}

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
      const providerA = new ModelProvider('openai', 'OpenAI', ProviderType.CUSTOM, 'message',
        $r('app.color.brand_openai'), '',
        ApiStyle.OPENAI)
      providerA.models = [
        new ModelInfo('gpt-4o', 'GPT-4o', 4096, true, false),
        new ModelInfo('gpt-4.1', 'GPT-4.1', 4096, false, false)
      ]

      const providerB = new ModelProvider('anthropic', 'Anthropic', ProviderType.CUSTOM, 'message',
        $r('app.color.brand_anthropic'), '',
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
      const provider = new ModelProvider('gateway', 'Gateway', ProviderType.CUSTOM, 'message',
        $r('app.color.brand_custom'), '',
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

    it('buildModelPickerRows_should_group_visible_models_by_brand', 0, () => {
      const result = buildModelPickerRows(
        ['gpt-4o', 'gpt-4.1', 'claude-3-5-sonnet'],
        new Set<string>(['gpt-4o']),
        '',
        false
      )

      expect(result.filteredModelIds.length).assertEqual(3)
      expect(result.visibleModelIds.length).assertEqual(3)
      expect(result.groups.length).assertEqual(2)
      expect(result.groups[0].name).assertEqual('OpenAI')
      expect(result.groups[0].modelIds.length).assertEqual(2)
      expect(result.groups[1].name).assertEqual('Claude')
      expect(result.groups[1].modelIds[0]).assertEqual('claude-3-5-sonnet')
    })

    it('resolveLayoutSizeClass_should_follow_breakpoints', 0, () => {
      expect(resolveLayoutSizeClass(599)).assertEqual(LayoutSizeClass.COMPACT)
      expect(resolveLayoutSizeClass(600)).assertEqual(LayoutSizeClass.MEDIUM)
      expect(resolveLayoutSizeClass(839)).assertEqual(LayoutSizeClass.MEDIUM)
      expect(resolveLayoutSizeClass(840)).assertEqual(LayoutSizeClass.EXPANDED)
    })

    it('getCompactTabsBarHeightForIndex_should_keep_tabs_stable_for_settings_drill_down', 0, () => {
      expect(getCompactTabsBarHeightForIndex(0)).assertEqual(56)
      expect(getCompactTabsBarHeightForIndex(18)).assertEqual(74)
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
      const emptyGroup: ProviderModelGroup = {
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

    it('sessionListItemData_key_should_change_when_selection_state_changes', 0, () => {
      const session = new ChatSession('s1', '会话标题', 'm1', 'p1')
      session.updatedAt = 1710000000000
      session.messageCount = 3
      session.lastMessagePreview = 'preview'

      const idleKey = new SessionListItemData(session, false, false).key
      const selectedKey = new SessionListItemData(session, true, false).key

      expect(idleKey === selectedKey).assertEqual(false)
    })

    it('sessionListItemData_key_should_preserve_previous_render_snapshot_when_session_mutates', 0, () => {
      const session = new ChatSession('s1', '旧标题', 'm1', 'p1')
      session.updatedAt = 1710000000000
      session.messageCount = 3
      session.lastMessagePreview = 'preview'

      const previousItem = new SessionListItemData(session, false, false)
      session.title = '新标题'
      const nextItem = new SessionListItemData(session, false, false)

      expect(previousItem.key === nextItem.key).assertEqual(false)
    })

    it('chatMessageListDataSource_should_only_notify_changed_row_when_order_is_stable', 0, () => {
      const dataSource = new ChatMessageListDataSource([
        createRow('m1', 'sig-1'),
        createRow('m2', 'sig-2')
      ])
      const listener = new TestDataChangeListener()
      dataSource.registerDataChangeListener(listener)

      dataSource.setItems([
        createRow('m1', 'sig-1'),
        createRow('m2', 'sig-2-updated')
      ])

      expect(listener.reloadCount).assertEqual(0)
      expect(listener.changedIndexes.length).assertEqual(1)
      expect(listener.changedIndexes[0]).assertEqual(1)
    })

    it('chatMessageListDataSource_should_reload_when_row_order_changes', 0, () => {
      const dataSource = new ChatMessageListDataSource([
        createRow('m1', 'sig-1'),
        createRow('m2', 'sig-2')
      ])
      const listener = new TestDataChangeListener()
      dataSource.registerDataChangeListener(listener)

      dataSource.setItems([
        createRow('m2', 'sig-2'),
        createRow('m1', 'sig-1')
      ])

      expect(listener.reloadCount).assertEqual(1)
      expect(listener.changedIndexes.length).assertEqual(0)
    })

    it('chatMessageRowData_key_should_change_when_render_signature_changes', 0, () => {
      const previousRow = createRow('m1', 'sig-1')
      const nextRow = createRow('m1', 'sig-2')

      expect(previousRow.stableId).assertEqual(nextRow.stableId)
      expect(previousRow.key === nextRow.key).assertEqual(false)
    })

    it('chatMessageRowRenderSignature_should_track_inline_edit_preview_only_for_editing_row', 0, () => {
      const message = createTestMessage('m1', '原始内容')
      const firstPreviewAttachments: MessageAttachment[] = [
        new MessageAttachment('a1', AttachmentType.IMAGE, 'first.png', '/tmp/first.png', 'image/png', 12)
      ]
      const secondPreviewAttachments: MessageAttachment[] = [
        new MessageAttachment('a2', AttachmentType.IMAGE, 'second.png', '/tmp/second.png', 'image/png', 34)
      ]

      const editingSignature = buildChatMessageRowRenderSignature(
        message,
        false,
        false,
        false,
        true,
        false,
        '',
        15,
        '',
        '编辑预览A',
        firstPreviewAttachments
      )
      const editingPreviewChangedSignature = buildChatMessageRowRenderSignature(
        message,
        false,
        false,
        false,
        true,
        false,
        '',
        15,
        '',
        '编辑预览B',
        secondPreviewAttachments
      )
      const nonEditingSignature = buildChatMessageRowRenderSignature(
        message,
        false,
        false,
        false,
        false,
        false,
        '',
        15,
        '',
        '编辑预览A',
        firstPreviewAttachments
      )
      const nonEditingPreviewChangedSignature = buildChatMessageRowRenderSignature(
        message,
        false,
        false,
        false,
        false,
        false,
        '',
        15,
        '',
        '编辑预览B',
        secondPreviewAttachments
      )

      expect(editingSignature === editingPreviewChangedSignature).assertEqual(false)
      expect(nonEditingSignature).assertEqual(nonEditingPreviewChangedSignature)
    })

    it('chatMessageRowRenderSignature_should_change_when_text_changes_with_same_length', 0, () => {
      const previousMessage = createTestMessage('m1', 'abc')
      const nextMessage = createTestMessage('m1', 'axc')

      const previousSignature = buildTestChatMessageSignature(previousMessage)
      const nextSignature = buildTestChatMessageSignature(nextMessage)

      expect(previousSignature === nextSignature).assertEqual(false)
    })

    it('chatMessageListDataSource_should_notify_row_change_when_tool_result_state_changes', 0, () => {
      const previousMessage = createTestMessage('m1', '工具结果')
      previousMessage.toolCalls = [new ToolCall('call-1', 'web_search', '{"q":"abc"}', 'web_search', '网页搜索', 'builtin',
        '搜索工具')]
      previousMessage.toolResults = [new ToolResult('call-1', '{"ok":1}', false, '网页搜索', '搜索工具')]

      const nextMessage = createTestMessage('m1', '工具结果')
      nextMessage.toolCalls = [new ToolCall('call-1', 'web_search', '{"q":"abc"}', 'web_search', '网页搜索', 'builtin',
        '搜索工具')]
      nextMessage.toolResults = [new ToolResult('call-1', '{"ok":1}', true, '执行失败', '错误来源')]

      const dataSource = new ChatMessageListDataSource([
        new ChatMessageRowData(previousMessage, false, false, false, false, false,
          buildTestChatMessageSignature(previousMessage))
      ])
      const listener = new TestDataChangeListener()
      dataSource.registerDataChangeListener(listener)

      dataSource.setItems([
        new ChatMessageRowData(nextMessage, false, false, false, false, false, buildTestChatMessageSignature(nextMessage))
      ])

      expect(listener.reloadCount).assertEqual(0)
      expect(listener.changedIndexes.length).assertEqual(1)
      expect(listener.changedIndexes[0]).assertEqual(0)
    })

    it('chatMessageRowRenderSignature_should_change_when_search_reference_content_changes', 0, () => {
      const previousMessage = createTestMessage('m1', '搜索结果')
      const previousReference = new SearchReference('ref-1', '结果A', 'https://a.example.com', '摘要A')
      previousReference.timestamp = 1710000000000
      previousMessage.searchReferences = [previousReference]

      const nextMessage = createTestMessage('m1', '搜索结果')
      const nextReference = new SearchReference('ref-1', '结果B', 'https://b.example.com', '摘要B')
      nextReference.timestamp = 1710000000000
      nextMessage.searchReferences = [nextReference]

      const previousSignature = buildTestChatMessageSignature(previousMessage)
      const nextSignature = buildTestChatMessageSignature(nextMessage)

      expect(previousSignature === nextSignature).assertEqual(false)
    })

    it('shouldShowScrollToTopButtonForChat_should_keep_original_visibility_contract', 0, () => {
      expect(shouldShowScrollToTopButtonForChat(false, 10, false, 960, 600)).assertEqual(true)
      expect(shouldShowScrollToTopButtonForChat(true, 10, false, 960, 600)).assertEqual(false)
      expect(shouldShowScrollToTopButtonForChat(false, 10, true, 960, 600)).assertEqual(false)
      expect(shouldShowScrollToTopButtonForChat(false, 10, false, 12, 600)).assertEqual(false)
      expect(shouldShowScrollToTopButtonForChat(false, 10, false, 480, 600)).assertEqual(true)
    })

    it('chatScrollUiFlow_should_use_absolute_scroll_offset_from_list_events', 0, () => {
      const state: TestScrollFlowState = {
        isScrollerAtEnd: false,
        scrollerOffset: 0,
        currentOffset: 0,
        lastOffset: 0,
        maxOffset: 1000,
        isAtTop: true,
        isAtBottom: false,
        isInputBarVisible: true,
        scrollProgress: 0,
        scrollToIndexCalls: 0,
        scrollEdgeCalls: 0
      }
      const flow = createScrollUiFlow(state)

      state.scrollerOffset = 300
      flow.handleMessageListDidScroll(300, ScrollState.Scroll)
      state.scrollerOffset = 500
      flow.handleMessageListDidScroll(500, ScrollState.Scroll)

      expect(state.currentOffset).assertEqual(500)
      expect(state.lastOffset).assertEqual(500)
      expect(state.isAtTop).assertEqual(false)
      expect(state.scrollProgress).assertEqual(0.5)
    })

    it('chatScrollUiFlow_should_leave_bottom_when_absolute_offset_decreases', 0, () => {
      const state: TestScrollFlowState = {
        isScrollerAtEnd: false,
        scrollerOffset: 500,
        currentOffset: 500,
        lastOffset: 500,
        maxOffset: 1000,
        isAtTop: false,
        isAtBottom: true,
        isInputBarVisible: true,
        scrollProgress: 0.5,
        scrollToIndexCalls: 0,
        scrollEdgeCalls: 0
      }
      const flow = createScrollUiFlow(state)

      state.scrollerOffset = 450
      flow.handleMessageListDidScroll(450, ScrollState.Scroll)

      expect(state.currentOffset).assertEqual(450)
      expect(state.lastOffset).assertEqual(450)
      expect(state.isAtBottom).assertEqual(false)
    })

    it('chatScrollUiFlow_should_cancel_pending_pinned_bottom_alignment_after_user_scrolls_away', 0,
      async () => {
        const state: TestScrollFlowState = {
          isScrollerAtEnd: false,
          scrollerOffset: 500,
          currentOffset: 500,
          lastOffset: 500,
          maxOffset: 1000,
          isAtTop: false,
          isAtBottom: true,
          isInputBarVisible: true,
          scrollProgress: 0.5,
          scrollToIndexCalls: 0,
          scrollEdgeCalls: 0
        }
        const flow = createScrollUiFlow(state)

        flow.alignToBottomIfPinned()
        state.scrollerOffset = 450
        flow.handleMessageListDidScroll(450, ScrollState.Scroll)
        await new Promise<void>((resolve) => {
          setTimeout(() => {
            resolve()
          }, 160)
        })

        expect(state.isAtBottom).assertEqual(false)
        expect(state.scrollToIndexCalls).assertEqual(0)
      })

    it('chatScrollUiFlow_should_keep_bottom_progress_stable_during_spring_bounce', 0, () => {
      const state: TestScrollFlowState = {
        isScrollerAtEnd: true,
        scrollerOffset: 992,
        currentOffset: 1000,
        lastOffset: 1000,
        maxOffset: 1000,
        isAtTop: false,
        isAtBottom: true,
        isInputBarVisible: true,
        scrollProgress: 1,
        scrollToIndexCalls: 0,
        scrollEdgeCalls: 0
      }
      const flow = createScrollUiFlow(state)

      flow.handleMessageListDidScroll(992, ScrollState.Scroll)

      expect(state.currentOffset).assertEqual(1000)
      expect(state.lastOffset).assertEqual(1000)
      expect(state.isAtBottom).assertEqual(true)
      expect(state.scrollProgress).assertEqual(1)
    })

    it('chatScrollUiFlow_handleReachStart_should_reset_top_state_and_progress', 0, () => {
      const state: TestScrollFlowState = {
        isScrollerAtEnd: false,
        scrollerOffset: 220,
        currentOffset: 220,
        lastOffset: 220,
        maxOffset: 1000,
        isAtTop: false,
        isAtBottom: false,
        isInputBarVisible: false,
        scrollProgress: 0.6,
        scrollToIndexCalls: 0,
        scrollEdgeCalls: 0
      }
      const flow = createScrollUiFlow(state)

      flow.handleReachStart()

      expect(state.currentOffset).assertEqual(0)
      expect(state.lastOffset).assertEqual(0)
      expect(state.isAtTop).assertEqual(true)
      expect(state.scrollProgress).assertEqual(0)
    })
  })
}
