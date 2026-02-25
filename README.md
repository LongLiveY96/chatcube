<p align="center">
  <img src="AppScope/resources/base/media/foreground.png" width="120" />
</p>

<h1 align="center">ChatCube</h1>

<p align="center">
  An open-source AI chat client for HarmonyOS NEXT.<br/>
  One app, 13+ providers, native experience.
</p>

<p align="center">
  <a href="./README_ZH.md">简体中文</a> · <a href="./LICENSE">MIT License</a>
</p>

---

## Why ChatCube?

- Built entirely with ArkTS — a true HarmonyOS native app, not a web wrapper
- Polished UI with dynamic blur, 7 color themes, and smooth interactions
- Highly customizable providers — add any OpenAI / Anthropic / Gemini compatible service in seconds
- Simple and intuitive — configure your API key and start chatting
- Home screen widget for quick access
- Background task support — keep receiving replies while multitasking

## Preview

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/chat.png" width="200" /><br/><sub>Chat</sub></td>
    <td align="center"><img src="docs/screenshots/tool_calling.png" width="200" /><br/><sub>Tool Calling</sub></td>
    <td align="center"><img src="docs/screenshots/markdown_preview.jpg" width="200" /><br/><sub>Markdown</sub></td>
    <td align="center"><img src="docs/screenshots/html_preview.jpg" width="200" /><br/><sub>HTML Preview</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/providers.png" width="200" /><br/><sub>Providers</sub></td>
    <td align="center"><img src="docs/screenshots/color_themes.png" width="200" /><br/><sub>Themes</sub></td>
    <td align="center"><img src="docs/screenshots/blur_effect.png" width="200" /><br/><sub>Dynamic Blur</sub></td>
    <td align="center"><img src="docs/screenshots/settings.png" width="200" /><br/><sub>Settings</sub></td>
  </tr>
</table>

## Features

### Talk to any model

Connect to 13+ AI providers out of the box. Bring your own API key, pick a model, and start chatting. Add any OpenAI / Anthropic / Gemini compatible provider in seconds.

### Tools that models can use

Built-in web search (Bing, zero config) and weather query (Open-Meteo, free). When a model supports function calling, it can reach out to the real world on its own.

### Markdown & beyond

Full markdown rendering — code blocks with syntax highlighting, tables, LaTeX formulas, images. Even raw HTML gets a live preview.

### Looks good, feels good

7 color themes. Dark / Light / System mode. Real-time dynamic blur effects. A UI that feels native because it is native.

### Smart Grip

Detects which hand you're holding the phone with and moves the "New Chat" button to the reachable side. One-handed use, done right.

### Your data, your rules

Export and import everything — conversations, provider configs, preferences. JSON format, no lock-in.

### Stays alive in the background

Switch to another app while waiting for a long response. ChatCube keeps working and notifies you when the reply is ready.

## Supported Providers

| Provider | API Format | Notes |
|----------|-----------|-------|
| OpenAI | OpenAI | GPT-4o, o1, etc. |
| Claude | Anthropic | Claude 4, 3.5, etc. |
| DeepSeek | OpenAI-compatible | DeepSeek-V3, R1, etc. |
| Gemini | Google | Gemini 2.5, etc. |
| Grok | OpenAI-compatible | xAI models |
| Ollama | OpenAI-compatible | Local models |
| OpenRouter | OpenAI-compatible | Multi-provider gateway |
| SiliconFlow | OpenAI-compatible | Chinese AI models |
| Qwen (Alibaba) | OpenAI-compatible | Qwen series |
| Zhipu AI | OpenAI-compatible | GLM series |
| Doubao (Volcengine) | OpenAI-compatible | Doubao series |
| MiniMax | OpenAI-compatible | MiniMax models |
| AiHubMix | OpenAI-compatible | Multi-provider gateway |

...or add any compatible provider yourself.

## Getting Started

### Requirements

- HarmonyOS NEXT (API 21+)
- DevEco Studio 5.0+

### Build & Run

```bash
git clone https://github.com/LongLiveY96/ChatCube.git
cd ChatCube
cp build-profile.json5.example build-profile.json5
# Edit build-profile.json5 with your signing config
```

Open in DevEco Studio → Sync → Run.

### Configure providers

In the app: **Settings → Provider Management** → add your API keys.

## Project Structure

```
entry/src/main/ets/
├── components/         # Reusable UI components
├── config/             # App & provider configuration
├── models/             # Data models
├── pages/              # App pages
├── services/           # Business logic
├── viewmodels/         # ViewModels (MVVM)
├── utils/              # Utilities
└── widget/             # Home screen widget
```

## License

[MIT](./LICENSE) — do whatever you want with it.
