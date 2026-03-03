// WhisperAPIASR.swift
// Shared
//
// Whisper 兼容 API 实现（multipart/form-data）

import Foundation

/// Whisper API ASR 实现
/// 支持 OpenAI Whisper API 及兼容接口（如 Groq、本地 whisper.cpp server）
final class WhisperAPIASR: ASRProvider {
    
    // MARK: - ASRProvider
    
    let name = "Whisper API"
    
    // MARK: - 私有属性
    
    /// API Key
    private let apiKey: String
    
    /// API URL
    private let baseURL: String
    
    /// 模型名称
    private let model: String
    
    /// URLSession
    private let session: URLSession
    
    // MARK: - 初始化
    
    /// 初始化 Whisper API ASR
    /// - Parameters:
    ///   - apiKey: API Key
    ///   - baseURL: API 地址
    ///   - model: 模型名称，默认 "whisper-1"
    init(
        apiKey: String,
        baseURL: String = Constants.Network.whisperDefaultURL,
        model: String = "whisper-1"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.ASR.timeout
        config.timeoutIntervalForResource = Constants.ASR.timeout
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 转写
    
    func transcribe(audioURL: URL) async throws -> String {
        try await transcribe(audioURL: audioURL, contextHint: nil)
    }
    
    func transcribe(audioURL: URL, contextHint: String?) async throws -> String {
        // 1. 读取音频文件
        let audioData = try Data(contentsOf: audioURL)
        
        // 2. 构建 multipart/form-data 请求
        let boundary = "Boundary-\(UUID().uuidString)"
        
        guard let url = URL(string: baseURL) else {
            throw VoxError.asrAPIError("无效的 API URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // 3. 构建 multipart body
        var body = Data()
        
        // 添加 file 字段
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")
        
        // 添加 model 字段
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("\(model)\r\n")
        
        // 添加 response_format 字段
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.append("json\r\n")
        
        // 添加 prompt 字段（上下文提示，提升 ASR 准确率）
        // Whisper API 支持 prompt 参数来引导转写风格和术语
        if let hint = contextHint, !hint.isEmpty {
            let trimmedHint = String(hint.suffix(200))  // 限制长度，避免过大
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            body.append("\(trimmedHint)\r\n")
        }
        
        // 结束标记
        body.append("--\(boundary)--\r\n")
        
        request.httpBody = body
        
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
    
    /// 解析 Whisper API JSON 响应
    /// 格式：{"text": "转写结果"}
    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            throw VoxError.asrAPIError("响应格式解析失败")
        }
        
        return text
    }
}

// MARK: - Data 扩展（用于 multipart 构建）

private extension Data {
    /// 追加字符串（UTF-8 编码）
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
