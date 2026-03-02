# 00 — Vox iOS 移植项目总览

> 日期：2026-03-02
> 状态：Planning（纯规划，未进入开发）

---

## 一句话目标

将 macOS 菜单栏语音输入工具 Vox 移植到 iOS，通过主 App + 自定义键盘扩展实现"说话即文字"的跨 App 语音输入体验。

---

## 项目背景

### Mac Vox 是什么

Vox 是一个开源的 macOS 菜单栏语音输入工具（仓库：github.com/justin7974/vox），用 Swift 编写，零第三方依赖。核心流程：

    用户按全局快捷键 → 录音（16kHz WAV）→ 云端 ASR（Qwen3-ASR-Flash / Whisper）→ 可选 LLM 后处理（去口语化、纠错、加标点）→ 文本格式化（CJK 间距）→ 自动粘贴到光标位置

关键特性：
- **全局快捷键触发**：Carbon HotKey API，支持 toggle（按一次开始、再按停止）和 hold-to-talk（按住说话、松开停止）两种模式
- **云端 ASR**：首推阿里 Qwen3-ASR-Flash，中英混合识别效果优秀；也支持 Whisper 兼容 API 和本地 whisper-cpp
- **LLM 后处理（可选）**：支持 Kimi、Qwen-LLM、DeepSeek、MiniMax、OpenRouter 等多家 provider，自动检测 Anthropic/OpenAI 两种 API 格式
- **上下文感知**：ContextDetector 检测当前前台 App 和浏览器 URL（57 个映射），自动调整 LLM Prompt 风格
- **自动粘贴**：CGEvent 模拟 Cmd+V，失败时 osascript 兜底
- **翻译模式**：中→英 / 英→中，独立 translatePrompt
- **历史记录**：JSON 持久化，支持 retention 自动清理
- **BYOK**（Bring Your Own Key）：无订阅费，用户自带 API Key

### 代码规模

macOS 版共 12 个 Swift 源文件，总计约 180KB / ~5500 行有效代码：
- AppDelegate.swift（18.7KB）— 主控制器和状态管理
- Transcriber.swift（17.1KB）— ASR 转写（多 provider）
- PostProcessor.swift（17.0KB）— LLM 后处理（多 provider）
- SetupWindow.swift（73.4KB）— 多步引导向导（AppKit NSWindow）
- HistoryWindowController.swift（20.1KB）— 历史记录窗口（AppKit）
- StatusOverlay.swift（9.4KB）— 录音/处理状态浮窗
- ContextDetector.swift（8.2KB）— 前台应用和 URL 检测
- PasteHelper.swift（5.0KB）— 自动粘贴（CGEvent + osascript）
- HistoryManager.swift（4.9KB）— 历史数据管理
- TextFormatter.swift（3.1KB）— CJK 文本格式化
- AudioRecorder.swift（2.2KB）— AVAudioRecorder 封装
- main.swift（0.1KB）— 入口

---

## 为什么移植到 iOS

### 动机

1. **使用场景延伸**：macOS 上的 Vox 用户在手机上也有同样的语音输入需求——在微信、邮件、备忘录等 App 中快速将语音转为高质量文字
2. **iOS 原生语音输入不足**：Apple 自带听写功能中文精度一般，不支持 LLM 后处理（去口头语、纠错），不支持中英混合识别
3. **跨平台一致体验**：让 Vox 用户在 macOS 和 iOS 上使用相同的 ASR 服务（Qwen）和 LLM 后处理，获得一致的输入质量
4. **移动端独特价值**：iOS 的自定义键盘扩展（Keyboard Extension）可以实现在任意 App 中直接注入文字，比 macOS 的快捷键+粘贴体验更自然

### 价值

- **对用户**：在手机上获得远超系统自带的语音输入质量，特别是中英混合场景
- **对项目**：扩大 Vox 的用户群和使用频次，iOS 是用户最高频使用的设备
- **技术复用**：核心业务逻辑（ASR 调用、LLM 后处理、文本格式化）可以高比例复用，迁移成本可控

---

## 项目范围

### 做什么（In Scope）

**P0 — 核心可用（主 App）**
- 主 App 内录音 → 云端 ASR（Qwen / Whisper API）→ 可选 LLM 后处理 → 文本格式化 → 复制到剪贴板
- 完整的首次使用引导（权限申请、API Key 配置）
- 设置页（ASR provider 选择、LLM provider 配置、录音模式）
- 触觉反馈替代 macOS 音效（开始/停止/成功/失败）
- Keychain 安全存储 API Key

**P1 — 全局输入（键盘扩展）**
- 自定义键盘扩展（VoxKeyboard）：按住说话 → 直接将文字注入到任意 App 的输入框
- App Group 配置共享（主 App 和键盘扩展共享配置和 API Key）
- 手动场景选择（替代 macOS 的自动上下文检测）
- textDocumentProxy 上下文感知
- Apple Speech 离线降级
- 翻译模式

**P2 — 打磨增强**
- 历史记录管理（增删查清、retention 清理、翻译记录）
- 自定义 prompt.txt 编辑
- Siri Shortcut / Action Button 集成
- 音频压缩优化（WAV → Opus，减少 80% 上传体积）
- 控制中心 Widget（iOS 18+）
- Live Activity（灵动岛录音状态）

### 不做什么（Out of Scope）

- **本地 whisper-cpp 在键盘扩展中运行**：内存限制（~48-80MB）无法容纳大模型，仅考虑主 App 内集成（P2）
- **后台录音**：iOS 对后台音频权限审核严格，语音输入工具不适合申请；键盘扩展在使用时天然是"前台"
- **自动上下文检测**：iOS 沙箱禁止访问其他 App 信息，改用手动场景选择 + textDocumentProxy 上下文
- **全局快捷键**：iOS 无此机制，用键盘扩展的按钮替代
- **Apple Watch 独立 App**：P2 之后再评估
- **iPad 专属布局**：初期使用 iPhone App 兼容模式，P2 再做 iPad 适配
- **App Store 上架**：初期走 TestFlight 内测，App Store 上架作为后续目标
- **macOS/iOS 数据同步**：不做跨设备配置或历史同步（iCloud 同步）
- **任何形式的用户认证/账号系统**：保持 BYOK 模式，无后端服务

---

## 技术方向总结

| 维度 | 决策 |
|------|------|
| 开发语言 | Swift 5.9+ |
| UI 框架 | SwiftUI（主 App）+ UIHostingController（键盘扩展） |
| 最低系统版本 | iOS 17.0 |
| 状态管理 | @Observable（Observation framework，iOS 17+） |
| 第三方依赖 | 零（与 macOS 版一致） |
| ASR 首选 | 云端 Qwen3-ASR-Flash |
| LLM 后处理 | 云端多 provider（Kimi/Qwen-LLM/DeepSeek 等） |
| 配置存储 | Keychain（API Key）+ UserDefaults/App Group（非敏感配置） |
| 文字输出 | 主 App: UIPasteboard → 键盘扩展: textDocumentProxy.insertText() |
| 触发方式 | 主 App 按钮（P0）→ 键盘扩展 hold-to-talk（P1）→ Siri/Action Button（P2） |
