// AudioDaemonService.swift
// VoxInput
//
// 主 App 后台音频守护进程：通过 App Group IPC 与键盘扩展通信

import Foundation
import AVFoundation

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

@MainActor
final class AudioDaemonService {

    private let defaults = AppGroup.sharedDefaults
    private let config = ConfigStore.shared
    private let recorder = AudioRecorder()
    private let networkMonitor = NetworkMonitor()

    private var pollTimer: Timer?
    private var heartbeatTimer: Timer?

    private var lastCommandID: Int = 0
    private var lastActivityAt: Date = Date()
    private var state: DaemonState = .idle

    private var processingTask: Task<Void, Never>?

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

        // 避免重启后重复执行旧命令
        lastCommandID = defaults.integer(forKey: AppGroup.ipcCommandIDKey)

        publishState(.idle, clearError: true)

        pollTimer = Timer.scheduledTimer(withTimeInterval: Constants.Daemon.commandPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollCommandIfNeeded()
                self?.checkIdleSleepIfNeeded()
            }
        }

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Constants.Daemon.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.writeHeartbeat()
            }
        }

        writeHeartbeat()
        SharedLogger.info("AudioDaemonService started")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        processingTask?.cancel()
        processingTask = nil

        recorder.cancel()
        releaseAudioSession()

        publishState(.dead, clearError: true)
        isStarted = false
        SharedLogger.info("AudioDaemonService stopped")
    }

    // MARK: - IPC Polling

    private func pollCommandIfNeeded() {
        let commandID = defaults.integer(forKey: AppGroup.ipcCommandIDKey)
        guard commandID > 0, commandID != lastCommandID else { return }

        let commandAt = defaults.double(forKey: AppGroup.ipcCommandAtKey)
        if commandAt > 0 {
            let age = Date().timeIntervalSince1970 - commandAt
            // 忽略超过 15 秒的陈旧指令，防止崩溃重启后误触发
            guard age <= 15 else {
                lastCommandID = commandID
                return
            }
        }

        lastCommandID = commandID
        guard let commandRaw = defaults.string(forKey: AppGroup.ipcCommandKey),
              let command = DaemonCommand(rawValue: commandRaw)
        else {
            return
        }

        touchActivity()

        switch command {
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
        // sleeping/dead 收到 start -> 先唤醒
        if state == .sleeping || state == .dead {
            publishState(.idle, clearError: true)
        }

        guard state == .idle else { return }

        do {
            try recorder.start()
            publishState(.recording, clearError: true)
            SharedLogger.info("daemon start recording")
        } catch {
            publishError("录音启动失败: \(error.localizedDescription)")
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
        }
    }

    private func handleCancelCommand() {
        recorder.cancel()
        processingTask?.cancel()
        processingTask = nil

        defaults.removeObject(forKey: AppGroup.ipcResultKey)
        defaults.synchronize()

        publishState(.idle, clearError: true)
        touchActivity()
        SharedLogger.info("daemon canceled")
    }

    // MARK: - Audio Processing

    private func processAudio(url: URL) async {
        defer {
            try? FileManager.default.removeItem(at: url)
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

        guard let timeout = config.daemonStandbyDuration.seconds else { return }

        let idleDuration = Date().timeIntervalSince(lastActivityAt)
        guard idleDuration >= timeout else { return }

        releaseAudioSession()
        publishState(.sleeping, clearError: true)
        SharedLogger.info("daemon enter sleeping after idle \(Int(idleDuration))s")
    }

    private func releaseAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func touchActivity() {
        lastActivityAt = Date()
        defaults.set(lastActivityAt.timeIntervalSince1970, forKey: AppGroup.ipcLastActiveAtKey)
        defaults.synchronize()
    }

    private func writeHeartbeat() {
        defaults.set(Date().timeIntervalSince1970, forKey: AppGroup.ipcHeartbeatKey)
        defaults.synchronize()
    }

    // MARK: - IPC Write Helpers

    private func publishState(_ newState: DaemonState, clearError: Bool) {
        state = newState
        defaults.set(newState.rawValue, forKey: AppGroup.ipcStateKey)
        if clearError {
            defaults.removeObject(forKey: AppGroup.ipcErrorKey)
        }
        defaults.synchronize()

        if newState == .idle || newState == .recording || newState == .processing {
            touchActivity()
        }
    }

    private func publishError(_ message: String) {
        state = .error
        defaults.set(DaemonState.error.rawValue, forKey: AppGroup.ipcStateKey)
        defaults.set(message, forKey: AppGroup.ipcErrorKey)
        defaults.synchronize()
        SharedLogger.error(message)
    }

    private func publishResult(_ text: String) {
        let nextID = defaults.integer(forKey: AppGroup.ipcResultIDKey) + 1
        defaults.set(text, forKey: AppGroup.ipcResultKey)
        defaults.set(nextID, forKey: AppGroup.ipcResultIDKey)
        defaults.synchronize()
    }
}
