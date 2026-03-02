// ASRFactory.swift
// VoxInput
//
// ASR 工厂：根据配置创建对应的 ASR 提供商

import Foundation

/// ASR 工厂
/// 根据 ConfigStore 中的配置创建对应的 ASR Provider 实例
enum ASRFactory {
    
    /// 根据当前配置创建 ASR Provider
    /// - Parameter config: 配置存储
    /// - Returns: ASR Provider 实例
    /// - Throws: VoxError.apiKeyMissing 如果 API Key 未配置
    static func create(config: ConfigStore = .shared) throws -> ASRProvider {
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
    
    /// 执行 ASR 转写（带重试逻辑）
    /// - Parameters:
    ///   - audioURL: 音频文件 URL
    ///   - config: 配置存储
    /// - Returns: 转写文本
    /// - Throws: VoxError
    static func transcribe(audioURL: URL, config: ConfigStore = .shared) async throws -> String {
        let provider = try create(config: config)
        
        return try await ASRRetryHelper.withRetry {
            try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await provider.transcribe(audioURL: audioURL)
                }
                
                group.addTask {
                    // 超时任务
                    try await Task.sleep(nanoseconds: UInt64(Constants.ASR.timeout * 1_000_000_000))
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
