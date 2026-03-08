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
}

@Observable
@MainActor
final class KeyboardState {

    // MARK: - Observable State

    private(set) var phase: KeyboardPhase = .idle {
        didSet {
            handlePhaseTransition(from: oldValue, to: phase)
        }
    }
    private(set) var statusMessage: String = ""

    /// 当前音频电平（键盘不再本地录音，保留占位）
    private(set) var currentLevel: Float = 0.0
    /// 电平历史（保留占位，兼容旧 UI）
    private(set) var levelHistory: [Float] = []

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
    private var waveformTimer: Timer?
    private var daemonStateObserver: DarwinNotificationObserver?
    private var lastResultID: Int = 0
    private var lastHeartbeatAt: TimeInterval = 0

    private var openAppHandler: ((URL, String) -> Bool)?
    private var insertTextHandler: ((String) -> Void)?

    /// 当前会话追踪（用于屏蔽旧状态抖动 + 超时兜底）
    private var isRequestInFlight = false
    private var hasSeenRecordingInCurrentRequest = false
    private var hasSentStopInCurrentRequest = false
    private var requestStartedAt: Date?
    private var startupAckTimeoutTask: Task<Void, Never>?
    private var requestTimeoutTask: Task<Void, Never>?

    /// 唤醒主 App 期间的状态锁，避免轮询状态机重复触发唤醒
    private var isWakingUp: Bool = false

    // MARK: - Wiring

    /// 由 ViewController 注入桥接能力
    func bindHandlers(openApp: @escaping (URL, String) -> Bool, insertText: @escaping (String) -> Void) {
        self.openAppHandler = openApp
        self.insertTextHandler = insertText
    }

    // MARK: - Lifecycle

    func activate() {
        config.reload()
        checkEnvironment()
        startIPCMonitoringIfNeeded()
        startDarwinStateObserverIfNeeded()
        updateFromIPC()
    }

    func deactivate() {
        ipcTimer?.invalidate()
        ipcTimer = nil
        stopFakeWaveformAnimation(resetToZero: true)
        daemonStateObserver?.stop()
        daemonStateObserver = nil
        clearRequestTracking()
        activeResetTask?.cancel()
        activeResetTask = nil
        wakeupFallbackTask?.cancel()
        wakeupFallbackTask = nil
        isWakingUp = false
    }

    // MARK: - Environment

    func checkEnvironment(systemHasFullAccess: Bool? = nil) {
        if let value = systemHasFullAccess {
            hasFullAccess = value
        } else {
            probeFullAccessAsync()
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

        // beta.46: 重置所有挂起状态
        openURLDidFail = false
        activeResetTask?.cancel()
        wakeupFallbackTask?.cancel()

        // 守护进程睡眠或心跳超时 -> 极速闪跳唤醒
        if shouldWakeMainApp() {
            isWakingUp = true
            phase = .processing
            statusMessage = "正在唤醒 Vox Input..."
            let _ = openMainAppForWakeup()
            scheduleWakeupSilentFailureFallback()
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
    }

    func cancelRecording() {
        sendCommand(.cancel)
        clearRequestTracking()
        phase = .idle
        statusMessage = ""
        currentLevel = 0
        openURLDidFail = false
    }

    // MARK: - Fake Waveform Animation

    private func handlePhaseTransition(from oldPhase: KeyboardPhase, to newPhase: KeyboardPhase) {
        let wasRecording: Bool
        if case .recording = oldPhase {
            wasRecording = true
        } else {
            wasRecording = false
        }

        let isRecording: Bool
        if case .recording = newPhase {
            isRecording = true
        } else {
            isRecording = false
        }

        if isRecording, !wasRecording {
            startFakeWaveformAnimation()
        } else if wasRecording, !isRecording {
            stopFakeWaveformAnimation(resetToZero: false)
        }
    }

    private func startFakeWaveformAnimation() {
        guard waveformTimer == nil else { return }

        let maxSamples = Constants.Keyboard.waveformSampleCount
        if levelHistory.count != maxSamples {
            levelHistory = Array(repeating: 0.0, count: maxSamples)
        }

        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            let randomLevel = Float.random(in: 0.1...0.8)
            currentLevel = randomLevel
            levelHistory.append(randomLevel)
            if levelHistory.count > maxSamples {
                levelHistory.removeFirst()
            }
        }
    }

    private func stopFakeWaveformAnimation(resetToZero: Bool) {
        waveformTimer?.invalidate()
        waveformTimer = nil

        let maxSamples = Constants.Keyboard.waveformSampleCount
        currentLevel = 0.0

        if resetToZero {
            levelHistory = Array(repeating: 0.0, count: maxSamples)
            return
        }

        var smoothed = levelHistory.suffix(maxSamples).map { max(0.0, $0 * 0.35) }
        if smoothed.count < maxSamples {
            smoothed = Array(repeating: 0.0, count: maxSamples - smoothed.count) + smoothed
        }
        levelHistory = smoothed
    }

    // MARK: - IPC Polling

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
                resultText: defaults.string(forKey: AppGroup.ipcResultKey)
            )

            Task { @MainActor [weak self] in
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: IPCSnapshot) {
        daemonState = snapshot.state
        daemonErrorMessage = snapshot.errorMessage
        lastHeartbeatAt = snapshot.heartbeat

        if snapshot.resultID > 0,
           snapshot.resultID != lastResultID,
           let inserted = snapshot.resultText,
           !inserted.isEmpty {
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

        syncPhaseWithDaemonState(snapshot.state)
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
        // 这是之前"错误界面闪一下就回到按住说话"的根因之一
        if openURLDidFail {
            // 唯一例外：守护进程恢复了（变成 idle/recording），说明用户已手动打开主 App
            if state == "recording" || state == "idle" {
                // 守护进程已恢复，自动清除错误状态
                openURLDidFail = false
                isWakingUp = false
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
            openURLDidFail = false
            isWakingUp = false
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
            // 守护进程恢复到 idle 且之前有 wakeup，说明唤醒成功
            if isWakingUp {
                isWakingUp = false
                openURLDidFail = false
                phase = .idle
                statusMessage = ""
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
            // 🔒 唤醒期间不覆盖状态
            if isWakingUp { return }
            
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

    private func shouldWakeMainApp() -> Bool {
        if daemonState == "sleeping" || daemonState == "dead" || daemonState.isEmpty {
            return true
        }
        if lastHeartbeatAt <= 0 {
            return true
        }
        let delta = Date().timeIntervalSince1970 - lastHeartbeatAt
        if delta > Constants.Daemon.heartbeatTimeout {
            return true
        }
        return false
    }

    private func openMainAppForWakeup() -> Bool {
        guard let handler = openAppHandler,
              let url = URL(string: "voxinput://record?source=keyboard&mode=wakeup")
        else {
            return false
        }
        return handler(url, "B")
    }

    /// 设置 Debug 跳转状态提示（供 UI 点击即时反馈）
    func markDebugJumpStatus(method: String) {
        statusMessage = "正在触发 方法 \(method.uppercased())..."
    }

    /// Debug 实验室：按指定方法触发跳转（A/B/C）
    func triggerDebugJump(method: String) {
        let normalized = method.uppercased()
        guard let handler = openAppHandler,
              let url = URL(string: "voxinput://record?source=keyboard&mode=wakeup")
        else {
            statusMessage = "跳转处理器未就绪"
            return
        }

        markDebugJumpStatus(method: normalized)
        let opened = handler(url, normalized)
        if !opened {
            statusMessage = "方法 \(normalized) 触发失败"
        }
    }

    /// beta.46: 唤醒超时后的回退处理
    /// 修复：不再提前清除 isWakingUp，让 syncPhaseWithDaemonState 的 sleeping/dead 分支不会重复触发
    private var wakeupFallbackTask: Task<Void, Never>?
    
    private func scheduleWakeupSilentFailureFallback() {
        wakeupFallbackTask?.cancel()
        wakeupFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            
            // 只在仍然处于唤醒等待状态时才触发回退
            guard self.isWakingUp else { return }
            guard self.phase == .processing else { return }
            
            // 设置失败标记（这会锁住 syncPhaseWithDaemonState 不再覆盖 UI）
            self.openURLDidFail = true
            self.isWakingUp = false
            self.phase = .error("无法自动唤醒 Vox Input")
            self.statusMessage = "跳转被系统拦截，请手动打开应用"
            // 注意：不调用 scheduleReset()，让错误 UI 持续显示
            // 用户必须通过 SwiftUI Link 手动跳转或点击"重新录音"
        }
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

        SharedLogger.info("[KeyboardState] startup ack timeout, retry wakeup via openURL")

        isWakingUp = true
        phase = .processing
        statusMessage = "正在唤醒 Vox Input..."
        let _ = openMainAppForWakeup()
        scheduleWakeupSilentFailureFallback()
    }

    private func handleRequestTimeoutIfNeeded() {
        guard isRequestInFlight else { return }
        guard phase == .recording || phase == .processing else {
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

    // MARK: - Permission checks

    private func probeFullAccessAsync() {
        ipcQueue.async { [weak self] in
            let probeKey = "vox.keyboard.accessCheck"
            let defaults = AppGroup.sharedDefaults
            defaults.set(true, forKey: probeKey)
            let hasAccess = defaults.object(forKey: probeKey) != nil

            Task { @MainActor [weak self] in
                self?.hasFullAccess = hasAccess
            }
        }
    }

    // MARK: - Utils

    /// beta.46: 用户手动打开 App 后重置状态，准备重新录音
    func resetToIdle() {
        clearRequestTracking()
        activeResetTask?.cancel()
        activeResetTask = nil
        wakeupFallbackTask?.cancel()
        wakeupFallbackTask = nil
        isWakingUp = false
        phase = .idle
        statusMessage = ""
        openURLDidFail = false
    }

    /// beta.37: 所有自动 openURL 策略均失败后，由 ViewController 调用
    func markOpenURLFailed() {
        guard needsAppWakeup || phase == .processing else { return }
        openURLDidFail = true
        if phase == .processing {
            phase = .error("后台服务已休眠，请手动打开一次 Vox App 重新激活")
            statusMessage = "自动唤醒失败，请手动打开应用"
        }
        SharedLogger.error("[openURL] 所有自动策略失败，切换到手动跳转 UI")
    }

    /// beta.46: 从错误状态重试唤醒
    func wakeupAppFromError() {
        guard openURLDidFail || needsAppWakeup else { return }
        isWakingUp = true
        openURLDidFail = false
        activeResetTask?.cancel()  // 取消任何挂起的 reset
        phase = .processing
        statusMessage = "正在唤醒 Vox Input..."
        let opened = openMainAppForWakeup()
        if !opened {
            isWakingUp = false
            openURLDidFail = true
            phase = .error("自动唤醒失败")
            statusMessage = "自动唤醒失败，请手动打开应用"
            return
        }
        scheduleWakeupSilentFailureFallback()
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
