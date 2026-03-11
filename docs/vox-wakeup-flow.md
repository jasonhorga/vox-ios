# Vox 唤醒链路分析（2026-03-11）

## 完整链路图

```
用户在其他 App 键入
    ↓
[键盘扩展 KeyboardViewController]
  viewWillAppear → KeyboardState.activate()
    - startIPCMonitoringIfNeeded()  ← Timer 轮询 App Group，间隔约 0.5s
    - startDarwinStateObserverIfNeeded()  ← 监听 daemonStateDidChange 通知
    - updateFromIPC()
    ↓
用户点击麦克风按钮
    ↓
[KeyboardState.startRecording()]
  1. 检查环境（full access / secure input）
  2. shouldWakeMainApp() → daemonState == "sleeping" | "dead"
     ├── 是（冷启动/休眠）→ openURLDidFail=true，phase=.error
     │     autoJumpHandler() → KeyboardViewController.autoJumpToMainApp()
     │       → UIResponder chain 发 URL: voxinput://record?source=keyboard&mode=wakeup
     └── 否（daemon 存活）→ 正常录音流程
         sendCommand(.start) → App Group UserDefaults
         AppGroupDarwinNotification.wakeUpAndRecord.post() → Darwin 通知
```

---

## 守护进程侧链路

```
[AudioDaemonService] （主 App 内，常驻后台）
  启动时 setupDarwinWakeObserver()
    → 监听 wakeUpAndRecord 通知
    → 收到通知时执行录音
  
  状态变更时发 daemonStateDidChange 通知
    → 键盘扩展 startDarwinStateObserverIfNeeded 已在监听
    → 键盘端立即 updateFromIPC()，拿最新状态
```

---

## 主 App 唤醒后的链路

```
[主 App] 收到 voxinput://record URL
    ↓
MainView.handleIncomingURL()
  isURLSchemeActivation = true
    ↓
AppState.primeDaemonForKeyboardWakeup()
  1. isPrimingAudio = true（显示 overlay）
  2. daemon.primeForBackgroundRecording()
     - 冷启动（state=dead）：最多重试 5 次，累计最长约 2.1 秒
     - 热唤醒（state=idle）：通常第 1 次即成功，< 0.5 秒
  3. prime 成功 → 判断 isURLSchemeActivation
     ├── true（URL 唤醒）→ 延迟 0.8s → perform("suspend")
     └── false（手动打开）→ 显示 "守护进程已就绪"
```

---

## 关键问题：冷启动为什么切不回去？

**热唤醒时序（成功）**：
```
用户 App 在前 → 键盘 URL → Vox 前台（< 0.5s prime）→ suspend → iOS 回上一个 App ✅
```

**冷启动时序（失败）**：
```
用户 App 在前 → 键盘 URL → Vox 冷启动（2s+ prime）→ Vox 已完全进入前台栈
                                                        → suspend → iOS 回桌面 ❌
```

**根因**：iOS 的 app switcher 转场上下文（"上一个 app"）在前台切换约 1 秒后失效。  
冷启动的 prime 耗时远超这个窗口，`suspend` 执行时已无法知道要回到哪里。

---

## 现有机制

### 键盘扩展已有的
- ✅ Darwin 通知监听（`daemonStateDidChange`）→ 触发 `updateFromIPC()`
- ✅ IPC 轮询（Timer 0.5s）
- ✅ App Group 共享状态（daemonState 字段）
- ✅ `shouldWakeMainApp()` 判断是否需要唤醒
- ✅ UIResponder chain 发 URL（Method D，唯一可行方案）

### 缺失的
- ❌ 键盘侧无法在 daemon ready 时"主动触发回跳"
- ❌ 无区分冷启动 / 热唤醒的不同 suspend 策略

---

## 修复方案

### 方案 A（推荐）：冷启动降级为手动返回

最小改动，最稳定：

**改动点**：`AppState.primeDaemonForKeyboardWakeup()`

```swift
// 在 prime 之前记录是否冷启动
let isColdStart = await daemon.state == .dead

// prime 完成后
if isURLSchemeActivation {
    if isColdStart {
        // 冷启动：无法自动切回，显示引导
        statusMessage = "✅ 守护进程已就绪，请手动切回"
        // 不 suspend，让 Vox 留在前台，用户自己返回
    } else {
        // 热唤醒：0.8s 后 suspend，可以自动回去
        statusMessage = "✅ 守护进程已就绪，自动返回..."
        try? await Task.sleep(nanoseconds: 800_000_000)
        UIApplication.shared.perform(NSSelectorFromString("suspend"))
    }
    isURLSchemeActivation = false
}
```

**优点**：改动极小，行为确定性高  
**缺点**：冷启动体验稍差（用户需手动返回，但至少不会回桌面）

---

### 方案 B（进阶）：键盘监听 ready + 反向唤回

理论上更好，但有不确定性：

键盘已经在监听 `daemonStateDidChange`，prime 完成时 daemon 从 `dead` → `idle` 会触发此通知。

**改动点**：`KeyboardState.syncPhaseWithDaemonState()`

```swift
case "idle":
    // 新增：如果这次从 dead 变成了 idle，说明是冷启动 prime 完成
    // 触发"请返回键盘"提示
    if wasDead && isRequestInFlight {
        statusMessage = "守护进程已就绪，请切回键盘继续"
        // 或者尝试反向唤回原 App（但 iOS 不允许 extension 直接切换 App，只能提示）
    }
```

**限制**：iOS 键盘扩展**无法**主动切换到其他 App，只能更新自身 UI 提示。  
反向唤回宿主 App 不可行，除非宿主 App 注册了 URL scheme 且允许从 extension 打开（这同样走 UIResponder chain，行为不确定）。

**结论**：方案 B 能做的其实只是在键盘 UI 上显示提示，和方案 A 主 App 侧显示提示效果相同。

---

## 推荐

**先做方案 A**，改动点 1 处，约 10 行代码：

1. prime 之前记录 `isColdStart`
2. prime 完成后根据 `isColdStart` 决定是否 `suspend`

预期效果：
- 热唤醒（daemon 存活）：体验不变，自动切回 ✅
- 冷启动（daemon 不在）：Vox 停在前台显示"已就绪，请手动返回"，不再退回桌面 ✅
