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
    /// 空闲
    case idle
    /// 录音中
    case recording
    /// 处理中（ASR + 格式化 + 复制）
    case processing
}

/// 全局应用状态
/// 管理完整的语音转文字 pipeline，驱动 UI 更新
@Observable
@MainActor
final class AppState {
    
    // MARK: - 可观察状态
    
    /// 当前录音/处理状态
    private(set) var recordingState: RecordingState = .idle
    
    /// 最近一次转写结果
    private(set) var lastResult: String?
    
    /// 最近一次错误
    private(set) var lastError: VoxError?
    
    /// 是否显示错误提示
    var showError: Bool = false
    
    /// 是否显示结果 Toast
    var showResult: Bool = false
    
    /// 处理进度描述（用于 UI 显示）
    private(set) var statusMessage: String = ""
    
    // MARK: - 子模块
    
    /// 录音管理器
    let audioRecorder = AudioRecorder()
    
    /// 网络状态监控
    let networkMonitor = NetworkMonitor()
    
    /// 配置存储
    let config = ConfigStore.shared
    
    // MARK: - 录音控制
    
    /// 历史记录管理器
    let historyManager = HistoryManager.shared
    
    /// 开始录音
    /// - 检查权限 → 触觉反馈 → 启动录音 → 开始静音检测
    func startRecording() async {
        // 防止重复启动
        guard recordingState == .idle else { return }
        
        // 检查麦克风权限
        guard await checkMicrophonePermission() else { return }
        
        do {
            // 触觉反馈：录音开始
            HapticFeedback.shared.recordStart()
            
            // 启动录音
            try audioRecorder.start()
            recordingState = .recording
            statusMessage = "录音中..."
            
            // 设置静音检测回调
            audioRecorder.silenceDetector.onSilenceTimeout = { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.stopRecording()
                }
            }
            
            // 设置超时自动停止回调（最长 60 秒）
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
    
    /// 停止录音并开始处理 pipeline
    func stopRecording() async {
        guard recordingState == .recording else { return }
        
        // 触觉反馈：录音停止
        HapticFeedback.shared.recordStop()
        
        do {
            // 停止录音，获取音频文件
            let audioURL = try audioRecorder.stop()
            
            // 进入处理阶段
            recordingState = .processing
            statusMessage = "正在识别..."
            
            // 执行异步处理 pipeline
            await processPipeline(audioURL: audioURL)
            
        } catch let error as VoxError {
            handleError(error)
            recordingState = .idle
        } catch {
            handleError(.unknown(error.localizedDescription))
            recordingState = .idle
        }
    }
    
    /// 切换录音状态（按钮按下/松开）
    func toggleRecording() async {
        switch recordingState {
        case .idle:
            await startRecording()
        case .recording:
            await stopRecording()
        case .processing:
            // 处理中不响应
            break
        }
    }
    
    /// 取消录音
    func cancelRecording() {
        audioRecorder.cancel()
        recordingState = .idle
        statusMessage = ""
    }
    
    // MARK: - 处理 Pipeline
    
    /// 执行完整的处理 pipeline
    /// 录音文件 → ASR 转写 → 翻译后处理 → 文本格式化 → 剪贴板输出
    private func processPipeline(audioURL: URL) async {
        defer {
            // 清理临时文件
            audioRecorder.cleanupTempFile()
        }
        
        do {
            // 步骤 1：ASR 转写（支持离线降级）
            statusMessage = networkMonitor.isConnected ? "正在识别语音..." : "离线识别中..."
            let rawText = try await ASRFactory.transcribe(
                audioURL: audioURL,
                networkAvailable: networkMonitor.isConnected
            )
            
            // 步骤 2：翻译后处理（仅在线且非 .none 模式时）
            var processedText = rawText
            let translationMode = config.translationMode
            if translationMode != .none && networkMonitor.isConnected {
                statusMessage = "正在翻译..."
                processedText = try await PostProcessor.process(
                    text: rawText,
                    mode: translationMode
                )
            }
            
            // 步骤 3：文本格式化
            statusMessage = "正在格式化..."
            let formattedText = TextFormatter.format(processedText)
            
            // 步骤 4：写入剪贴板
            statusMessage = "正在复制..."
            try ClipboardOutput.copy(formattedText)
            
            // 步骤 5：保存到历史记录
            let providerName = networkMonitor.isConnected
                ? (try? ASRFactory.create())?.name ?? "Unknown"
                : "Apple Speech (Offline)"
            historyManager.add(text: formattedText, provider: providerName)
            
            // 成功
            lastResult = formattedText
            lastError = nil
            showResult = true
            recordingState = .idle
            statusMessage = "已复制到剪贴板"
            
            // 自动隐藏结果提示
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
    
    /// 检查麦克风权限
    /// - Returns: 是否已授权
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
    
    /// 统一错误处理
    private func handleError(_ error: VoxError) {
        lastError = error
        showError = true
        statusMessage = error.shortDescription
        
        // 错误触觉反馈
        HapticFeedback.shared.error()
        
        // 自动隐藏错误提示
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Constants.UI.toastDuration * 1_000_000_000))
            showError = false
            if recordingState == .idle {
                statusMessage = ""
            }
        }
    }
    
    // MARK: - 计算属性
    
    /// 是否有有效的 API Key 配置
    var hasAPIKey: Bool {
        config.hasValidAPIKey
    }
    
    /// 是否已完成首次设置
    var hasCompletedSetup: Bool {
        config.hasCompletedSetup
    }
    
    /// 是否有网络连接
    var isNetworkAvailable: Bool {
        networkMonitor.isConnected
    }
}
