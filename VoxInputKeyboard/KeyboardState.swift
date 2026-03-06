// KeyboardState.swift
// VoxInputKeyboard
//
// 键盘扩展状态机：管理录音→识别→注入的完整流程

import Foundation
import Observation

/// 键盘扩展状态
enum KeyboardPhase: Equatable {
    /// 空闲，等待用户操作
    case idle
    /// 正在录音
    case recording
    /// 正在处理（ASR + 格式化）
    case processing
    /// 处理完成，文字已注入
    case done(String)
    /// 发生错误
    case error(String)
}

/// 键盘扩展状态管理器
/// 驱动键盘 UI 更新和 pipeline 流程控制
@Observable
@MainActor
final class KeyboardState {
    
    // MARK: - 可观察状态
    
    /// 当前阶段
    private(set) var phase: KeyboardPhase = .idle
    
    /// 状态消息（显示在键盘 UI 上）
    private(set) var statusMessage: String = ""
    
    /// 当前音频电平（归一化 0.0 ~ 1.0）
    private(set) var currentLevel: Float = 0.0
    
    /// 电平历史（波形显示）
    private(set) var levelHistory: [Float] = []
    
    /// 是否有 Full Access 权限
    private(set) var hasFullAccess: Bool = false
    
    /// 是否有麦克风权限
    private(set) var hasMicPermission: Bool = false
    
    /// 是否在密码输入框中
    private(set) var isSecureInput: Bool = false
    
    /// 输入上下文提示（光标前的文本，用于提升 ASR 准确率）
    var inputContextHint: String?
    
    // MARK: - 子模块
    
    /// 键盘专用录音器
    let audioRecorder = KeyboardAudioRecorder()
    
    /// 共享配置
    let config = SharedConfigStore.shared
    
    /// 网络监控
    let networkMonitor = NetworkMonitor()
    
    // MARK: - 状态更新
    
    /// 检查环境权限
    func checkEnvironment(systemHasFullAccess: Bool? = nil) {
        // 检查 Full Access（Open Access）
        if let systemHasFullAccess {
            hasFullAccess = systemHasFullAccess
        } else {
            hasFullAccess = checkFullAccess()
        }
        
        // 检查麦克风权限
        hasMicPermission = checkMicPermission()
        
        SharedLogger.info("环境检查: fullAccess=\(hasFullAccess), mic=\(hasMicPermission)")
    }
    
    /// 检测是否在密码输入框中
    /// - Parameter isSecure: textDocumentProxy.isSecureTextEntry
    func updateSecureInputState(_ isSecure: Bool) {
        isSecureInput = isSecure
        if isSecure {
            statusMessage = "密码输入框，语音输入不可用"
        }
    }
    
    // MARK: - 录音控制
    
    /// 开始录音
    /// - Parameter proxy: UITextDocumentProxy，用于后续文字注入
    func startRecording() {
        config.reload()
        
        guard phase == .idle else { return }
        guard !isSecureInput else {
            phase = .error("密码输入框不支持语音输入")
            scheduleReset()
            return
        }
        guard hasFullAccess else { return }
        guard hasMicPermission else { return }
        guard config.hasValidAPIKey else {
            phase = .error("请在主 App 中配置 API Key")
            scheduleReset()
            return
        }
        // 网络不可用时仍可使用离线识别（不再阻断）
        
        do {
            try audioRecorder.start()
            phase = .recording
            statusMessage = "录音中..."
            levelHistory = []
            SharedLogger.info("录音开始, provider=\(config.asrProvider.rawValue), contextHint=\(inputContextHint?.prefix(50) ?? "nil")")
            
            // 设置电平更新回调
            audioRecorder.onLevelUpdate = { [weak self] level, peak in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentLevel = level
                    self.levelHistory.append(level)
                    if self.levelHistory.count > Constants.Keyboard.waveformSampleCount {
                        self.levelHistory.removeFirst()
                    }
                }
            }
            
            // 设置静音超时回调
            audioRecorder.onSilenceTimeout = { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.stopRecording()
                }
            }
            
            // 设置录音超时回调（最长 60 秒）
            audioRecorder.onMaxDurationReached = { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.stopRecording()
                }
            }
            
        } catch {
            phase = .error("录音启动失败")
            scheduleReset()
        }
    }
    
    /// 停止录音并开始 ASR 处理
    /// - Returns: 转写文本（如果成功）
    @discardableResult
    func stopRecording() async -> String? {
        guard phase == .recording else { return nil }
        
        do {
            let audioURL = try audioRecorder.stop()
            
            phase = .processing
            statusMessage = "正在识别..."
            currentLevel = 0.0
            
            // ASR 转写
            let rawText = try await transcribe(audioURL: audioURL)
            
            // 文本格式化
            let formatted = TextFormatter.format(rawText)
            
            // 清理临时文件
            audioRecorder.cleanupTempFile()
            
            // 更新状态
            phase = .done(formatted)
            statusMessage = "已输入"
            SharedLogger.info("ASR 完成: \(formatted.prefix(80))")
            
            // 延迟重置状态
            scheduleReset()
            
            return formatted
            
        } catch let error as VoxError {
            audioRecorder.cleanupTempFile()
            phase = .error(error.shortDescription)
            statusMessage = error.shortDescription
            SharedLogger.error("ASR 失败 (VoxError): \(error.shortDescription)")
            scheduleReset()
            return nil
        } catch {
            audioRecorder.cleanupTempFile()
            phase = .error("识别失败")
            statusMessage = "识别失败"
            SharedLogger.error("ASR 失败: \(error.localizedDescription)")
            scheduleReset()
            return nil
        }
    }
    
    /// 取消录音
    func cancelRecording() {
        audioRecorder.cancel()
        phase = .idle
        statusMessage = ""
        currentLevel = 0.0
    }
    
    // MARK: - ASR Pipeline
    
    /// 执行 ASR 转写（键盘扩展专用：15s 超时、1 次重试）
    /// 支持离线降级到 Apple 本地识别
    private func transcribe(audioURL: URL) async throws -> String {
        let isOnline = networkMonitor.isConnected
        let provider = try createASRProvider(networkAvailable: isOnline)
        let timeoutSeconds: TimeInterval = 15.0
        let contextHint = inputContextHint
        
        return try await ASRRetryHelper.withRetry(
            maxRetries: Constants.ASR.keyboardMaxRetries,
            initialDelay: Constants.ASR.initialRetryDelay
        ) {
            try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await provider.transcribe(audioURL: audioURL, contextHint: contextHint)
                }
                
                group.addTask {
                    // 15 秒超时
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw VoxError.asrTimeout
                }
                
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        }
    }
    
    /// 创建 ASR Provider（复用 Shared 配置，支持离线降级）
    private func createASRProvider(networkAvailable: Bool = true) throws -> ASRProvider {
        // 断网时降级到 Apple 本地识别
        guard networkAvailable else {
            return AppleSpeechASR(timeout: 15.0)
        }
        
        switch config.asrProvider {
        case .qwen:
            let apiKey = config.qwenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else { throw VoxError.apiKeyMissing }
            return QwenASR(apiKey: apiKey, model: config.qwenModel)
            
        case .whisper:
            let apiKey = config.whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else { throw VoxError.apiKeyMissing }
            return WhisperAPIASR(
                apiKey: apiKey,
                baseURL: config.whisperBaseURL,
                model: config.whisperModel
            )
        }
    }
    
    // MARK: - 权限检查
    
    /// 检查 Full Access（Open Access）权限
    /// 键盘扩展中通过尝试访问 UIPasteboard 或 App Group 来间接判断
    private func checkFullAccess() -> Bool {
        // 在键盘扩展中，hasFullAccess 属性直接反映 "Allow Full Access" 开关
        // UIInputViewController.hasFullAccess 由系统提供
        // 这里通过尝试读取 App Group UserDefaults 来验证
        let defaults = AppGroup.sharedDefaults
        defaults.set(true, forKey: "vox.keyboard.accessCheck")
        return defaults.synchronize()
    }
    
    /// 检查麦克风权限
    /// iOS 17+ 使用 AVAudioApplication.shared.recordPermission（返回 AVAudioApplication.RecordPermission）
    /// iOS 16  使用 AVAudioSession.sharedInstance().recordPermission（返回 AVAudioSession.RecordPermission）
    /// 两者是不同类型，因此分别处理并直接返回 Bool。
    private func checkMicPermission() -> Bool {
        if #available(iOS 17.0, *) {
            let permission = AVAudioApplication.shared.recordPermission
            switch permission {
            case .granted:
                return true
            case .denied, .undetermined:
                return false
            @unknown default:
                return false
            }
        } else {
            let permission = AVAudioSession.sharedInstance().recordPermission
            switch permission {
            case .granted:
                return true
            case .denied, .undetermined:
                return false
            @unknown default:
                return false
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /// 延迟重置状态到 idle
    private func scheduleReset() {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Constants.Keyboard.statusClearDelay * 1_000_000_000))
            if phase != .recording && phase != .processing {
                phase = .idle
                statusMessage = ""
            }
        }
    }
}

// MARK: - AVFoundation Import
import AVFoundation
