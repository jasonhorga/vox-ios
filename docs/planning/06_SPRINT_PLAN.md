# 06 — 分阶段执行计划

> 日期：2026-03-02
> 本文档使用依赖关系和优先级排列，不使用日历时间

---

## P0 — 核心可用（主 App MVP）

### 目标
跑通"录音 → ASR → 可选 LLM 后处理 → 格式化 → 剪贴板"完整闭环，主 App 可独立交付 TestFlight 内测。

### 包含功能
- 主 App 内大按钮录音（toggle 模式：点一次开始，再点停止）
- 实时波形动画
- 云端 ASR 转写（Qwen / Whisper API）
- 可选 LLM 后处理（多 provider 支持）
- 文本格式化（CJK 间距 + 标点规范化）
- 剪贴板输出 + 触觉反馈
- 静音检测 + 短录音丢弃
- LLM 失败降级到原文
- 完整设置页（ASR/LLM provider 配置 + API Key 管理）
- 首次使用引导（权限申请 + API Key 配置）
- Keychain 安全存储 API Key
- 网络状态监控
- 统一错误处理

### 细分 Sprint

#### Sprint 0: 项目骨架与录音（预估 1-2 天）

| # | 任务 | 产物 | 验收标准 |
|---|------|------|---------|
| 0.1 | 创建 Xcode 项目（SwiftUI App, iOS 17+, 主 App Target） | .xcodeproj | 编译通过 |
| 0.2 | Info.plist 配置（NSMicrophoneUsageDescription） | Info.plist | 权限弹窗正常 |
| 0.3 | AudioRecorder 实现（AVAudioSession + AVAudioRecorder + 电平采样） | AudioRecorder.swift | 真机录音成功 |
| 0.4 | WaveformView 实现（SwiftUI Canvas + TimelineView） | WaveformView.swift | 波形随声音变化 |
| 0.5 | HapticFeedback 实现（4 种反馈） | HapticFeedback.swift | 触觉可感知 |
| 0.6 | VoxError 统一错误类型 | VoxError.swift | 枚举编译通过 |
| 0.7 | 最小 AppState + MainView（开始/停止按钮 + 波形） | AppState.swift, MainView.swift | 按钮切换状态，波形显示 |
| 0.8 | 麦克风权限请求流程 | 权限逻辑 | 授权→可录音；拒绝→引导设置 |

**验收标准**：真机上可启动 → 点按钮 → 波形动画 → 停止 → tmp/ 下生成 16kHz WAV

#### Sprint 1: ASR 转写（预估 2-3 天）

| # | 任务 | 产物 | 验收标准 |
|---|------|------|---------|
| 1.1 | ASRProvider 协议 + ASRFactory | ASRProvider.swift | 协议清晰 |
| 1.2 | QwenASR 实现（async/await） | QwenASR.swift | Qwen API 调用成功 |
| 1.3 | WhisperAPIASR 实现 | WhisperAPIASR.swift | Whisper API 调用成功 |
| 1.4 | ConfigStore 实现（JSON 读写, App Group 路径） | ConfigStore.swift | 配置持久化 |
| 1.5 | KeychainStore 实现 | KeychainStore.swift | Keychain 读写成功 |
| 1.6 | AppGroupConfig 实现 | AppGroupConfig.swift | App Group 配置 |
| 1.7 | NetworkMonitor 实现 | NetworkMonitor.swift | 网络状态可观察 |
| 1.8 | AppState 集成 ASR + 错误处理 | AppState 更新 | 转写结果显示 |
| 1.9 | 超时 + 重试逻辑（25s, 2 次） | 重试函数 | 超时后重试 |
| 1.10 | 音频临时文件清理 | 逻辑更新 | 无残留文件 |

**验收标准**：中文/英文/中英混合语音 → Qwen ASR → 正确文本；断网有提示

#### Sprint 2: LLM + 格式化 + 输出（预估 2-3 天）

| # | 任务 | 产物 | 验收标准 |
|---|------|------|---------|
| 2.1 | PostProcessor 移植（Anthropic + OpenAI 双格式） | PostProcessor.swift | 双格式调用成功 |
| 2.2 | enable_thinking: false 修正 | 代码更新 | Qwen LLM < 3s |
| 2.3 | Anthropic 格式 thinking block 过滤 | 代码更新 | 只取 text block |
| 2.4 | TextFormatter 复制（零改动） | TextFormatter.swift | CJK 格式化正确 |
| 2.5 | ClipboardOutput 升级（过期时间 + 触觉） | ClipboardOutput.swift | 剪贴板 + 震动 |
| 2.6 | LLM 降级链路 | AppState 更新 | LLM 超时不阻塞 |
| 2.7 | SceneSelector 实现 | SceneSelector.swift | 场景影响 Prompt |
| 2.8 | MainView 更新（场景选择 + 结果展示 + Toast） | UI 更新 | 可切换场景 |

**验收标准**：录音 → ASR → LLM 优化 → 格式化 → 剪贴板完整闭环；LLM 超时自动降级

#### Sprint 3: 设置 + 引导 + MVP 打包（预估 2-3 天）

| # | 任务 | 产物 | 验收标准 |
|---|------|------|---------|
| 3.1 | SetupView 完善（4 步引导） | SetupView.swift | 引导流程顺畅 |
| 3.2 | SettingsView 完善（所有 provider 配置） | SettingsView.swift | 全部 provider 可配 |
| 3.3 | API Key 仅存 Keychain | 安全逻辑 | config.json 无明文 Key |
| 3.4 | AppleSpeechASR 离线备用 | AppleSpeechASR.swift | 离线可降级 |
| 3.5 | 端到端测试（20 次样本） | 测试记录 | 成功率 >= 95% |
| 3.6 | 性能 profiling（内存、延迟） | 性能记录 | 内存 < 50MB |
| 3.7 | App Icon + LaunchScreen | 资源文件 | 启动正常 |
| 3.8 | TestFlight 打包 | .ipa | 可安装使用 |

**验收标准**：首次用户从安装到成功使用 < 3 分钟；20 次录音成功率 >= 95%；WiFi 30s 音频端到端 <= 8s

### P0 总产物
- 可通过 TestFlight 安装的 iOS App
- 完整的录音→ASR→LLM→格式化→剪贴板 pipeline
- 设置和引导界面
- 版本号：v0.1.0

### P0 预估总时长
7-11 天（单人全职）

---

## P1 — 全局输入（键盘扩展 + 增强功能）

### 目标
通过自定义键盘扩展实现跨 App 语音输入——这是 iOS 版 Vox 的核心差异化价值。同时补齐翻译模式、历史记录等重要功能。

### 包含功能
- 自定义键盘扩展（VoxKeyboard）
- Hold-to-talk 手势（按住说话，松开处理+注入）
- textDocumentProxy.insertText() 跨 App 文字注入
- App Group 配置共享
- Keychain 共享（API Key 跨 Target 读取）
- hasFullAccess / 麦克风权限检查与引导
- AVAudioSession .playAndRecord + .mixWithOthers（不中断宿主 App 音频）
- textDocumentProxy 上下文感知（光标前文字作为 LLM hint）
- 键盘内场景选择
- 翻译模式（translatePrompt + 历史记录标记）
- 历史记录管理（HistoryManager + HistoryView）

### 细分 Sprint

#### Sprint 4: 键盘扩展基础（预估 3-4 天）

| # | 任务 | 产物 | 验收标准 |
|---|------|------|---------|
| 4.1 | 创建 VoxKeyboard Extension Target | Xcode Target | 编译通过 |
| 4.2 | App Group 配置（主 App + 键盘扩展） | Capabilities | 共享容器可访问 |
| 4.3 | Keychain Sharing 配置 | Capabilities | Key 跨 Target 可读 |
| 4.4 | Info.plist: RequestsOpenAccess = YES | Info.plist | 可联网 |
| 4.5 | Shared 代码引用（双 Target Membership） | 项目结构 | 共享代码编译通过 |
| 4.6 | KeyboardViewController 实现 | 键盘控制器 | 键盘可见 |
| 4.7 | KeyboardView (SwiftUI) 实现 | 键盘 UI | UI 可操作 |
| 4.8 | KeyboardState 实现 | 状态管理 | 状态响应 |
| 4.9 | Hold-to-talk + AVAudioSession 配置 | 手势+音频 | 按住录音松开停止 |
| 4.10 | insertText 注入 | 输出 | 文字注入到目标 App |
| 4.11 | hasFullAccess + 麦克风权限检查 | 权限 | 未授权有引导 |
| 4.12 | **地球键（输入法切换）实现** | 键盘 UI | needsInputModeSwitchKey 检查 + advanceToNextInputMode() |
| 4.13 | **secureTextEntry 场景验证** | 测试记录 | 密码框自动切回系统键盘，Vox 键盘无异常 |

**验收标准**：在微信/备忘录/Safari 中切到 Vox 键盘 → 按住麦克风 → 说话 → 松开 → 文字出现；不中断宿主 App 音乐；地球键可切换到下一输入法

#### Sprint 5: 键盘扩展打磨 + 增强功能（预估 3-4 天）

| # | 任务 | 产物 | 验收标准 |
|---|------|------|---------|
| 5.1 | 内存 profiling（目标 < 60MB） | 性能记录 | 峰值 < 60MB |
| 5.2 | 键盘高度/机型适配 | AutoLayout | 各机型显示正常 |
| 5.3 | textDocumentProxy 上下文 → LLM hint | 逻辑集成 | 上下文影响输出 |
| 5.4 | 翻译模式（translatePrompt + UI toggle） | 功能实现 | 中→英翻译正确 |
| 5.5 | HistoryManager 移植 + HistoryView | 历史功能 | 历史记录可查看 |
| 5.6 | 键盘 Debug 日志 | 日志逻辑 | 可在主 App 查看 |
| 5.7 | DragGesture 重复触发修复 | Bug 修复 | 不会重复启动录音 |
| 5.8 | TestFlight 键盘扩展验证 | .ipa | 键盘可用 |
| 5.9 | **键盘扩展兼容性测试矩阵** | 测试记录 | 见下方验收矩阵 |
| 5.10 | **审核合规自查** | 检查清单 | 地球键、隐私弹窗、Open Access 文案 |

**验收标准**：键盘扩展内存 < 60MB；连续 10 分钟不崩溃；3 种机型显示正常；通过下方兼容性矩阵

**键盘扩展兼容性验收矩阵（DoD）**：

| 测试 App | 验收项 | 预期结果 |
|---------|--------|---------|
| 微信（聊天输入框） | 语音输入 → 文字注入 | ✅ 文字出现在输入框 |
| 备忘录 | 语音输入 → 文字注入 | ✅ 文字出现 |
| Safari（搜索框） | 语音输入 → 文字注入 | ✅ 文字出现 |
| 邮件（正文） | 语音输入 → 文字注入 | ✅ 文字出现 |
| 任意 App 密码框 | 切到密码框 | ✅ 自动切回系统键盘，无崩溃 |
| 银行类 App（如有） | 打开 App | ⚠️ 可能不允许第三方键盘，无崩溃即可 |
| 地球键 | 点击地球键 | ✅ 切换到下一输入法 |
| Open Access 关闭时 | 关闭完全访问后使用 | ✅ 显示引导提示，不崩溃 |
| 麦克风未授权时 | 尝试录音 | ✅ 显示引导提示，不崩溃 |

### P1 总产物
- 主 App + 键盘扩展的完整 App
- 跨 App 语音输入能力
- 翻译模式 + 历史记录
- 版本号：v0.2.0

### P1 前置依赖
- P0 完成（Sprint 3 验收通过）
- Apple Developer 证书支持 App Group
- 已确定最终 Bundle ID

### P1 预估总时长
6-8 天（单人全职）

---

## P2 — 打磨发布（增强功能 + App Store 准备）

### 目标
完善产品体验，增加高级功能，准备 App Store 审核材料并提交上架。

### 包含功能

| 功能 | 说明 | 预估工时 |
|------|------|---------|
| 自定义 prompt.txt 编辑器 | Settings 中多行文本编辑 + 恢复默认 | 1 天 |
| 音频压缩（WAV → Opus）⚠️ **待验证** | 需 libopus SPM 集成（AVAudioConverter 原生不支持 Opus 编码），fallback: PCM + 限长 | 1-2 天 |
| Apple Speech 完善 | 优化离线降级体验，流式识别 | 1 天 |
| Siri Shortcut 集成 | AppIntent + "Hey Siri, 用 Vox 录音" | 2 天 |
| Action Button 集成 | iPhone 15 Pro+ 侧边按钮快捷录音 | 0.5 天 |
| 控制中心 Widget (iOS 18+) | 控制中心快捷按钮 | 1 天 |
| Live Activity（灵动岛） | 录音状态常驻灵动岛 | 2 天 |
| iPad 适配 | 多列布局 + Split View 支持 | 2 天 |
| App Store 审核准备 | 隐私标签、审核附注、演示视频、截图 | 2 天 |
| App Store 提交 | 提交审核 + 应对审核反馈 | 1-3 天（含等待） |
| whisper.cpp 本地 ASR (仅主 App) | SPM 集成 + 模型管理 UI | 3 天 |

### P2 总产物
- App Store 上架版本
- 完整的增强功能
- 版本号：v0.3.0（App Store 首发）、v0.4.0+（持续迭代）

### P2 前置依赖
- P1 完成（Sprint 5 验收通过）
- App Store 审核材料准备完毕

### P2 预估总时长
15-20 天（可拆分优先级逐步迭代）

---

## 前置依赖关系图

    前置条件确认（Bundle ID、Apple Developer、API Key）
      │
      ▼
    Sprint 0（骨架+录音）
      │
      ▼
    Sprint 1（ASR 转写）— 依赖 Sprint 0 + API Key
      │
      ▼
    Sprint 2（LLM + 格式化 + 输出）— 依赖 Sprint 1
      │
      ▼
    Sprint 3（设置 + 引导 + MVP 打包）— 依赖 Sprint 2
      │                                    │
      │     ┌──── v0.1.0 MVP ────────────── │
      │     │    TestFlight 发布            │
      ▼     ▼                               │
    Sprint 4（键盘扩展基础）                  │
      │  — 依赖 Sprint 3 + App Group 配置   │
      ▼                                     │
    Sprint 5（键盘扩展打磨 + 增强）           │
      │  — 依赖 Sprint 4                    │
      │     ┌──── v0.2.0 ──────────────────│
      │     │    键盘扩展版 TestFlight       │
      ▼     ▼                               │
    Sprint 6+（P2 增强功能）                  │
      │  — 各功能可独立并行                   │
      │     ┌──── v0.3.0 ──────────────────│
      │     │    App Store 首发             │
      ▼     ▼

---

## 里程碑检查点

| 里程碑 | Sprint | 关键验收 | 版本 |
|--------|--------|---------|------|
| M0 | Sprint 0 | 真机可录音 + 波形显示 | — |
| M1 | Sprint 1 | 中英文 ASR 转写正确 | — |
| M2 | Sprint 2 | 完整 pipeline 闭环（录音→剪贴板） | — |
| **M3 (MVP)** | Sprint 3 | TestFlight 可安装使用，成功率 >= 95% | v0.1.0 |
| M4 | Sprint 4 | 键盘扩展可在微信中注入文字 | — |
| **M5 (键盘版)** | Sprint 5 | 键盘扩展内存 < 60MB，3 机型通过 | v0.2.0 |
| **M6 (App Store)** | Sprint 6+ | App Store 审核通过 | v0.3.0 |

---

## 发布策略

| 版本 | 内容 | 分发渠道 | 审核要求 | 备注 |
|------|------|---------|---------|------|
| v0.1.0 | MVP（主 App + 剪贴板） | TestFlight **内部测试** | ❌ 无需审核 | 最多 100 人，上传后几分钟可用 |
| v0.2.0 | + 键盘扩展 + 翻译 + 历史 | TestFlight **外部测试** | ⚠️ **需要 Beta App Review** | 最多 10,000 人，首次审核通常 24-48h |
| v0.3.0 | + Siri / 音频压缩 / 完善体验 | App Store 首发 | ✅ 需要正式审核 | 完整审核流程 |
| v0.4.0+ | + Live Activity / iPad / whisper.cpp | App Store 更新 | ✅ 需要审核 | 持续迭代 |

> ⚠️ **TestFlight 审核注意**：内部测试（Internal Testing）无需审核，但仅限开发团队成员（最多 100 人，需要 App Store Connect 角色）。外部测试（External Testing）可邀请最多 10,000 人，但**首次提交需通过 Beta App Review**。后续版本如果无重大功能变更可自动通过。建议在 Sprint 5 的时间估算中预留 2 天的外部测试审核缓冲。
