# 04 — iOS 版架构设计

> 日期：2026-03-02

---

## 1. 整体架构

iOS 版 Vox 由三个组件构成：

    ┌─────────────────────────────────────────────────────────┐
    │                      VoxiOS (主 App)                    │
    │                                                         │
    │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐     │
    │  │ UI层 │→│录音层 │→│ ASR层│→│ LLM层│→│输出层 │     │
    │  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘     │
    │                                                         │
    │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐               │
    │  │设置  │  │历史  │  │网络  │  │反馈  │               │
    │  └──────┘  └──────┘  └──────┘  └──────┘               │
    └─────────────────┬───────────────────────────────────────┘
                      │  App Group（共享容器）
                      │  - UserDefaults(suiteName:)
                      │  - Keychain(accessGroup:)
                      │  - 共享文件目录
    ┌─────────────────┴───────────────────────────────────────┐
    │                VoxKeyboard (键盘扩展)                    │
    │                                                         │
    │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐     │
    │  │键盘UI│→│录音层 │→│ ASR层│→│ LLM层│→│注入层 │     │
    │  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘     │
    │                                                         │
    │  textDocumentProxy.insertText() → 宿主 App 输入框       │
    └─────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────┐
    │                  Shared（共享代码库）                     │
    │                                                         │
    │  AudioRecorder / ASRProvider / QwenASR / WhisperAPIASR  │
    │  PostProcessor / TextFormatter / ConfigStore            │
    │  KeychainStore / AppGroupConfig / VoxError              │
    │  HapticFeedback / NetworkMonitor                        │
    └─────────────────────────────────────────────────────────┘

### 关键设计原则

1. **共享核心逻辑**：录音、ASR、LLM、格式化等核心模块放在 Shared 中，主 App 和键盘扩展共用同一份代码（通过 Xcode Target Membership）
2. **UI 各自实现**：主 App 使用 SwiftUI 全屏界面，键盘扩展使用 UIHostingController 包装 SwiftUI
3. **App Group 桥梁**：主 App 负责配置写入，键盘扩展读取配置
4. **零第三方依赖**：与 macOS 版一致，全部使用系统框架

---

## 2. 模块划分

### 2.1 UI 层（各自独立）

**主 App UI**
| 模块 | 职责 |
|------|------|
| VoxiOSApp | @main 入口，App 生命周期 |
| AppState | @Observable 全局状态管理，pipeline 流程编排 |
| MainView | 主录音界面：大按钮 + 波形 + 状态 + 结果展示 |
| WaveformView | 录音波形可视化（Canvas + TimelineView） |
| SettingsView | 完整设置页（ASR/LLM provider、API Key、场景、翻译等） |
| SetupView | 首次使用引导（权限 → API Key → 键盘设置 → 完成） |
| HistoryView | 历史记录列表（搜索、删除、复制、翻译记录展示） |

**键盘扩展 UI**
| 模块 | 职责 |
|------|------|
| KeyboardViewController | UIInputViewController 子类，管理键盘生命周期，处理 `needsInputModeSwitchKey` |
| KeyboardView | SwiftUI 键盘界面：麦克风按钮 + 波形 + 场景选择 + **地球键（输入法切换）** + 状态 |
| KeyboardState | @Observable 键盘状态（recording / processing / error 等） |

**键盘扩展性能预算**
| 指标 | 目标值 | 说明 |
|------|--------|------|
| 首帧渲染 | < 300ms | 从键盘被激活到 UI 完整显示 |
| 峰值内存 | < 55MB | 包含录音中的音频缓冲、网络请求、SwiftUI 视图 |
| 空闲内存 | < 30MB | 键盘显示但未录音时 |
| 录音启动延迟 | < 100ms | 从用户触摸到 AVAudioRecorder 开始录音 |

> 📌 iOS 键盘扩展的内存上限约 48-80MB（因设备和 iOS 版本而异），超限会被系统静默 kill。55MB 的峰值目标留有安全余量。如果 SwiftUI 视图复杂度导致超限，应简化视图层级（减少嵌套、避免大图片、懒加载），而非切换到 UIKit。

### 2.2 录音层（Shared）

| 模块 | 职责 |
|------|------|
| AudioRecorder | AVAudioSession 配置 + AVAudioRecorder 封装 + 电平采样 + 静音检测 |

关键行为：
- 支持两种 AudioSession 模式：mainApp（.record + .measurement）和 keyboardExtension（.playAndRecord + .mixWithOthers）
- 输出格式：16kHz / 16bit / Mono WAV（与 macOS 一致）
- 电平采样频率：100ms
- 静音检测阈值：peakPower > -50dB
- 最小文件大小：16000 bytes（约 0.5 秒）

### 2.3 ASR 层（Shared）

| 模块 | 职责 |
|------|------|
| ASRProvider | ASR 协议定义（transcribe(audioFile:) async throws -> String） |
| ASRFactory | 工厂方法：根据配置创建 provider + 离线降级 provider |
| QwenASR | Qwen3-ASR-Flash 实现（base64 音频 + DashScope Chat API） |
| WhisperAPIASR | Whisper 兼容 API 实现（multipart/form-data） |
| AppleSpeechASR | Apple Speech Framework 实现（离线降级用） |

关键行为：
- 超时：25 秒
- 重试：最多 2 次，指数退避（0.8s, 1.6s）
- 降级链：Qwen → Apple Speech（网络不可用时）
- 结果校验：空文本或少于 2 字符视为无效

### 2.4 LLM 后处理层（Shared）

| 模块 | 职责 |
|------|------|
| PostProcessor | 多 provider LLM 调用，支持 Anthropic 和 OpenAI 两种 API 格式 |
| TextFormatter | CJK/ASCII 间距 + 标点规范化（从 macOS 零改动复用） |

关键行为：
- 超时：12 秒
- 失败降级：LLM 失败时用 ASR 原文 + TextFormatter 格式化
- enable_thinking: false（Qwen 3.5+ 必加，否则延迟暴增）
- 翻译模式：独立 translatePrompt
- 自定义 prompt：从 prompt.txt 加载，# 开头行过滤
- 场景 hint：SceneSelector / textDocumentProxy 上下文

### 2.5 输出层

| 模块 | 位置 | 职责 |
|------|------|------|
| ClipboardOutput | 主 App | UIPasteboard 写入 + 5 分钟过期 |
| textDocumentProxy.insertText | 键盘扩展 | 直接注入文字到宿主 App |

### 2.6 配置层（Shared）

| 模块 | 职责 |
|------|------|
| ConfigStore | config.json 读写（App Group Container 路径） |
| KeychainStore | API Key 安全存储（Keychain + App Group Access Group） |
| AppGroupConfig | App Group 常量 + 共享 UserDefaults(suiteName:) |

### 2.7 辅助模块（Shared）

| 模块 | 职责 |
|------|------|
| VoxError | 统一错误类型枚举（permissionDenied / audioEmpty / asrTimeout 等） |
| HapticFeedback | 触觉反馈管理（recordStart / recordStop / success / error） |
| NetworkMonitor | NWPathMonitor 网络状态监控（离线时自动切 Apple Speech） |
| SceneSelector | 手动场景选择（替代 macOS ContextDetector） |
| HistoryManager | 历史记录管理（增删查清、retention 清理、翻译记录） |

---

## 3. 数据流

### 3.1 主 App 完整数据流

    用户点击麦克风按钮
      → AppState.toggleRecording()
      → 检查麦克风权限（AudioRecorder.requestPermission）
         → 未授权：显示引导页，流程终止
         → 已授权：继续
      → HapticFeedback.recordStart()（触觉反馈）
      → AudioRecorder.start(mode: .mainApp)
         → AVAudioSession.setCategory(.record, mode: .measurement)
         → AVAudioRecorder 开始录制 16kHz WAV 到 tmp/
         → Timer 100ms 采样电平 → WaveformView 波形动画
      → recordingState = .recording
    
    用户再次点击按钮（停止）
      → HapticFeedback.recordStop()
      → AudioRecorder.stop() → audioURL
      → 检查 hasAudio（peakPower > -50dB）
         → 静音：丢弃文件，显示"未检测到有效语音"，恢复 idle
      → 检查文件大小（>= 16000 bytes）
         → 过短：丢弃文件，显示"录音过短"，恢复 idle
      → recordingState = .processing
    
    后台处理（async）
      → Step 1: ASR 转写
         → NetworkMonitor.isConnected?
            → 有网络：ASRFactory.create(config) → Qwen/Whisper API
            → 无网络：ASRFactory.offlineFallback() → Apple Speech
         → 超时 25s，重试 2 次
         → 结果为空：显示"未识别到有效文字"，恢复 idle
      → Step 2: LLM 后处理（可选）
         → PostProcessor.isConfigured?
            → 是：获取 sceneHint → PostProcessor.process(rawText, sceneHint, translateMode)
            → 否：跳过，使用 ASR 原文
         → 超时 12s，失败降级到 ASR 原文
      → Step 3: 文本格式化（始终执行）
         → TextFormatter.format(text) → CJK 间距 + 标点规范化
      → Step 4: 输出
         → ClipboardOutput.copy(text) → UIPasteboard 写入（5 分钟过期）
         → HapticFeedback.success()
      → Step 5: 历史记录
         → HistoryManager.addRecord(text, originalText, isTranslation)
      → recordingState = .idle
      → 显示结果 Toast
    
    异常路径
      → ASR 失败 + Apple Speech 也失败：显示错误 + HapticFeedback.error()
      → LLM 失败：降级到 ASR 原文 + TextFormatter（非阻断）
      → 剪贴板失败：显示文本让用户手动复制

### 3.2 键盘扩展数据流

    用户在任意 App 中切换到 Vox 键盘
      → KeyboardViewController.viewDidLoad()
      → 检查 hasFullAccess
         → 否：显示"请在设置中开启完全访问"引导
         → 是：显示正常键盘 UI
    
    用户按住麦克风按钮（touchDown / DragGesture.onChanged）
      → 检查 AVAudioSession.recordPermission
         → 未授权：显示"请在 Vox App 中授权麦克风"引导
         → 已授权：继续
      → AVAudioSession.setCategory(.playAndRecord, .mixWithOthers, .allowBluetooth)
      → AudioRecorder.start(mode: .keyboardExtension)
      → KeyboardState.status = .recording
      → 波形动画
    
    用户松开按钮（touchUp / DragGesture.onEnded）
      → AudioRecorder.stop() → audioURL
      → 读取 textDocumentProxy.documentContextBeforeInput（上下文）
      → KeyboardState.status = .processing
      → 后台处理（短事务模式——超时更短，见下方说明）
         → ASR 超时 15s（短于主 App 的 25s），重试 1 次
         → LLM 超时 8s（短于主 App 的 12s）
      → textDocumentProxy.insertText(finalText)（直接注入文字）
      → AVAudioSession.setActive(false, .notifyOthersOnDeactivation)
      → KeyboardState.status = .idle
    
    异常路径（键盘扩展特有）
      → 请求进行中用户切走键盘：下次激活时清理残留状态，提示重试
      → 进程被系统回收：状态丢失，下次冷启动重新初始化
      → 网络请求超时：显示错误 + 提供"在主 App 中重试"的引导

---

## 4. 状态机

### 4.1 主 App 录音状态机

    ┌──────────────────────────────────┐
    │              idle                │ ← 初始状态
    └──────────┬───────────────────────┘
               │ 用户点击按钮
               │ 权限检查通过
               ▼
    ┌──────────────────────────────────┐
    │           recording              │ ← 录音中（波形动画）
    └──────────┬───────────────────────┘
               │ 用户点击停止
               │ 静音/过短检查
               │   → 失败：回到 idle + 错误提示
               ▼
    ┌──────────────────────────────────┐
    │          processing              │ ← 处理中（ASR → LLM → Format）
    └──────┬──────────────┬────────────┘
           │ 成功          │ 失败
           ▼              ▼
    ┌────────────┐  ┌────────────┐
    │  idle      │  │  idle      │
    │ + 结果Toast │  │ + 错误提示 │
    └────────────┘  └────────────┘

### 4.2 键盘扩展状态机

    idle → [touchDown] → recording → [touchUp] → processing → [完成] → idle
     │                                                │
     ├── noAccess ← [hasFullAccess 检查失败]            │
     ├── noMicPermission ← [麦克风未授权]               │
     └── error ← [ASR/LLM 失败] ←─────────────────────┘

### 4.3 首次使用状态机

    未完成设置 → SetupView
      Step 1: 欢迎页（说明功能）
      Step 2: 麦克风权限申请
      Step 3: API Key 配置
      Step 4: 键盘扩展设置引导（可跳过）
      Step 5: 测试录音
      Step 6: 完成
    → 已完成设置 → MainView

---

## 5. App Group / 共享容器设计

### 5.1 共享机制（双 Entitlement 配置）

iOS 上主 App 与键盘扩展的数据共享依赖**两套独立的 entitlement 机制**，必须分别配置：

| 机制 | Entitlement | 标识符格式 | 共享内容 |
|------|------------|-----------|---------|
| **App Group** | `com.apple.security.application-groups` | `group.com.{bundlePrefix}.vox` | 共享文件容器、UserDefaults(suiteName:) |
| **Keychain Sharing** | `keychain-access-groups` | `$(TeamID).com.{bundlePrefix}.vox.shared` | Keychain 中的 API Key 等敏感数据 |

> ⚠️ **常见误区**：App Group 和 Keychain Sharing 是两回事。配了 App Group 不等于 Keychain 也能共享。两个 Target 必须在 Xcode → Signing & Capabilities 中分别添加 App Groups **和** Keychain Sharing，并指向相同的 group/access group 标识符。

### 5.2 数据存储分布

| 数据 | 存储方式 | 写入方 | 读取方 | 说明 |
|------|---------|--------|--------|------|
| API Key（Qwen ASR） | **Keychain**（通过 Keychain Sharing entitlement） | 主 App | 主 App + 键盘扩展 | kSecAttrAccessGroup = `$(TeamID).com.xxx.vox.shared` |
| API Key（LLM） | **Keychain**（通过 Keychain Sharing entitlement） | 主 App | 主 App + 键盘扩展 | 同上 |
| config.json | **App Group 共享文件容器** | 主 App | 主 App + 键盘扩展 | provider 选择、模型等 |
| prompt.txt | **App Group 共享文件容器** | 主 App | 主 App + 键盘扩展 | 自定义 System Prompt |
| history.json | **App Group 共享文件容器** | 主 App | 仅主 App | 键盘扩展不需要访问 |
| debug.log | **App Group 共享文件容器** | 主 App + 键盘扩展 | 主 App | 调试日志（见下方安全策略） |
| 偏好设置 | **UserDefaults**(suiteName: App Group ID) | 主 App | 主 App + 键盘扩展 | ASR provider、场景选择等 |

### 5.3 文件目录结构

    App Group Container/
    └── Vox/
        ├── config.json      — 非敏感配置（provider、模型、选项）
        ├── prompt.txt       — 自定义 System Prompt
        ├── history.json     — 历史记录（仅主 App 读写）
        └── debug.log        — 调试日志（双方写入）

### 5.4 日志安全策略

debug.log 位于 App Group 共享容器中，可能包含 ASR 识别文本、LLM 响应片段、错误上下文等敏感信息。在键盘扩展场景下（用户输入可能包含密码、私密对话），需要特别注意日志安全：

| 策略 | 说明 |
|------|------|
| **默认关闭详细日志** | Release 版本默认 logLevel = .error，不记录 ASR/LLM 的输入输出文本 |
| **日志脱敏** | 即使 Debug 模式，对 ASR 识别结果和 LLM 响应仅记录前 20 字符 + "..." 的摘要形式 |
| **按天滚动 + 自动清理** | 日志按天分文件（debug-YYYY-MM-DD.log），保留最近 7 天，自动清理过期日志 |
| **导出需用户确认** | 主 App 中的"导出调试日志"功能需用户主动点击确认 |
| **不记录 API Key** | 任何日志级别都不记录 API Key 的明文或部分内容 |

### 5.5 并发注意事项

- 主 App 和键盘扩展理论上可能同时运行（用户在某个 App 中使用 Vox 键盘，同时 Vox 主 App 在后台）
- 实际场景中几乎不会同时写入同一个文件
- MVP 阶段不需要文件锁或 Actor 保护
- debug.log 并发写入最多丢几行日志，不影响功能
- 如果后续需要严格一致性，可引入 NSFileCoordinator

---

## 6. 权限模型

### 6.1 主 App 权限

| 权限 | iOS API | 用途 | 何时申请 | Info.plist Key |
|------|---------|------|---------|----------------|
| 麦克风 | AVAudioSession.requestRecordPermission | 录音 | 首次使用引导 Step 2 | NSMicrophoneUsageDescription |
| 语音识别 | SFSpeechRecognizer.requestAuthorization | Apple Speech 离线 ASR | 首次使用引导（可选） | NSSpeechRecognitionUsageDescription |

### 6.2 键盘扩展权限

| 权限 | 说明 | 获取方式 |
|------|------|---------|
| Full Access（完全访问） | 联网、麦克风、App Group | 用户手动在 Settings → Keyboards → Vox 中开启 |
| 麦克风 | 录音 | 必须在主 App 中预先授权；键盘扩展无法弹权限弹窗 |
| 网络 | ASR/LLM API 调用 | Full Access 开启后自动获得 |

### 6.3 权限检查流程

    启动主 App
      → 检查 hasCompletedSetup
         → 否：进入 SetupView 引导流程
            → Step 2: requestRecordPermission
               → 授权：继续
               → 拒绝：引导到系统设置
            → Step 4: 引导用户去 Settings 添加 Vox 键盘 + 开启完全访问
    
    使用键盘扩展
      → 检查 hasFullAccess
         → 否：显示内联引导文字
      → 检查 AVAudioSession.recordPermission
         → .undetermined / .denied：显示"请在 Vox App 中授权"
         → .granted：正常使用

### 6.4 权限被撤销的处理

- 用户随时可以在 Settings 中关闭麦克风权限或键盘完全访问
- 每次录音前都要检查权限状态
- 权限被撤销时：显示清晰的引导信息，不崩溃不报错
- 主 App 可以通过 URL Scheme 引导到系统设置（UIApplication.openSettings）
- 键盘扩展无法调用 openURL，只能显示文字引导

---

## 7. 技术栈总览

| 层次 | 技术选型 | 版本 |
|------|---------|------|
| UI 框架 | SwiftUI | iOS 17+ |
| 状态管理 | @Observable (Observation framework) | iOS 17+ |
| 录音 | AVFoundation (AVAudioRecorder, AVAudioSession) | iOS 17+ |
| 云端 ASR | URLSession (async/await) | iOS 17+ |
| 离线 ASR (P1) | Speech.framework (SFSpeechRecognizer) | iOS 17+ |
| 本地 ASR (P2) | whisper.cpp SPM | — |
| LLM 后处理 | URLSession (async/await) | iOS 17+ |
| 文本格式化 | Foundation (NSRegularExpression) | iOS 17+ |
| 配置存储 | UserDefaults (App Group) | iOS 17+ |
| 密钥存储 | Security.framework (Keychain + App Group) | iOS 17+ |
| 键盘扩展 | UIInputViewController + UIHostingController + SwiftUI | iOS 17+ |
| 网络监控 | Network.framework (NWPathMonitor) | iOS 17+ |
| 触觉反馈 | UIKit (UIFeedbackGenerator) | iOS 17+ |
| App Intent (P2) | AppIntents.framework | iOS 17+ |
| 音频压缩 (P2, 待验证) | Opus 编码（需 libopus SPM 集成，AVAudioConverter 原生不支持 Opus 编码）；fallback: PCM + 限长 | iOS 17+ |
| 语言 | Swift 5.9+ | — |
| 第三方依赖 | 零 | — |
