# 05 — 逐模块迁移策略

> 日期：2026-03-02
> 迁移复杂度：1（直接复制）— 5（完全重写或新建）
> 工时单位：人天（1 人天 ≈ 6-8 有效小时）

---

## 迁移策略总表

| # | 模块 | Mac 版实现 | iOS 迁移策略 | 复杂度 | 工时 | 关键风险 |
|---|------|-----------|------------|--------|------|---------|
| 1 | TextFormatter | Foundation 正则操作（CJK 间距 + 标点规范化） | **直接复用** | 1 | 0.1 | 无 |
| 2 | AudioRecorder | AVAudioRecorder 16kHz WAV + 电平采样 | **需适配** | 2 | 0.5 | 键盘扩展 AudioSession 配置与宿主 App 冲突 |
| 3 | HistoryManager | JSON 文件持久化（增删查清 + retention） | **需适配** | 2 | 0.5 | 存储路径改 App Group Container |
| 4 | QwenASR | URLSession + base64 + DashScope Chat API | **需适配** | 2 | 1.0 | DispatchSemaphore → async/await 改造 |
| 5 | WhisperAPIASR | URLSession + multipart/form-data | **需适配** | 2 | 0.5 | 同上 |
| 6 | PostProcessor | URLSession + 多 provider + 双 API 格式 | **需适配** | 3 | 1.5 | async/await 改造 + enable_thinking + thinking block 过滤 |
| 7 | ConfigStore | JSON 文件读写（~/.vox/） | **需适配** | 2 | 0.5 | 路径改 App Group Container |
| 8 | KeychainStore | — | **新建** | 3 | 1.0 | App Group Keychain 共享配置 |
| 9 | AppGroupConfig | — | **新建** | 2 | 0.3 | App Group 常量 + 共享 UserDefaults |
| 10 | VoxError | — | **新建** | 1 | 0.3 | 统一错误类型枚举 |
| 11 | HapticFeedback | NSSound（4 种音效） | **完全重写** | 2 | 0.3 | UIFeedbackGenerator 替代 |
| 12 | NetworkMonitor | — | **新建** | 2 | 0.3 | NWPathMonitor 网络状态 |
| 13 | SceneSelector | ContextDetector（NSWorkspace + AppleScript） | **完全重写** | 3 | 0.5 | 手动场景选择替代自动检测 |
| 14 | AppleSpeechASR | — | **新建** | 3 | 1.0 | SFSpeechRecognizer 离线降级，continuation 重入保护 |
| 15 | ASRProvider 协议 | Transcriber enum | **完全重写** | 2 | 0.5 | 拆分为协议 + 工厂 |
| 16 | AppState | AppDelegate（macOS 菜单栏 App 状态管理） | **完全重写** | 4 | 2.0 | @Observable + pipeline 编排 + 错误处理 |
| 17 | MainView | — | **新建** | 3 | 1.5 | SwiftUI 主界面 |
| 18 | WaveformView | StatusOverlay（NSWindow 浮窗 + CALayer） | **完全重写** | 3 | 1.0 | SwiftUI Canvas + TimelineView |
| 19 | SettingsView | SetupWindow 的部分（NSWindow + NSView） | **完全重写** | 4 | 2.0 | SwiftUI Form，所有 provider 配置 |
| 20 | SetupView | SetupWindow（73KB AppKit 多步向导） | **完全重写** | 3 | 1.5 | SwiftUI 引导流程，含键盘设置引导 |
| 21 | HistoryView | HistoryWindowController（NSTableView） | **完全重写** | 3 | 1.0 | SwiftUI List + 搜索 + 滑动删除 |
| 22 | ClipboardOutput | PasteHelper（NSPasteboard + CGEvent） | **完全重写** | 2 | 0.3 | UIPasteboard + 过期时间 |
| 23 | VoxiOSApp | main.swift（NSApplication） | **完全重写** | 1 | 0.2 | SwiftUI @main App 协议 |
| 24 | KeyboardViewController | — | **新建** | 5 | 3.0 | UIInputViewController + 权限检查 + 音频配置 + **needsInputModeSwitchKey/地球键** |
| 25 | KeyboardView | — | **新建** | 4 | 2.0 | SwiftUI 键盘 UI + hold-to-talk 手势 + **地球键 UI** |
| 26 | KeyboardState | — | **新建** | 2 | 0.3 | @Observable 键盘状态 |
| 27 | Xcode 项目配置 | build.sh（命令行构建） | **新建** | 4 | 1.5 | .xcodeproj + 双 Target + App Group + Capabilities |

---

## 工时汇总

| 类别 | 模块数 | 总工时（人天） |
|------|--------|-------------|
| 直接复用 | 1 | 0.1 |
| 需适配 | 6 | 4.5 |
| 完全重写 | 10 | 10.8 |
| 新建 | 10 | 10.2 |
| **总计** | **27** | **25.6** |

**含缓冲（×1.3）：约 33 人天**

注意：此工时估算假设一名有经验的 iOS 开发者全职投入，熟悉 Swift/SwiftUI/键盘扩展开发。

---

## 迁移策略详细说明

### 直接复用（1 个模块）

**TextFormatter**
- 零改动复制到 iOS 项目
- Foundation 的 NSRegularExpression 在 iOS 上行为完全一致
- 唯一需要确认的是 Unicode 正则在 iOS 上的处理（经验上没有差异）

### 需适配（6 个模块）

**AudioRecorder**
- 核心录音逻辑（AVAudioRecorder 参数、电平采样）不变
- 新增 AudioSessionMode 枚举，区分主 App 和键盘扩展的 AVAudioSession 配置
- 键盘扩展的 .playAndRecord + .mixWithOthers 是关键适配点
- 录音结束后的 deactivateAudioSession 需正确处理

**HistoryManager**
- 数据结构和逻辑不变
- 存储路径从 `~/.vox/history.json` 改为 App Group Container
- 建议用 Codable（JSONDecoder/JSONEncoder）替代手动 JSONSerialization
- 日期格式使用 ISO8601

**QwenASR / WhisperAPIASR**
- 网络调用逻辑不变（URL、Headers、Body 格式）
- DispatchSemaphore 同步阻塞 → withCheckedThrowingContinuation 或原生 async/await
- 配置读取路径适配
- 补充 asr_options 中的 format 字段

**PostProcessor**
- 多 provider 配置和 API 调用逻辑不变
- DispatchSemaphore → async/await 改造
- 补充 enable_thinking: false（Qwen 3.5+ 优化）
- Anthropic 格式响应解析：过滤 thinking blocks，只取 type == "text"
- 翻译模式 translatePrompt 直接移植
- prompt.txt 路径适配到 App Group Container

**ConfigStore**
- JSON 读写逻辑不变
- 路径从 FileManager 的 applicationSupport 改为 containerURL(forSecurityApplicationGroupIdentifier:)
- 确保 App Group Container 可被两个 Target 访问

### 完全重写（10 个模块）

需要完全重写的模块主要是两类：
1. **AppKit UI → SwiftUI**：MainView、SettingsView、SetupView、HistoryView、WaveformView
2. **macOS 专属 API → iOS 替代**：AppState（热键→按钮）、HapticFeedback（NSSound→UIFeedbackGenerator）、SceneSelector（NSWorkspace→手动选择）、ClipboardOutput（CGEvent→UIPasteboard）、VoxiOSApp（NSApp→SwiftUI App）

这些模块虽然需要完全重写代码，但 macOS 版的设计思路、流程编排、功能需求可以作为参考。

### 新建（10 个模块）

新建模块主要是：
1. **iOS 特有需求**：KeyboardViewController、KeyboardView、KeyboardState（键盘扩展全套）
2. **架构改进**：ASRProvider 协议、ASRFactory（macOS 版是单一 enum，iOS 版拆为协议+多实现）
3. **iOS 基础设施**：KeychainStore、AppGroupConfig、VoxError、NetworkMonitor、AppleSpeechASR
4. **Xcode 项目配置**：双 Target + App Group + Capabilities

---

## 关键风险清单

| 模块 | 风险 | 缓解方案 |
|------|------|---------|
| KeyboardViewController | 键盘扩展是整个项目最复杂的新建模块，涉及权限检查、音频配置、SwiftUI 嵌入、textDocumentProxy 交互 | 从 Sprint 4 开始，已有稳定的主 App pipeline 作为基础 |
| AudioRecorder（键盘扩展模式） | AVAudioSession .playAndRecord + .mixWithOthers 可能与某些宿主 App 不兼容 | 广泛测试（微信、备忘录、Safari、邮件等） |
| PostProcessor（async 改造） | DispatchSemaphore → async/await 改造可能引入竞态问题 | 仔细处理 Task 取消和超时 |
| SettingsView | 需要支持所有 provider 的配置模板，UI 复杂度高 | 参考 macOS SetupWindow 的 provider 列表，逐个实现 |
| Xcode 项目配置 | 双 Target + App Group + Keychain Sharing 的 Capabilities 配置容易出错 | 逐步配置，每步验证（先主 App，再加键盘扩展） |
| AppleSpeechASR | SFSpeechRecognizer recognitionTask 回调可能多次触发，continuation 只能 resume 一次 | 加 flag 保证只 resume 一次 |
