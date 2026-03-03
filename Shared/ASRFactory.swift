// ASRFactory.swift
// Shared
//
// ASR 工厂：根据配置创建对应的 ASR 提供商
// Sprint 2: 添加离线降级到 AppleSpeechASR

import Foundation

/// ASR 工厂
/// 根据 SharedConfigStore 中的配置创建对应的 ASR Provider 实例
/// 断网时自动降级到 Apple 本地识别
enum ASRFactory {
    
    /// 根据当前配置创建 ASR Provider
    /// - Parameters:
    ///   - config: 配置存储
    ///   - networkAvailable: 网络是否可用（断网时降级到本地识别）
    /// - Returns: ASR Provider 实例
    /// - Throws: VoxError.apiKeyMissing 如果 API Key 未配置（在线模式）
    static func create(config: SharedConfigStore = .shared, networkAvailable: Bool = true) throws -> ASRProvider {
        // 断网时自动降级到 Apple 本地识别
        guard networkAvailable else {
            return AppleSpeechASR()
        }
        
        switch config.asrProvider {
        case .qwen:
            let apiKey = config.qwenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw VoxError.apiKeyMissing
            }
            return QwenASR(apiKey: apiKey)
            
        case .whisper:
            let apiKey = config.whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw VoxError.apiKeyMissing
            }
            return WhisperAPIASR(
                apiKey: apiKey,
                baseURL: config.whisperBaseURL,
                model: config.whisperModel
            )
        }
    }
    
    /// 执行 ASR 转写（带重试逻辑 + 15s 超时）
    /// - Parameters:
    ///   - audioURL: 音频文件 URL
    ///   - config: 配置存储
    ///   - networkAvailable: 网络是否可用
    /// - Returns: 转写文本
    /// - Throws: VoxError
    static func transcribe(
        audioURL: URL,
        config: SharedConfigStore = .shared,
        networkAvailable: Bool = true
    ) async throws -> String {
        let provider = try create(config: config, networkAvailable: networkAvailable)
        let timeoutSeconds: TimeInterval = 15.0
        
        return try await ASRRetryHelper.withRetry {
            try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await provider.transcribe(audioURL: audioURL)
                }
                
                group.addTask {
                    // 15 秒超时
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw VoxError.asrTimeout
                }
                
                // 返回第一个完成的结果（成功或超时）
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        }
    }
}
