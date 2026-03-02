// ASRProvider.swift
// VoxInput
//
// ASR 协议定义

import Foundation

/// ASR（自动语音识别）提供商协议
/// 所有 ASR 实现（Qwen、Whisper 等）必须遵守此协议
protocol ASRProvider {
    
    /// 提供商名称（用于日志和 UI 显示）
    var name: String { get }
    
    /// 将音频文件转写为文本
    /// - Parameter audioURL: 本地音频文件 URL（16kHz/16bit/Mono WAV）
    /// - Returns: 转写后的文本
    /// - Throws: VoxError
    func transcribe(audioURL: URL) async throws -> String
}

/// ASR 结果校验工具
enum ASRResultValidator {
    
    /// 校验 ASR 结果是否有效
    /// - Parameter text: ASR 返回的文本
    /// - Returns: 清理后的有效文本
    /// - Throws: VoxError.asrEmptyResult 如果结果无效
    static func validate(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmed.count >= Constants.ASR.minimumResultLength else {
            throw VoxError.asrEmptyResult
        }
        
        return trimmed
    }
}

/// ASR 请求重试工具
enum ASRRetryHelper {
    
    /// 带重试的异步操作执行器
    /// - Parameters:
    ///   - maxRetries: 最大重试次数
    ///   - initialDelay: 初始重试延迟（秒），后续按指数退避
    ///   - operation: 要执行的异步操作
    /// - Returns: 操作结果
    /// - Throws: 最后一次尝试的错误
    static func withRetry<T>(
        maxRetries: Int = Constants.ASR.maxRetries,
        initialDelay: TimeInterval = Constants.ASR.initialRetryDelay,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // 最后一次尝试不需要等待
                if attempt < maxRetries {
                    // 指数退避：0.8s, 1.6s, 3.2s, ...
                    let delay = initialDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? VoxError.unknown("重试耗尽")
    }
}
