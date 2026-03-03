// AppleSpeechASR.swift
// VoxInput
//
// 离线降级：使用 Apple Speech.framework（SFSpeechRecognizer）进行本地语音识别
// 断网时由 ASRFactory 自动降级到此实现

import Foundation
import Speech

/// Apple 本地语音识别（离线降级用）
/// 使用 SFSpeechRecognizer + on-device recognition
final class AppleSpeechASR: ASRProvider {
    
    let name = "Apple Speech (Offline)"
    
    /// 本地语音识别超时时间（秒）
    private let timeout: TimeInterval
    
    init(timeout: TimeInterval = 15.0) {
        self.timeout = timeout
    }
    
    // MARK: - 权限请求
    
    /// 请求语音识别权限
    /// - Returns: 是否已授权
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    /// 当前授权状态
    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }
    
    // MARK: - ASRProvider
    
    func transcribe(audioURL: URL) async throws -> String {
        // 检查权限
        guard Self.authorizationStatus == .authorized else {
            throw VoxError.speechPermissionDenied
        }
        
        // 创建识别器（支持中英文自动检测）
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans")) else {
            throw VoxError.asrAPIError("无法创建本地语音识别器")
        }
        
        guard recognizer.isAvailable else {
            throw VoxError.asrAPIError("本地语音识别不可用")
        }
        
        // 优先使用 on-device 识别
        if recognizer.supportsOnDeviceRecognition {
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false
            
            return try await performRecognition(recognizer: recognizer, request: request)
        } else {
            // 设备不支持 on-device，尝试普通识别（需要网络）
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.shouldReportPartialResults = false
            
            return try await performRecognition(recognizer: recognizer, request: request)
        }
    }
    
    // MARK: - Private
    
    /// 执行语音识别（带超时）
    private func performRecognition(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [timeout] in
                // 识别任务
                let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
                    recognizer.recognitionTask(with: request) { result, error in
                        if let error {
                            continuation.resume(throwing: VoxError.asrAPIError("本地识别失败: \(error.localizedDescription)"))
                            return
                        }
                        
                        guard let result, result.isFinal else {
                            // 等待最终结果，partial results 被忽略
                            return
                        }
                        
                        continuation.resume(returning: result)
                    }
                }
                
                return result.bestTranscription.formattedString
            }
            
            group.addTask { [timeout] in
                // 超时任务
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw VoxError.asrTimeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return try ASRResultValidator.validate(result)
        }
    }
}
