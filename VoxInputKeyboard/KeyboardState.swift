// KeyboardState.swift
// VoxInputKeyboard
//
// 键盘扩展状态机：Remote Control + App Group IPC

import Foundation
import Observation

/// 键盘扩展状态
enum KeyboardPhase: Equatable {
    case idle
    case recording
    case processing
    case done(String)
    case error(String)
}

private struct IPCSnapshot {
    let state: String
    let errorMessage: String?
    let heartbeat: TimeInterval
    let resultID: Int
    let resultText: String?
    let resultAt: TimeInterval
}

@Observable
@MainActor
final class KeyboardState {

    // MARK: - Observable State

    private(set) var phase: KeyboardPhase = .idle
    private(set) var statusMessage: String = ""

    /// beta.58: 简化为纯布尔标记，波形动画交给 TimelineView 自驱动
    var isRecordingForWaveform: Bool {
        if case .recording = phase { return true }
        return false
    }

    private(set) var hasFullAccess: Bool = false
    private(set) var isSecureInput: Bool = false

    var inputContextHint: String?

    /// 当前 IPC 守护进程状态字符串
    private(set) var daemonState: String = "dead"

    /// 最近一次 daemon 错误
    private(set) var daemonErrorMessage: String?
    
    /// 是否为需要唤醒后台服务的特定错误
    var needsAppWakeup: Bool {
        daemonErrorMessage?.contains("后台服务已休眠") == true
    }

    /// beta.37: 所有自动化 openURL 策略均已失败，需要显示手动跳转 UI
    private(set) var openURLDidFail: Bool = false

    // MARK: - IPC Internals

    let config = SharedConfigStore.shared

    private let ipcQueue = DispatchQueue(label: "com.jasonhorga.vox.keyboard.ipc", qos: .userInitiated)
    private var ipcTimer: Timer?
    private var daemonStateObserver: DarwinNotificationObserver?
    private var lastResultID: Int = 0
    private var lastHeartbeatAt: TimeInterval = 0

    private var insertTextHandler: ((String) -> Void)?
    private var autoJumpHandler: (() -> Bool)?

    /// 当前会话追踪（用于屏蔽旧状态抖动 + 超时兜底）
    private var isRequestInFlight = false
    private var hasSeenRecordingInCurrentRequest = false
    private var hasSentStopInCurrentRequest = false
    private var requestStartedAt: Date?
    private var startupAckTimeoutTask: Task<Void, Never>?
    private var requestTimeoutTask: Task<Void, Never>?

    // MARK: - Wiring

    /// 由 ViewController 注入桥接能力
    func bindHandlers(insertText: @escaping (String) -> Void, autoJump: @escaping () -> Bool) {
        self.insertTextHandler = insertText
        self.autoJumpHandler = autoJump
    }

    // MARK: - Lifecycle

    func activate() {
        config.reload()
        checkEnvironment()
        bootstrapLastResultID()
        startIPCMonitoringIfNeeded()
        startDarwinStateObserverIfNeeded()
        updateFromIPC()
    }

    func deactivate() {
        ipcTimer?.invalidate()
        ipcTimer = nil
        daemonStateObserver?.stop()
        daemonStateObserver = nil
        clearRequestTracking()
        activeResetTask?.cancel()
        activeResetTask = nil
    }

    // MARK: - Environment

    func checkEnvironment(systemHasFullAccess: Bool? = nil) {
        // beta.61: 只信任 UIInputViewController.hasFullAccess 传入的权威值（review M5）。
        // 旧的 probeFullAccessAsync 在同进程写后读，即使没有 Full Access 也会误报 true。
        if let value = systemHasFullAccess {
            hasFullAccess = value
        }

        SharedLogger.info("环境检查: fullAccess=\(hasFullAccess)")
    }

    func updateSecureInputState(_ isSecure: Bool) {
        isSecureInput = isSecure
        if isSecure {
            statusMessage = "密码输入框，语音输入不可用"
        }
    }

    // MARK: - Recording (Remote Control)

    @discardableResult
    func startRecording() -> Bool {
        config.reload()

        guard phase == .idle else { return false }

        guard !isSecureInput else {
            phase = .error("密码输入框不支持语音输入")
            statusMessage = "密码输入框不支持语音输入"
            scheduleReset()
            return false
        }

        guard hasFullAccess else {
            phase = .error("请先开启完全访问")
            statusMessage = "请在系统设置中开启\u{201C}完全访问\u{201D}"
            scheduleReset()
            return false
        }

        // beta.50: 重置所有挂起状态
        openURLDidFail = false
        activeResetTask?.cancel()

        // beta.50: 守护进程休眠时不再编程式跳转，由 UI 层 SwiftUI Link 处理
        // beta.53: 改为立即主动调用 autoJump，"没点中 Link 也会自动跳"
        if shouldWakeMainApp() {
            openURLDidFail = true
            phase = .error("后台服务已休眠")
            statusMessage = "请点击唤醒按钮打开 Vox Input"
            _ = autoJumpHandler?()
            return false
        }

        beginRequestTracking()
        sendCommand(.start, postWakeNotification: true)
        phase = .processing
        statusMessage = "正在连接后台录音..."
        return true
    }

    func stopRecording() {
        guard phase == .recording else { return }
        hasSentStopInCurrentRequest = true
        sendCommand(.stop)
        phase = .processing
        statusMessage = "识别中..."
        // 用户点击停止后，开始处理超时计时
        requestTimeoutTask?.cancel()
        requestTimeoutTask = Task { [weak self] in
            let timeout = Constants.Keyboard.resultTimeout
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await MainActor.run { [weak self] in
                self?.handleRequestTimeoutIfNeeded()
            }
        }
    }

    func cancelRecording() {
        sendCommand(.cancel)
        clearRequestTracking()
        phase = .idle
        statusMessage = ""
    }

    // MARK: - IPC Polling

    /// beta.61: 键盘进程启动时，把当前已存在的 result_id 设为基线，
    /// 这样上一次会话残留的结果不会被当成"新结果"注入（review H3）。
    private func bootstrapLastResultID() {
        ipcQueue.async { [weak self] in
            let existing = AppGroup.sharedDefaults.integer(forKey: AppGroup.ipcResultIDKey)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.lastResultID == 0 { self.lastResultID = existing }
            }
        }
    }

    private func startIPCMonitoringIfNeeded() {
        guard ipcTimer == nil else { return }

        ipcTimer = Timer.scheduledTimer(withTimeInterval: Constants.Keyboard.ipcPollInterval, repeats: true) { [weak self] _ in
            self?.updateFromIPC()
        }
    }

    private func startDarwinStateObserverIfNeeded() {
        guard daemonStateObserver == nil else { return }

        daemonStateObserver = DarwinNotificationObserver(name: .daemonStateDidChange) { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateFromIPC()
            }
        }
        daemonStateObserver?.start()
    }

    private func updateFromIPC() {
        ipcQueue.async { [weak self] in
            guard let self else { return }
            let defaults = AppGroup.sharedDefaults
            let snapshot = IPCSnapshot(
                state: defaults.string(forKey: AppGroup.ipcStateKey) ?? "dead",
                errorMessage: defaults.string(forKey: AppGroup.ipcErrorKey),
                heartbeat: defaults.double(forKey: AppGroup.ipcHeartbeatKey),
                resultID: defaults.integer(forKey: AppGroup.ipcResultIDKey),
                resultText: defaults.string(forKey: AppGroup.ipcResultKey),
                resultAt: defaults.double(forKey: AppGroup.ipcResultAtKey)
            )

            Task { @MainActor [weak self] in
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: IPCSnapshot) {
        // beta.49: 在源头掐断僵尸状态——心跳超时则强制视为 dead
        // 根因：主 App 被杀后 UserDefaults 残留 idle，导致 syncPhaseWithDaemonState
        // 误以为守护进程仍存活，清除 openURLDidFail 并把 phase 闪回 .idle
        var effectiveState = snapshot.state
        if effectiveState != "dead" && effectiveState != "sleeping" {
            if snapshot.heartbeat <= 0 {
                // 心跳从未写入——守护进程从未启动过，视为 dead
                effectiveState = "dead"
            } else {
                let age = Date().timeIntervalSince1970 - snapshot.heartbeat
                if age > Constants.Daemon.heartbeatTimeout {
                    effectiveState = "dead"
                }
            }
        }
        
        daemonState = effectiveState
        daemonErrorMessage = snapshot.errorMessage
        lastHeartbeatAt = snapshot.heartbeat

        if snapshot.resultID > 0,
           snapshot.resultID != lastResultID,
           let inserted = snapshot.resultText,
           !inserted.isEmpty {
            // beta.61: 防陈旧/防越界注入（review H3）。结果太旧（或无时间戳）只更新基线、
            // 清掉残留、不注入——否则上一次会话的转写可能在之后、甚至在别的 App 输入框里凭空出现。
            let resultAge = snapshot.resultAt > 0
                ? Date().timeIntervalSince1970 - snapshot.resultAt
                : .greatestFiniteMagnitude
            guard resultAge <= Constants.Keyboard.resultStaleAfter else {
                lastResultID = snapshot.resultID
                clearResultAsync(expectedID: snapshot.resultID)
                return
            }

            lastResultID = snapshot.resultID
            clearResultAsync(expectedID: snapshot.resultID)

            clearRequestTracking()
            openURLDidFail = false
            insertTextHandler?(inserted)
            phase = .done("已输入：\(inserted)")
            statusMessage = "已注入文本"
            scheduleReset()
            return
        }

        syncPhaseWithDaemonState(effectiveState)
    }

    private func clearResultAsync(expectedID: Int) {
        ipcQueue.async {
            let defaults = AppGroup.sharedDefaults
            let latestID = defaults.integer(forKey: AppGroup.ipcResultIDKey)
            guard latestID == expectedID else { return }
            defaults.removeObject(forKey: AppGroup.ipcResultKey)
        }
    }

    private func syncPhaseWithDaemonState(_ state: String) {
        // beta.46: 🔒 如果已经处于 openURLDidFail 状态，锁定 UI 不被轮询覆盖
        // 这是之前"错误界面闪一下就回到空闲状态"的根因之一
        if openURLDidFail {
            // 唯一例外：守护进程恢复了（变成 idle/recording），说明用户已手动打开主 App
            if state == "recording" || state == "idle" {
                // 守护进程已恢复，自动清除错误状态
                openURLDidFail = false
                // 继续走下面的正常处理逻辑
            } else {
                // 守护进程仍然不可用，保持错误 UI 不变
                return
            }
        }
        
        switch state {
        case "recording":
            hasSeenRecordingInCurrentRequest = true
            startupAckTimeoutTask?.cancel()
            startupAckTimeoutTask = nil
            requestTimeoutTask?.cancel()
            requestTimeoutTask = nil
            openURLDidFail = false
            phase = .recording
            statusMessage = "录音中..."

        case "processing":
            // 避免上一轮残留 processing 把新一轮录音瞬间"顶掉"
            if isRequestInFlight, !hasSeenRecordingInCurrentRequest, !hasSentStopInCurrentRequest {
                return
            }
            phase = .processing
            statusMessage = "识别中..."

        case "error":
            clearRequestTracking()
            let message = daemonErrorMessage ?? "识别失败"
            phase = .error(message)
            statusMessage = message
            if !needsAppWakeup {
                scheduleReset()
            }

        case "idle":
            // 新请求 start 后，daemon 可能短暂还在 idle，不能误判
            if isRequestInFlight, !hasSeenRecordingInCurrentRequest, !hasSentStopInCurrentRequest {
                return
            }
            // 自动恢复逻辑：当 phase 是 .error 且不需要唤醒 App 时
            if case .error = phase, !needsAppWakeup, !openURLDidFail {
                clearRequestTracking()
                phase = .idle
                statusMessage = ""
            }
            if case .recording = phase {
                phase = .processing
                statusMessage = "识别中..."
            }

        case "sleeping", "dead":
            // 只在有活跃请求时才切换到错误状态
            // （idle 状态下守护进程睡眠是正常的，不需要显示错误）
            if isRequestInFlight || phase == .recording || phase == .processing {
                clearRequestTracking()
                openURLDidFail = true
                phase = .error("后台服务已休眠")
                statusMessage = "守护进程已休眠，请手动打开一次 Vox App"
            }

        default:
            break
        }
    }

    // MARK: - Command / Wakeup

    private enum IPCCommand: String {
        case start
        case stop
        case cancel
    }

    private func sendCommand(_ command: IPCCommand, postWakeNotification: Bool = false) {
        ipcQueue.async {
            let defaults = AppGroup.sharedDefaults
            let nextID = defaults.integer(forKey: AppGroup.ipcCommandIDKey) + 1
            defaults.set(command.rawValue, forKey: AppGroup.ipcCommandKey)
            defaults.set(nextID, forKey: AppGroup.ipcCommandIDKey)
            defaults.set(Date().timeIntervalSince1970, forKey: AppGroup.ipcCommandAtKey)

            if postWakeNotification {
                AppGroupDarwinNotification.wakeUpAndRecord.post()
            }
        }
    }

    /// beta.50: 守护进程状态检测（internal，供 KeyboardView 访问）
    /// daemonState 已在 apply() 中经过心跳校准，僵尸状态已被标记为 dead
    func shouldWakeMainApp() -> Bool {
        return daemonState == "sleeping" || daemonState == "dead" || daemonState.isEmpty
    }

    /// UI 点击唤醒 Link 时更新提示文案
    func markWakingUp() {
        statusMessage = "正在唤醒..."
    }

    // MARK: - Request Watchdog

    private func beginRequestTracking() {
        clearRequestTracking()
        isRequestInFlight = true
        hasSeenRecordingInCurrentRequest = false
        hasSentStopInCurrentRequest = false
        requestStartedAt = Date()

        startupAckTimeoutTask = Task { [weak self] in
            let timeout = Constants.Keyboard.startupAckTimeout
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await MainActor.run { [weak self] in
                self?.handleStartupAckTimeoutIfNeeded()
            }
        }

        requestTimeoutTask = Task { [weak self] in
            let timeout = Constants.Keyboard.resultTimeout
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await MainActor.run { [weak self] in
                self?.handleRequestTimeoutIfNeeded()
            }
        }
    }

    private func clearRequestTracking() {
        isRequestInFlight = false
        hasSeenRecordingInCurrentRequest = false
        hasSentStopInCurrentRequest = false
        requestStartedAt = nil

        startupAckTimeoutTask?.cancel()
        startupAckTimeoutTask = nil

        requestTimeoutTask?.cancel()
        requestTimeoutTask = nil
    }

    private func handleStartupAckTimeoutIfNeeded() {
        guard isRequestInFlight else { return }
        guard !hasSeenRecordingInCurrentRequest else { return }

        guard phase == .recording || phase == .processing else {
            clearRequestTracking()
            return
        }

        let elapsed = Date().timeIntervalSince(requestStartedAt ?? Date())
        guard elapsed >= Constants.Keyboard.startupAckTimeout else { return }

        sendCommand(.cancel)
        clearRequestTracking()

        SharedLogger.info("[KeyboardState] startup ack timeout, showing wakeup Link")

        // beta.53: 启动确认超时时也主动补一枪自动跳转，避免用户必须手动点 Link
        openURLDidFail = true
        phase = .error("后台服务无响应")
        statusMessage = "请点击唤醒按钮打开 Vox Input"
        _ = autoJumpHandler?()
    }

    private func handleRequestTimeoutIfNeeded() {
        guard isRequestInFlight else { return }
        guard phase == .processing else {
            clearRequestTracking()
            return
        }

        let elapsed = Date().timeIntervalSince(requestStartedAt ?? Date())
        guard elapsed >= Constants.Keyboard.resultTimeout else { return }

        sendCommand(.cancel)
        clearRequestTracking()
        phase = .error("后台录音超时，请打开主程序")
        statusMessage = "后台录音超时，请打开主程序"
        scheduleReset()
    }

    // MARK: - Utils

    /// beta.50: 用户手动打开 App 后重置状态，准备重新录音
    func resetToIdle() {
        clearRequestTracking()
        activeResetTask?.cancel()
        activeResetTask = nil
        phase = .idle
        statusMessage = ""
        openURLDidFail = false
    }

    /// beta.46: scheduleReset 必须尊重 openURLDidFail 和 needsAppWakeup 状态
    /// 之前的 bug：scheduleReset 无条件在 2s 后重置到 idle，导致错误 UI 闪退
    private var activeResetTask: Task<Void, Never>?
    
    private func scheduleReset() {
        // 取消之前的重置任务（防止多个 reset 互相踩踏）
        activeResetTask?.cancel()
        
        activeResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Constants.Keyboard.statusClearDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            
            // 🔒 关键修复：如果用户需要手动唤醒 App，不要重置状态！
            // 这是之前 UI "闪一下就消失" 的根因
            if self.openURLDidFail || self.needsAppWakeup {
                return
            }
            
            if self.phase != .recording && self.phase != .processing {
                self.phase = .idle
                self.statusMessage = ""
            }
        }
    }
}
