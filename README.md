<p align="center">
  <img src="AppScope/resources/base/media/foreground.png" width="120" />
</p>

<h1 align="center">ChatCube</h1>

<p align="center">
  一个开源的 HarmonyOS NEXT AI 聊天客户端。<br/>
  一个应用，13+ 服务商，原生体验。
</p>

<p align="center">
  <a href="./README_EN.md">English</a> · <a href="./LICENSE">MIT License</a>
</p>

---

## 为什么选 ChatCube？

- 完全使用 ArkTS 原生开发，不是 WebView 套壳
- 界面精致，动态模糊、7 种配色主题、流畅交互
- 适配手机、平板和大屏设备，布局更合理
- 服务商高度自定义，几秒添加任何 OpenAI / Anthropic / Gemini 兼容服务
- 简单易上手，填个 API Key 就能开聊
- 桌面小组件，快速发起对话
- 后台任务支持，切到其他应用也不耽误接收回复

## 应用预览

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/chat.png" width="200" /><br/><sub>对话</sub></td>
    <td align="center"><img src="docs/screenshots/tool_calling.png" width="200" /><br/><sub>工具调用</sub></td>
    <td align="center"><img src="docs/screenshots/markdown_preview.jpg" width="200" /><br/><sub>Markdown 渲染</sub></td>
    <td align="center"><img src="docs/screenshots/html_preview.jpg" width="200" /><br/><sub>HTML 预览</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/providers.png" width="200" /><br/><sub>服务商管理</sub></td>
    <td align="center"><img src="docs/screenshots/color_themes.png" width="200" /><br/><sub>配色主题</sub></td>
    <td align="center"><img src="docs/screenshots/blur_effect.png" width="200" /><br/><sub>动态模糊</sub></td>
    <td align="center"><img src="docs/screenshots/settings.png" width="200" /><br/><sub>设置</sub></td>
  </tr>
</table>

## 功能特性

### 和任何模型对话

内置 13+ AI 服务商，填入 API Key 选个模型就能聊。支持自定义添加任何 OpenAI / Anthropic / Gemini 兼容的服务商，几秒搞定。

### 模型能用的工具

内置联网搜索（Bing，零配置）。支持 Function Calling 的模型可以自主调用工具，获取实时信息。

### Markdown 及更多

完整的 Markdown 渲染，支持语法高亮代码块、表格、LaTeX 公式、图片。甚至原始 HTML 也能实时预览。

### 好看，好用

7 种配色主题，深色 / 浅色 / 跟随系统。实时动态模糊效果。原生 UI 的流畅感，因为它就是原生的。

### 手机、平板都顺手

针对手机、平板和大屏设备做了布局适配。聊天、设置、服务商管理等页面在更大屏幕上也能保持清晰、顺手的使用体验。

### 智感握姿

检测你用哪只手握着手机，自动把「新对话」按钮移到够得着的一侧。单手操作，就该这么简单。

### 数据在你手里

导出和导入一切，对话、服务商配置、偏好设置都能带走。JSON 格式，没有锁定。

### 后台也不掉线

切到其他应用等待长回复？ChatCube 在后台继续工作，回复完成后通知你。

## 支持的服务商

| 服务商 | API 格式 | 说明 |
|--------|---------|------|
| OpenAI | OpenAI | GPT-4o、o1 等 |
| Claude | Anthropic | Claude 4、3.5 等 |
| DeepSeek | OpenAI 兼容 | DeepSeek-V3、R1 等 |
| Gemini | Google | Gemini 2.5 等 |
| Grok | OpenAI 兼容 | xAI 模型 |
| Ollama | OpenAI 兼容 | 本地模型 |
| OpenRouter | OpenAI 兼容 | 多服务商网关 |
| 硅基流动 | OpenAI 兼容 | 国产 AI 模型 |
| 阿里云百炼 | OpenAI 兼容 | 通义千问系列 |
| 智谱 AI | OpenAI 兼容 | GLM 系列 |
| 火山引擎 | OpenAI 兼容 | 豆包系列 |
| MiniMax | OpenAI 兼容 | MiniMax 模型 |
| AiHubMix | OpenAI 兼容 | 多服务商网关 |

……或者自己添加任何兼容的服务商。

## 快速开始

### 环境要求

- HarmonyOS NEXT（API 23）
- DevEco Studio 5.0+

### 构建运行

```bash
git clone https://github.com/LongLiveY96/ChatCube.git
cd ChatCube
cp build-profile.json5.example build-profile.json5
# 编辑 build-profile.json5 填入你的签名配置
```

用 DevEco Studio 打开 → 同步 → 运行。

### 邀请测试

已开启华为应用市场邀测，欢迎体验最新版本：

- 邀测地址：<https://appgallery.huawei.com/link/invite-test-wap?taskId=950c3ff7c47af3d4ea25b68382a491da&invitationCode=2sM0HJ9vjqa>

### 配置服务商

在应用中：**设置 → 服务商管理** → 添加你的 API Key。

## 项目结构

```
entry/src/main/ets/
├── components/         # 可复用 UI 组件
├── config/             # 应用和服务商配置
├── models/             # 数据模型
├── pages/              # 应用页面
├── services/           # 业务逻辑服务
├── viewmodels/         # ViewModel（MVVM）
├── utils/              # 工具函数
└── widget/             # 桌面小组件
```

## 交流反馈

欢迎加入 ChatCube 交流反馈群，一起提建议、聊体验、报问题。

- QQ 群号：`752237762`

<p align="center">
  <img src="assets/qrcode_1772160303793.jpg" width="280" alt="ChatCube QQ 群二维码" />
</p>

## English README

英文说明请查看：[README_EN.md](./README_EN.md)

## 许可证

[MIT](./LICENSE) — 随便用，开心就好。

## 捐赠支持

如果 ChatCube 对你有帮助，欢迎自愿捐赠支持开发。

你的支持将主要用于：

- 购买模型 token
- 联调和测试不同服务商能力
- 持续迭代和打磨 ChatCube

微信打赏码如下：

<p align="center">
  <img src="assets/wechat-pay.png" width="280" alt="ChatCube 微信打赏码" />
</p>
