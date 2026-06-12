// AppleSpeechASR.swift
// Shared
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
            group.addTask {
                // beta.61: 持有识别任务，超时/取消时取消它并确保 continuation 恰好 resume 一次，
                // 避免识别器后台空转与 continuation 泄漏（review L1）。
                let box = SpeechRecognitionBox()
                let result: SFSpeechRecognitionResult = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        let task = recognizer.recognitionTask(with: request) { result, error in
                            if let error {
                                box.finish(.failure(VoxError.asrAPIError("本地识别失败: \(error.localizedDescription)")))
                                return
                            }
                            guard let result, result.isFinal else { return }  // 忽略 partial
                            box.finish(.success(result))
                        }
                        box.attach(continuation: continuation, task: task)
                    }
                } onCancel: {
                    box.cancel()
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

/// beta.61: 串行化 SFSpeechRecognitionTask 的 continuation，保证恰好 resume 一次，
/// 并在取消时真正取消底层识别任务（review L1）。
private final class SpeechRecognitionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>?
    private var task: SFSpeechRecognitionTask?
    private var isCancelled = false

    func attach(continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>, task: SFSpeechRecognitionTask) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            task.cancel()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        self.task = task
        lock.unlock()
    }

    func finish(_ outcome: Result<SFSpeechRecognitionResult, Error>) {
        lock.lock()
        guard let cont = continuation else { lock.unlock(); return }
        continuation = nil
        lock.unlock()
        cont.resume(with: outcome)
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let cont = continuation
        continuation = nil
        let runningTask = task
        lock.unlock()
        runningTask?.cancel()
        cont?.resume(throwing: CancellationError())
    }
}
