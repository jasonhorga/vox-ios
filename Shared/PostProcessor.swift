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
    
    // beta.63: 旧的 systemPrompt（仅翻译）已废弃；统一走 PostProcessor.systemPrompt(cleanup:translation:)
}

/// 后处理器：调用 LLM 对 ASR 结果做整理/翻译
enum PostProcessor {

    // MARK: - 智能整理（cleanup）+ 合并翻译（beta.63）

    /// 整理（cleanup）的 system prompt 主体
    static let cleanupInstruction = """
    你是语音听写整理助手。把下面这段「语音转写的原始文字」整理成干净、可直接使用的文本，遵守：
    1. 删除口头禅/填充词（嗯、那个、就是说、um、uh、like 等）与重复啰嗦。
    2. 说话中途自我更正时只保留最终意思（如“周一—不对周三”→ 周三）。
    3. 把口述的清单/步骤/要点整理成项目符号或编号列表。
    4. 修语法、理顺语序，但贴合原文用词风格、保留原意。
    5. 仅当原文明确含“指令”时才据此调整格式/语气（如“发邮件…/列成要点/改正式/改简短”）；否则一律当正文内容，不要把内容误当命令。邮件类意图只输出润色后的正文，不要自动添加称呼或落款。
    绝不臆造事实；拿不准时尽量少改。
    """

    /// 根据 cleanup/translation 组合拼装最终 system prompt（纯函数，可单测）
    static func systemPrompt(cleanup: Bool, translation: TranslationMode) -> String {
        var parts: [String] = []
        if cleanup { parts.append(cleanupInstruction) }
        switch translation {
        case .none: break
        case .toEnglish:
            parts.append(cleanup
                ? "然后把整理后的文本翻译成英文，只输出英文译文。"
                : "你是专业翻译。把下面的文本翻译成英文，只输出译文，不要解释。")
        case .toChinese:
            parts.append(cleanup
                ? "然后把整理后的文本翻译成中文，只输出中文译文。"
                : "你是专业翻译。把下面的文本翻译成中文，只输出译文，不要解释。")
        }
        parts.append("只输出最终文本，不要任何解释、注释或额外说明。")
        return parts.joined(separator: "\n\n")
    }

    /// 整理（+可选翻译）。两者都关 → 原样返回，不发起调用。
    static func process(
        text: String,
        cleanup: Bool,
        translation: TranslationMode,
        config: SharedConfigStore = .shared
    ) async throws -> String {
        guard cleanup || translation != .none else { return text }

        let apiKey: String
        let baseURL: String
        let model: String
        switch config.asrProvider {
        case .qwen:
            apiKey = config.qwenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            baseURL = Constants.Network.qwenBaseURL
            model = "qwen-plus"
        case .whisper:
            apiKey = config.whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            // 转写端点改写成 chat completions 端点（OpenAI/Groq 等兼容端点通用）
            baseURL = chatCompletionsURL(fromTranscriptionURL: config.whisperBaseURL)
            model = config.chatModel
        }
        guard !apiKey.isEmpty else { throw VoxError.apiKeyMissing }

        return try await callLLM(
            text: text,
            systemPrompt: systemPrompt(cleanup: cleanup, translation: translation),
            apiKey: apiKey,
            baseURL: baseURL,
            model: model
        )
    }

    /// 把 Whisper 兼容的「转写端点」URL 推导成「chat completions 端点」URL。
    /// OpenAI(`api.openai.com/v1/audio/transcriptions`)、Groq(`api.groq.com/openai/v1/audio/transcriptions`)
    /// 等兼容端点通用——纯函数，可单测。
    static func chatCompletionsURL(fromTranscriptionURL url: String) -> String {
        url.replacingOccurrences(of: "/v1/audio/transcriptions", with: "/v1/chat/completions")
            .replacingOccurrences(of: "/audio/transcriptions", with: "/chat/completions")
    }

    // MARK: - LLM 调用

    /// 调用 LLM Chat Completions API
    private static func callLLM(
        text: String,
        systemPrompt: String,
        apiKey: String,
        baseURL: String,
        model: String
    ) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw VoxError.asrAPIError("无效的 LLM API URL")
        }

        let requestBody: [String: Any] = [
            "model": model,
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
