# Vox iOS 下一步执行计划（AI Coding 实战版）

> 日期：2026-03-02  
> 基于 CONSENSUS_FINAL.md 与全套 planning 文档  
> 已确认：必须做键盘扩展，最低 iOS 17

---

## 0. 开工前准备清单

> 🔴 = 阻塞开工（Sprint 0 无法启动）  
> 🟡 = 阻塞 Sprint 1 或 Sprint 2  
> 🟢 = 可推迟但建议尽早

| # | 项目 | 优先级 | 说明 | 谁做 |
|---|------|--------|------|------|
| P1 | Apple Developer Program 付费会员 | 🔴 | 真机调试、App Group、TestFlight 都需要。免费账号无法使用 App Group | horga |
| P2 | 确定 Bundle ID | 🔴 | 如 `com.justin7974.vox`——确定后不可更改。键盘扩展 ID 会自动派生为 `xxx.vox.keyboard` | horga |
| P3 | 确定 App 名称 | 🔴 | 在 App Store Connect 检查 "Vox" 是否可用；备选：Vox Input / VoxVoice | horga |
| P4 | 确定 Git 仓库策略 | 🟡 | 推荐新建独立 repo `vox-ios`（与 macOS 项目分离） | horga |
| P5 | Qwen ASR API Key 可用 | 🟡 | Sprint 1 需要（阿里云 DashScope） | horga |
| P6 | 至少一个 LLM API Key | 🟡 | Sprint 2 需要（推荐 Qwen LLM 与 ASR 共用一个 Key） | horga |
| P7 | Privacy Policy URL | 🟡 | TestFlight 外部测试前必须有。可用 GitHub Pages 快速搭建 | AI 可代劳 |
| P8 | Support URL | 🟡 | 同上 | AI 可代劳 |
| P9 | Mac + Xcode 15.2+ 就绪 | 🔴 | macOS Sonoma 14+ | horga 确认 |
| P10 | iPhone（iOS 17+）可用 | 🔴 | 真机测试必须（模拟器不支持麦克风） | horga 确认 |
| P11 | Apple Developer Portal 注册 App ID + App Group + Keychain Sharing | 🟡 | Sprint 4 前完成即可，但建议 Sprint 0 就配好 | horga（AI 可出步骤指引） |

### 🔴 硬性先决：P1 + P2 + P3 + P9 + P10 缺任何一项 Sprint 0 无法启动。

---

## Sprint 0：打通主链路（录音 → ASR → 剪贴板）

### 目标
在真机上跑通"点按钮 → 录音 → Qwen ASR 转写 → 文本格式化 → 剪贴板"的完整闭环。**不做**设置页、不做 LLM 后处理、不做键盘扩展。

### 前置条件
- 🔴 P1/P2/P3/P9/P10 全部就绪
- 🟡 P5（Qwen API Key）——硬编码到代码中临时测试也行，但最好有

### 任务列表

| # | 任务 | 完成判据 | 可并行 |
|---|------|---------|--------|
| S0-1 | 创建 Xcode 项目（SwiftUI App, iOS 17+, 单 Target） | `xcodebuild` 编译通过 | — |
| S0-2 | Info.plist 配置 NSMicrophoneUsageDescription | 真机首次运行弹出权限弹窗 | 与 S0-1 同步 |
| S0-3 | AudioRecorder：AVAudioSession(.record) + AVAudioRecorder + 电平采样 | 真机录音，tmp/ 下生成 16kHz/16bit/Mono WAV | 依赖 S0-1 |
| S0-4 | WaveformView：SwiftUI Canvas + TimelineView | 波形随声音实时变化 | 依赖 S0-3 |
| S0-5 | VoxError 统一错误枚举 | 编译通过 | 与 S0-3 并行 |
| S0-6 | HapticFeedback（4 种触觉反馈） | 真机可感知震动 | 与 S0-3 并行 |
| S0-7 | AppState + MainView（开始/停止按钮 + 波形 + 状态） | 按钮切换状态，波形随录音显示 | 依赖 S0-3/4 |
| S0-8 | 麦克风权限请求流程（授权→可录音；拒绝→引导设置） | 两条路径均正确 | 依赖 S0-7 |
| S0-9 | ASRProvider 协议 + ASRFactory | 协议编译通过 | 与 S0-3 并行 |
| S0-10 | QwenASR 实现（async/await + base64 + DashScope Chat API） | 调用 Qwen API 返回正确文本 | 依赖 S0-9 |
| S0-11 | WhisperAPIASR 实现（multipart/form-data） | 调用 Whisper API 返回正确文本 | 依赖 S0-9，与 S0-10 并行 |
| S0-12 | TextFormatter 直接复用（零改动） | CJK 间距 + 标点规范化正确 | 独立 |
| S0-13 | ClipboardOutput（UIPasteboard + 5 分钟过期 + 触觉反馈） | 文本写入剪贴板可粘贴 | 依赖 S0-6 |
| S0-14 | AppState 集成完整 Pipeline：录音 → ASR → TextFormatter → 剪贴板 | 端到端闭环 | 依赖上述全部 |
| S0-15 | 静音检测 + 短录音丢弃 + 超时重试（25s, 2次） | 静音不调 API；超时自动重试 | 依赖 S0-14 |
| S0-16 | NetworkMonitor（NWPathMonitor） | 断网时有提示 | 与 S0-10 并行 |

### 完成判据（DoD）
- [ ] 真机上：启动 App → 点按钮 → 说中文/英文/中英混合 → 文字出现在剪贴板 → 粘贴到备忘录正确
- [ ] 断网时显示明确错误提示
- [ ] 静音 3 秒后停止，不调用 ASR
- [ ] 中文、英文、中英混合各测 3 次，成功率 ≥ 80%（首次可容忍 API 配置问题）

### 验收测试
```
Test 1: 中文纯语音 → 剪贴板 → 粘贴到备忘录 → 文本正确
Test 2: 英文纯语音 → 同上
Test 3: 中英混合 → 同上
Test 4: 静音录音 → 显示"未检测到有效语音"
Test 5: 断网 → 显示网络错误提示
Test 6: 录音 < 0.5s → 显示"录音过短"
```

### 风险
- Qwen ASR 海外调用延迟高：首次验证 API 连通性，延迟 > 10s 则优先切 Whisper API
- Xcode 签名配置：Automatically manage signing 通常够用，出问题手动配 Profile

### 可并行性
S0-5/6/9/12/16 可以与 S0-3 并行开发。一个 AI coding session 可以同时推进 AudioRecorder + ASR 协议 + TextFormatter。

---

## Sprint 1：键盘扩展 + App Group + Keychain Sharing

### 目标
实现跨 App 语音输入：在微信/备忘录/Safari 中切到 Vox 键盘 → 按住说话 → 松开 → 文字注入到输入框。

### 前置条件
- Sprint 0 完成（主链路闭环验证通过）
- 🔴 Apple Developer Portal 已注册 App Group + Keychain Sharing（P11）
- 🟡 P5/P6 API Key 可用

### 任务列表

| # | 任务 | 完成判据 | 可并行 |
|---|------|---------|--------|
| S1-1 | 创建 VoxKeyboard Extension Target | 编译通过，两个 Target 共存 | — |
| S1-2 | App Group 配置（Xcode Capabilities，两个 Target 都开启） | `containerURL(forSecurityApplicationGroupIdentifier:)` 返回有效路径 | 依赖 S1-1 |
| S1-3 | Keychain Sharing 配置（两个 Target 指向同一 accessGroup） | 主 App 写入 Key → 键盘扩展可读取 | 依赖 S1-1 |
| S1-4 | KeychainStore 实现（Security.framework） | Keychain CRUD 通过 + 跨 Target 可读 | 依赖 S1-3 |
| S1-5 | ConfigStore 适配（路径改 App Group Container） | 主 App 写入 config.json → 键盘扩展可读 | 依赖 S1-2 |
| S1-6 | AppGroupConfig 常量模块 | Group ID / Keychain AccessGroup 常量统一 | 与 S1-2 并行 |
| S1-7 | Shared 代码双 Target Membership | AudioRecorder/ASR/TextFormatter 等在两个 Target 中编译通过 | 依赖 S1-1 |
| S1-8 | KeyboardViewController（UIInputViewController 子类） | 键盘在任意 App 中可见 | 依赖 S1-7 |
| S1-9 | KeyboardView（SwiftUI 键盘 UI：麦克风按钮 + 波形 + 状态） | UI 正常显示 | 依赖 S1-8 |
| S1-10 | KeyboardState（@Observable 键盘状态机） | 状态切换正确：idle → recording → processing → idle | 依赖 S1-8 |
| S1-11 | 地球键实现：`needsInputModeSwitchKey` + `advanceToNextInputMode()` | 地球键可见且点击切换到下一输入法 | 依赖 S1-8 |
| S1-12 | Hold-to-talk 手势 + AVAudioSession(.playAndRecord, .mixWithOthers) | 按住录音，松开停止，不中断宿主 App 音频 | 依赖 S1-8 |
| S1-13 | hasFullAccess 检查 + 麦克风权限检查 + 引导 UI | 未授权时显示清晰引导 | 依赖 S1-8 |
| S1-14 | `textDocumentProxy.insertText()` 注入 | 文字出现在宿主 App 输入框 | 依赖 S1-12 |
| S1-15 | 键盘扩展完整 Pipeline：按住 → 录音 → ASR → TextFormatter → insertText | 端到端闭环 | 依赖上述全部 |
| S1-16 | secureTextEntry 场景验证 | 密码框不崩溃，自动切回系统键盘或显示提示 | 依赖 S1-15 |
| S1-17 | PostProcessor 移植（Anthropic + OpenAI 双格式 + enable_thinking:false） | LLM 后处理可用，失败降级到原文 | 与 S1-12 并行 |
| S1-18 | LLM 降级链路 | LLM 超时 → 自动使用 ASR 原文 + TextFormatter | 依赖 S1-17 |
| S1-19 | SceneSelector（手动场景选择） | 场景影响 LLM Prompt | 依赖 S1-17 |
| S1-20 | SettingsView（ASR/LLM provider 配置 + API Key 管理） | 全部 provider 可配，Key 存 Keychain | 依赖 S1-4/5 |
| S1-21 | SetupView 首次引导（权限 → Key → 键盘设置引导） | 新用户从安装到使用 < 3 分钟 | 依赖 S1-20 |

### 完成判据（DoD）
- [ ] 微信聊天框：切到 Vox 键盘 → 按住说话 → 松开 → 文字出现在输入框
- [ ] 备忘录：同上
- [ ] Safari 搜索框：同上
- [ ] 地球键点击 → 切换到下一输入法
- [ ] 密码框：不崩溃
- [ ] Open Access 关闭：显示引导，不崩溃
- [ ] 麦克风未授权：显示引导，不崩溃
- [ ] 键盘扩展连续使用 10 分钟不崩溃
- [ ] 键盘扩展内存峰值 < 60MB
- [ ] LLM 后处理可用；LLM 关闭/超时时降级到原文不阻断
- [ ] 设置页可配置所有 provider + API Key

### 验收测试
```
Test 1: 微信聊天 → Vox 键盘 → 按住说中文 → 松开 → 文字注入
Test 2: 备忘录 → 同上（英文）
Test 3: Safari 搜索框 → 同上（中英混合）
Test 4: 地球键 → 切换到系统拼音键盘 → 再切回 Vox
Test 5: 密码框 → 无崩溃
Test 6: 关闭 Full Access → 显示引导文字
Test 7: 边听音乐边用 Vox 键盘 → 音乐不中断
Test 8: 连续录音 10 次 → 无崩溃无内存泄漏
Test 9: LLM 开启 → 语音 → 文字经 LLM 优化后注入
Test 10: LLM 超时 → 自动降级到 ASR 原文注入
```

### 风险
- **键盘扩展内存超限（R04）**：Instruments Memory Graph 持续监控，峰值逼近 55MB 时简化 SwiftUI 视图
- **Keychain 跨 Target 读取失败**：确认两个 Target 的 accessGroup 完全一致，entitlement 文件无拼写错误
- **AVAudioSession 与宿主冲突（R08）**：`.mixWithOthers` + 录音结束 `.notifyOthersOnDeactivation`
- **DragGesture 重复触发**：加状态锁防止多次启动录音

### 可并行性
- S1-17/18/19（LLM 后处理）可与 S1-8~16（键盘扩展）并行开发
- S1-20/21（设置/引导）可在键盘基础完成后开始
- 两个 AI coding session 可以分别推进"键盘扩展核心"和"LLM + 设置页"

---

## Sprint 2：稳定性与发布准备

### 目标
打磨到可以 TestFlight 发布的质量。内部测试 v0.1.0（主 App）+ 外部测试 v0.2.0（含键盘扩展）。

### 前置条件
- Sprint 1 完成（键盘扩展 + LLM + 设置页 DoD 通过）
- 🟡 P7/P8 Privacy Policy URL + Support URL 就绪（外部测试必须）

### 任务列表

| # | 任务 | 完成判据 | 可并行 |
|---|------|---------|--------|
| S2-1 | 键盘高度/机型适配（iPhone SE / 标准 / Pro Max） | 3 种屏幕尺寸键盘显示正常 | — |
| S2-2 | textDocumentProxy 上下文 → LLM hint | 光标前文字影响 LLM 输出 | 独立 |
| S2-3 | 翻译模式（translatePrompt + UI toggle） | 中→英翻译正确 | 独立 |
| S2-4 | HistoryManager + HistoryView | 历史记录可查看、搜索、删除 | 独立 |
| S2-5 | AppleSpeechASR 离线降级 | 断网时自动切到 Apple Speech | 独立 |
| S2-6 | 键盘 Debug 日志（写入 App Group → 主 App 可查看） | 日志脱敏 + 7 天滚动 | 独立 |
| S2-7 | 端到端测试（20 次样本） | 成功率 ≥ 95% | 依赖上述 |
| S2-8 | Instruments 性能 profiling | 主 App 内存 < 50MB；键盘内存 < 60MB | 依赖 S2-7 |
| S2-9 | 键盘兼容性矩阵测试（见下方） | 全部通过 | 依赖 S2-7 |
| S2-10 | 审核合规自查（地球键、隐私弹窗、Open Access 文案） | 自查清单全绿 | 依赖 S2-9 |
| S2-11 | App Icon + LaunchScreen | 启动画面正常 | 独立 |
| S2-12 | TestFlight 内部测试打包（v0.1.0 主 App only） | TestFlight 可安装 | 依赖 S2-7 |
| S2-13 | TestFlight 外部测试打包（v0.2.0 含键盘扩展） | Beta App Review 通过 | 依赖 S2-10 |

**键盘兼容性矩阵（S2-9）**：

| 测试 App | 验收项 | 预期 |
|---------|--------|------|
| 微信（聊天） | 语音→文字注入 | ✅ |
| 备忘录 | 语音→文字注入 | ✅ |
| Safari（搜索框） | 语音→文字注入 | ✅ |
| 邮件（正文） | 语音→文字注入 | ✅ |
| 密码框 | 切到密码框 | ✅ 无崩溃 |
| 银行类 App | 打开 App | ⚠️ 不崩溃即可 |
| 地球键 | 点击切换 | ✅ |
| Full Access 关闭 | 使用 | ✅ 引导提示 |
| 麦克风未授权 | 录音 | ✅ 引导提示 |

### 完成判据（DoD）
- [ ] 20 次录音端到端成功率 ≥ 95%
- [ ] WiFi 下 30s 音频端到端延迟 ≤ 8s
- [ ] 键盘兼容性矩阵全部通过
- [ ] 审核合规自查清单全绿
- [ ] TestFlight 内部测试可安装使用
- [ ] 首次用户从安装到成功使用 < 3 分钟

### 验收测试
```
Test 1-20: 20 次端到端录音（中/英/混合各分布），≥19 次成功
Test 21: WiFi 30s 音频 → 端到端 ≤ 8s
Test 22: 4G 网络 → 端到端可用
Test 23: 断网 → Apple Speech 自动降级
Test 24: 全新设备安装 → 完成引导 → 成功使用 < 3 分钟
Test 25: 翻译模式 → 中文语音 → 英文输出
Test 26: 历史记录 → 可查看/搜索/删除
```

### 风险
- **Beta App Review 被拒（R01/R02）**：预留 2 天缓冲；准备好审核附注和演示视频
- **外部测试需要 Privacy Policy URL**：提前准备 GitHub Pages 托管

### 可并行性
S2-1~6 全部可并行。一个 AI coding session 可以同时推进多个独立模块。S2-7~13 为串行收尾。

---

## 与现有 Planning 文档的冲突与统一

| 冲突点 | 现有文档表述 | 本计划统一口径 |
|--------|------------|--------------|
| Opus 音频压缩时机 | 02 中"挑战 9"写"P1 引入 Opus"；04/06/08 写"P2 待验证" | **统一为 P2 技术 spike 验证，Sprint 0~2 使用 WAV + base64** |
| Sprint 编号映射 | 06 中 Sprint 0~3 = P0（主 App），Sprint 4~5 = P1（键盘扩展） | **本计划合并为 Sprint 0（主链路）→ Sprint 1（键盘+LLM+设置）→ Sprint 2（稳定+发布）。功能范围一致，只是节奏更紧凑** |
| Q04（iOS 最低版本） | 08 中标为"待决策" | **已确认 iOS 17，不再是 open question** |
| Q06（是否做键盘扩展） | 08 中标为"Sprint 0 前确认" | **已确认必须做，不再是 open question** |
| 音频路由兼容测试 | CONSENSUS_FINAL 建议在 Sprint 5 补测 | **纳入 Sprint 2 兼容性矩阵，增加 AirPods/蓝牙路由切换 smoke test** |

> 上述冲突均为表述/节奏差异，无架构级矛盾。建议在开工前花 30 分钟统一 00/02 中的 Opus 旧表述。

---

## 今天就能开始做的前 3 件事

> 无需等待任何外部条件，立刻可以做。

1. **统一文档口径**：修订 `02_IOS_CHALLENGES.md` 中挑战 9 的 Opus 表述，统一为"P2 验证"；同步更新 `00_OVERVIEW.md`。（AI 可直接执行，5 分钟）

2. **准备 Privacy Policy + Support 页面草稿**：基于 BYOK 模式写好隐私政策和支持页内容，后续 horga 确认后部署到 GitHub Pages。（AI 可直接执行，15 分钟）

3. **编写 Xcode 项目脚手架脚本/文档**：准备好 Sprint 0 的项目结构模板（目录结构、文件命名、Target 配置步骤），horga 确认 Bundle ID 后即可一键创建。（AI 可直接执行，20 分钟）

---

## 必须由 horga 决策的清单（最小集）

| # | 决策项 | 阻塞什么 | 推荐选项 |
|---|--------|---------|---------|
| D1 | Bundle ID 前缀 | Sprint 0 | `com.justin7974.vox` 或 horga 指定 |
| D2 | App 名称（检查 App Store 可用性） | Sprint 0 | "Vox" 优先，备选 "Vox Input" |
| D3 | Apple Developer 付费账号状态 | Sprint 0 | 确认已有 or 需要注册（1-3 天） |
| D4 | Git 仓库策略 | Sprint 0 | 推荐独立 `vox-ios` repo |
| D5 | 确认现有 API Key（Qwen ASR + LLM） | Sprint 1 | horga 确认已有 or 需开通 |
| D6 | 联系人邮箱（App Store Connect 用） | Sprint 2 | horga 提供 |

> 仅 6 项，其余设计决策已在 planning 文档中达成共识，按推荐选项执行即可。
> Q01（触发方式）、Q07（LLM 是否必须）、Q08（商业模式）等可推迟到 Sprint 2 后再决策。

---

## 附：Sprint 节奏概览

```
Sprint 0（主链路闭环）
  前置：D1/D2/D3 就绪
  并行度：高（多个模块独立）
  关键里程碑：真机端到端录音→剪贴板

Sprint 1（键盘扩展 + LLM + 设置）
  前置：Sprint 0 通过 + App Group/Keychain 配好
  并行度：中（键盘核心 vs LLM+设置 可并行）
  关键里程碑：微信中语音输入注入文字

Sprint 2（稳定 + 发布）
  前置：Sprint 1 通过 + Privacy Policy URL
  并行度：高（多个打磨任务独立）
  关键里程碑：TestFlight 内部测试 v0.1.0 / 外部测试 v0.2.0
```

每个 Sprint 无固定时间框：以 DoD 为准。AI coding 并行推进时，Sprint 0 可能几小时完成，Sprint 1 可能需要 1-2 个 AI session 迭代。
