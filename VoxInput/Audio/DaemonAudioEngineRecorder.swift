// DaemonAudioEngineRecorder.swift
// VoxInput
//
// 后台守护进程专用录音器：基于 AVAudioEngine（不依赖 AVAudioRecorder）

import AVFoundation
import Foundation

@MainActor
final class DaemonAudioEngineRecorder {

    // MARK: - Public

    var onMaxDurationReached: (() -> Void)?
    var onRuntimeError: ((String) -> Void)?

    private(set) var isRecording: Bool = false

    // MARK: - Private

    private let silenceDetector = SilenceDetector()

    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var timeoutTimer: Timer?

    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var runtimeError: String?

    private static let maxRecordingDuration: TimeInterval = 60.0

    private var tempRecordingURL: URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent(Constants.Audio.tempFileName)
    }

    func start() throws {
        cleanupTempFile()
        runtimeError = nil

        try configureSessionForRecord()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

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

        let converter = AVAudioConverter(from: inputFormat, to: target)
        if converter == nil {
            throw VoxError.recordingFailed("音频格式转换器初始化失败")
        }

        self.engine = engine
        self.audioFile = outputFile
        self.recordingURL = url
        self.targetFormat = target
        self.converter = converter
        self.silenceDetector.reset()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.handleIncomingBuffer(buffer)
        }

        do {
            try engine.start()
        } catch {
            cleanupAfterFailure(removeTapOn: inputNode)
            throw VoxError.recordingFailed("AVAudioEngine 启动失败: \(error.localizedDescription)")
        }

        isRecording = true
        startTimeoutTimer()
    }

    func stop() throws -> URL {
        stopTimeoutTimer()

        guard let engine else {
            throw VoxError.recordingFailed("没有活跃的录音会话")
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        self.engine = nil
        self.audioFile = nil
        self.targetFormat = nil
        self.converter = nil
        self.isRecording = false

        if let runtimeError, !runtimeError.isEmpty {
            cleanupTempFile()
            throw VoxError.recordingFailed(runtimeError)
        }

        guard let url = recordingURL else {
            throw VoxError.audioFileInvalid
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

        return url
    }

    func cancel() {
        stopTimeoutTimer()

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        engine = nil
        audioFile = nil
        targetFormat = nil
        converter = nil
        runtimeError = nil
        isRecording = false

        cleanupTempFile()
    }

    func cleanupTempFile() {
        let url = tempRecordingURL
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
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

    private func cleanupAfterFailure(removeTapOn inputNode: AVAudioInputNode) {
        inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        audioFile = nil
        targetFormat = nil
        converter = nil
        isRecording = false
        cleanupTempFile()
    }

    private func handleIncomingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecording else { return }
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
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        engine = nil
        audioFile = nil
        targetFormat = nil
        converter = nil
        isRecording = false

        onRuntimeError?(message)
    }
}
