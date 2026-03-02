# 01 — Mac Vox 源码逐模块分析

> 日期：2026-03-02
> 基于 GitHub 仓库 justin7974/vox 的源码结构和已有分析文件

---

## 源码总览

Mac Vox 仓库结构：

    vox/
    ├── .gitignore
    ├── AppIcon.icns              — App 图标
    ├── CHANGELOG.md              — 版本变更日志
    ├── DEVLOG.md                 — 开发日志
    ├── HANDOFF-TO-CLAW.md        — 交接文档
    ├── Info.plist                — App 配置
    ├── LICENSE                   — MIT 许可
    ├── README.md                 — 项目说明
    ├── build.sh                  — 构建脚本
    ├── config.example.json       — 配置文件示例
    ├── setup-signing.sh          — 签名配置脚本
    └── Vox/                      — 源码目录
        ├── main.swift
        ├── AppDelegate.swift
        ├── AudioRecorder.swift
        ├── Transcriber.swift
        ├── PostProcessor.swift
        ├── TextFormatter.swift
        ├── PasteHelper.swift
        ├── ContextDetector.swift
        ├── HistoryManager.swift
        ├── HistoryWindowController.swift
        ├── SetupWindow.swift
        └── StatusOverlay.swift

共 12 个 Swift 源文件，总代码约 180KB（~5500 行有效代码），零第三方依赖。

---

## 逐模块分析

### 1. main.swift

| 属性 | 详情 |
|------|------|
| **功能** | App 入口点，创建 NSApplication 并设置 AppDelegate |
| **代码规模** | ~0.1KB，约 5 行 |
| **核心依赖** | AppKit (NSApplication) |
| **iOS 可复用度** | 低 ❌ |
| **原因** | iOS 使用 @main + App 协议（SwiftUI）或 UIApplicationDelegate，完全不同的启动机制 |
| **iOS 替代** | VoxiOSApp.swift 使用 SwiftUI App 协议（@main struct VoxiOSApp: App） |

---

### 2. AppDelegate.swift（核心控制器）

| 属性 | 详情 |
|------|------|
| **功能** | 全局状态管理 + 录音控制 + 热键注册 + 菜单栏 UI + 状态切换 + 音效 + 录音→ASR→LLM→粘贴的完整流程编排 |
| **代码规模** | ~18.7KB，约 550 行 |
| **核心依赖** | AppKit (NSStatusBar, NSMenu, NSSound), Carbon (RegisterEventHotKey), AVFoundation, Dispatch |
| **iOS 可复用度** | 低 ❌ |
| **原因** | 深度耦合 macOS 专属 API：Carbon HotKey、NSStatusBar（菜单栏）、NSSound（音效）、CGEvent（粘贴）。业务流程编排逻辑可参考但不能直接复用 |

**需要替换的 macOS 专属部分**：
- `RegisterEventHotKey` / Carbon HotKey → iOS 无全局热键，改为 App 内按钮 + 键盘扩展
- `NSStatusBar` / `NSStatusItem` → iOS 无菜单栏，改为 SwiftUI 主界面
- `NSSound("Tink/Pop/Glass/Basso").play()` → `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`
- `NSPasteboard.general` → `UIPasteboard.general`
- hotKeyPressed / hotKeyReleased 回调 → SwiftUI 按钮事件 / 键盘扩展手势
- toggle/hold 模式的热键逻辑 → 键盘扩展的 DragGesture（hold-to-talk）

**可参考的业务逻辑**：
- 录音→ASR→LLM→格式化→输出的完整 pipeline 流程
- 静音检测（peakPower > -50dB）
- 文件大小检查（fileSize < 16000 丢弃）
- LLM 失败降级到原文 + TextFormatter
- 录音状态机（idle → recording → processing → idle）

---

### 3. AudioRecorder.swift

| 属性 | 详情 |
|------|------|
| **功能** | AVAudioRecorder 封装，16kHz/16bit/Mono WAV 录音，电平采样 |
| **代码规模** | ~2.2KB，约 65 行 |
| **核心依赖** | AVFoundation (AVAudioRecorder, AVAudioSession) |
| **iOS 可复用度** | 高 ✅ |
| **原因** | AVFoundation 在 iOS 上完全可用，录音参数（16kHz/16bit/Mono）通用，核心逻辑几乎不需要改 |

**需要适配的部分**：
- AVAudioSession category：macOS 可能使用 .record，iOS 主 App 也用 .record + .measurement，但键盘扩展必须用 .playAndRecord + .mixWithOthers（避免中断宿主 App 音频）
- 键盘扩展中需要区分 AudioSessionMode（mainApp vs keyboardExtension）
- 权限请求：macOS 自动弹窗，iOS 需要主动调用 requestRecordPermission（且键盘扩展无法弹权限弹窗，必须在主 App 预先授权）

---

### 4. Transcriber.swift（ASR 转写）

| 属性 | 详情 |
|------|------|
| **功能** | 多 provider ASR 转写引擎：Qwen ASR（DashScope Chat API，base64 音频）、Custom Whisper API（multipart/form-data）、本地 whisper-cpp（Process 调用） |
| **代码规模** | ~17.1KB，约 500 行 |
| **核心依赖** | Foundation (URLSession, JSONSerialization, Process), Dispatch (DispatchSemaphore) |
| **iOS 可复用度** | 中 ⚠️ |
| **原因** | Qwen ASR 和 Whisper API 的网络调用逻辑可直接复用（URLSession 跨平台）；但本地 whisper-cpp 通过 Process() 调用命令行工具，iOS 不支持；DispatchSemaphore 阻塞模式应改为 async/await |

**需要替换的 macOS 专属部分**：
- `Process()` 调用 `/opt/homebrew/bin/whisper-cli` → iOS 不支持 Process，本地 ASR 需用 whisper.cpp SPM 包直接集成
- `DispatchSemaphore` 同步阻塞 → 改为 Swift Concurrency async/await
- 配置读取从 `~/.vox/config.json` → App Group Container

**可直接复用的部分**：
- Qwen ASR 请求构建（base64 编码、API 请求格式）
- Whisper API 请求构建（multipart/form-data）
- 幻觉过滤逻辑 isHallucination()（如果后续集成本地 Whisper）
- ASR 配置加载逻辑（provider 选择、API Key 管理）

**建议的架构改进**：
- 拆分为 ASRProvider 协议 + QwenASR / WhisperAPIASR / AppleSpeechASR 具体实现
- 增加 ASRFactory 工厂方法和离线降级逻辑

---

### 5. PostProcessor.swift（LLM 后处理）

| 属性 | 详情 |
|------|------|
| **功能** | 多 provider LLM 后处理：支持 Kimi、Qwen-LLM、DeepSeek、MiniMax、OpenRouter、Moonshot、GLM 等；自动检测 Anthropic 和 OpenAI 两种 API 格式；翻译模式；自定义 prompt.txt 加载 |
| **代码规模** | ~17.0KB，约 500 行 |
| **核心依赖** | Foundation (URLSession, JSONSerialization), Dispatch (DispatchSemaphore) |
| **iOS 可复用度** | 高 ✅ |
| **原因** | 纯网络调用逻辑，URLSession 跨平台通用；多 provider 配置、双格式 API 支持、prompt 构建逻辑都可直接移植 |

**需要适配的部分**：
- `DispatchSemaphore` 同步阻塞 → 改为 async/await
- 配置文件路径从 `~/.vox/` → App Group Container
- prompt.txt 路径适配
- 补充 `enable_thinking: false`（Qwen 3.5+ 性能优化，原版已有但需确认 iOS 版本是否完整保留）
- Anthropic 格式响应解析需过滤 thinking blocks（只取 type == "text"）

**可直接复用的部分**：
- 全部 provider 配置和 URL 映射
- System Prompt 构建逻辑（defaultPrompt + userContext + contextHint）
- 翻译模式 translatePrompt
- prompt.txt 注释过滤（# 开头行跳过）
- API 格式自动检测（Anthropic vs OpenAI）

---

### 6. TextFormatter.swift

| 属性 | 详情 |
|------|------|
| **功能** | 文本格式化：CJK/ASCII 间距（Pangu 规则）、半角→全角标点转换（中文上下文）、多空格折叠 |
| **代码规模** | ~3.1KB，约 90 行 |
| **核心依赖** | Foundation (NSRegularExpression) |
| **iOS 可复用度** | 完全复用 ✅✅ |
| **原因** | 纯 Foundation 正则操作，无任何平台相关代码，可零改动直接放入 iOS 项目 |

**不需要任何改动**，这是唯一可以原封不动复制的模块。

---

### 7. PasteHelper.swift

| 属性 | 详情 |
|------|------|
| **功能** | 文字输出到光标位置：NSPasteboard 写入 → CGEvent 模拟 Cmd+V（需 Accessibility 权限）→ 失败兜底用 osascript |
| **代码规模** | ~5.0KB，约 150 行 |
| **核心依赖** | AppKit (NSPasteboard), CoreGraphics (CGEvent), Foundation (Process — osascript) |
| **iOS 可复用度** | 低 ❌ |
| **原因** | 深度依赖 macOS 专属 API：CGEvent、Accessibility 权限、osascript。iOS 沙箱完全封锁了这些机制 |

**iOS 替代方案**：
- 主 App：UIPasteboard.general（写入剪贴板，用户手动粘贴）
- 键盘扩展：textDocumentProxy.insertText()（直接注入文字到输入框，这是 iOS 唯一的合法跨 App 文字注入方式）
- 触觉反馈替代音效提示

---

### 8. ContextDetector.swift

| 属性 | 详情 |
|------|------|
| **功能** | 上下文感知：检测当前前台 App（NSWorkspace.frontmostApplication.bundleIdentifier）+ AppleScript 获取浏览器 URL → 57 个 app/url 映射到场景提示词 |
| **代码规模** | ~8.2KB，约 240 行 |
| **核心依赖** | AppKit (NSWorkspace), Foundation (Process — osascript) |
| **iOS 可复用度** | 低 ❌ |
| **原因** | iOS 沙箱完全禁止访问其他 App 信息（bundleID、URL 等），这个模块在 iOS 上无法实现 |

**iOS 替代方案**：
- 手动场景选择（SceneSelector）：用户在主 App 或键盘扩展中手动选择当前场景（邮件/聊天/文档/编程/默认等）
- 键盘扩展的 textDocumentProxy.documentContextBeforeInput 可获取光标前部分文字（通常几百字符），可作为 LLM 的上下文信号
- 虽然不如 macOS 的自动检测精准，但手动选择给用户更多控制权

**57 个映射的价值**：映射表中的场景提示词（如"用户正在写邮件，请使用正式语气"）可以复用到 iOS 的 SceneSelector 中

---

### 9. HistoryManager.swift

| 属性 | 详情 |
|------|------|
| **功能** | 历史记录管理：增删查清、JSON 持久化、retention 自动清理（按天数）、翻译记录（原文+译文） |
| **代码规模** | ~4.9KB，约 145 行 |
| **核心依赖** | Foundation (JSONSerialization, FileManager) |
| **iOS 可复用度** | 高 ✅ |
| **原因** | 纯 Foundation 文件 I/O，逻辑通用。只需适配存储路径（从 ~/.vox/ 改为 App Group Container） |

**需要适配的部分**：
- 存储路径从 `~/.vox/history.json` → `App Group Container/Vox/history.json`
- 建议用 Codable 替代手动 JSONSerialization（提升类型安全）
- 键盘扩展是否需要访问历史记录需要决策（建议不需要，主 App 独享）

---

### 10. HistoryWindowController.swift

| 属性 | 详情 |
|------|------|
| **功能** | 历史记录窗口 UI：NSWindow + NSTableView，搜索、删除、复制、清空、时间显示 |
| **代码规模** | ~20.1KB，约 590 行 |
| **核心依赖** | AppKit (NSWindow, NSTableView, NSSearchField, NSMenu) |
| **iOS 可复用度** | 低 ❌ |
| **原因** | 全部是 AppKit UI 代码（NSWindow、NSTableView），iOS 使用 SwiftUI 完全重写 |

**iOS 替代方案**：
- SwiftUI List + NavigationStack
- 搜索用 .searchable() modifier
- 删除用 .swipeActions()
- 复制到剪贴板功能保留
- 翻译记录的双语展示

---

### 11. SetupWindow.swift

| 属性 | 详情 |
|------|------|
| **功能** | 多步引导向导：欢迎 → API Key 配置 → 热键设置 → 录音模式选择 → 测试录音 → 完成。所有 UI 用 AppKit NSView 手写 |
| **代码规模** | ~73.4KB，约 2150 行（项目中最大的文件） |
| **核心依赖** | AppKit (NSWindow, NSView, NSTextField, NSButton, NSComboBox, NSSecureTextField, 大量手动 AutoLayout) |
| **iOS 可复用度** | 低 ❌ |
| **原因** | 全部 AppKit UI 代码，iOS 用 SwiftUI 重写。但引导流程设计（步骤顺序、验证逻辑）有参考价值 |

**可参考的设计**：
- 引导步骤顺序和每步的内容
- API Key 验证逻辑
- 录音测试流程
- 配置保存逻辑
- 权限申请时机

**iOS 替代方案**：
- SwiftUI TabView + PageTabViewStyle 实现分步引导
- 大幅简化（iOS 无需配置热键、无需选择录音模式——默认 hold-to-talk）
- 增加键盘扩展设置引导（iOS 特有）

---

### 12. StatusOverlay.swift

| 属性 | 详情 |
|------|------|
| **功能** | 录音/处理状态浮层：NSWindow 浮窗，波形动画（录音中）、笔写动画✏️（处理中），始终在最前端 |
| **代码规模** | ~9.4KB，约 275 行 |
| **核心依赖** | AppKit (NSWindow, NSView, CALayer, CAShapeLayer, CADisplayLink) |
| **iOS 可复用度** | 低 ❌ |
| **原因** | NSWindow 浮窗 + CoreAnimation 手写动画，iOS 不需要浮窗方案 |

**iOS 替代方案**：
- 主 App：SwiftUI WaveformView（已有设计，使用 Canvas + TimelineView）
- 键盘扩展：在键盘 UI 内部直接显示波形和状态
- 触觉反馈替代视觉浮窗提示

---

## 模块复用度总结

| 模块 | 文件大小 | iOS 可复用度 | 迁移策略 |
|------|---------|-------------|---------|
| TextFormatter | 3.1KB | ✅✅ 完全复用 | 零改动复制 |
| AudioRecorder | 2.2KB | ✅ 高 | 小幅适配（AudioSession mode） |
| HistoryManager | 4.9KB | ✅ 高 | 路径适配 + 可选 Codable 改造 |
| PostProcessor | 17.0KB | ✅ 高 | async/await 改造 + 路径适配 |
| Transcriber | 17.1KB | ⚠️ 中 | 拆分为协议+多实现，去掉 Process/Semaphore |
| AppDelegate | 18.7KB | ❌ 低 | 业务流程可参考，代码完全重写 |
| ContextDetector | 8.2KB | ❌ 低 | 替代方案：手动场景选择 |
| PasteHelper | 5.0KB | ❌ 低 | 替代方案：UIPasteboard + textDocumentProxy |
| StatusOverlay | 9.4KB | ❌ 低 | 替代方案：SwiftUI WaveformView |
| SetupWindow | 73.4KB | ❌ 低 | SwiftUI 完全重写，参考引导流程 |
| HistoryWindowController | 20.1KB | ❌ 低 | SwiftUI 完全重写 |
| main.swift | 0.1KB | ❌ 低 | SwiftUI App 协议替代 |

**总结**：
- 可高比例复用的核心业务逻辑：约 44KB（TextFormatter + AudioRecorder + HistoryManager + PostProcessor + 部分 Transcriber）
- 需要完全重写的 UI 和平台相关代码：约 136KB（所有 AppKit UI、Carbon HotKey、CGEvent 粘贴等）
- 按代码量计约 24% 可复用，但按功能价值计核心 pipeline 逻辑（ASR 调用、LLM 调用、格式化）复用率超过 70%

---

## macOS 专属 API 替换清单

| macOS API | 用途 | iOS 替代 |
|-----------|------|---------|
| Carbon RegisterEventHotKey | 全局快捷键 | App 内按钮 + 键盘扩展 |
| NSStatusBar / NSStatusItem | 菜单栏驻留 | SwiftUI 主界面 |
| NSSound | 音效反馈 | UIFeedbackGenerator（触觉反馈） |
| NSPasteboard | 剪贴板 | UIPasteboard |
| CGEvent (Cmd+V) | 自动粘贴 | textDocumentProxy.insertText() |
| Process() (osascript) | 脚本执行 | 不适用 |
| Process() (whisper-cli) | 本地 ASR | whisper.cpp SPM 直接集成 |
| NSWorkspace.frontmostApplication | 前台 App 检测 | iOS 沙箱禁止，改手动选择 |
| NSWindow (浮窗) | 状态浮层 | SwiftUI 内联 UI |
| NSTableView | 历史列表 | SwiftUI List |
| NSView + AutoLayout | 所有 UI | SwiftUI |
| DispatchSemaphore (同步阻塞) | 网络同步调用 | Swift Concurrency async/await |
| FileManager (~/.vox/) | 配置存储 | App Group Container |
