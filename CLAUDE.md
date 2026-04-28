
# HarmonyOS ArkTS 开发提示词

**始终以中文回复**

---

## 文档查询（必须遵守）

不确定 HarmonyOS API 用法、组件属性、权限配置、版本差异、代码示例时，**必须查询官方资料，禁止猜测**。

只接受以下官方来源：

- `https://developer.huawei.com/consumer/cn/doc/`
- 华为官方 AI 问答返回内容
- HarmonyOS 官方知识库返回内容

---

## ask-huawei-qa 工具

### 可用工具

| 工具 | 功能 | 示例 |
| --- | --- | --- |
| `ask_ai` | 华为官方 AI 问答（单次） | `ask_ai({ query: "Navigation 页面跳转传参" })` |
| `ask_ai_batch` | 华为官方 AI 问答（批量并行） | `ask_ai_batch({ queries: ["问题1", "问题2"] })` |
| `read_more` | 读取被截断的完整回答 | `read_more({ resourceId: "qa-result-1-xxx" })` |

### 使用策略

- **多个复杂问题（需要完整解释）** → `ask_ai_batch`
- **单个复杂问题（需要完整解释）** → `ask_ai`
- **回答被截断** → `read_more`

---

## codegenie-mcp 工具

`codegenie-mcp` 用于 HarmonyOS API 查询、工程同步、构建检查、启动运行和 UI 验证。

### 可用工具

| 工具 | 功能 | 使用场景 |
| --- | --- | --- |
| `harmonyos_knowledge_search` | 查询 HarmonyOS 官方知识库 | API 用法、组件属性、版本新特性、变更说明 |
| `init_project_path` | 初始化工程根目录 | 工具提示未配置工程路径时 |
| `project_sync` | 工程同步 | 初始化项目、修改依赖、ohpm/hvigor 同步 |
| `check_ets_files` | ArkTS 静态检查 | 修改 `.ets` 文件后检查语法和类型问题 |
| `build_project` | 构建项目 | 验证完整工程或指定模块是否可构建 |
| `start_app` | 启动应用 | 在真机或模拟器运行指定模块和 Ability |
| `perform_ui_action` | UI 操作 | 点击、滑动、输入、返回、截图 |
| `get_app_ui_tree` | 获取 UI 树 | 定位控件、分析页面结构、辅助 UI 验证 |

### 使用策略

- **查询 API / 组件 / 版本特性** → `harmonyos_knowledge_search`
- **修改依赖或工程配置后** → `project_sync`
- **修改 `.ets` 文件后** → `check_ets_files`
- **需要验证工程完整性** → `build_project`
- **需要运行应用** → `start_app`
- **需要验证界面行为** → `perform_ui_action` + `get_app_ui_tree`
- **工具提示未找到工程路径** → `init_project_path`

---

## 工具选择原则

- HarmonyOS API 解释、代码示例、复杂问题：优先用 `ask-huawei-qa`
- HarmonyOS API 新特性、版本变更、官方知识库查询：优先用 `codegenie-mcp harmonyos_knowledge_search`
- ArkTS 文件是否有语法/类型问题：用 `check_ets_files`
- 工程是否能构建：用 `build_project`
- App 是否能启动、页面是否正常：用 `start_app` 和 UI 工具

---

## 禁止事项

- 不确定 API 时禁止凭记忆写代码
- 不要把官方链接当成已经读过正文
- 不要为了使用新 API 随意提高 `compatibleSdkVersion`
- 不要在未验证行为变更前升级 `targetSdkVersion`
- 不要用复杂封装掩盖数据结构设计问题

