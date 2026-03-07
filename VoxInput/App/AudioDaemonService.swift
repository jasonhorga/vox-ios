// AudioDaemonService.swift
// VoxInput
//
// 主 App 后台音频守护进程：通过 App Group IPC 与键盘扩展通信

import Foundation
import AVFoundation
import UIKit

/// 守护进程状态
private enum DaemonState: String {
    case idle
    case recording
    case processing
    case error
    case sleeping
    case dead
}

/// IPC 指令
private enum DaemonCommand: String {
    case start
    case stop
    case cancel
}

private struct CommandSnapshot {
    let id: Int
    let command: DaemonCommand
    let commandAt: TimeInterval
}

@MainActor
final class AudioDaemonService {

    private let config = ConfigStore.shared
    private let recorder = DaemonAudioEngineRecorder()
    private let silentKeeper = SilentAudioKeeper()
    private let networkMonitor = NetworkMonitor()

    private let ipcQueue = DispatchQueue(label: "com.jasonhorga.vox.daemon.ipc", qos: .userInitiated)

    private var pollTimer: Timer?
    private var heartbeatTimer: Timer?

    private var lastCommandID: Int = 0
    private var lastActivityAt: Date = Date()
    private var state: DaemonState = .idle

    private var processingTask: Task<Void, Never>?
    private var wakeObserver: DarwinNotificationObserver?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    /// 标记守护进程是否已初始化
    private(set) var isStarted = false

    func start() {
        guard !isStarted else {
            reevaluateSilentKeeper(trigger: "start-already")
            return
        }
        isStarted = true

        recorder.onMaxDurationReached = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleStopCommand()
            }
        }

        recorder.onRuntimeError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.publishError("录音运行时异常: \(message)")
                self?.reevaluateSilentKeeper(trigger: "runtime-error")
            }
        }

        // 避免重启后重复执行旧命令
        bootstrapLastCommandID()

        setupDarwinWakeObserver()
        observeLifecycleNotifications()
        publishState(.idle, clearError: true)

        pollTimer = Timer.scheduledTimer(withTimeInterval: Constants.Daemon.commandPollInterval, repeats: true) { [weak self] _ in
            self?.pollCommandIfNeeded()
            Task { @MainActor [weak self] in
                self?.checkIdleSleepIfNeeded()
            }
        }

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Constants.Daemon.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.writeHeartbeat()
        }

        writeHeartbeat()
        reevaluateSilentKeeper(trigger: "start")
        SharedLogger.info("AudioDaemonService started")
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)

        pollTimer?.invalidate()
        pollTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        processingTask?.cancel()
        processingTask = nil

        wakeObserver?.stop()
        wakeObserver = nil

        recorder.cancel()
        stopSilentKeeperAndReleaseSession()
        endBackgroundKeepAlive()

        publishState(.dead, clearError: true)
        isStarted = false
        SharedLogger.info("AudioDaemonService stopped")
    }

    /// 在 URL Scheme 唤醒时，趁 App 还在前台，提前激活音频会话并开始后台任务。
    /// 这是解决时序竞争的关键：在 App 退入后台之前抢先占住音频会话。
    ///
    /// beta.32: 改为 async，等系统充分完成前台切换后再激活音频会话，
    /// 并使用多次重试 + 递增延迟，彻底消除 OSStatus 560557684 竞争。
    /// 返回 true 表示音频会话已确认激活。
    func primeForBackgroundRecording() async -> Bool {
        beginBackgroundKeepAlive(reason: "url-scheme-prime")

        // 唤醒 daemon 状态机
        if state == .sleeping || state == .dead {
            publishState(.idle, clearError: true)
        }
        touchActivity()

        // 等待系统完成前台切换（关键！不能立刻激活，系统需要时间）
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        let session = AVAudioSession.sharedInstance()
        let retryDelaysNs: [UInt64] = [
            200_000_000,  // 0.2s
            300_000_000,  // 0.3s
            500_000_000,  // 0.5s
            800_000_000,  // 0.8s
        ]

        for attempt in 1...5 {
            do {
                try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth])
                try session.setActive(true, options: [])

                // 验证会话确实处于活跃状态
                let isOtherPlaying = session.isOtherAudioPlaying
                SharedLogger.info("audio session primed on attempt \(attempt)/5 (otherAudioPlaying=\(isOtherPlaying))")

                // 启动静音保活
                do {
                    try startSilentKeeperIfNeeded(trigger: "url-scheme-prime-attempt-\(attempt)")
                } catch {
                    SharedLogger.error("silent keeper start failed after session prime: \(error.localizedDescription)")
                    // 静音保活失败不影响主流程，session 已经激活
                }

                SharedLogger.info("audio session primed via URL scheme while app is foreground (attempt \(attempt))")
                return true
            } catch {
                SharedLogger.error("primeForBackgroundRecording attempt \(attempt)/5 failed: \(error.localizedDescription)")
                if attempt < 5 {
                    try? await Task.sleep(nanoseconds: retryDelaysNs[attempt - 1])
                }
            }
        }

        SharedLogger.error("primeForBackgroundRecording: all 5 attempts failed")
        return false
    }

    // MARK: - Darwin Wake Observer

    private func setupDarwinWakeObserver() {
        wakeObserver = DarwinNotificationObserver(name: .wakeUpAndRecord) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleWakeFromKeyboard()
            }
        }
        wakeObserver?.start()
        SharedLogger.info("Darwin wake observer started")
    }

    private func handleWakeFromKeyboard() {
        beginBackgroundKeepAlive(reason: "darwin-wake")
        touchActivity()
        if state == .sleeping || state == .dead {
            publishState(.idle, clearError: true)
        }
        // 预先激活音频会话，这样当 start 命令到达时会话已经准备好
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth])
            try session.setActive(true, options: [])
            try startSilentKeeperIfNeeded(trigger: "darwin-wake-prime")
            SharedLogger.info("audio session primed from Darwin wake")
        } catch {
            SharedLogger.error("Darwin wake audio prime failed: \(error.localizedDescription)")
        }
    }

    // MARK: - IPC Polling

    private func bootstrapLastCommandID() {
        ipcQueue.async { [weak self] in
            guard let self else { return }
            let existing = AppGroup.sharedDefaults.integer(forKey: AppGroup.ipcCommandIDKey)
            Task { @MainActor [weak self] in
                self?.lastCommandID = existing
            }
        }
    }

    private func pollCommandIfNeeded() {
        ipcQueue.async { [weak self] in
            guard let self else { return }
            let defaults = AppGroup.sharedDefaults
            let commandID = defaults.integer(forKey: AppGroup.ipcCommandIDKey)
            guard commandID > 0 else { return }

            guard let commandRaw = defaults.string(forKey: AppGroup.ipcCommandKey),
                  let command = DaemonCommand(rawValue: commandRaw)
            else { return }

            let commandAt = defaults.double(forKey: AppGroup.ipcCommandAtKey)
            let snapshot = CommandSnapshot(id: commandID, command: command, commandAt: commandAt)

            Task { @MainActor [weak self] in
                self?.applyCommandSnapshot(snapshot)
            }
        }
    }

    private func applyCommandSnapshot(_ snapshot: CommandSnapshot) {
        guard snapshot.id != lastCommandID else { return }

        if snapshot.commandAt > 0 {
            let age = Date().timeIntervalSince1970 - snapshot.commandAt
            // 忽略超过 15 秒的陈旧指令，防止崩溃重启后误触发
            if age > 15 {
                lastCommandID = snapshot.id
                return
            }
        }

        lastCommandID = snapshot.id
        touchActivity()

        switch snapshot.command {
        case .start:
            handleStartCommand()
        case .stop:
            Task { await handleStopCommand() }
        case .cancel:
            handleCancelCommand()
        }
    }

    // MARK: - State Machine

    private func handleStartCommand() {
        beginBackgroundKeepAlive(reason: "recording")

        // sleeping/dead/error 收到 start -> 先唤醒
        if state == .sleeping || state == .dead || state == .error {
            publishState(.idle, clearError: true)
        }

        guard state == .idle else {
            SharedLogger.info("忽略 start：当前状态=\(state.rawValue)")
            return
        }

        do {
            try ensureSessionPrimedForBackgroundStart()
            try recorder.start()
            publishState(.recording, clearError: true)
            SharedLogger.info("daemon start recording")
            stopSilentKeeperIfRunning(trigger: "recording-started")
        } catch {
            // 任何失败都立刻落盘 error 并广播，确保键盘侧不会无限等待
            publishError("录音启动失败: \(error.localizedDescription)")
            reevaluateSilentKeeper(trigger: "start-failed")
            endBackgroundKeepAlive()
        }
    }

    private func handleStopCommand() async {
        guard state == .recording else { return }

        do {
            let url = try recorder.stop()
            publishState(.processing, clearError: true)
            SharedLogger.info("daemon stop -> processing")

            processingTask?.cancel()
            processingTask = Task { [weak self] in
                await self?.processAudio(url: url)
            }
        } catch {
            publishError("停止录音失败: \(error.localizedDescription)")
            publishState(.idle, clearError: false)
            reevaluateSilentKeeper(trigger: "stop-failed")
        }
    }

    private func handleCancelCommand() {
        recorder.cancel()
        processingTask?.cancel()
        processingTask = nil

        ipcQueue.async {
            AppGroup.sharedDefaults.removeObject(forKey: AppGroup.ipcResultKey)
        }

        publishState(.idle, clearError: true)
        touchActivity()
        reevaluateSilentKeeper(trigger: "cancel")
        endBackgroundKeepAlive()
        SharedLogger.info("daemon canceled")
    }

    // MARK: - Audio Processing

    private func processAudio(url: URL) async {
        defer {
            try? FileManager.default.removeItem(at: url)
            endBackgroundKeepAlive()
        }

        do {
            let rawText = try await transcribeViaPreferredProvider(audioURL: url)
            let formatted = TextFormatter.format(rawText)

            publishResult(formatted)
            publishState(.idle, clearError: true)
            touchActivity()
            reevaluateSilentKeeper(trigger: "processing-done")
            SharedLogger.info("daemon processing done")
        } catch {
            publishError("识别失败: \(error.localizedDescription)")
            publishState(.idle, clearError: false)
            reevaluateSilentKeeper(trigger: "processing-failed")
        }
    }

    /// 优先 Qwen ASR；在离线或 Qwen 失败时降级到工厂策略
    private func transcribeViaPreferredProvider(audioURL: URL) async throws -> String {
        if networkMonitor.isConnected {
            let key = config.qwenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                let provider = QwenASR(apiKey: key, model: config.qwenModel)
                do {
                    return try await provider.transcribe(audioURL: audioURL)
                } catch {
                    SharedLogger.error("Qwen ASR 失败，降级通用策略: \(error.localizedDescription)")
                }
            }
        }

        return try await ASRFactory.transcribe(
            audioURL: audioURL,
            config: .shared,
            networkAvailable: networkMonitor.isConnected
        )
    }

    // MARK: - Idle Sleep

    private func checkIdleSleepIfNeeded() {
        guard state == .idle else { return }

        guard let timeout = config.daemonStandbyDuration.seconds else {
            reevaluateSilentKeeper(trigger: "standby-never")
            return
        }

        let idleDuration = Date().timeIntervalSince(lastActivityAt)
        guard idleDuration >= timeout else { return }

        stopSilentKeeperAndReleaseSession()
        publishState(.sleeping, clearError: true)
        SharedLogger.info("daemon enter sleeping after idle \(Int(idleDuration))s")
    }

    // MARK: - Background Task

    private func beginBackgroundKeepAlive(reason: String) {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "VoxDaemon-\(reason)") { [weak self] in
            Task { @MainActor [weak self] in
                self?.endBackgroundKeepAlive()
            }
        }
        SharedLogger.info("background task started: \(reason)")
    }

    private func endBackgroundKeepAlive() {
        guard backgroundTaskID != .invalid else { return }
        let taskID = backgroundTaskID
        backgroundTaskID = .invalid
        UIApplication.shared.endBackgroundTask(taskID)
        SharedLogger.info("background task ended")
    }

    // MARK: - Audio Session / Silent Keeper

    private func ensureSessionPrimedForBackgroundStart() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth])

        // 重试激活音频会话，应对后台转换时序竞争（OSStatus 560557684）
        // beta.32: 增加重试次数和延迟时间
        let retryDelays: [TimeInterval] = [0.15, 0.25, 0.40, 0.60]
        var lastError: Error?
        for attempt in 1...5 {
            do {
                try session.setActive(true, options: [])
                if attempt > 1 {
                    SharedLogger.info("audio session activated on retry attempt \(attempt)")
                }
                // 会话确认激活后再启动静音保活
                try startSilentKeeperIfNeeded(trigger: "prime-before-start")
                return
            } catch {
                lastError = error
                SharedLogger.error("audio session activation attempt \(attempt)/5 failed: \(error.localizedDescription)")
                if attempt < 5 {
                    // 短暂等待让系统完成前后台切换
                    Thread.sleep(forTimeInterval: retryDelays[attempt - 1])
                }
            }
        }
        throw lastError ?? VoxError.recordingFailed("音频会话激活失败（5次重试均失败）")
    }

    private func startSilentKeeperIfNeeded(trigger: String) throws {
        try silentKeeper.startIfNeeded()
        SharedLogger.info("silent keeper started (\(trigger))")
    }

    private func stopSilentKeeperIfRunning(trigger: String) {
        silentKeeper.stop()
        SharedLogger.info("silent keeper stopped (\(trigger))")
    }

    private func stopSilentKeeperAndReleaseSession() {
        silentKeeper.stop()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            SharedLogger.error("releaseAudioSession failed: \(error.localizedDescription)")
        }
    }

    private func reevaluateSilentKeeper(trigger: String) {
        let appState = UIApplication.shared.applicationState
        let isBackground = appState == .background
        let standbyAllowsKeepAlive = state == .idle

        guard isBackground, standbyAllowsKeepAlive else {
            stopSilentKeeperIfRunning(trigger: "reevaluate-stop-\(trigger)")
            return
        }

        do {
            try startSilentKeeperIfNeeded(trigger: "reevaluate-\(trigger)")
        } catch {
            publishError("静音保活启动失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Lifecycle

    private func observeLifecycleNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(onWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(onDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(onWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(onDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc
    private func onWillResignActive() {
        // 必须在真正进入后台前抢先启动保活音频，降低被系统立刻挂起概率
        if state == .idle {
            do {
                try startSilentKeeperIfNeeded(trigger: "will-resign-active")
            } catch {
                publishError("静音保活预启动失败: \(error.localizedDescription)")
            }
        }
    }

    @objc
    private func onDidEnterBackground() {
        reevaluateSilentKeeper(trigger: "did-enter-background")
    }

    @objc
    private func onWillEnterForeground() {
        reevaluateSilentKeeper(trigger: "will-enter-foreground")
    }

    @objc
    private func onDidBecomeActive() {
        reevaluateSilentKeeper(trigger: "did-become-active")
    }

    // MARK: - IPC + Helpers

    private func touchActivity() {
        lastActivityAt = Date()
        let ts = lastActivityAt.timeIntervalSince1970
        ipcQueue.async {
            AppGroup.sharedDefaults.set(ts, forKey: AppGroup.ipcLastActiveAtKey)
        }
    }

    private func writeHeartbeat() {
        let ts = Date().timeIntervalSince1970
        ipcQueue.async {
            AppGroup.sharedDefaults.set(ts, forKey: AppGroup.ipcHeartbeatKey)
        }
    }

    // MARK: - IPC Write Helpers

    private func publishState(_ newState: DaemonState, clearError: Bool) {
        state = newState

        ipcQueue.async {
            let defaults = AppGroup.sharedDefaults
            defaults.set(newState.rawValue, forKey: AppGroup.ipcStateKey)
            if clearError {
                defaults.removeObject(forKey: AppGroup.ipcErrorKey)
            }
            AppGroupDarwinNotification.daemonStateDidChange.post()
        }

        if newState == .idle || newState == .recording || newState == .processing {
            touchActivity()
        }
    }

    private func publishError(_ message: String) {
        state = .error

        ipcQueue.async {
            let defaults = AppGroup.sharedDefaults
            defaults.set(DaemonState.error.rawValue, forKey: AppGroup.ipcStateKey)
            defaults.set(message, forKey: AppGroup.ipcErrorKey)
            AppGroupDarwinNotification.daemonStateDidChange.post()
        }

        SharedLogger.error(message)
    }

    private func publishResult(_ text: String) {
        ipcQueue.async {
            let defaults = AppGroup.sharedDefaults
            let nextID = defaults.integer(forKey: AppGroup.ipcResultIDKey) + 1
            defaults.set(text, forKey: AppGroup.ipcResultKey)
            defaults.set(nextID, forKey: AppGroup.ipcResultIDKey)
            AppGroupDarwinNotification.daemonStateDidChange.post()
        }
    }
}
