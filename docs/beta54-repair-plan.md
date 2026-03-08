# Beta.54 Four-Phase Repair Plan

## 真因分析

### Issue 1: 录音几秒/10秒自动停止
**根因**：`KeyboardState.beginRequestTracking()` 创建的 `requestTimeoutTask` 在 `Constants.Keyboard.resultTimeout`（10秒）后触发 `handleRequestTimeoutIfNeeded()`。该方法检查 `phase == .recording || phase == .processing`，两者都会被cancel。**超时逻辑应该只作用于 `.processing` 阶段**，录音期间不应有超时。

此外 `startupAckTimeoutTask`（0.5秒）在收到 recording 状态后会 cancel，这个没问题。但 `requestTimeoutTask` 从 start 开始就计时，10秒后无论是否还在录音都会 cancel。

**修复**：
- `handleRequestTimeoutIfNeeded()` 中，如果 `phase == .recording`，不执行超时取消
- 或者：进入 `.recording` 后取消 `requestTimeoutTask`，只在 `.processing` 阶段重新启动超时

### Issue 2: 切回来后无波形
**根因**：键盘扩展 `deactivate()` 取消 `waveformTask`。再次 `activate()` 后，`updateFromIPC()` → `syncPhaseWithDaemonState()` 设置 `phase = .recording`，但如果 phase 之前已经是 `.recording`（oldValue == newValue），`handlePhaseTransition` 不会触发，`startFakeWaveformAnimation()` 不会被调用。

**修复**：
- `activate()` 中检查当前 phase，如果是 `.recording` 则主动调用 `startFakeWaveformAnimation()`

### Issue 3: 主App返回提示
**根因**：`MainView.handleScenePhaseChange()` 每次从后台切到前台都会调用 `primeDaemonForKeyboardWakeup()`，显示"正在获取麦克风..."overlay + "✅ 守护进程已就绪"。只有 `isURLSchemeActivation == true` 时才应该显示"请返回输入法"的提示。

但当前实现中 `handleScenePhaseChange` 在手动打开时也会触发 prime，显示 overlay 让用户困惑。

**修复**：
- `handleScenePhaseChange()` 中只在 `isURLSchemeActivation == true` 时才执行 prime + 显示 overlay
- 手动打开 App 时，不显示 prime overlay，静默 prime

### Issue 4: Icon 有 alpha channel
**根因**：之前生成的 PNG 图标可能仍带 alpha channel。TestFlight 要求 App Store 1024px 图标无 alpha。

**修复**：
- 用 Python/ImageMagick 重新生成所有尺寸图标，强制移除 alpha channel
- 验证 1024px 大图无 alpha

---

## 执行阶段

### Phase 1: 修复录音超时自动停止
- 修改 `KeyboardState.swift`
- `handleRequestTimeoutIfNeeded()` 只在 `.processing` 阶段执行超时取消
- 进入 `.recording` 后取消 `requestTimeoutTask`，切到 `.processing` 后重新启动
- Commit + Push + 等 CI

### Phase 2: 修复波形二次失效
- 修改 `KeyboardState.swift`
- `activate()` 中如果 phase == .recording，主动启动波形动画
- Commit + Push + 等 CI

### Phase 3: 修复主App返回提示
- 修改 `MainView.swift` + `AppState.swift`
- `handleScenePhaseChange()` 只在 URL 唤醒时显示 prime overlay
- 手动打开时静默 prime
- Commit + Push + 等 CI

### Phase 4: 修复 Icon alpha
- 重新生成无 alpha 的图标 PNG
- Commit + Push + 等 CI
