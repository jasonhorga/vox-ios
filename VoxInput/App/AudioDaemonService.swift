// AudioDaemonService.swift
// VoxInput
//
// 主 App 后台音频守护进程：通过 App Group IPC 与键盘扩展通信
// beta.40: Typeless Always-On 架构（prime 常驻引擎 + start/stop 软开关）

import AVFoundation
import Foundation
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
    private let networkMonitor = NetworkMonitor()

    private let ipcQueue = DispatchQueue(label: "com.jasonhorga.vox.daemon.ipc", qos: .userInitiated)

    private var pollTimer: Timer?
    private var heartbeatTimer: DispatchSourceTimer?

    private var lastCommandID: Int = 0
    private var lastActivityAt: Date = Date()
    private var state: DaemonState = .idle

    private var processingTask: Task<Void, Never>?
    private var wakeObserver: DarwinNotificationObserver?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    /// 标记守护进程是否已初始化
    private(set) var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        recorder.onMaxDurationReached = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleStopCommand()
            }
        }

        recorder.onRuntimeError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.publishError("录音运行时异常: \(message)")
            }
        }

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

        heartbeatTimer = DispatchSource.makeTimerSource(queue: ipcQueue)
        heartbeatTimer?.schedule(deadline: .now(), repeating: Constants.Daemon.heartbeatInterval)
        heartbeatTimer?.setEventHandler { [weak self] in
            self?.writeHeartbeat()
        }
        heartbeatTimer?.resume()

        writeHeartbeat()
        SharedLogger.info("AudioDaemonService started")
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)

        pollTimer?.invalidate()
        pollTimer = nil
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        processingTask?.cancel()
        processingTask = nil

        wakeObserver?.stop()
        wakeObserver = nil

        recorder.cancel(keepEngineAlive: false)
        endBackgroundKeepAlive()

        publishState(.dead, clearError: true)
        isStarted = false
        SharedLogger.info("AudioDaemonService stopped")
    }

    /// beta.40: 在 URL Scheme 唤醒时，提前 prime 引擎（input tap 常驻）
    func primeForBackgroundRecording() async -> Bool {
        beginBackgroundKeepAlive(reason: "url-scheme-prime")

        if state == .sleeping || state == .dead {
            publishState(.idle, clearError: true)
        }
        touchActivity()

        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        let retryDelaysNs: [UInt64] = [200_000_000, 300_000_000, 500_000_000, 800_000_000]
        for attempt in 1 ... 5 {
            do {
                try recorder.primeIfNeeded()
                SharedLogger.info("daemon primeForBackgroundRecording success (attempt \(attempt)/5)")
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

        Task { @MainActor in
            await primeEngineWithRetry(trigger: "darwin-wake")
        }
    }

    /// beta.40: wake 时重试 prime 常驻引擎
    private func primeEngineWithRetry(trigger: String) async {
        let retryDelays: [UInt64] = [100_000_000, 200_000_000, 400_000_000, 800_000_000]

        for attempt in 1 ... 5 {
            do {
                try recorder.primeIfNeeded()
                SharedLogger.info("\(trigger) prime success (attempt \(attempt)/5)")
                return
            } catch {
                SharedLogger.error("\(trigger) prime attempt \(attempt)/5 failed: \(error.localizedDescription)")
                if attempt < 5 {
                    try? await Task.sleep(nanoseconds: retryDelays[attempt - 1])
                }
            }
        }

        SharedLogger.error("\(trigger): all 5 prime attempts failed")
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

        if state == .sleeping || state == .dead || state == .error {
            publishState(.idle, clearError: true)
        }

        guard state == .idle else {
            SharedLogger.info("忽略 start：当前状态=\(state.rawValue)")
            return
        }

        Task { @MainActor in
            await startRecordingWithRetry()
        }
    }

    /// beta.40: start 只切换采集，不负责引擎生命周期
    private func startRecordingWithRetry() async {
        let retryDelays: [UInt64] = [200_000_000, 400_000_000, 800_000_000]

        for attempt in 1 ... 4 {
            do {
                try recorder.primeIfNeeded()
                try recorder.start()
                publishState(.recording, clearError: true)
                SharedLogger.info("daemon start capturing (attempt \(attempt))")
                return
            } catch {
                SharedLogger.error("录音启动 attempt \(attempt)/4 失败: \(error.localizedDescription)")

                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: retryDelays[attempt - 1])
                    continue
                }

                if let wakeupHint = backgroundWakeupHint(from: error) {
                    publishError(wakeupHint)
                } else {
                    publishError("录音启动失败: \(error.localizedDescription)")
                }
                endBackgroundKeepAlive()
            }
        }
    }

    private func handleStopCommand() async {
        guard state == .recording else { return }

        do {
            let url = try recorder.stop()
            publishState(.processing, clearError: true)
            SharedLogger.info("daemon stop capture -> processing")

            processingTask?.cancel()
            processingTask = Task { [weak self] in
                await self?.processAudio(url: url)
            }
        } catch {
            publishError("停止录音失败: \(error.localizedDescription)")
            publishState(.idle, clearError: false)
        }
    }

    private func handleCancelCommand() {
        let keepAlive = shouldKeepEngineAliveAfterCancel()

        recorder.cancel(keepEngineAlive: keepAlive)
        processingTask?.cancel()
        processingTask = nil

        ipcQueue.async {
            AppGroup.sharedDefaults.removeObject(forKey: AppGroup.ipcResultKey)
        }

        if keepAlive {
            publishState(.idle, clearError: true)
        } else {
            publishState(.sleeping, clearError: true)
        }

        touchActivity()
        endBackgroundKeepAlive()
        SharedLogger.info("daemon canceled (keepAlive=\(keepAlive))")
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
            SharedLogger.info("daemon processing done")
        } catch {
            publishError("识别失败: \(error.localizedDescription)")
            publishState(.idle, clearError: false)
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
            return
        }

        let idleDuration = Date().timeIntervalSince(lastActivityAt)
        guard idleDuration >= timeout else { return }

        recorder.sleepShutdown()
        publishState(.sleeping, clearError: true)
        SharedLogger.info("daemon enter sleeping after idle \(Int(idleDuration))s")
    }

    private func shouldKeepEngineAliveAfterCancel() -> Bool {
        // 仅在后台且允许待机时才保活；前台 cancel / 立即休眠场景直接关闭引擎
        let isBackground = UIApplication.shared.applicationState == .background

        guard isBackground else { return false }

        if config.daemonStandbyDuration.seconds == nil {
            return true
        }

        let idleDuration = Date().timeIntervalSince(lastActivityAt)
        let timeout = config.daemonStandbyDuration.seconds ?? 0
        return idleDuration < timeout
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

    // MARK: - Error Translation

    private static let audioSessionIncompatibleOperationError: Int32 = 560557684
    private static let backgroundWakeupRecoveryMessage = "后台服务已休眠，请手动打开一次 Vox App 重新激活"
    private static let cannotInterruptOthersHint = "cannot interrupt others"

    private func translatedAudioSessionActivationError(_ error: Error?) -> VoxError? {
        guard let error else { return nil }

        if let nsError = error as NSError? {
            if nsError.code == Self.audioSessionIncompatibleOperationError {
                return .recordingFailed(Self.backgroundWakeupRecoveryMessage)
            }

            let lowercased = nsError.localizedDescription.lowercased()
            if lowercased.contains(Self.cannotInterruptOthersHint) {
                return .recordingFailed(Self.backgroundWakeupRecoveryMessage)
            }
        }

        return nil
    }

    private func backgroundWakeupHint(from error: Error) -> String? {
        if let translated = translatedAudioSessionActivationError(error),
           case .recordingFailed(let message) = translated {
            return message
        }

        let localized = error.localizedDescription
        if localized.contains(Self.backgroundWakeupRecoveryMessage) {
            return Self.backgroundWakeupRecoveryMessage
        }

        return nil
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
        // beta.40: 尽早 prime，帮助后台黄灯连续性
        Task { @MainActor in
            _ = await primeForBackgroundRecording()
        }
    }

    @objc
    private func onDidEnterBackground() {
        if state == .idle {
            Task { @MainActor in
                try? recorder.primeIfNeeded()
            }
        }
    }

    @objc
    private func onWillEnterForeground() {
        // no-op: 进入前台不主动关引擎
    }

    @objc
    private func onDidBecomeActive() {
        // no-op
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
