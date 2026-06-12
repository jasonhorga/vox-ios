# 代码 Review 结论（2026-06-06）

- **被 review 的提交**：`66f2810`（main，`fix(app): detect cold-start by first-URL-in-session flag … beta.60.5`）
- **范围**：逻辑 / IPC / 音频 / 网络 / 存储等正确性与安全相关面。纯展示型视图初版仅略读，二次核验时已补读关键路径。
- **二次核验**：因 Codex 后台限流不可用，改由 **Fable 独立对抗式复核**（2026-06-06）。结论：初版 14 条中 **确认 12、部分 1（M4）、驳回 1（L4）**，并**新增 5 条**真实问题（H3 / M5 / M6 / M7 / L7）。下方每条带「✅核验」批注。
- **总体**：工程质量良好。**建议优先处理 H1、H2、H3**。

## 速查表

| ID | 严重度 | 区域 | 一句话 | 主要位置 | 核验 |
|----|--------|------|--------|----------|------|
| H1 | 🔴 高 | 配置/Keychain | `reload()` 经 `didSet` 写回 Keychain，键盘高频调用，有丢 key 的窗口 | `Shared/SharedConfigStore.swift:266` | ✅ 确认 |
| H2 | 🔴 高 | 翻译 | LLM 模型名写死、忽略配置；翻译失败丢掉已识别文字（连音频一起）；键盘路径根本不翻译 | `Shared/PostProcessor.swift:106`、`AppState.swift:122` | ✅ 确认（更重） |
| H3 | 🔴 高 | IPC | 键盘对结果无防陈旧/防越界：旧转写可能在之后、在**别的 App 输入框**里被静默注入 | `VoxInputKeyboard/KeyboardState.swift:255` | 🆕 Fable 新增 |
| M1 | 🟠 中 | 测试 | `ConfigStoreTests` 用生产单例 + `resetAll()`，对真实设备有破坏性、非隔离 | `VoxInputTests/ConfigStoreTests.swift:16` | ✅ 确认 |
| M2 | 🟠 中 | 存储 | `HistoryItem.audioFilePath` 存绝对路径，重装/更新/恢复后失效（重试按钮静默失效） | `VoxInput/History/HistoryItem.swift:25` | ✅ 确认（略被低估） |
| M3 | 🟠 中 | 音频 | App 内录音器与守护进程争抢同一 AudioSession（并共用同一临时文件） | `AudioRecorder.swift:104`、`DaemonAudioEngineRecorder.swift:224` | ✅ 确认 |
| M4 | 🟠 中 | 网络 | 重试器对所有错误都重试；多层超时不一致（键盘 10s vs daemon 可达数十秒） | `Shared/ASRProvider.swift:73` | ⚠️ 部分（例子更正） |
| M5 | 🟠 中 | 键盘/权限 | `probeFullAccessAsync` 同进程写后读，无 Full Access 也可能误判为「有」 | `VoxInputKeyboard/KeyboardState.swift:472` | 🆕 Fable 新增 |
| M6 | 🟠 中 | 并发 | `@MainActor` 状态被实时音频线程在 tap 回调里直接改 → 数据竞争/潜在崩溃 | `DaemonAudioEngineRecorder.swift:64` | 🆕 Fable 新增 |
| M7 | 🟠 中 | 架构 | 录音上限 1 小时，但整段音频 base64 进内存 JSON：长录音必爆内存/超时/超限 | `QwenASR.swift:62`、`AudioRecorder.swift:72` | 🆕 Fable 新增 |
| L1 | 🟡 低 | 音频 | `AppleSpeechASR` 超时后识别任务/continuation 未取消，泄漏 | `Shared/AppleSpeechASR.swift:80` | ✅ 确认 |
| L2 | 🟡 低 | 日志 | 日志轮转会丢一行；每行 open/close 文件，开销偏大 | `Shared/SharedLogger.swift:128` | ✅ 确认 |
| L3 | 🟡 低 | 清理 | 死代码 `SilentAudioKeeper`（整文件无引用） | `VoxInput/Audio/SilentAudioKeeper.swift` | ✅ 确认 |
| L4 | ~~🟡 低~~ | ~~清理~~ | ~~遗留调试 `print`~~ → **驳回：在 `#Preview` 内，非线上代码** | `VoxInput/UI/PermissionView.swift:145` | ❌ 已驳回 |
| L5 | 🟡 低 | 清理 | `defaults.synchronize()` 已无必要 | `Shared/SharedConfigStore.swift:272` | ✅ 确认 |
| L6 | 🟡 低 | 隐私 | 日志用 `%{public}@` 且明文写入 App Group 文件（`DebugLogView` 展示之） | `Shared/SharedLogger.swift:100` | ✅ 确认 |
| L7 | 🟡 低 | 清理 | 死常量 `keyboardTimeout` / `keyboardMaxRetries`（远控架构前的遗留） | `Shared/Constants.swift:51` | 🆕 Fable 新增 |
| N1 | ℹ️ 说明 | UI | 键盘波形是程序化假动画，不反映真实电平（有意为之） | `VoxInputKeyboard/KeyboardView.swift:215` | ✅ 确认 |
| N2 | ℹ️ 说明 | 网络 | `NetworkMonitor` 首次回调前默认 `true`；`HistoryView` 用新建实例恒为 `true` | `Shared/NetworkMonitor.swift:18`、`HistoryView.swift:160` | ✅ 确认（略被低估） |

---

## 🔴 高优先级

### H1 — `SharedConfigStore.reload()` 会把 API Key 写回 Keychain

**位置**：`Shared/SharedConfigStore.swift:266-267`（`reload()`），配合 `:96/:101` 的 `didSet`；调用方 `VoxInputKeyboard/KeyboardState.swift:92`（`activate()`）与 `:132`（每次 `startRecording()`）。

**现象**：`reload()` 逐一重新赋值，`qwenAPIKey`/`whisperAPIKey` 的 `didSet` 执行 `KeychainStore.write(...)`（内部**先 `delete` 再 `add`**，`:78-92`/`:102-112`）。读成功也会原值重写（浪费）；**读失败（`nil`→`""`）会把真实 key 覆盖成空**（`SecItemCopyMatching` 任何非成功状态都返回 nil，`KeychainStore.swift:59-64`）。键盘每次激活/录音都触发。

**为什么重要**：键盘扩展易被系统 jetsam，若在 delete 与 add 之间被杀即丢 key（App/键盘共享的那份）；丢失静默且永久。

> **✅ 核验（Fable）**：链路全部坐实。`grep` 确认 `KeychainStore.write` 仅有这两个 `didSet`（+ 一次性迁移 `:220/:227`）调用；`init`（`:150-151`）里赋值不触发 `didSet`，但 `reload()` 是 init 后的方法调用、会触发。`@Observable` 不改变这点（Observation 宏保留 `didSet`，且 `SettingsView.saveSettings:190-195` 正是靠 `didSet` 落盘）。**严重度判断**：单次 clobber 概率低（需瞬时 Keychain 失败），但高频运行在易被杀的扩展里、丢失静默永久、主 App 内存副本仍正常工作导致用户无法关联原因 → High 成立。次要更正：每次 reload 实际是 **6 次** `SecItem`（2 删×2 group + 2 加），非 4 次。

**建议修复**：`reload()` 不触发 `didSet` 写回——用 `isLoading` 标志短路、读到 `nil` 时不赋值、或改显式 `save()`。

### H2 — 翻译模式：模型名写死 + 失败丢结果 + 键盘路径不翻译

**位置**：`Shared/PostProcessor.swift:106`、`VoxInput/App/AppState.swift:122-128`、`VoxInput/App/AudioDaemonService.swift:379-407`。

**现象（已验证）**：
1. `callLLM` 把 `"model": "gpt-4o-mini"` **写死**，无视 `qwenModel`/`whisperModel`。Qwen 用户 baseURL = `dashscope…/compatible-mode/v1/chat/completions`（`Constants.swift:66`）→ 把 `gpt-4o-mini` 发给 DashScope（很可能被拒，机制非结论）。
2. `processPipeline` 里翻译是 `try await PostProcessor.process(...)`，抛错即走 catch（`:153-159`）→ 已识别文字不格式化、不进剪贴板。
3. `AudioDaemonService.processAudio` 不调用 `PostProcessor` → **键盘输入永不翻译**。

> **✅ 核验（Fable）**：三条全部坐实，且**比初版更重**——in-app 路径翻译失败时 `defer { audioRecorder.cleanupTempFile() }`（`AppState.swift:109-111`）还会删掉音频，而 daemon 路径有 `saveAudioToDocuments` 兜底、in-app 没有 → **文字 + 音频双丢**。`PostProcessor.process` 全仓库唯一调用点就是 `AppState.swift:124`。

**建议修复**：模型名取自 config；翻译失败降级为返回原文（且保留音频兜底）；明确翻译是否覆盖键盘路径，要的话在 daemon 侧接上。

### H3 — 键盘对 IPC 结果缺少防陈旧/防越界保护（可能向错误 App 注入旧转写）🆕

**位置**：`VoxInputKeyboard/KeyboardState.swift:255-269`（`apply`）、`:67`（`lastResultID = 0`）、`:274-281`（`clearResultAsync`）；对照 daemon `AudioDaemonService.swift:233-241`（`bootstrapLastCommandID`）、`:266-273`（15s 指令时效）、`:361-363`（仅 cancel 时清 result）。

**现象**：`apply` 只要 `resultID > 0 && resultID != lastResultID && 非空` 就注入文本——**不判断是否有在途请求**；而 `lastResultID` 每个键盘进程都从 0 开始、**从不从 defaults 引导**（与指令侧的 `bootstrapLastCommandID` 形成鲜明对比）。daemon 对结果**既不打时间戳、也只在 cancel 时清除**。

**为什么重要**：在「处理中」时关掉键盘（或在 `insertText` 后、`clearResultAsync` 落盘前被杀），daemon 完成后写入的 result 不会被清；下次键盘激活（可能几小时后、在**另一个 App 的输入框**里）`lastResultID=0` 读到该陈旧 result → **静默注入旧转写**。这正是初版只盯了指令侧防护、漏掉的结果侧对称缺口。

> **✅ 核验（我已二次确认）**：`grep` 证实 `lastResultID` 仅在 `:259` 消费结果时赋值，无任何引导逻辑；daemon 结果无时间戳。

**建议修复**：`activate()` 时从 defaults 引导 `lastResultID`；daemon 给结果打时间戳、键盘忽略过期结果；注入前判断 `isRequestInFlight`；消费后稳健清除。

---

## 🟠 中优先级

### M1 — `ConfigStoreTests` 非隔离且对真实环境有破坏性
**位置**：`VoxInputTests/ConfigStoreTests.swift:16-28`；`resetAll()` 见 `SharedConfigStore.swift:281-296`。`setUp`/`tearDown` 对生产单例 `ConfigStore.shared` 调 `resetAll()`（删 Keychain + 覆盖 App Group defaults），并把测试 key 写进真实共享 Keychain（`:54`）。
> **✅ 核验（Fable）**：确认。补强证据：`project.yml:104` 的 `TEST_HOST` = `VoxInput.app`，测试在生产 App 的容器/entitlements 内运行。`HistoryManagerTests:20-26` 用注入 `UserDefaults(suiteName:)` 是正确对照。
**建议修复**：给 `SharedConfigStore` 增加可注入 `UserDefaults`/Keychain 抽象的 init，测试走独立 suite。

### M2 — `HistoryItem.audioFilePath` 存绝对路径，跨容器失效
**位置**：`HistoryItem.swift:25`；写入 `AudioDaemonService.saveAudioToDocuments:410-422`；消费 `HistoryManager.updateText:92-94` 与 `HistoryView.swift:149-151`。
> **✅ 核验（Fable）**：确认，且初版略低估——iOS 容器 UUID 在 **App 更新时也常变**（不只重装/恢复）。具体后果：`HistoryView` 的「转文字」重试按钮在路径失效时 `guard fileExists … else { return }` → **静默无反应**。
**建议修复**：只存文件名/相对路径，用时以当前 Documents 目录拼接。

### M3 — App 内录音器与守护进程争抢 AudioSession（并共用临时文件）
**位置**：`AudioRecorder.swift:104-105`（`.record` + `setActive(true)`，停止/取消时 `:186/:218` `setActive(false)`）、`DaemonAudioEngineRecorder.swift:222-226`（`.playAndRecord` + 活动 tap，前台经 `MainView.swift:345-349` 也会 prime）；共用 `vox_recording.wav`（`Constants.swift:42`）。
> **✅ 核验（Fable）**：确认。补强：in-app 停止时 `setActive(false)` 会在已 prime 的引擎底下停用共享会话；双方 start 都会删同一文件（`AudioRecorder.swift:98`、`DaemonAudioEngineRecorder.swift:88`、`AppState.swift:109-111`）。文件冲突需双方同时 capture，较少见——主要风险是会话争用，方向与严重度均正确。
**建议修复**：两路径用不同临时文件名；明确同一时刻只有一个组件拥有 AudioSession。

### M4 — 重试器对所有错误都重试 + 多层超时不一致
**位置**：`Shared/ASRProvider.swift:73-86`（`withRetry`）；`ASRFactory.swift:60`（15s）；`QwenASR.swift:49-50`（25s）；键盘 `Constants.swift:121`（10s）。
> **⚠️ 核验（Fable，部分更正）**：
> - 「无差别重试」确认：HTTP 401/400（`asrAPIError`）、`asrEmptyResult` 都会被无谓重试。
> - **更正**：`apiKeyMissing` 这个例子**错了**——它在 `ASRFactory.create()`（`:59`）抛出、位于 `withRetry` 闭包之外（`:62`），**不会被重试**。
> - 超时不一致确认，且更甚：daemon 的**直接** QwenASR 调用（`AudioDaemonService.swift:430-432`）**没有** 15s 包装；最坏 ≈ 25s + ~47s 兜底 vs 键盘 10s。
> - 软化点：键盘超时会发 `cancel`（`KeyboardState.swift:463`），daemon ~0.2s 内轮询到并取消 `processingTask`（`:354-359`）——所以 daemon 不会在键盘放弃后空转数十秒；真正损失是「凡需 >10s 的结果都被丢弃」。
**建议修复**：错误分「可重试/不可重试」；对齐各处超时（含 daemon 直连）。

### M5 — `probeFullAccessAsync` 无法报告「无 Full Access」🆕
**位置**：`VoxInputKeyboard/KeyboardState.swift:472-483`。写入一个 key 后在**同一进程内**的 `UserDefaults` 实例读回——内存缓存即使在 App Group 持久化被拒时也能 round-trip，于是 `hasFullAccess` 可能在没有 Full Access 时仍探测为 true。次序更糟：`viewWillAppear` 先设权威值（`UIInputViewController.hasFullAccess`），随后 `activate()` → `checkEnvironment()`（无参，`:92-93/:111-119`）可能用错误探测覆盖它，直到 `viewDidAppear` 才纠正。
**为什么重要**：无 Full Access 时 `startRecording()` 的 guard 被放过 → 指令写进非共享容器 → 表现为「录音无响应」，而非显示引导页。
**建议修复**：仅依赖 `UIInputViewController.hasFullAccess`，弃用写后读探测。（属运行时行为，建议真机确认。）

### M6 — `@MainActor` 状态被实时音频线程直接修改（数据竞争）🆕
**位置**：`DaemonAudioEngineRecorder.swift:64-67`（`installTap` 回调）→ 同步调用 `handleIncomingBuffer`/`failRuntime`（`:261-309`）。
**现象**：类是 `@MainActor`，但 tap 回调在实时音频线程执行，却直接改 `isCapturing`/`isRecording`/`runtimeError`/`audioFile`，并 off-main 地 `invalidate` 主 runloop 上的 `Timer`（`stopTimeoutTimer:235-238`），与主 actor 上的 `stop()`/`cancel()` 竞争（如 `audioFile` 在写入中途被清空）。仅因 Swift 5 模式不对 `AVAudioNodeTapBlock` 做 Sendable 检查才编译通过。
**为什么重要**：潜在数据竞争/崩溃，且难复现、难定位。
**建议修复**：tap 内只做最小工作，把状态变更/文件写入 hop 到专用串行队列；或让 recorder 不挂 `@MainActor`、用锁保护状态；不要在 tap 里碰主 actor 状态或 Timer。

### M7 — 录音时长与上传架构不匹配（长录音必失败）🆕
**位置**：`AudioRecorder.swift:72` / `DaemonAudioEngineRecorder.swift:42`（上限 3600s）；`QwenASR.swift:62-63`（整段读入 + `base64EncodedString` 进内存 JSON）；`WhisperAPIASR.swift:60-106`（整段 multipart 进内存）。
**现象**：1 小时 WAV ≈ 110MB → base64 ~147MB 字符串（再加序列化拷贝）→ 足以让后台 daemon 被 jetsam，且远超 API 体积上限；叠加 25s 会话超时，连 ~10 分钟的听写也基本必然失败 → 落为「未识别音频」。
**建议修复**：限制实际录音时长；改为从磁盘流式/multipart 上传，或分片。

---

## 🟡 低优先级 / 清理

- **L1 — ✅ 确认**：`AppleSpeechASR.swift:84` 丢弃 `SFSpeechRecognitionTask`（不保存/不取消）；超时时 `group.cancelAll()`（`:109`）无法解除卡在 `withCheckedThrowingContinuation`（`:83`，无取消处理）的兄弟任务，continuation 可能永不 resume、识别器继续跑。仅离线兜底路径，Low 合适。
- **L2 — ✅ 确认**：`SharedLogger.writeToFile` 存在性检查（`:124`）在轮转（`:130-134`）之前；`rotateLogFile()` move 走文件后（`:152`），`FileHandle(forWritingTo:)`（`:137`）失败（`try?`→nil），该行被静默丢弃；每行 open/seek/write/close 开销偏大。
- **L3 — ✅ 确认**：`VoxInput/Audio/SilentAudioKeeper.swift`（83 行）全仓库零引用，XcodeGen 仍会编进 App。可删。
- **L4 — ❌ 已驳回**：`PermissionView.swift:145` 的 `print("权限已授权")` 在 `#Preview` 块（`:143-147`）内，是预览占位回调，**线上不执行**，并非遗留调试代码。（这正是初版自认「PermissionView 仅 grep」的失误所在——已二次确认 `print` 位于 `#Preview {` 内。）
- **L5 — ✅ 确认**：`synchronize()`（`SharedConfigStore.swift:272/277`）Apple 已说明无必要，可删。
- **L6 — ✅ 确认**：`%{public}@`（`SharedLogger.swift:100`）+ 明文 App Group 文件（`:111-141`），由 `DebugLogView.swift:51` 展示；API 报错体经 `AudioDaemonService.swift:402`→`:621`（`publishError`→`SharedLogger.error`）流入，且 `asrAPIError` 内嵌原始 HTTP body（`QwenASR.swift:116-117`）。注意别把敏感串塞进日志。
- **L7 — 🆕 死常量**：`Constants.ASR.keyboardTimeout`（`Constants.swift:51`）与 `keyboardMaxRetries`（`:55`）零引用（已 `grep` 确认），是远控架构前键盘自己转写时代的遗留。鉴于 CLAUDE.md 把 `Constants.swift` 当作「现行调参入口」，死常量会误导——删除或接回。

---

## ℹ️ 说明（非 bug）

- **N1 — ✅ 确认**：`KeyboardView.swift:215-261`（`KeyboardWaveformView`）是 `TimelineView(.animation)` 上的纯 sin/cos，注释（`:212-214`）说明意图（beta.58 防假死）。属有意为之，但不反映真实电平。
- **N2 — ✅ 确认（且略被低估）**：除启动初期默认 `true`（`NetworkMonitor.swift:18`），`HistoryView.swift:160` 用**新建的** `NetworkMonitor().isConnected` 判断 → 该读取恒为 `true` → 离线时历史重试**总被路由到云端 ASR 并失败**。

---

## 覆盖范围与方法

- 初版集中在逻辑/IPC/音频/网络/存储，每条高/中结论对照源码核实；纯展示视图（`PermissionView`/`DebugLogView`/`HistoryView`/`WaveformView` 及 guide/haptics）初版仅略读——L4 误报即源于此。
- **二次核验**由 Fable 独立对抗式完成（2026-06-06），逐条以 `file:line` 取证，并补读了上述视图与键盘 IPC 结果侧。新增的 H3/M5/M6/M7/L7 中，H3、L7 我已二次 `grep` 确认；M5 属运行时行为、建议真机验证。
- **待办**：Codex 后台限流恢复（~06:00 UTC+8）后可再跑一次 `codex:rescue` 全仓库 review，作为第三方交叉验证。

**核验计分：确认 12，部分 1（M4），驳回 1（L4），新增 5（H3/M5/M6/M7/L7）。**
