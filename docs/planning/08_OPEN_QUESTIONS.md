# 08 — 待决策问题清单（Open Questions）

> 日期：2026-03-02
> 需要 horga 决策或补充信息的问题

---

## Q01: 触发方式决策

### 背景
macOS 版通过全局快捷键触发录音，iOS 没有全局快捷键机制。需要决定 iOS 版的主要触发方式和优先级。

### 需要决策的具体问题
1. P0 阶段主 App 的录音按钮是使用 toggle 模式（点一次开始，再点停止）还是 hold-to-talk 模式（按住说话，松开停止），还是两者都支持？
2. P2 阶段要投入多少精力在 Siri Shortcut / Action Button / 控制中心 Widget 等辅助触发方式上？

### 决策影响
- 影响模块：AppState（状态管理）、MainView（UI 交互）、KeyboardView（手势设计）
- 影响程度：中——主要影响 UI 交互设计

### 推荐选项
- 主 App P0：toggle 模式（简单可靠，与 macOS 默认模式一致）
- 键盘扩展 P1：hold-to-talk（按住说话更自然，类似微信语音消息）
- P2 辅助方式：按需添加，不阻塞核心功能

---

## Q02: ASR 服务选型

### 背景
macOS 版支持 Qwen ASR（推荐）、Whisper API、本地 whisper-cpp 三种 ASR。iOS 版需要决定默认/推荐的 ASR 服务。

### 需要决策的具体问题
1. iOS 版的默认推荐 ASR 是否仍然是 Qwen？
2. 是否需要在 P0 就支持多个 ASR provider，还是 P0 只支持 Qwen，其他放到 P1？
3. Apple Speech 离线降级在 P0 还是 P1 实现？
4. 海外用户（Qwen 延迟高）是否需要特别考虑？

### 决策影响
- 影响模块：ASRProvider、QwenASR、WhisperAPIASR、AppleSpeechASR、SettingsView
- 影响程度：高——决定核心 pipeline 的 ASR 环节

### 推荐选项
- P0 默认推荐 Qwen ASR（中英混合最佳），同时支持 Whisper API
- Apple Speech 离线降级放到 P1（Sprint 3 后补）
- 海外用户推荐 Whisper API（Groq 等更近的服务器）

---

## Q03: 分发渠道（App Store vs TestFlight 内测）

### 背景
App Store 上架涉及审核风险（键盘扩展 Open Access、麦克风权限），且审核可能被拒。TestFlight 分为内部测试和外部测试两种模式。

### TestFlight 审核机制说明

| 模式 | 人数上限 | 审核要求 | 说明 |
|------|---------|---------|------|
| **内部测试** | 100 人 | ❌ 无需审核 | 仅限 App Store Connect 团队成员，上传后几分钟可用 |
| **外部测试** | 10,000 人 | ⚠️ **需要 Beta App Review** | 首次提交通常需 24-48h 审核；后续更新如无重大功能变更可自动通过 |

> 📌 外部测试虽然不是完整的 App Store 审核，但 Apple 仍会检查基本的合规性和功能完整性。键盘扩展的 Open Access 和麦克风权限在 Beta Review 中也可能被关注。

### 需要决策的具体问题
1. 目标是最终上 App Store，还是长期通过 TestFlight 分发？
2. 如果目标是 App Store，什么时间点开始准备审核材料？
3. 如果 App Store 审核被拒，是否有退路（如仅分发不含键盘扩展的精简版）？
4. v0.2.0（键盘扩展版）是否需要外部测试？如果是，需要预留审核缓冲时间

### 决策影响
- 影响模块：所有（App Store 对代码质量、隐私合规有额外要求）
- 影响程度：高——影响项目整体规划和发布策略

### 推荐选项
- 短期：P0 使用 TestFlight **内部测试**（无审核，快速迭代）
- P1：如果需要扩大测试范围，使用 TestFlight **外部测试**（需预留 Beta Review 时间）
- 长期：P2 准备 App Store 上架（准备完整审核材料后提交）
- 如果审核被拒：根据反馈修改重新提交；极端情况下考虑不含键盘扩展的精简版

---

## Q04: 目标 iOS 最低版本

### 背景
当前设计基于 iOS 17.0（@Observable 宏、onChange 改进、TipKit、键盘扩展内存放宽）。是否有需要支持 iOS 16 的用户群体？

### 需要决策的具体问题
1. 是否接受 iOS 17.0 作为最低版本？
2. 如果有 iOS 16 用户需要支持，是否愿意承担额外的代码复杂度（@Published + ObservableObject 替代 @Observable）？

### 决策影响
- 影响模块：所有使用 @Observable 的模块（AppState、KeyboardState、NetworkMonitor）
- 影响程度：中——如果改为 iOS 16，需要大量状态管理代码重写

### 推荐选项
- 选择 iOS 17.0（截至 2026 年覆盖率 > 90%，开发效率高）
- 不建议支持 iOS 16（代码复杂度大幅增加，收益低）

---

## Q05: 是否支持 iPad

### 背景
iOS App 默认可在 iPad 上以 iPhone 兼容模式运行（带黑边）。是否需要针对 iPad 做原生适配（多列布局、Split View 支持）？

### 需要决策的具体问题
1. iPad 是否在目标设备中？
2. 如果支持，放在 P1 还是 P2？
3. iPad 的键盘扩展体验是否需要特别优化（iPad 键盘更宽）？

### 决策影响
- 影响模块：所有 UI 模块（MainView、SettingsView、KeyboardView 需要适配更宽屏幕）
- 影响程度：中——iPad 适配主要是 UI 布局调整

### 推荐选项
- P0/P1：iPhone 优先，iPad 以兼容模式运行（不做专门适配）
- P2：如果有需求，做 iPad 原生适配

---

## Q06: 键盘扩展 vs 其他触发方式的优先级

### 背景
键盘扩展是唯一能跨 App 注入文字的方案，但开发复杂度高、用户设置成本高。另一种思路是不做键盘扩展，主要依靠主 App + 剪贴板 + Siri Shortcut。

### 需要决策的具体问题
1. 键盘扩展是否是必须做的功能？
2. 如果不做键盘扩展，"主 App 录音 → 剪贴板 → 用户手动粘贴"这个流程是否可以接受？
3. 是否愿意承担键盘扩展带来的额外复杂度（App Group、Open Access 审核、内存限制等）？

### 决策影响
- 影响模块：决定是否开发整个键盘扩展模块（~5 人天的工作量）
- 影响程度：高——是项目的核心方向决策

### 推荐选项
- 建议做键盘扩展（这是 iOS 版的核心差异化价值）
- 但 P0 先用主 App + 剪贴板验证核心 pipeline
- 键盘扩展放 P1，在 P0 稳定后再投入

---

## Q07: LLM 后处理是否必须

### 背景
macOS 版的 LLM 后处理是可选功能（用户可以关闭）。iOS 版是否需要保持这个定位？

### 需要决策的具体问题
1. LLM 后处理在 iOS 上是"推荐开启"还是"可选功能"？
2. 首次引导时是否默认开启 LLM 后处理？
3. 如果用户没有 LLM API Key，是否仍然可以使用基本的 ASR + TextFormatter？

### 决策影响
- 影响模块：AppState（pipeline 流程）、SetupView（引导步骤）、SettingsView（配置项）
- 影响程度：低——架构上 LLM 已是可选的，主要影响 UX 决策

### 推荐选项
- LLM 后处理保持"可选"定位（与 macOS 一致）
- 首次引导中提供选项但不强制
- 没有 LLM Key 也能正常使用（ASR + TextFormatter 已能满足基本需求）
- 推荐 Qwen LLM 作为默认（与 ASR 共用一个阿里云 Key，降低配置摩擦）

---

## Q08: 商业模式

### 背景
macOS 版是开源免费的 BYOK 模式。iOS 版需要决定是否有变现计划。

### 需要决策的具体问题
1. iOS 版是否免费？
2. 是否考虑收费模式（一次性购买 / 订阅 / 内购）？
3. 如果免费，是否开源？
4. 如果收费，定价策略是什么？

### 决策影响
- 影响模块：App Store 配置、可能的 StoreKit 集成
- 影响程度：低（短期不影响技术实现）

### 推荐选项
- P0/P1：免费，保持 BYOK 模式（与 macOS 一致）
- P2 再评估：如果有足够用户量，可考虑 Pro 版本（更多 ASR provider / 高级功能）
- 不建议订阅模式（Vox 没有后端服务，用户自带 Key，订阅缺乏正当性）

---

## Q09: Bundle ID 和 App 名称

### 背景
需要确定最终的 Bundle ID 和 App Store 展示名称。这是开工的前置条件之一。

### 需要决策的具体问题
1. Bundle ID 前缀是什么？（如 `com.justin7974.vox`、`com.jasonhorga.vox`）
2. App 名称是 "Vox" 还是需要另一个名称？（"Vox" 在 App Store 可能已被占用）
3. 是否需要准备备用名称？

### 决策影响
- 影响模块：所有（Bundle ID 贯穿整个项目配置）
- 影响程度：高——开工前必须确定，确定后不可更改

### 推荐选项
- 先在 App Store Connect 检查 "Vox" 名称可用性
- 准备备用名称如 "Vox Input"、"VoxVoice"、"Vox Talk"
- Bundle ID 使用与 macOS 版一致的前缀

---

## Q10: Git 仓库策略

### 背景
macOS 版源码在 github.com/justin7974/vox。iOS 版的源码应该放在哪里？

### 需要决策的具体问题
1. iOS 版是放在现有 vox repo 的 `ios/` 子目录，还是创建新 repo（如 `vox-ios`）？
2. 共享代码（如 TextFormatter）是否做成 Swift Package 跨 repo 引用？

### 决策影响
- 影响模块：项目结构、CI/CD
- 影响程度：低——不影响功能

### 推荐选项
- 创建独立 repo `vox-ios`（更干净，避免 macOS 项目和 iOS 项目的 Xcode 配置冲突）
- 暂不做 Swift Package（复用的代码量不大，直接复制即可）

---

## Q11: 默认 LLM Provider 选择

### 背景
macOS 版推荐 Kimi（Moonshot）作为默认 LLM provider，但实际验证发现 Kimi API URL 可能有误（当前用的是 `api.kimi.com/coding/v1/messages`，而非标准的 `api.moonshot.cn/v1/chat/completions`）。

### 需要决策的具体问题
1. iOS 版的默认/推荐 LLM provider 是 Kimi 还是 Qwen LLM？
2. Kimi 的 API URL 需要确认（标准 URL vs 当前使用的 URL）
3. 是否保留全部 7+ 个 LLM provider 选项，还是精简为 3-4 个？

### 决策影响
- 影响模块：PostProcessor、SettingsView
- 影响程度：中——影响默认体验和配置复杂度

### 推荐选项
- 默认推荐 Qwen LLM（与 ASR 共用阿里云 Key，一个 Key 搞定全部）
- 保留 Kimi / DeepSeek 作为备选
- 精简 provider 列表到 4-5 个（Qwen / Kimi / DeepSeek / OpenRouter / 自定义）

---

## Q12: 音效 vs 触觉反馈

### 背景
macOS 版使用 4 种音效（Tink/Pop/Glass/Basso）。iOS 版计划用触觉反馈替代，但是否还需要可选的音效？

### 需要决策的具体问题
1. iOS 版是否只用触觉反馈，完全不要音效？
2. 是否提供"音效 + 触觉"的选项让用户自定义？
3. 键盘扩展中是否需要反馈（触觉/音效）？

### 决策影响
- 影响模块：HapticFeedback、可能的 AudioFeedback 新模块
- 影响程度：低——不影响核心功能

### 推荐选项
- P0：仅触觉反馈（简单可靠，不干扰他人）
- P2 可选：添加音效选项（用户在设置中开启）
- 键盘扩展：仅触觉反馈（音效可能干扰宿主 App）

---

## Q13: 纯 BYOK vs 轻代理（服务端代理层）架构

### 背景
当前 Vox 设计为纯 BYOK（Bring Your Own Key）——用户的 API Key 存储在客户端 Keychain，由客户端直接调用 ASR/LLM API。这在 macOS 上运作良好，但在 iOS 键盘扩展场景下有额外的考量。

### 问题分析
**纯 BYOK 的优势**：
- 零后端成本，无服务器运维
- 用户数据不经过 Vox 服务器，隐私最大化
- 无需用户注册/登录

**纯 BYOK 在键盘扩展场景的潜在问题**：
- API Key 存在客户端 Keychain，如果设备被攻破无法远程吊销
- 无法做服务端审计（滥用检测、异常调用监控）
- 无法做 provider 动态路由（如某 provider 宕机时自动切换）
- 用户需要自行管理多个 provider 的 Key，配置门槛高
- 隐私合规上"Vox 不是数据处理者"的定位更清晰（这反而是优势）

**轻代理架构（如果做）**：
- Vox 后端做 token exchange：用户注册 → Vox 发放 token → 客户端用 token 调用 Vox 后端 → Vox 后端转发到 ASR/LLM API
- 用户不需要自己注册 API 账号，但需要注册 Vox 账号
- 引入后端运维成本和合规责任（数据处理者义务）

### 需要决策的具体问题
1. 短期（P0-P1）是否维持纯 BYOK？（**推荐是**）
2. 长期是否考虑引入轻代理层？如果是，什么条件下触发这个决策？
3. 是否愿意承担后端运维成本和合规责任？

### 决策影响
- 影响模块：全局架构、合规策略、商业模式
- 影响程度：高——这是架构级决策

### 推荐选项
- P0-P1：维持纯 BYOK（零后端成本，聚焦核心功能）
- 如果以下条件出现再考虑轻代理：1) 用户普遍反馈配置 Key 太难 2) 需要变现（后端可控收费） 3) 需要审计和风控
- 记录"不做后端"的长期代价，确保团队有共识

---

## Q14: Live Activity（灵动岛）的边界与协同

### 背景
P2 计划包含 Live Activity（灵动岛录音状态显示）。但 Live Activity 由主 App 通过 ActivityKit 管理，键盘扩展进程无法直接更新 Live Activity 状态。

### 技术约束
- `ActivityKit` 的 `Activity.update()` 只能从主 App 进程或通过 APNs push 更新
- 键盘扩展作为独立进程，无法调用 `Activity.update()`
- 如果要在键盘扩展录音时更新灵动岛状态，需要跨进程通信（如通过 App Group 文件/UserDefaults + 主 App 后台轮询，但主 App 在后台不活跃）

### 需要决策的具体问题
1. Live Activity 是否仅用于主 App 会话（主 App 录音时显示灵动岛）？
2. 键盘扩展录音时是否需要灵动岛状态？如果需要，如何解决跨进程更新问题？
3. 是否降低 Live Activity 的优先级，聚焦更有价值的功能？

### 决策影响
- 影响模块：Live Activity 实现方案
- 影响程度：中——影响 P2 排期

### 推荐选项
- Live Activity 仅用于**主 App 会话**（主 App 录音时灵动岛显示状态）
- 键盘扩展不做灵动岛联动（键盘扩展自身 UI 已提供录音状态）
- 如果后续确认有强需求，可通过本地通知（而非 Live Activity）从键盘扩展触发主 App 更新

---

## Q15: 音频压缩方案验证（Opus 编码可行性）

### 背景
P2 计划中的音频压缩原定为"AVAudioConverter PCM → Opus"，但 AVAudioConverter **原生不支持 Opus 编码**（仅支持解码）。实际需要通过 libopus C 库的 SPM 集成来实现。

### 需要验证的问题
1. libopus SPM 包是否成熟可用？（如 [opus-swift](https://github.com/nicklama/opus-swift) 或自建 SPM wrapper）
2. Opus 编码在键盘扩展的内存限制下是否可行？（libopus 本身内存占用不大，但需验证）
3. Qwen ASR DashScope API 是否支持接收 Opus 格式音频？（base64 编码的 Opus/OGG）
4. 如果 Opus 不可行，AAC-LC/m4a 是否是可接受的替代？（需确认 ASR 端支持）

### 决策影响
- 影响模块：AudioRecorder、ASR 请求构建
- 影响程度：中——影响 P2 排期和网络优化效果

### 推荐选项
- P0/P1 阶段维持 WAV + base64（已验证可工作）
- P2 开始前做一个**技术 spike**（1 天）验证 Opus 编码全链路：libopus 集成 → 编码 → base64 → ASR API 是否接受
- Fallback 方案：如果 Opus 不可行，使用 PCM + 限制录音时长（如 30s 上限 ≈ 960KB WAV）

---

## 决策优先级总结

| 优先级 | 问题编号 | 问题 | 阻塞程度 |
|--------|---------|------|---------|
| 🔴 开工前必须 | Q09 | Bundle ID 和 App 名称 | 阻塞 Sprint 0 |
| 🔴 开工前必须 | Q04 | 目标 iOS 最低版本 | 阻塞架构决策 |
| 🟡 Sprint 0 前确认 | Q06 | 是否做键盘扩展 | 影响项目范围 |
| 🟡 Sprint 0 前确认 | Q02 | ASR 服务选型 | 影响 Sprint 1 |
| 🟡 Sprint 0 前确认 | Q10 | Git 仓库策略 | 影响项目初始化 |
| 🟡 Sprint 0 前确认 | Q13 | 纯 BYOK vs 轻代理架构 | 影响全局架构方向 |
| 🟢 可推迟 | Q01 | 触发方式细节 | Sprint 4 前决策 |
| 🟢 可推迟 | Q03 | 分发渠道 | P2 前决策 |
| 🟢 可推迟 | Q05 | iPad 支持 | P2 前决策 |
| 🟢 可推迟 | Q07 | LLM 是否必须 | 影响小 |
| 🟢 可推迟 | Q08 | 商业模式 | P2 前决策 |
| 🟢 可推迟 | Q11 | 默认 LLM provider | Sprint 2 前决策 |
| 🟢 可推迟 | Q12 | 音效 vs 触觉 | 影响小 |
| 🟢 可推迟 | Q14 | Live Activity 边界 | P2 前决策 |
| 🟢 可推迟 | Q15 | Opus 编码可行性 | P2 前验证 |
