# 常驻/免跳转（功能 ③）Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development（或 executing-plans）逐任务实现。步骤用 `- [ ]`。

**Goal:** 把现有「后台语音待机时长」重构成清晰的「免跳转 / 后台常驻」UX —— 让用户明白：常驻越久越多次听写能免跳转直接录、代价是麦克风灯常亮+耗电。

**Architecture:** ③ 的保活内核已存在（`AudioDaemonService` 的 primed 引擎 + `SharedConfigStore.DaemonStandbyDuration`；`never` 在 `checkIdleSleepIfNeeded` 直接 `return`、永不休眠、引擎保持 primed）。Phase 1 **纯 UX**：改 `DaemonStandbyDuration.displayName` 文案 + `SettingsView` 这一节的标签/说明。**不改枚举 rawValue（保持持久化兼容）、不改休眠/prime 逻辑、不新增 target、不动 IPC。**

**Tech Stack:** SwiftUI；现有 App Group 配置。

> ⚠️ 本地无 Xcode，靠 push→CI 验证。纯逻辑（`seconds`/`displayName`）写单测；UI 文案以 CI 编译为门。
> **Phase 2（灵动岛 Live Activity 外壳）不在本计划**，见末尾说明，单独立计划。

---

## File Structure

- **Modify** `Shared/SharedConfigStore.swift` — `DaemonStandbyDuration.displayName` 文案改清楚（**rawValue 与 seconds 不动**）。
- **Modify** `VoxInput/UI/SettingsView.swift` — 「后台语音守护」Section 改标题/Picker 标签/footer 为「免跳转 / 后台常驻」叙事。
- **Create** `VoxInputTests/DaemonStandbyDurationTests.swift` — 测 `seconds` 映射与 `displayName` 非空（纯逻辑，CI 跑）。
- 新增测试文件后 `xcodegen generate`（CI 做）。无 `project.yml` 改动。

---

## Task 1: 改 displayName 文案 + 单测

**Files:** Modify `Shared/SharedConfigStore.swift`；Create `VoxInputTests/DaemonStandbyDurationTests.swift`

- [ ] **Step 1: 改 displayName（只改文案，rawValue/seconds 保持原样）**

把 `DaemonStandbyDuration.displayName` 改为：
```swift
    var displayName: String {
        switch self {
        case .minutes3: return "3 分钟后休眠（最省电）"
        case .minutes10: return "10 分钟后休眠"
        case .never: return "始终常驻（免跳转）"
        }
    }
```
（`enum` 的 `case minutes3 = "3m"` 等 rawValue、以及 `seconds` 计算属性**保持不变**。）

- [ ] **Step 2: 写单测**

`VoxInputTests/DaemonStandbyDurationTests.swift`：
```swift
import XCTest
@testable import VoxInput

final class DaemonStandbyDurationTests: XCTestCase {
    func testSeconds() {
        XCTAssertEqual(DaemonStandbyDuration.minutes3.seconds, 180)
        XCTAssertEqual(DaemonStandbyDuration.minutes10.seconds, 600)
        XCTAssertNil(DaemonStandbyDuration.never.seconds)   // never = 永不休眠（保持常驻）
    }
    func testDisplayNamesNonEmpty() {
        for d in DaemonStandbyDuration.allCases {
            XCTAssertFalse(d.displayName.isEmpty)
        }
    }
    func testRawValuesStable() {
        // 持久化兼容：rawValue 不能变
        XCTAssertEqual(DaemonStandbyDuration.minutes3.rawValue, "3m")
        XCTAssertEqual(DaemonStandbyDuration.minutes10.rawValue, "10m")
        XCTAssertEqual(DaemonStandbyDuration.never.rawValue, "never")
    }
}
```

- [ ] **Step 3: 提交**
```bash
git add Shared/SharedConfigStore.swift VoxInputTests/DaemonStandbyDurationTests.swift
git commit -m "feat(keepalive): clearer DaemonStandbyDuration labels + tests (③ phase 1)"
```

---

## Task 2: SettingsView 重构这一节为「免跳转 / 后台常驻」

**Files:** Modify `VoxInput/UI/SettingsView.swift`

- [ ] **Step 1: 改标题 / Picker 标签 / footer**

把现有「后台语音守护」Section（Picker「后台语音待机时长」+ 那段 footer）整体替换为：
```swift
                // MARK: - 免跳转 / 后台常驻
                Section {
                    Picker("后台常驻时长", selection: $config.daemonStandbyDuration) {
                        ForEach(DaemonStandbyDuration.allCases, id: \.self) { duration in
                            Text(duration.displayName).tag(duration)
                        }
                    }
                } header: {
                    Text("免跳转 / 后台常驻")
                } footer: {
                    Text("键盘要打开麦克风必须先切到主 App（iOS 的限制）。让主 App 在后台常驻得越久，越多次听写能「免跳转」——直接录、并自动切回输入框；代价是常驻期间系统麦克风指示灯常亮、更耗电。「始终常驻」跳转最少、最费电；较短时长更省电，但空闲超时后再用需切一次 App。")
                }
```

- [ ] **Step 2: 提交**
```bash
git add VoxInput/UI/SettingsView.swift
git commit -m "feat(settings): reframe standby as 免跳转/后台常驻 with explanation (③ phase 1)"
```

---

## Task 3: 重生工程 + CI

- [ ] **Step 1:** （有 Mac）`xcodegen generate`；本地无 Xcode 则跳过（CI 做）。
- [ ] **Step 2:** 开分支 push + 对 main 开 PR：
```bash
git checkout -b feat/keepalive-ux
git push -u origin feat/keepalive-ux
```
- [ ] **Step 3:** 读 CI：`Build & Test` ✅（含 `DaemonStandbyDurationTests`）+ `Swift Lint` ✅。
- [ ] **Step 4:** CI 红按日志修（常见：SettingsView Section 语法、footer 行宽 warn140）。
- [ ] **Step 5:** 绿了征得用户同意再合。

---

## Self-Review

- **Spec coverage（Phase 1 部分）**：UX 重构「免跳转/待机」+ 说明 = Task 2；诚实标注「始终=麦克风灯常亮+耗电」= Task 2 footer + Task 1 displayName；保活可靠性 = 已存在（`never` 在 `checkIdleSleepIfNeeded` 直接 return 不休眠、引擎保持 primed，无需改动，本计划在 Architecture 注明）；不新增 target/不动 IPC = 遵守。✅
- **Placeholder scan**：无 TODO；每步有完整代码/命令。✅
- **Type consistency**：`DaemonStandbyDuration`、`displayName`、`seconds`、`rawValue` 全程一致；只动 displayName 文案。✅
- **回归风险**：极低——只改展示文案与设置页文字 + 加纯逻辑单测；rawValue/seconds/休眠逻辑不变，持久化与行为兼容。

---

## Phase 2（不在本计划 — 单独立计划）

**灵动岛 Live Activity 外壳**：录音/常驻期间在灵动岛+锁屏显示状态 + 停止/返回控制（= Typeless「灵动岛」模式）。为何单独做：
- 需**新增一个 Widget Extension target**（改 `project.yml`：新 target、ActivityKit 框架、App Intents），并加 Live Activities 的 Info.plist（`NSSupportsLiveActivities`）/entitlements。
- 本地无 Xcode **无法验证工程配置**，只能靠 CI 反复试，工程级配置错误的 CI 往返成本高。
- 审核敏感（Live Activity 行为/持续性）。
- 机制上 Live Activity **只是可见外壳**，保活仍靠 Phase 1 已覆盖的音频会话；BGCPT 不能录音（见 memory: ios-background-mic-keepalive）。

→ 待 Phase 1 合入、且需要灵动岛可见控制时，单独写 `…-phase2-live-activity.md` 计划实现。
