# 后台常驻 / 免跳转（always-on keep-alive）v1 — 设计文档（2026-06-12）

## 背景（经 deep-research 与竞品截图核实）

**iOS 键盘扩展不能访问麦克风**(Apple 硬限制,出于隐私)。所以任何第三方语音输入法都必须:**录音放在主 App,首次需把主 App 拉前台一次开麦**。"键盘当遥控器 + 常驻 daemon"是 Vox 已有的正确、行业标准架构(微信输入法、Typeless 同构)。

行业通用缓解法:**把音频会话"焐热"一段时间,后续听写就免跳转**。
- 微信输入法:"语音待机时长 → 免跳转"。
- Typeless:"跳过应用切换:始终 / 12 小时 / 5 分钟" + 灵动岛/画中画外壳。
- **Vox 已有核心**:`DaemonStandbyDuration`(3m / 10m / 永不)+ beta.40 "常驻引擎 primed"。

本功能 = 把这块**打磨到对齐竞品**,不是新造轮子。

## 机制(已核实,见 memory: ios-background-mic-keepalive)

- **保活/保热 = `audio` 后台模式 + 一个前台开始且持续在采集的 AVAudioSession**(= Vox 的 primed 引擎)。不能从后台开麦;空闲会话被挂起;橙色麦克风指示灯强制常亮。
- **灵动岛 Live Activity = 纯可见外壳(透明化 + 控制),不提供运行时**。
- **画中画**可能额外加固"保热"(可见浮窗更不易被回收),但挪用 API、有审核风险(2.5.1/2.5.4)、且无源证明其 mic 效果。
- **`BGContinuedProcessingTask` 不能录音**(计算类、退后台 ~50s 被杀、iOS 26+),不采用。

## 范围

**In（v1）**
1. **保热可靠性**:让"永不 / 长时长"下 primed 引擎尽量稳活(活跃音频会话),减少被系统回收 → 减少冷启动 → 多数时候免跳转或自动切回。
2. **UX 重构**:把"后台语音待机时长"重新包装成清晰的「**免跳转 / 后台常驻:始终 · 长 · 短 · 关**」+ 说明文案(对齐微信/Typeless:"键盘需切到主 App 开麦是 iOS 限制;开启常驻可跳过此步")。诚实标注**代价**:常驻=麦克风灯常亮 + 耗电。
3. **(可选)灵动岛 Live Activity 外壳**:常驻/录音期间显示,做透明化 + 停止/返回控制(= Typeless 灵动岛模式)。**作为音频会话保活之上的 UI 外壳,不依赖它提供运行时**。需新增 **Widget Extension**(第三个 target)+ App Intents;Live Activity iOS 16.1+、交互按钮 iOS 17+。
4. **自动切回打磨**:需要唤醒(睡/冷)时,沿用 beta.60 的热唤醒 `suspend` 自动切回;把"尽量保持热 → 少唤醒 → 多自动切回/不切"写进目标。

**Out / 硬限制（如实记录）**
- **键盘内直接录音:不可能**(无麦克风权限)。架构保持 daemon。
- **冷启动那一次的自动切回:iOS 死限**(App 被系统杀 → 冷启动 prime 慢 → `suspend` 转场上下文已过期)→ 退回手动"请返回"。竞品(含 Typeless)冷启动八成也是手动。
- **BGContinuedProcessingTask / PiP**:不采用 / 后置(理由见上)。

## 配置 / 接入点

- `DaemonStandbyDuration` 扩充/改名为"免跳转/常驻"语义(加"始终"已存在 = `never`);`SettingsView` 重做这一节文案。
- (可选外壳)新增 Widget Extension target(ActivityKit widget + Stop/Return App Intents),共享 `Shared/` 的 IPC/常量;`project.yml` + `xcodegen generate`。
- 保热可靠性在 `AudioDaemonService`(primed 引擎 + 待机判定,已存在)上打磨。

## 关联

- 与 review **M3(音频会话争用)**相关:保热可靠性会动到会话处理,一并考虑。
- 依赖 review 已修的稳定性基础。

## 建议分期

- **Phase 1(低风险高价值,先做)**:UX 重构"免跳转/常驻" + primed 保热可靠性打磨。**不新增 target**。
- **Phase 2**:灵动岛 Live Activity 外壳(Widget Extension)。
- **(后置)**:画中画。

## 未决

- "始终"在 iOS 内存/热压力下的真实存活率与续航代价(需真机量化)。
- 灵动岛外壳是否进 v1 还是放 Phase 2。
- Typeless「灵动岛 vs 画中画」的确切内部实现仍无权威来源(deep-research 开放问题)——但不影响本设计(我们走已证实的音频会话保活 + 可选 Live Activity 外壳)。
