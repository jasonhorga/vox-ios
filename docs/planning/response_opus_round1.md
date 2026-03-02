# Opus 对 GPT Round 1 Review 的逐条回应

> 日期：2026-03-02
> 回应方：Opus（初稿作者）
> 针对：review_gpt_round1.md（18 条意见）

---

## 汇总

| 处理结果 | 数量 | 编号 |
|---------|------|------|
| ✅ 接受 | 10 | R001, R002, R003, R005, R007, R009, R011, R012, R014, R018 |
| 🔶 部分接受 | 6 | R004, R006, R008, R010, R015, R016 |
| ❌ 拒绝 | 2 | R013, R017 |

修改的文件：02_IOS_CHALLENGES.md, 03_REQUIREMENTS.md, 04_ARCHITECTURE.md, 05_MIGRATION_MAP.md, 06_SPRINT_PLAN.md, 07_RISKS.md, 08_OPEN_QUESTIONS.md

---

## 逐条回应

### R001 — Keychain 共享与 App Group 混为一谈
- **判定：✅ 接受**
- **理由**：GPT 指出的问题是准确的。Keychain Sharing 和 App Group 确实是两套独立机制，依赖不同的 entitlement。原文档中 `kSecAttrAccessGroup = App Group 级共享` 的表述确实可能造成实施时的混淆——Keychain 共享需要 `keychain-access-groups` entitlement，access group 标识符格式为 `$(TeamID).com.xxx.vox.shared`，与 App Group 的 `group.com.xxx.vox` 是不同的概念。如果开发者只配了 App Group 而忘了 Keychain Sharing entitlement，键盘扩展确实会读不到 API Key。
- **修改方案**：
  1. 在 `04_ARCHITECTURE.md` 的 5.1/5.2 节明确区分两套共享机制，分别说明 entitlement 配置
  2. 在 `02_IOS_CHALLENGES.md` 挑战 2 的解决方案表中修正表述
  3. 在 `03_REQUIREMENTS.md` 的证书和 Profile 节中增加 Keychain Sharing entitlement 配置步骤

---

### R002 — 自定义键盘在密码框/安全输入被禁用
- **判定：✅ 接受**
- **理由**：这是一个重要的遗漏。`secureTextEntry = true` 的输入框（密码框、验证码框等）确实会强制切回系统键盘，且宿主 App 可以通过 `UIApplicationDelegate.application(_:shouldAllowExtensionPointIdentifier:)` 返回 false 来拒绝所有第三方键盘（银行类 App 常用此策略）。不在文档中说明会导致用户误以为功能失效。
- **修改方案**：
  1. 在 `02_IOS_CHALLENGES.md` 挑战 5 中新增"不可用场景矩阵"
  2. 在 `03_REQUIREMENTS.md` 中增加相关 UX 降级提示需求

---

### R003 — 缺少地球键（输入法切换键）合规要求
- **判定：✅ 接受**
- **理由**：Apple 的 Human Interface Guidelines 和 App Review Guidelines 要求自定义键盘必须提供切换到下一输入法的能力。系统通过 `needsInputModeSwitchKey` 属性告知键盘是否需要显示地球键，`UIInputViewController` 提供 `advanceToNextInputMode()` 方法。不实现这个功能确实会导致审核被拒，且用户无法切回系统键盘。
- **修改方案**：
  1. 在 `03_REQUIREMENTS.md` 增加地球键/输入法切换合规要求
  2. 在 `04_ARCHITECTURE.md` 键盘 UI 部分补充 needsInputModeSwitchKey 处理
  3. 在 `06_SPRINT_PLAN.md` Sprint 4 中增加地球键实现任务

---

### R004 — UIKit vs SwiftUI 在键盘扩展内的性能权衡
- **判定：🔶 部分接受**
- **接受部分**：同意需要为键盘扩展设定明确的性能预算（首帧延迟、峰值内存）。这对于键盘扩展这种对启动速度极其敏感的场景确实重要。
- **拒绝部分**：不接受"关键路径回退 UIKit"作为 fallback 方案。原因：
  1. 键盘扩展的 SwiftUI 界面本身很简单（一个录音按钮 + 波形 + 场景选择 + 状态文字），不是什么"复杂 SwiftUI 层级"
  2. 同时维护 UIKit 和 SwiftUI 两套键盘 UI 会显著增加代码复杂度和维护成本
  3. iOS 17+ 的 SwiftUI 渲染性能已经成熟，UIHostingController 的开销在简单视图下可以忽略
  4. 如果性能真有问题，正确的做法是简化 SwiftUI 视图层级，而不是切换框架
- **修改方案**：在 `04_ARCHITECTURE.md` 中增加键盘扩展性能预算指标，但不添加 UIKit fallback 方案

---

### R005 — 深链接到键盘设置页的可行性
- **判定：✅ 接受**
- **理由**：GPT 说得对。`UIApplication.openSettingsURLString` 只能跳转到本 App 的设置页面，无法精确跳转到 Settings → General → Keyboard → Keyboards。这确实需要修正用户引导路径。
- **修改方案**：在 `07_RISKS.md` R09 缓解方案中修正为"跳转 App 设置页 + 图文步骤引导"

---

### R006 — TestFlight 外部测试仍需 Beta App Review
- **判定：🔶 部分接受**
- **接受部分**：确实需要区分"内部测试"和"外部测试"。外部测试（External Testing）确实需要 Beta App Review，通常需要 24-48 小时。这一点在文档中表述不够精确。
- **拒绝部分**：但 GPT 说"多处表达'TestFlight 可回避审核压力'"有些夸大。文档中 `06_SPRINT_PLAN.md` 的发布策略已经区分了 v0.1.0 内部测试（无需审核）和 v0.2.0 扩大内测（可选 Beta Review）。问题更多出在 `08_OPEN_QUESTIONS.md` Q03 的表述上。
- **修改方案**：
  1. 在 `06_SPRINT_PLAN.md` 发布策略中明确区分内部/外部测试的审核差异
  2. 在 `08_OPEN_QUESTIONS.md` Q03 中修正表述
  3. 在 Sprint 5 的时间预估中预留首次外部测试审核的缓冲

---

### R007 — 缺少隐私政策 URL / 支持 URL 等审核硬性要求
- **判定：✅ 接受**
- **理由**：这些确实是 App Store Connect 的硬性元数据要求——没有 Privacy Policy URL 和 Support URL 连 TestFlight 外部测试都提交不了。这属于文档遗漏。
- **修改方案**：在 `03_REQUIREMENTS.md` 的前置依赖检查清单中新增法律与元数据准备项

---

### R008 — GDPR / PIPL / 跨境传输合规
- **判定：🔶 部分接受**
- **接受部分**：同意需要增加合规准备清单。Vox 上传音频到阿里云 DashScope（中国大陆服务器），如果海外用户使用确实涉及跨境传输问题。数据流图和用户同意文案确实应该提前准备。
- **拒绝部分**：不接受把合规准备做到 GPT 建议的深度（"保留与删除策略、第三方 DPA/条款映射"）。原因：
  1. Vox 是 BYOK 模式——音频发到用户自己的 API 账号，Vox 本身不做数据中转和存储
  2. BYOK 模式下，Vox 更像是一个"工具"而非"数据处理者"，合规责任主要在 API 服务商和用户自身
  3. 一个初创独立开发者项目要求 DPA 条款映射不切实际
  4. 但用户告知义务和隐私政策确实需要
- **修改方案**：
  1. 在 `03_REQUIREMENTS.md` 增加精简版合规准备清单（隐私政策、数据流说明、用户告知文案）
  2. 在 `07_RISKS.md` 增加合规风险条目，注明 BYOK 模式的合规边界

---

### R009 — App Group 容器内日志/历史泄露面
- **判定：✅ 接受**
- **理由**：GPT 指出的问题有价值。debug.log 确实可能包含 ASR 识别文本、LLM 响应片段等敏感信息。在键盘扩展场景下（用户输入可能包含密码、私密对话），日志泄露风险更高。且 App Group 共享容器理论上可被同一 App Group 内的任何进程访问。
- **修改方案**：
  1. 在 `04_ARCHITECTURE.md` 5.3 文件目录结构中增加日志安全策略
  2. 在 `07_RISKS.md` 新增日志泄露风险条目

---

### R010 — AVAudioConverter 直接转 Opus 可行性
- **判定：🔶 部分接受**
- **接受部分**：同意 iOS 上 Opus 编码的可行性需要标记为"待验证"。`AVAudioConverter` 原生不支持 Opus 编码输出（支持解码但不支持编码）。实际要做 Opus 编码需要集成 libopus（C 库通过 SPM 集成），这确实增加了工作量和复杂度。
- **拒绝部分**：不同意 AAC-LC/m4a 作为"稳态 fallback"。原因是 Qwen ASR 的 DashScope Chat API 接收 base64 音频，其支持的格式列表需要确认。如果 ASR 端不支持 AAC，转 AAC 就没有意义。正确的 fallback 应该是"保持 PCM/WAV + 限制录音时长"。
- **修改方案**：
  1. 在 `08_OPEN_QUESTIONS.md` 新增 Opus 编码可行性验证的决策项
  2. 在 `06_SPRINT_PLAN.md` P2 音频压缩任务标注为"待验证"
  3. 在 `04_ARCHITECTURE.md` 技术栈表修正音频压缩描述

---

### R011 — 扩展进程生命周期短、长请求易被挂起/回收
- **判定：✅ 接受**
- **理由**：键盘扩展作为 extension 进程确实有独立的生命周期约束——系统可能在任何时候因资源压力回收 extension 进程。这与"后台模式"不同，是 extension 自身的问题。长时间的网络请求（ASR 25s 超时 + LLM 12s 超时 = 最多 37s）确实面临被中途 kill 的风险。
- **修改方案**：
  1. 在 `02_IOS_CHALLENGES.md` 挑战 5 中新增扩展进程生命周期约束的详细说明
  2. 在 `04_ARCHITECTURE.md` 键盘扩展数据流中增加"短事务策略"

---

### R012 — 是否引入服务端代理层
- **判定：✅ 接受**
- **理由**：这是一个有价值的架构级决策问题。虽然当前 Vox 的定位是 BYOK + 无后端，但在键盘扩展场景下确实有额外的考量：API Key 存在客户端（Keychain）有安全边界问题，用户 Key 泄露后无法远程吊销。至少需要在 Open Questions 中明确讨论"不做后端"的长期代价和适用边界。
- **修改方案**：在 `08_OPEN_QUESTIONS.md` 新增"纯 BYOK vs 轻代理架构"的决策项

---

### R013 — Share Extension / Action Extension / Keyboard Extension 权衡
- **判定：❌ 拒绝**
- **理由**：
  1. **问题方向偏离**：Vox 的核心场景是"在任意输入框中直接注入语音转文字"，这唯一的实现路径就是 Keyboard Extension。Share Extension 和 Action Extension 的功能定位完全不同——Share Extension 用于"分享内容到其他 App"，Action Extension 用于"对当前内容执行操作"，两者都不能向宿主 App 的输入框注入文字。
  2. **不存在"三选一"的权衡**：这三种 extension 解决不同问题。Keyboard Extension 是 Vox 场景的唯一合法选择，不需要与其他两种做"系统化权衡"。
  3. **已有明确覆盖**：`08_OPEN_QUESTIONS.md` Q06 已经讨论了"是否做键盘扩展"的决策，`02_IOS_CHALLENGES.md` 挑战 1/4 已经分析了各种触发方式的优劣。再加一个三种 extension 的比较表不会增加决策信息量。
  4. 如果 GPT 的意图是讨论"是否可以用 Share Extension 作为补充入口（如在 Safari 中分享选中文本给 Vox 翻译）"，这是一个有效的 P2 功能点，但不应该与 Keyboard Extension 放在同一个"权衡决策"中。

---

### R014 — Live Activity 与键盘扩展协同的可行性
- **判定：✅ 接受**
- **理由**：Live Activity 确实存在跨进程状态同步的复杂度——Live Activity 由主 App 通过 ActivityKit 管理，键盘扩展进程无法直接更新 Live Activity 状态。如果不提前澄清边界，P2 实现时会发现"键盘扩展录音时灵动岛无法实时更新"的问题。
- **修改方案**：在 `08_OPEN_QUESTIONS.md` 新增 Live Activity 边界与协同的决策项

---

### R015 — Apple Developer 账号类型决策不充分
- **判定：🔶 部分接受**
- **接受部分**：同意应该明确说明企业账号不适用于 App Store 分发，以及组织账号在品牌展示和协作上的差异。
- **拒绝部分**：不接受做详细的"账号类型决策表"。原因：
  1. 对于独立开发者项目，个人账号几乎总是正确选择。Vox 不是一个需要多人协作签名的企业项目。
  2. 组织账号需要 D-U-N-S 编号和法律实体，对个人项目来说门槛过高且不必要。
  3. 文档已经写了"个人账号足够"，这个判断是正确的。
- **修改方案**：在 `03_REQUIREMENTS.md` 账号类型部分增加简短的选型说明（个人 vs 组织 vs 企业的适用场景），但不做详细决策表。

---

### R016 — 境外可达性/区域网络策略风险
- **判定：🔶 部分接受**
- **接受部分**：同意应在风险登记簿中补充网络可达性维度——不仅是"慢"的问题，确实可能在某些地区不可用。
- **拒绝部分**：不接受"多区域 endpoint"和"地域化默认配置"的建议。原因：
  1. Vox 是 BYOK 模式，endpoint 由用户的 API Key 决定，不是 Vox 能控制的
  2. 对于阿里云 DashScope，全球只有一个 API endpoint（dashscope.aliyuncs.com），Vox 无法部署"多区域 endpoint"
  3. 正确的缓解方案是：推荐海外用户使用 Whisper API（Groq 等全球可用的服务），以及保持 Apple Speech 离线降级
- **修改方案**：在 `07_RISKS.md` R07 中补充网络不可用（而非仅延迟高）的风险维度和正确的缓解策略

---

### R017 — 音频采样率/路由兼容
- **判定：❌ 拒绝**
- **理由**：
  1. **AVAudioRecorder 自动处理采样率转换**：当指定录音格式为 16kHz 时，无论物理麦克风的原生采样率是多少（iPhone 内建 48kHz、AirPods 16kHz SCO 等），AVAudioRecorder 会自动进行重采样。开发者不需要手动处理不同设备的采样率差异。
  2. **AVAudioSession 的 route change 处理**：iOS 系统会自动处理音频路由切换（如蓝牙设备断开时回退到内建麦克风）。AVAudioRecorder 在录音过程中也能平滑处理路由变化。这是系统框架级别的能力，不需要在应用层特别处理。
  3. **过度工程**：要求为"内建麦克风、AirPods、蓝牙车机"建立设备矩阵并分别测试采样率兼容性，对于一个使用标准 AVAudioRecorder API 的项目来说是过度工程。这不是自定义 AudioUnit/AudioGraph 场景。
  4. **已有覆盖**：`04_ARCHITECTURE.md` 已经指定录音参数为 16kHz/16bit/Mono WAV，使用 AVAudioRecorder 标准 API。这个配置在 iOS 上经过大量 App 的验证，是成熟可靠的。
  5. 如果确实出现特定设备的兼容问题，在测试阶段自然会发现并处理，不需要在规划阶段为此建立复杂的设备矩阵。

---

### R018 — 缺少键盘扩展专属验收项清单
- **判定：✅ 接受**
- **理由**：GPT 提出的验收项都很实际且有价值：目标 App 兼容性测试、secure field 提示、宿主禁用第三方键盘场景、审核前自查清单。当前 Sprint 4/5 的验收标准偏技术指标（内存 < 60MB、不崩溃），缺少"真实场景可用性"的验收维度。
- **修改方案**：
  1. 在 `06_SPRINT_PLAN.md` Sprint 4/5 中增加键盘扩展专属验收项
  2. 验收项包括：目标 App 兼容性矩阵、secure field 降级提示、宿主禁用场景处理、审核合规自查

---
