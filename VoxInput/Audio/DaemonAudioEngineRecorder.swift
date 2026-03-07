// DaemonAudioEngineRecorder.swift
// VoxInput
//
// 后台守护进程专用录音器：基于 AVAudioEngine（不依赖 AVAudioRecorder）
// beta.40: Typeless Always-On 架构（引擎常驻 + 软开关采集）

import AVFoundation
import Foundation

@MainActor
final class DaemonAudioEngineRecorder {

    // MARK: - Public

    var onMaxDurationReached: (() -> Void)?
    var onRuntimeError: ((String) -> Void)?

    /// 语义：当前是否处于“采集中”会话（start->stop 之间）
    private(set) var isRecording: Bool = false

    // MARK: - Private

    private let silenceDetector = SilenceDetector()

    private var engine: AVAudioEngine?
    private var inputFormat: AVAudioFormat?

    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var timeoutTimer: Timer?

    /// 软开关：tap 持续产出 buffer，但只有 true 才落盘
    private var isCapturing: Bool = false
    /// 引擎是否已完成 prime（session active + engine running + tap installed）
    private var isPrimed: Bool = false

    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var runtimeError: String?

    private static let maxRecordingDuration: TimeInterval = 60.0

    private var tempRecordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(Constants.Audio.tempFileName)
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

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.handleIncomingBuffer(buffer)
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

        runtimeError = nil
        silenceDetector.reset()
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

        self.audioFile = outputFile
        self.recordingURL = url
        self.targetFormat = target
        self.converter = converter

        isCapturing = true
        isRecording = true
        startTimeoutTimer()
    }

    /// stop 命令：只关闭采集，不停引擎（黄灯继续亮，守护进程保持可唤醒）
    func stop() throws -> URL {
        stopTimeoutTimer()

        guard isRecording else {
            throw VoxError.recordingFailed("没有活跃的录音会话")
        }

        isCapturing = false
        isRecording = false

        let localRuntimeError = runtimeError
        runtimeError = nil

        guard let url = recordingURL else {
            clearCaptureResources()
            throw VoxError.audioFileInvalid
        }

        clearCaptureResources(keepURL: true)

        if let localRuntimeError, !localRuntimeError.isEmpty {
            cleanupTempFile()
            throw VoxError.recordingFailed(localRuntimeError)
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        guard fileSize >= Constants.Audio.minimumFileSize else {
            cleanupTempFile()
            throw VoxError.audioTooShort
        }

        guard silenceDetector.hasDetectedSound else {
            cleanupTempFile()
            throw VoxError.audioEmpty
        }

        recordingURL = nil
        return url
    }

    /// cancel 命令：默认只取消本次采集，保留已 prime 引擎
    func cancel(keepEngineAlive: Bool = true) {
        stopTimeoutTimer()

        isCapturing = false
        isRecording = false
        runtimeError = nil

        clearCaptureResources()
        cleanupTempFile()

        if !keepEngineAlive {
            sleepShutdown()
        }
    }

    /// 仅在超时休眠或明确不需要保活时调用：真正关引擎 + 释放 session
    func sleepShutdown() {
        stopTimeoutTimer()

        isCapturing = false
        isRecording = false
        runtimeError = nil

        clearCaptureResources()
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
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecordingDuration, repeats: false) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.onMaxDurationReached?()
        }
    }

    private func stopTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    private func clearCaptureResources(keepURL: Bool = false) {
        audioFile = nil
        targetFormat = nil
        converter = nil
        if !keepURL {
            recordingURL = nil
        }
    }

    private func cleanupAfterFailure(removeTapOn inputNode: AVAudioInputNode) {
        inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        inputFormat = nil
        isPrimed = false
        isCapturing = false
        isRecording = false
        clearCaptureResources()
        cleanupTempFile()
    }

    private func handleIncomingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isCapturing, isRecording else { return }
        guard let converter, let targetFormat, let audioFile else { return }

        do {
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(targetFormat.sampleRate) * buffer.frameLength / AVAudioFrameCount(max(buffer.format.sampleRate, 1)) + 1024
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
                updateSilenceDetector(with: convertedBuffer)
            }
        } catch {
            failRuntime(error)
        }
    }

    private func updateSilenceDetector(with buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var peak: Float = 0
        var index = 0
        let step = 32
        while index < frameCount {
            let value = abs(data[index])
            if value > peak { peak = value }
            index += step
        }

        let safePeak = max(peak, 0.000_0001)
        let peakDB = 20.0 * log10(safePeak)
        _ = silenceDetector.update(peakPower: peakDB)
    }

    private func failRuntime(_ error: Error) {
        let message = error.localizedDescription
        runtimeError = message

        stopTimeoutTimer()
        isCapturing = false
        isRecording = false

        clearCaptureResources(keepURL: true)

        onRuntimeError?(message)
    }
}
