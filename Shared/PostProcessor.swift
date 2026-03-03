// PostProcessor.swift
// Shared
//
// 翻译模式后处理器：根据 TranslationMode 调用 LLM 进行翻译
// 使用用户自己的 API Key（BYOK 模式）

import Foundation

/// 翻译模式
enum TranslationMode: String, CaseIterable, Codable {
    /// 不翻译，直接输出
    case none = "none"
    /// 翻译为英文
    case toEnglish = "toEnglish"
    /// 翻译为中文
    case toChinese = "toChinese"
    
    var displayName: String {
        switch self {
        case .none: return "不翻译"
        case .toEnglish: return "翻译为英文"
        case .toChinese: return "翻译为中文"
        }
    }
    
    /// LLM System Prompt
    var systemPrompt: String {
        switch self {
        case .none:
            return ""
        case .toEnglish:
            return """
            You are a professional translator. Translate the following text to English. \
            Output ONLY the translated text, without any explanation, notes, or additional commentary.
            """
        case .toChinese:
            return """
            你是一位专业翻译。请将以下文本翻译为中文。\
            只输出翻译结果，不要添加任何解释、注释或额外说明。
            """
        }
    }
}

/// 后处理器：调用 LLM 对 ASR 结果进行翻译
enum PostProcessor {
    
    /// 对 ASR 结果进行后处理（翻译）
    /// - Parameters:
    ///   - text: ASR 转写文本
    ///   - mode: 翻译模式
    ///   - config: 配置存储
    /// - Returns: 处理后的文本
    /// - Throws: VoxError
    static func process(
        text: String,
        mode: TranslationMode,
        config: SharedConfigStore = .shared
    ) async throws -> String {
        // 不翻译模式直接返回
        guard mode != .none else { return text }
        
        // 获取 API 配置
        let apiKey: String
        let baseURL: String
        
        switch config.asrProvider {
        case .qwen:
            apiKey = config.qwenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            baseURL = Constants.Network.qwenBaseURL
        case .whisper:
            apiKey = config.whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            // Whisper API 用户通常也有 OpenAI chat completions 访问权限
            // 将 /v1/audio/transcriptions 替换为 /v1/chat/completions
            baseURL = config.whisperBaseURL
                .replacingOccurrences(of: "/v1/audio/transcriptions", with: "/v1/chat/completions")
                .replacingOccurrences(of: "/audio/transcriptions", with: "/chat/completions")
        }
        
        guard !apiKey.isEmpty else {
            throw VoxError.apiKeyMissing
        }
        
        return try await callLLM(
            text: text,
            systemPrompt: mode.systemPrompt,
            apiKey: apiKey,
            baseURL: baseURL
        )
    }
    
    // MARK: - LLM 调用
    
    /// 调用 LLM Chat Completions API
    private static func callLLM(
        text: String,
        systemPrompt: String,
        apiKey: String,
        baseURL: String
    ) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw VoxError.asrAPIError("无效的 LLM API URL")
        }
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15.0
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // 带超时的请求
        let result: String = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw VoxError.asrNetworkError("无效的 LLM 服务器响应")
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorBody = String(data: data, encoding: .utf8) ?? "未知错误"
                    throw VoxError.asrAPIError("LLM HTTP \(httpResponse.statusCode): \(errorBody)")
                }
                
                // 解析 Chat Completions 响应
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let message = firstChoice["message"] as? [String: Any],
                      let content = message["content"] as? String
                else {
                    throw VoxError.asrAPIError("LLM 响应格式解析失败")
                }
                
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(15.0 * 1_000_000_000))
                throw VoxError.asrTimeout
            }
            
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
        
        guard !result.isEmpty else {
            throw VoxError.asrEmptyResult
        }
        
        return result
    }
}
