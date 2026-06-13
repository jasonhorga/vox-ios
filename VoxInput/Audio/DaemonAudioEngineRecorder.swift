// DaemonAudioEngineRecorder.swift
// VoxInput
//
// 后台守护进程专用录音器：基于 AVAudioEngine（不依赖 AVAudioRecorder）
// beta.40: Typeless Always-On 架构（引擎常驻 + 软开关采集）
// M6: 采集状态搬入线程安全的 DaemonCaptureSink，tap 回调（实时音频线程）不再触碰 @MainActor 状态

import AVFoundation
import Foundation

/// 实时音频线程与主线程共享的采集状态。
///
/// M6: `installTap` 的回调在 AVAudioEngine 的音频线程上执行，原先它同步调用 @MainActor 的
/// `handleIncomingBuffer`、直接读写 `audioFile/converter/isCapturing/hasReceivedAudio/runtimeError`
/// 等 actor 隔离状态，而主线程的 `stop()/cancel()` 同时也在改这些——数据竞争。
/// 现在把这些状态全部收进本类，用 `NSLock` 保护，所有方法都可从音频线程安全调用；
/// 录音器（@MainActor）只通过 `begin/finish` 与之交互。`@unchecked Sendable` 由内部锁保证安全。
final class DaemonCaptureSink: @unchecked Sendable {

    private let lock = NSLock()

    // 以下全部受 lock 保护
    private var capturing = false
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var received = false
    private var runtimeError: String?
    /// 采集中途出错时回调（只触发一次），由录音器跳回主线程处理
    private var onError: (@Sendable (String) -> Void)?

    /// 开始落盘（start 时由主线程调用）
    func begin(
        file: AVAudioFile,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        onError: (@Sendable (String) -> Void)?
    ) {
        lock.lock(); defer { lock.unlock() }
        self.audioFile = file
        self.converter = converter
        self.targetFormat = targetFormat
        self.onError = onError
        self.received = false
        self.runtimeError = nil
        self.capturing = true
    }

    /// 停止落盘并取出结果（stop/cancel/sleep 时由主线程调用），同时清理采集资源
    @discardableResult
    func finish() -> (received: Bool, runtimeError: String?) {
        lock.lock(); defer { lock.unlock() }
        capturing = false
        let result = (received, runtimeError)
        audioFile = nil
        converter = nil
        targetFormat = nil
        onError = nil
        // 取完结果后清空，避免下次（begin 之前）误报上一段的状态
        received = false
        runtimeError = nil
        return result
    }

    /// tap 回调（实时音频线程）调用：格式转换 + 落盘。线程安全。
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard capturing, let converter, let targetFormat, let audioFile else {
            lock.unlock()
            return
        }

        var firedError: (cb: (@Sendable (String) -> Void), msg: String)?
        do {
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(targetFormat.sampleRate) * buffer.frameLength
                    / AVAudioFrameCount(max(buffer.format.sampleRate, 1)) + 1024
            ) else {
                throw VoxError.recordingFailed("音频缓冲区分配失败")
            }

            var sourceConsumed = false
            let status = converter.convert(to: convertedBuffer, error: nil) { _, outStatus in
                if sourceConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                } else {
                    sourceConsumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }
            }

            guard status != .error else {
                throw VoxError.recordingFailed("音频格式转换失败")
            }

            if convertedBuffer.frameLength > 0 {
                try audioFile.write(from: convertedBuffer)
                received = true
            }
        } catch {
            let message = error.localizedDescription
            runtimeError = message
            capturing = false
            if let cb = onError {
                firedError = (cb, message)
                onError = nil   // 只触发一次
            }
        }

        lock.unlock()
        // 在锁外回调，避免在持锁时执行外部代码
        if let firedError {
            firedError.cb(firedError.msg)
        }
    }
}

@MainActor
final class DaemonAudioEngineRecorder {

    // MARK: - Public

    var onMaxDurationReached: (() -> Void)?
    var onRuntimeError: ((String) -> Void)?

    /// 语义：当前是否处于“采集中”会话（start->stop 之间）
    private(set) var isRecording: Bool = false

    // MARK: - Private

    private var engine: AVAudioEngine?
    private var inputFormat: AVAudioFormat?

    private var recordingURL: URL?
    private var timeoutTimer: Timer?

    /// M6: 采集状态（audioFile/converter/落盘/错误）全部由线程安全的 sink 持有
    private let sink = DaemonCaptureSink()

    /// 引擎是否已完成 prime（session active + engine running + tap installed）
    private var isPrimed: Bool = false

    // 最长录音时长集中在 Constants.Audio.maxRecordingDuration（M7: 由 1h 收紧到 10min，到点自动停止）

    /// M3: 守护进程用独立临时文件名，避免与主 App 直录路径（AudioRecorder）互踩同一文件
    private var tempRecordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(Constants.Audio.daemonTempFileName)
    }

    // MARK: - Typeless lifecycle

    /// beta.40: 只做底层 prime，不开启采集
    func primeIfNeeded() throws {
        if isPrimed, let engine, engine.isRunning {
            return
        }

        try configureSessionForRecord()

        let engine = self.engine ?? AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        self.inputFormat = inputFormat

        // M6: tap 闭包只捕获线程安全的 sink，不捕获 self（不触碰 @MainActor 状态）
        let sink = self.sink
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
            sink.append(buffer)
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                cleanupAfterFailure(removeTapOn: inputNode)
                throw VoxError.recordingFailed("AVAudioEngine 启动失败: \(error.localizedDescription)")
            }
        }

        self.engine = engine
        self.isPrimed = true
    }

    /// start 命令：不负责启动引擎（优先复用 prime），只开启本次采集会话
    func start() throws {
        guard !isRecording else { return }

        cleanupTempFile()

        // 若外部尚未 prime，兜底一次（保证行为稳定）
        try primeIfNeeded()

        guard let inputFormat else {
            throw VoxError.recordingFailed("输入音频格式不可用")
        }

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.Audio.sampleRate,
            channels: AVAudioChannelCount(Constants.Audio.channels),
            interleaved: false
        ) else {
            throw VoxError.recordingFailed("无法创建目标音频格式")
        }

        let url = tempRecordingURL
        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: target.sampleRate,
            AVNumberOfChannelsKey: Int(target.channelCount),
            AVLinearPCMBitDepthKey: Constants.Audio.bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let outputFile = try AVAudioFile(forWriting: url, settings: fileSettings)
        guard let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw VoxError.recordingFailed("音频格式转换器初始化失败")
        }

        self.recordingURL = url

        // M6: 把采集资源交给 sink；中途出错时跳回主线程处理
        sink.begin(file: outputFile, converter: converter, targetFormat: target) { [weak self] message in
            Task { @MainActor in
                self?.handleRuntimeError(message)
            }
        }

        isRecording = true
        startTimeoutTimer()
    }

    /// stop 命令：只关闭采集，不停引擎（黄灯继续亮，守护进程保持可唤醒）
    func stop() throws -> URL {
        stopTimeoutTimer()

        guard isRecording else {
            throw VoxError.recordingFailed("没有活跃的录音会话")
        }

        isRecording = false

        // M6: 关闭采集并取回结果（received / runtimeError），sink 同时清理采集资源
        let result = sink.finish()

        guard let url = recordingURL else {
            recordingURL = nil
            throw VoxError.audioFileInvalid
        }
        recordingURL = nil

        if let localRuntimeError = result.runtimeError, !localRuntimeError.isEmpty {
            cleanupTempFile()
            throw VoxError.recordingFailed(localRuntimeError)
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        guard fileSize >= Constants.Audio.minimumFileSize else {
            cleanupTempFile()
            throw VoxError.audioTooShort
        }

        guard result.received else {
            cleanupTempFile()
            throw VoxError.audioEmpty
        }

        return url
    }

    /// cancel 命令：默认只取消本次采集，保留已 prime 引擎
    func cancel(keepEngineAlive: Bool = true) {
        stopTimeoutTimer()

        isRecording = false
        sink.finish()
        recordingURL = nil
        cleanupTempFile()

        if !keepEngineAlive {
            sleepShutdown()
        }
    }

    /// 仅在超时休眠或明确不需要保活时调用：真正关引擎 + 释放 session
    func sleepShutdown() {
        stopTimeoutTimer()

        isRecording = false
        sink.finish()
        recordingURL = nil
        cleanupTempFile()

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        self.engine = nil
        self.inputFormat = nil
        self.isPrimed = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // 休眠阶段失败不阻断主流程
        }
    }

    func cleanupTempFile() {
        let url = tempRecordingURL
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func configureSessionForRecord() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setActive(true, options: [])
    }

    private func startTimeoutTimer() {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Constants.Audio.maxRecordingDuration, repeats: false) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.onMaxDurationReached?()
        }
    }

    private func stopTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    private func cleanupAfterFailure(removeTapOn inputNode: AVAudioInputNode) {
        inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        inputFormat = nil
        isPrimed = false
        isRecording = false
        sink.finish()
        recordingURL = nil
        cleanupTempFile()
    }

    /// 采集中途出错（来自 sink，已跳回主线程）：收尾计时器/状态机并上报。
    /// sink 已自行停止采集并记录错误；临时文件保留，由后续 stop/cancel 清理。
    private func handleRuntimeError(_ message: String) {
        guard isRecording else { return }
        stopTimeoutTimer()
        isRecording = false
        onRuntimeError?(message)
    }
}
