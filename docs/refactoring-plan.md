# chatbox 重构任务清单

> 状态：Task 1 / Task 2 / Task 3 已完成，当前进入 Task 4。  
> 用法：只看清单推进，不要再把这份文档当成长篇说明书。

---

## 0. 当前状态

- [x] Task 1：能力推断 DSL / Registry DSL
- [x] Task 2：状态收敛到 `AppSettingsStore`
- [x] Task 3：预设服务商声明式 + Migration + 余额查询
- [~] Task 4：Assistant 升级为完整对话配置模板

### 已完成提交

- `3281017 refactor: 统一 Assistant 模型回退解析`
- `32bfeae refactor: 扩展 Assistant 模板数据层`
- `e45cd87 docs: 更新重构任务清单`
- `48593e6 feat: 完成预设服务商声明式改造`
- `c315711 docs: ModelManagePage refreshFromCache 注释对齐 Store 后的语义`
- `01cb6fb refactor: Prompt 模板收敛到 AppSettingsStore,完结 DefaultModel 迁移`
- `323e41d refactor: 默认模型配置收敛到 AppSettingsStore`
- `71cab2f refactor: Assistant 状态收敛到 AppSettingsStore`
- `564a86f refactor: 抽出 AppSettingsStore 统一 provider 状态管理`

### 当前结论

- `AppSettingsStore` 已经是 Providers / Assistants / DefaultModel / Prompt 模板的统一入口。
- `ProviderViewModel` / `AssistantService` / `DefaultModelService` 对外签名仍保持不变。
- Task 3 的构建已通过；余额接口已由你本地验证过，不需要重复跑真实账号请求，除非 provider 接口改动。

---

## 1. Task 3 结果记录

### 1.1 已完成项

- [x] `PresetProviders.ets` 升级为声明式 `PresetProviderDef`
- [x] `AppSettingsStore.doInitialize()` 改为 `applyPresetOnMissing()`
- [x] `ALL_PRESET_PROVIDER_IDS` 删除，改为从预设表派生
- [x] `state/migrations/` 框架落地
- [x] MiniMax 历史 baseUrl 修复迁移化
- [x] 余额查询接入 `ProviderDetailSheet`
- [x] `check_ets_files` / `assembleHap` 通过

### 1.2 Task 3 关键文件

- `entry/src/main/ets/config/PresetProviders.ets`
- `entry/src/main/ets/state/AppSettingsStore.ets`
- `entry/src/main/ets/state/migrations/MigrationContext.ets`
- `entry/src/main/ets/state/migrations/ProviderMigrations.ets`
- `entry/src/main/ets/state/migrations/types.ets`
- `entry/src/main/ets/components/ProviderDetailSheet.ets`

---

## 2. Task 4 任务列表

### 4.1 数据层扩展

- [x] 在 `entry/src/main/ets/models/AssistantModels.ets` 增加完整模板字段
- [x] 在 `entry/src/main/ets/services/DatabaseService.ets` 补 `assistants` 表列
- [x] 复用 Task 3 的 migration 框架，新增 Assistant migration
- [x] 写入前做 normalize，读取后做孤立引用清理
- [x] 旧数据兼容默认值统一为 `0 / '' / false`

建议新增字段：

- `contextMessageSize`
- `maxTokens`
- `reasoningLevel`
- `customHeadersJson`
- `customBodiesJson`
- `mcpServerIdsJson`
- `quickMessageIdsJson`
- `presetMessagesJson`
- `tagsJson`

验收标准：

- [x] 旧 assistant 数据能正常加载
- [x] 新字段写入后重启仍保留
- [x] 缺失的 provider / model 能回退到全局默认

### 4.2 编辑页接入

- [x] 在 `AssistantManagePage.ets` 补采样配置入口
- [x] 在 `AssistantManagePage.ets` 补扩展配置入口
- [x] `MCP / 快捷消息 / 预设消息` 先只读展示
- [x] 保存后只写 Store，不改发送链路

验收标准：

- [x] 除只读展示项外的新字段能编辑、能保存
- [x] 老字段行为不回归
- [x] 页面还能保持现有列表 / 删除 / 排序行为

### 4.3 模型解析回退

- [x] 在 Store 或 `AssistantService` 增加 `resolveChatModel(assistant)`
- [x] `defaultModelId` / `defaultProviderId` 为空时回退全局 chat 默认模型
- [x] `ChatViewModel.sendMessage*` 改走 resolver
- [x] `ChatPageLoadFlow` 的展示也改用解析后的结果

验收标准：

- [x] assistant 模型配置为空时不再依赖业务层特判
- [x] title / translate / searchOpt 仍继续使用全局默认

### 4.4 页面拆分

- [ ] 将 `AssistantManagePage.ets` 拆成列表页 + 详情页
- [ ] 拆出 `AssistantBasicTab.ets`
- [ ] 拆出 `AssistantModelTab.ets`
- [ ] 拆出 `AssistantSamplingTab.ets`
- [ ] 拆出 `AssistantExtensionsTab.ets`
- [ ] 手机全屏 / 平板 side-by-side 行为对齐 ProviderDetailPage

验收标准：

- 单页体积明显下降
- 导航行为不变
- 保存 / 返回流程不变

---

## 3. 推荐执行顺序

1. 先做 4.1 数据层扩展
2. 再做 4.3 模型解析回退
3. 然后做 4.2 编辑页接入
4. 最后做 4.4 页面拆分

---

## 4. 关键文件索引

### 状态层

- `entry/src/main/ets/state/AppSettingsState.ets`
- `entry/src/main/ets/state/AppSettingsStore.ets`
- `entry/src/main/ets/state/AppUiState.ets`

### 数据模型

- `entry/src/main/ets/models/ChatModels.ets`
- `entry/src/main/ets/models/AssistantModels.ets`

### 持久化

- `entry/src/main/ets/services/DatabaseService.ets`
- `entry/src/main/ets/services/PreferencesService.ets`

### Facade

- `entry/src/main/ets/viewmodels/ProviderViewModel.ets`
- `entry/src/main/ets/services/AssistantService.ets`
- `entry/src/main/ets/services/DefaultModelService.ets`

### 预设配置

- `entry/src/main/ets/config/PresetProviders.ets`
- `entry/src/main/ets/config/DefaultPrompts.ets`
- `entry/src/main/ets/config/AppStorageKeys.ets`

### UI 入口

- `entry/src/main/ets/pages/AssistantManagePage.ets`
- `entry/src/main/ets/pages/ModelManagePage.ets`
- `entry/src/main/ets/pages/DefaultModelPage.ets`
- `entry/src/main/ets/components/ProviderDetailSheet.ets`

---

## 5. 项目约定

- 始终中文回复
- 不确定 HarmonyOS API 时先查官方，不猜
- ArkTS 写入变更尽量保持整数组替换
- 每个 task 尽量保持独立 commit
- 构建验证用：

```bash
/mnt/c/Windows/System32/cmd.exe /c hvigorw.cmd assembleHap --no-daemon
```

---

## 6. 新会话起手提示

```text
接手 chatbox 重构。当前进度见 docs/refactoring-plan.md。

已完成 Task 1 / Task 2 / Task 3，当前只推进 Task 4。
Task 3 已提交到 48593e6，余额查询已验证过。

接下来请按文档里的 Task 4 顺序推进，优先做数据层，再做 resolver，再做 UI。
```

---

## 7. 待观察

- `setAppUiStateValue` 的时间戳脉冲还没清理
- `AppUiState` 仍是单一大类，后续可再分域
- `syncProviderProperties` 的浅拷贝仍保留在 `ProviderViewModel`
- `Provider` 的部分兼容字段仍是后续独立项，不混进 Task 4

---

## 8. 参考路径

- `rikkahub/ai/src/main/java/me/rerere/ai/provider/DefaultProviders.kt`
- `rikkahub/app/src/main/java/me/rerere/rikkahub/data/datastore/PreferencesStore.kt`
- `rikkahub/app/src/main/java/me/rerere/rikkahub/data/model/Assistant.kt`
- `rikkahub/app/src/main/java/me/rerere/rikkahub/ui/pages/assistant/AssistantDetailScreen.kt`
