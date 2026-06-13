# 录音按钮重做 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用一个统一、纯灰阶、四态原地形变的 `RecordButton` SwiftUI 组件，替换键盘的 `KeyboardWaveformView` 和主 App 的 `WaveformView` + 录音按钮。

**Architecture:** 在 `Shared/UI/RecordButton.swift` 放一个**纯呈现**组件（只吃一个 `phase`，不含点击逻辑），键盘与主 App 各自把自己的状态映射成 `RecordButtonPhase` 并用各自的点击包裹（键盘保留休眠时的唤醒 `Link`）。装饰动画用 `TimelineView(.animation)` 自驱动（沿用 beta.58 防冻结经验），不接真实电平。

**Tech Stack:** Swift 5.9 / SwiftUI（iOS 17+）；XcodeGen（`Shared/` 已 glob 进两 target，新增文件后 `xcodegen generate`）；SF Symbols（mic.fill / checkmark）。

> ⚠️ **本地无 Xcode**：无法本地编译/跑测试。验证门 = **push 到分支 + 对 main 开 PR → GitHub Actions（build app + keyboard、VoxInputTests、SwiftLint）**。可测的纯逻辑（Task 1）写真 XCTest（CI 上跑）；视觉组件（Task 2–4）以 CI 编译通过为准，并配 `#Preview` 供日后真机肉眼校验。建议：Task 1–4 各自提交，最后一次性 push 跑 CI；CI 报错按日志修。

---

## File Structure

- **Create** `Shared/UI/RecordButton.swift` — `RecordButtonPhase` 枚举 + `RecordButton` 视图（两 target 共用；只用 SwiftUI，无 app/扩展专属 API）。
- **Modify** `VoxInput/UI/MainView.swift` — 用 `RecordButton(phase:)` 替换 `waveformSection`+`recordButton`；加 `RecordButtonPhase(_: RecordingState)` 映射。
- **Modify** `VoxInputKeyboard/KeyboardView.swift` — 用 `RecordButton(phase:)` 替换 `micButtonIcon` 与 `KeyboardWaveformView`；删除 `KeyboardWaveformView`；加 `KeyboardPhase → RecordButtonPhase` 内联映射（保留 `micActionControl` 的 Link/Button 逻辑）。
- **Delete** `VoxInput/UI/WaveformView.swift` —（替换后无引用）。
- **Modify** `VoxInputTests/RecordButtonPhaseTests.swift`（新建）— 测 `RecordButtonPhase` + `RecordingState` 映射（CI 上跑）。
- `project.yml` 无需改（`Shared/` 与各 target 目录已 glob）；新增/删除文件后执行 `xcodegen generate`（CI 会做）。

设计原则：`RecordButton` 只负责"长什么样"，不含任何 start/stop/wake 逻辑——点击行为留在调用方（键盘的休眠唤醒 Link、录音 Button；主 App 的 Button + 长按）。这样组件可在两端复用且不破坏现有唤醒链路。

---

## Task 1: `RecordButtonPhase` 枚举 + RecordingState 映射（含单测）

**Files:**
- Create: `Shared/UI/RecordButton.swift`（先只放枚举 + 映射，视图在 Task 2 补）
- Create: `VoxInputTests/RecordButtonPhaseTests.swift`

- [ ] **Step 1: 写枚举与 RecordingState 映射**

`Shared/UI/RecordButton.swift`（本任务先写这部分）：
```swift
// RecordButton.swift
// Shared/UI
//
// 统一录音按钮的呈现阶段 + 视图（键盘与主 App 共用）。纯呈现，不含点击逻辑。

import SwiftUI

/// 录音按钮的呈现阶段
enum RecordButtonPhase: Equatable {
    case idle        // 待命：浅色圆 + 麦克风
    case recording   // 录音：墨色 + 波形 + 柔和晕开
    case processing  // 识别中：墨色 + 三点
    case done        // 完成：墨色 + 对勾
}
```

`VoxInput/App/AppState.swift` 末尾追加（app target，可被 VoxInputTests 测）：
```swift
extension RecordButtonPhase {
    /// 主 App 录音状态 → 按钮阶段（主 App 无独立 done 态）
    init(_ state: RecordingState) {
        switch state {
        case .idle:       self = .idle
        case .recording:  self = .recording
        case .processing: self = .processing
        }
    }
}
```

- [ ] **Step 2: 写单测**

`VoxInputTests/RecordButtonPhaseTests.swift`：
```swift
import XCTest
@testable import VoxInput

final class RecordButtonPhaseTests: XCTestCase {
    func testRecordingStateMapping() {
        XCTAssertEqual(RecordButtonPhase(.idle), .idle)
        XCTAssertEqual(RecordButtonPhase(.recording), .recording)
        XCTAssertEqual(RecordButtonPhase(.processing), .processing)
    }
}
```

- [ ] **Step 3: 提交**
```bash
git add Shared/UI/RecordButton.swift VoxInput/App/AppState.swift VoxInputTests/RecordButtonPhaseTests.swift
git commit -m "feat(ui): add RecordButtonPhase + RecordingState mapping (recording-button redesign)"
```

> 验证：随 Task 5 的 CI 一起跑（`testRecordingStateMapping` 应通过）。本地无 Xcode，不单独本地跑。

---

## Task 2: `RecordButton` 视图（四态 + 波形 + 晕开）

**Files:**
- Modify: `Shared/UI/RecordButton.swift`（在枚举下方追加视图）

- [ ] **Step 1: 实现视图**

追加到 `Shared/UI/RecordButton.swift`：
```swift
/// 统一录音按钮：纯灰阶、圆形、同一按钮原地走四态。装饰动画（不接真实电平）。
/// 仅负责呈现；点击/唤醒逻辑由调用方包裹。
struct RecordButton: View {
    let phase: RecordButtonPhase
    var size: CGFloat = 96

    @Environment(\.colorScheme) private var scheme

    private var ink: Color { scheme == .dark ? .white : Color(white: 0.10) }
    private var idleFill: Color { scheme == .dark ? Color(white: 0.22) : Color(white: 0.91) }
    private var activeFill: Color { scheme == .dark ? Color(white: 0.95) : Color(white: 0.09) }
    /// 录音/识别/完成态按钮上的内容色（与 activeFill 反相）
    private var onActive: Color { scheme == .dark ? Color(white: 0.09) : .white }

    var body: some View {
        ZStack {
            if phase == .recording { bloom }
            Circle()
                .fill(phase == .idle ? idleFill : activeFill)
                .frame(width: size, height: size)
                .overlay {
                    if phase == .idle {
                        Circle().strokeBorder(ink.opacity(0.12), lineWidth: 1)
                    }
                }
                .overlay { content }
                .scaleEffect(phase == .recording ? 1.04 : 1.0)
                .shadow(color: .black.opacity(phase == .idle ? 0 : 0.18), radius: 12, y: 6)
        }
        .frame(width: size * 1.9, height: size * 1.9)   // 给 bloom 留扩散空间
        .animation(.easeInOut(duration: 0.35), value: phase)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle: return "录音"
        case .recording: return "录音中，点击结束"
        case .processing: return "识别中"
        case .done: return "完成"
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.34))
                .foregroundStyle(ink.opacity(0.55))
        case .recording:
            waveform
        case .processing:
            dots
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(onActive)
        }
    }

    /// 密排细条波形：TimelineView 自驱动，杀后台重开不冻结（beta.58 经验）
    private var waveform: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<11, id: \.self) { i in
                    Capsule()
                        .fill(onActive)
                        .frame(width: 2.5, height: barHeight(i: i, t: t))
                }
            }
            .frame(height: size * 0.44)
        }
    }

    private func barHeight(i: Int, t: Double) -> CGFloat {
        let maxH = size * 0.44
        let v = sin(t * 6.0 + Double(i) * 0.5) * 0.5 + 0.5   // 0...1
        return max(maxH * 0.18, maxH * CGFloat(0.2 + 0.8 * v))
    }

    /// 识别中：三个白点呼吸
    private var dots: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.08) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(onActive)
                        .frame(width: size * 0.10, height: size * 0.10)
                        .opacity(0.3 + 0.7 * (sin(t * 4.0 + Double(i) * 0.6) * 0.5 + 0.5))
                }
            }
        }
    }

    /// 录音态柔和晕开：低透明灰圆向外 scale + fade，多层错相
    private var bloom: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let p = ((t / 2.6) + Double(i) / 3.0).truncatingRemainder(dividingBy: 1.0) // 0...1
                    Circle()
                        .fill(ink.opacity(0.12 * (1.0 - p)))
                        .frame(width: size, height: size)
                        .scaleEffect(0.6 + 1.7 * p)
                        .blur(radius: 5)
                }
            }
        }
    }
}

#Preview("RecordButton states") {
    VStack(spacing: 28) {
        RecordButton(phase: .idle)
        RecordButton(phase: .recording)
        RecordButton(phase: .processing)
        RecordButton(phase: .done)
    }
    .padding(40)
}
```

- [ ] **Step 2: 提交**
```bash
git add Shared/UI/RecordButton.swift
git commit -m "feat(ui): RecordButton view — monochrome 4-state with waveform + bloom"
```

> 验证：随 Task 5 的 CI 编译验证。`#Preview` 供日后真机肉眼校验四态与动画。

---

## Task 3: 接入键盘（替换 KeyboardWaveformView + micButtonIcon）

**Files:**
- Modify: `VoxInputKeyboard/KeyboardView.swift`

- [ ] **Step 1: 加 KeyboardPhase → RecordButtonPhase 映射**

在 `KeyboardView.swift` 顶部（`import SwiftUI` 下方）追加：
```swift
private extension RecordButtonPhase {
    /// 键盘相位 → 按钮阶段。error 按待命呈现（错误文案另由 statusMessage 显示）。
    init(_ phase: KeyboardPhase) {
        switch phase {
        case .idle, .error: self = .idle
        case .recording:    self = .recording
        case .processing:   self = .processing
        case .done:         self = .done
        }
    }
}
```

- [ ] **Step 2: `micActionControl` 用 RecordButton 替换 micButtonIcon**

把 `micActionControl`（约 KeyboardView.swift:123-149）中两处 `micButtonIcon(isActive:)` 调用替换为 `RecordButton(phase: RecordButtonPhase(state.phase), size: Constants.Keyboard.micButtonSize)`：
```swift
@ViewBuilder
private var micActionControl: some View {
    if state.shouldWakeMainApp() {
        Link(destination: URL(string: "voxinput://record?source=keyboard&mode=wakeup")!) {
            RecordButton(phase: .idle, size: Constants.Keyboard.micButtonSize)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { state.markWakingUp() })
        .accessibilityLabel("点击唤醒 Vox Input")
    } else {
        Button {
            if state.phase == .recording { onRecordStop() } else { onRecordStart() }
        } label: {
            RecordButton(phase: RecordButtonPhase(state.phase), size: Constants.Keyboard.micButtonSize)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: 录音态视图去掉单独波形（已并入按钮）**

`recordingView`（约 :71-83）删除 `KeyboardWaveformView(...)` 那一行；保留 `micActionControl` 和文案。修改后：
```swift
private var recordingView: some View {
    VStack(spacing: 12) {
        micActionControl
        Text("录音中，点击结束")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.red)
    }
}
```

- [ ] **Step 4: 删除 KeyboardWaveformView + 不再需要的 micButtonIcon**

删除 `KeyboardWaveformView` 整个 struct（约 :212-261）与 `micButtonIcon(isActive:)`（约 :151-163）。`KeyboardState.isRecordingForWaveform`（KeyboardState.swift:36-39）此后无引用，可一并删除（可选；保留无害）。

- [ ] **Step 5: 提交**
```bash
git add VoxInputKeyboard/KeyboardView.swift VoxInputKeyboard/KeyboardState.swift
git commit -m "feat(keyboard): use RecordButton; drop KeyboardWaveformView"
```

---

## Task 4: 接入主 App（替换 WaveformView + recordButton）

**Files:**
- Modify: `VoxInput/UI/MainView.swift`
- Delete: `VoxInput/UI/WaveformView.swift`

- [ ] **Step 1: 用 RecordButton 替换 waveformSection + recordButton**

把 `body` 里的 `waveformSection`、`recordButton` 两块（VStack 中，约 :45-48）合并为一个 `recordControl`。删除 `waveformSection`（:184-193）与原 `recordButton`（:197-249）两个计算属性，新增：
```swift
private var recordControl: some View {
    let isProcessing = appState.recordingState == .processing
    return Button {
        Task { await appState.toggleRecording() }
    } label: {
        RecordButton(phase: RecordButtonPhase(appState.recordingState),
                     size: Constants.UI.recordButtonSize)
    }
    .buttonStyle(.plain)
    .disabled(isProcessing)
    .sensoryFeedback(.impact(flexibility: .solid), trigger: appState.recordingState == .recording)
    .simultaneousGesture(
        LongPressGesture(minimumDuration: 0.2).onEnded { _ in
            if appState.recordingState == .idle {
                Task { await appState.startRecording() }
            }
        }
    )
}
```
并把 `body` 的 VStack 中 `waveformSection` + `recordButton` 两行换成单行 `recordControl`。

- [ ] **Step 2: 删除 WaveformView 文件**
```bash
git rm VoxInput/UI/WaveformView.swift
```

- [ ] **Step 3: 提交**
```bash
git add VoxInput/UI/MainView.swift
git commit -m "feat(app): MainView uses RecordButton; remove WaveformView"
```

---

## Task 5: 重新生成工程 + CI 验证

**Files:** 无（构建/验证）

- [ ] **Step 1: （有 Mac 时）本地重生工程**
```bash
xcodegen generate
```
（本地无 Xcode 时跳过——CI 会跑 `xcodegen generate`。）

- [ ] **Step 2: 开分支并 push 触发 CI**
```bash
git checkout -b feat/recording-button
git push -u origin feat/recording-button
```
然后对 `main` 开 PR（CI 在 PR 上跑 build app + keyboard、VoxInputTests、SwiftLint）。

- [ ] **Step 3: 读 CI 结论**

Expected: `Build & Test` ✅ + `Swift Lint` ✅。`RecordButtonPhaseTests.testRecordingStateMapping` 通过。

- [ ] **Step 4: CI 红则按日志修**

常见点：`overlay { if ... }` 的 ViewBuilder、`TimelineView` 可用性、SwiftLint 行宽（warn 140 / error 200）、`force_unwrapping`（注意 `URL(string:)!` —— 键盘里那处唤醒 URL 是现有代码沿用；若 SwiftLint 报错，改为 `if let`）。逐条按 CI 日志修后重 push。

- [ ] **Step 5: 绿了合 PR**（征得用户同意后）。

---

## Self-Review

- **Spec coverage**：四态（待命/录音/识别/完成）= Task 2 `content`；纯灰阶+深浅色 = `ink/idleFill/activeFill/onActive`（`@Environment(\.colorScheme)`）；圆形+原地形变 = 单一 `Circle` + `animation(value: phase)`；波形（静止压成线、说话动）= 录音态 `waveform`，待命态无波形（mic 图标）符合"同一按钮原地变"；晕开 = `bloom`；装饰不接真实电平 = 纯 `TimelineView` 时间驱动；替换键盘 `KeyboardWaveformView` = Task 3；替换主 App `WaveformView` + 按钮 = Task 4；新增文件后 xcodegen = Task 5；保留键盘休眠唤醒 Link = Task 3 Step 2 保留 `if state.shouldWakeMainApp()` 分支。✅ 全覆盖。
- **Placeholder scan**：无 TODO/TBD；每步含完整代码或确切命令。✅
- **Type consistency**：`RecordButtonPhase` 四 case 全程一致；`RecordButton(phase:size:)` 签名在 Task 2 定义、Task 3/4 调用一致；`RecordButtonPhase(_ RecordingState)`（Task 1）与 `RecordButtonPhase(_ KeyboardPhase)`（Task 3）均为 `init`。✅
- **已知约束**：`RecordButtonPhase(_:KeyboardPhase)` 在键盘 target，VoxInputTests（`@testable import VoxInput`）测不到 → 仅 CI 编译验证；可测的 `RecordingState` 映射已在 Task 1 覆盖。

---
