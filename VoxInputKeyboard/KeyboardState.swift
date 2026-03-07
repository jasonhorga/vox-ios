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

    private(set) var phase: KeyboardPhase = .idle
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
    private var daemonStateObserver: DarwinNotificationObserver?
    private var lastResultID: Int = 0
    private var lastHeartbeatAt: TimeInterval = 0

    private var openAppHandler: ((URL) -> Bool)?
    private var insertTextHandler: ((String) -> Void)?

    /// 当前会话追踪（用于屏蔽旧状态抖动 + 超时兜底）
    private var isRequestInFlight = false
    private var hasSeenRecordingInCurrentRequest = false
    private var hasSentStopInCurrentRequest = false
    private var requestStartedAt: Date?
    private var startupAckTimeoutTask: Task<Void, Never>?
    private var requestTimeoutTask: Task<Void, Never>?

    // MARK: - Wiring

    /// 由 ViewController 注入桥接能力
    func bindHandlers(openApp: @escaping (URL) -> Bool, insertText: @escaping (String) -> Void) {
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
        daemonStateObserver?.stop()
        daemonStateObserver = nil
        clearRequestTracking()
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
            statusMessage = "请在系统设置中开启"完全访问""
            scheduleReset()
            return false
        }

        // 重置 openURL 失败标记
        openURLDidFail = false

        // 守护进程睡眠或心跳超时 -> 极速闪跳唤醒
        if shouldWakeMainApp() {
            phase = .processing
            statusMessage = "正在唤醒 Vox Input..."
            let opened = openMainAppForWakeup()
            if !opened {
                phase = .error("无法打开 Vox Input")
                statusMessage = "打开 Vox Input 失败，请手动打开应用"
                openURLDidFail = true
                // 不 scheduleReset，让用户看到手动跳转 UI
                return false
            }
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
        switch state {
        case "recording":
            hasSeenRecordingInCurrentRequest = true
            startupAckTimeoutTask?.cancel()
            startupAckTimeoutTask = nil
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
            // 新请求 start 后，daemon 可能短暂还在 idle，不能误判为 processing
            if isRequestInFlight, !hasSeenRecordingInCurrentRequest, !hasSentStopInCurrentRequest {
                return
            }
            if case .recording = phase {
                phase = .processing
                statusMessage = "识别中..."
            }

        case "sleeping", "dead":
            if isRequestInFlight || phase == .recording || phase == .processing {
                clearRequestTracking()
                phase = .error("守护进程已休眠")
                statusMessage = "守护进程已休眠，请重试"
                scheduleReset()
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

        guard lastHeartbeatAt > 0 else { return true }
        let delta = Date().timeIntervalSince1970 - lastHeartbeatAt
        return delta > Constants.Daemon.heartbeatTimeout
    }

    private func openMainAppForWakeup() -> Bool {
        guard let handler = openAppHandler,
              let url = URL(string: "voxinput://record?source=keyboard&mode=wakeup")
        else {
            return false
        }
        return handler(url)
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
        
        // beta.37: 启动超时通常意味着主 App 未能打开或守护进程无法启动
        // 显示手动跳转 UI 而非简单的"请重试"
        phase = .error("后台服务已休眠，请手动打开一次 Vox App 重新激活")
        statusMessage = "后台服务已休眠，请手动打开一次 Vox App 重新激活"
        // 不 scheduleReset，让 needsAppWakeup 的 UI 持续显示
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

    /// beta.37: 用户手动打开 App 后重置状态，准备重新录音
    func resetToIdle() {
        clearRequestTracking()
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

    func wakeupAppFromError() {
        guard needsAppWakeup else { return }
        openURLDidFail = false
        phase = .processing
        statusMessage = "正在唤醒 Vox Input..."
        let opened = openMainAppForWakeup()
        if !opened {
            openURLDidFail = true
            phase = .error("自动唤醒失败")
            statusMessage = "自动唤醒失败，请手动打开应用"
        }
    }

    private func scheduleReset() {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Constants.Keyboard.statusClearDelay * 1_000_000_000))
            if phase != .recording && phase != .processing {
                phase = .idle
                statusMessage = ""
                openURLDidFail = false
            }
        }
    }
}
