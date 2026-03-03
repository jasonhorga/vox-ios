// QwenASR.swift
// Shared
//
// Qwen3-ASR（通义千问 ASR）实现
// 使用 DashScope Chat API + base64 音频

import Foundation

/// Qwen ASR 实现
/// 通过 DashScope Chat Completions API 发送 base64 编码的音频数据
final class QwenASR: ASRProvider {
    
    // MARK: - ASRProvider
    
    let name = "Qwen ASR"
    
    // MARK: - 私有属性
    
    /// API Key
    private let apiKey: String
    
    /// API URL
    private let baseURL: String
    
    /// URLSession（用于网络请求）
    private let session: URLSession
    
    // MARK: - 初始化
    
    /// 初始化 Qwen ASR
    /// - Parameters:
    ///   - apiKey: DashScope API Key
    ///   - baseURL: API 地址，默认使用 DashScope 兼容模式
    init(apiKey: String, baseURL: String = Constants.Network.qwenBaseURL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        
        // 配置带超时的 URLSession
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.ASR.timeout
        config.timeoutIntervalForResource = Constants.ASR.timeout
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 转写
    
    func transcribe(audioURL: URL) async throws -> String {
        // 1. 读取音频文件并编码为 base64
        let audioData = try Data(contentsOf: audioURL)
        let base64Audio = audioData.base64EncodedString()
        
        // 2. 构建 DashScope Chat API 请求体
        // Qwen-ASR 使用 Chat Completions 格式，音频作为 input_audio 类型发送
        let requestBody: [String: Any] = [
            "model": "qwen2-audio-instruct",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": "data:audio/wav;base64,\(base64Audio)",
                                "format": "wav"
                            ]
                        ],
                        [
                            "type": "text",
                            "text": "请将这段音频转写为文字，只输出转写结果，不要添加任何额外说明。"
                        ]
                    ]
                ]
            ]
        ]
        
        // 3. 构建 HTTP 请求
        guard let url = URL(string: baseURL) else {
            throw VoxError.asrAPIError("无效的 API URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // 4. 发送请求
        let (data, response) = try await session.data(for: request)
        
        // 5. 检查 HTTP 状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoxError.asrNetworkError("无效的服务器响应")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "未知错误"
            throw VoxError.asrAPIError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
        
        // 6. 解析响应
        let text = try parseResponse(data)
        
        // 7. 校验结果
        return try ASRResultValidator.validate(text)
    }
    
    // MARK: - 响应解析
    
    /// 解析 DashScope Chat API 响应
    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw VoxError.asrAPIError("响应格式解析失败")
        }
        
        return content
    }
}
