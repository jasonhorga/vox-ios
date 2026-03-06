// AppState.swift
// VoxInput
//
// 全局状态管理 + Pipeline 编排
// 录音 → ASR → PostProcessor(翻译) → TextFormatter → ClipboardOutput

import Foundation
import Observation
import AVFoundation

/// 录音流程状态
enum RecordingState: Equatable {
    case idle
    case recording
    case processing
}

@Observable
@MainActor
final class AppState {

    // MARK: - 可观察状态

    private(set) var recordingState: RecordingState = .idle
    private(set) var lastResult: String?
    private(set) var lastError: VoxError?

    var showError: Bool = false
    var showResult: Bool = false

    /// 处理进度描述（用于 UI 显示）
    private(set) var statusMessage: String = ""

    // MARK: - 子模块

    let audioRecorder = AudioRecorder()
    let networkMonitor = NetworkMonitor()
    let config = ConfigStore.shared
    let historyManager = HistoryManager.shared

    // MARK: - 录音控制

    func startRecording() async {
        guard recordingState == .idle else { return }
        guard await checkMicrophonePermission() else { return }

        do {
            HapticFeedback.shared.recordStart()

            try audioRecorder.start()
            recordingState = .recording
            statusMessage = "录音中..."

            audioRecorder.silenceDetector.onSilenceTimeout = { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.stopRecording()
                }
            }

            audioRecorder.onMaxDurationReached = { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.stopRecording()
                }
            }

        } catch let error as VoxError {
            handleError(error)
        } catch {
            handleError(.recordingFailed(error.localizedDescription))
        }
    }

    func stopRecording() async {
        guard recordingState == .recording else { return }

        HapticFeedback.shared.recordStop()

        do {
            let audioURL = try audioRecorder.stop()
            recordingState = .processing
            statusMessage = "正在识别..."
            await processPipeline(audioURL: audioURL)
        } catch let error as VoxError {
            handleError(error)
            recordingState = .idle
        } catch {
            handleError(.unknown(error.localizedDescription))
            recordingState = .idle
        }
    }

    func toggleRecording() async {
        switch recordingState {
        case .idle:
            await startRecording()
        case .recording:
            await stopRecording()
        case .processing:
            break
        }
    }

    func cancelRecording() {
        audioRecorder.cancel()
        recordingState = .idle
        statusMessage = ""
    }

    // MARK: - 处理 Pipeline

    private func processPipeline(audioURL: URL) async {
        defer {
            audioRecorder.cleanupTempFile()
        }

        do {
            statusMessage = networkMonitor.isConnected ? "正在识别语音..." : "离线识别中..."
            let rawText = try await ASRFactory.transcribe(
                audioURL: audioURL,
                networkAvailable: networkMonitor.isConnected
            )

            var processedText = rawText
            let translationMode = config.translationMode
            if translationMode != .none && networkMonitor.isConnected {
                statusMessage = "正在翻译..."
                processedText = try await PostProcessor.process(
                    text: rawText,
                    mode: translationMode
                )
            }

            statusMessage = "正在格式化..."
            let formattedText = TextFormatter.format(processedText)

            statusMessage = "正在复制..."
            try ClipboardOutput.copy(formattedText)

            let providerName = networkMonitor.isConnected
                ? (try? ASRFactory.create())?.name ?? "Unknown"
                : "Apple Speech (Offline)"
            historyManager.add(text: formattedText, provider: providerName)

            lastResult = formattedText
            lastError = nil
            showResult = true
            recordingState = .idle
            statusMessage = "已复制到剪贴板"

            Task {
                try? await Task.sleep(nanoseconds: UInt64(Constants.UI.toastDuration * 1_000_000_000))
                showResult = false
                statusMessage = ""
            }

        } catch let error as VoxError {
            handleError(error)
            recordingState = .idle
        } catch {
            handleError(.unknown(error.localizedDescription))
            recordingState = .idle
        }
    }

    // MARK: - 权限检查

    private func checkMicrophonePermission() async -> Bool {
        switch audioRecorder.permissionStatus {
        case .granted:
            return true
        case .undetermined:
            return await audioRecorder.requestPermission()
        case .denied:
            handleError(.microphonePermissionDenied)
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - 错误处理

    private func handleError(_ error: VoxError) {
        lastError = error
        showError = true
        statusMessage = error.shortDescription

        HapticFeedback.shared.error()

        Task {
            try? await Task.sleep(nanoseconds: UInt64(Constants.UI.toastDuration * 1_000_000_000))
            showError = false
            if recordingState == .idle {
                statusMessage = ""
            }
        }
    }

    // MARK: - 计算属性

    var hasAPIKey: Bool {
        config.hasValidAPIKey
    }

    var hasCompletedSetup: Bool {
        config.hasCompletedSetup
    }

    /// 是否正在为后台录音准备音频会话（URL Scheme 唤醒流程）
    private(set) var isPrimingAudio: Bool = false

    /// beta.32: 键盘闪跳唤醒主 App 后，异步准备音频会话
    /// 主 App 会短暂停留在前台并显示"正在获取麦克风..."，
    /// 等音频会话确认激活后再允许退出。
    func primeDaemonForKeyboardWakeup(daemon: AudioDaemonService) async {
        showResult = false
        isPrimingAudio = true
        statusMessage = "正在获取麦克风..."

        let success = await daemon.primeForBackgroundRecording()

        isPrimingAudio = false

        if success {
            statusMessage = "后台语音守护已就绪"
        } else {
            statusMessage = "麦克风准备失败，请重试"
        }

        try? await Task.sleep(nanoseconds: UInt64(Constants.UI.toastDuration * 1_000_000_000))
        if recordingState == .idle {
            statusMessage = ""
        }
    }

    var isNetworkAvailable: Bool {
        networkMonitor.isConnected
    }
}
