// AppState.swift
// VoxInput
//
// 全局状态管理 + Pipeline 编排
// 录音 → ASR → PostProcessor(翻译) → TextFormatter → ClipboardOutput

import Foundation
import UIKit
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

            // Sprint 3: 静音自动停止已移除，录音只能由用户手动点停止结束

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
                do {
                    processedText = try await PostProcessor.process(
                        text: rawText,
                        mode: translationMode
                    )
                } catch {
                    // beta.61: 翻译失败不丢弃已识别文本，降级为原文输出（review H2）
                    SharedLogger.error("翻译失败，降级为原文输出: \(error.localizedDescription)")
                    processedText = rawText
                }
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

    /// Sprint 3: 标记本次激活是否由 URL Scheme 唤醒（区分启动来源）
    var isURLSchemeActivation: Bool = false
    /// beta.60: 记录此次 URL 唤醒是否是冷启动（App 从 not-running 被启动）
    /// 由 MainView 在收到第一个 onOpenURL 时，根据 hasHandledFirstURL 标志判断
    var isWakeupColdStart: Bool = false
    /// beta.60: App 本次生命周期内是否已经处理过第一个 URL
    /// false = 这是 App 启动后第一个 URL，说明是冷启动
    var hasHandledFirstURL: Bool = false

    /// beta.32: 键盘闪跳唤醒主 App 后，异步准备音频会话
    /// 主 App 会短暂停留在前台并显示"正在获取麦克风..."，
    /// 等音频会话确认激活后再允许退出。
    func primeDaemonForKeyboardWakeup(daemon: AudioDaemonService) async {
        showResult = false
        isPrimingAudio = true
        statusMessage = "正在获取麦克风..."

        // beta.60: isColdStart 由 handleIncomingURL 在 App 启动瞬间设置
        // 不在这里重新读心跳——此时 daemon 已启动并写入心跳，判断会失准
        let isColdStart = isWakeupColdStart

        SharedLogger.info("[WakeupFlow] primeDaemonForKeyboardWakeup START — isURLScheme=\(isURLSchemeActivation) isPriming=\(isPrimingAudio) isColdStart=\(isColdStart)")

        let success = await daemon.primeForBackgroundRecording()

        SharedLogger.info("[WakeupFlow] primeForBackgroundRecording DONE — success=\(success) isURLScheme=\(isURLSchemeActivation) isColdStart=\(isColdStart)")

        isPrimingAudio = false

        if success {
            if isURLSchemeActivation {
                isURLSchemeActivation = false

                if isColdStart {
                    // 冷启动：prime 耗时长，iOS 转场上下文已失效，suspend 会退回桌面
                    // 直接显示引导，让用户手动返回
                    SharedLogger.info("[WakeupFlow] cold-start → showing return guidance, NO suspend")
                    statusMessage = "✅ 守护进程已就绪，请返回原应用"
                } else {
                    // 热唤醒：prime 极快，转场上下文仍有效，可以自动切回
                    SharedLogger.info("[WakeupFlow] hot-wakeup → will suspend after 0.8s")
                    statusMessage = "✅ 守护进程已就绪，自动返回..."
                    // 延迟 0.8s 等待系统转场动画彻底稳定，否则挂起可能退回桌面
                    Task {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        await MainActor.run {
                            SharedLogger.info("[WakeupFlow] executing suspend")
                            let selector = NSSelectorFromString("suspend")
                            if UIApplication.shared.responds(to: selector) {
                                UIApplication.shared.perform(selector)
                            }
                        }
                    }
                }
            } else {
                SharedLogger.info("[WakeupFlow] not URL-scheme activation, showing ready message only")
                statusMessage = "✅ 守护进程已就绪"
            }
        } else {
            SharedLogger.info("[WakeupFlow] prime FAILED")
            statusMessage = "麦克风准备失败，请重试"
            try? await Task.sleep(nanoseconds: UInt64(Constants.UI.toastDuration * 1_000_000_000))
            if recordingState == .idle {
                statusMessage = ""
            }
        }
    }

    /// Phase 3: 静默 prime，不显示 overlay，用于手动打开 App 时
    func silentPrimeDaemon(daemon: AudioDaemonService) async {
        let _ = await daemon.primeForBackgroundRecording()
    }

    var isNetworkAvailable: Bool {
        networkMonitor.isConnected
    }
}
