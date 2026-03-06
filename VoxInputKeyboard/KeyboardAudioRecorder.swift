// KeyboardAudioRecorder.swift
// VoxInputKeyboard
//
// 键盘扩展专用录音器
// 与主 App AudioRecorder 的关键区别：
//   - AVAudioSession 在 extension 场景下做更保守的 fallback
//   - 录音路径优先 App Group，并显式验证可写
//   - AVAudioRecorder 失败时自动回退 AVAudioEngine（规避 record() returned false）
//   - 无 Observation 依赖（通过回调通知状态）

import AVFoundation
import Foundation
import os.log

private let log = OSLog(subsystem: "com.jasonhorga.vox.keyboard", category: "KeyboardAudioRecorder")

/// 键盘扩展专用录音管理器
final class KeyboardAudioRecorder: NSObject {

    // MARK: - 状态

    /// 当前是否正在录音
    private(set) var isRecording: Bool = false

    // MARK: - 回调

    /// 电平更新回调：(normalizedLevel, peakPowerDB)
    var onLevelUpdate: ((Float, Float) -> Void)?

    /// 静音超时回调
    var onSilenceTimeout: (() -> Void)?

    /// 录音异常结束回调
    var onRecordingInterrupted: (() -> Void)?

    // MARK: - 私有属性

    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var recordingURL: URL?
    private let silenceDetector = SilenceDetector()

    /// 音频会话串行队列（避免主线程阻塞和并发 setActive 竞争）
    private let audioSessionQueue = DispatchQueue(label: "com.jasonhorga.vox.keyboard.audio-session", qos: .userInitiated)

    /// 录音后端（AVAudioRecorder 或 AVAudioEngine）
    private enum ActiveBackend {
        case none
        case recorder
        case engine
    }
    private var activeBackend: ActiveBackend = .none

    // AVAudioEngine fallback
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var engineTapInstalled: Bool = false
    private var latestEnginePeakPower: Float = -160.0

    // MARK: - 稳定性常量

    /// 最长录音时间（秒），超时自动停止
    private static let maxRecordingDuration: TimeInterval = 60.0

    /// 录音失败最大重试次数
    private static let maxRetryCount: Int = 2

    /// AudioSession 激活重试延迟（微秒）
    private static let activationRetryDelaysUs: [UInt32] = [0, 20_000, 80_000, 180_000]

    /// AVAudioEngine 启动前重试延迟（微秒）
    private static let engineStartDelaysUs: [UInt32] = [0, 50_000, 120_000]

    /// 超时自动停止回调
    var onMaxDurationReached: (() -> Void)?

    /// 超时定时器
    private var timeoutTimer: Timer?

    /// 当前重试次数
    private var retryCount: Int = 0

    // MARK: - 录音控制

    /// 开始录音（带重试逻辑，最多 2 次）
    /// - Throws: VoxError 如果 AudioSession 配置或录音启动失败
    func start() throws {
        retryCount = 0

        let permission = AVAudioSession.sharedInstance().recordPermission
        os_log("start recording, permission=%{public}@", log: log, type: .info, String(describing: permission))
        guard permission == .granted else {
            throw VoxError.microphonePermissionDenied
        }

        try attemptStart()
    }

    /// 尝试启动录音
    private func attemptStart() throws {
        cleanupTempFile()

        let session = AVAudioSession.sharedInstance()

        do {
            try configureAudioSessionForKeyboardRecording(session)
        } catch {
            os_log("AudioSession configure failed: %{public}@", log: log, type: .error, error.localizedDescription)
            if retryCount < Self.maxRetryCount {
                retryCount += 1
                try attemptStart()
                return
            }
            throw VoxError.recordingFailed("AudioSession 配置失败: \(error.localizedDescription)")
        }

        let url = try prepareWritableRecordingURL()

        do {
            if try startWithAVAudioRecorder(url: url, session: session) {
                return
            }

            // AVAudioRecorder 在部分键盘扩展场景会持续 record() false，回退到 AVAudioEngine
            os_log("AVAudioRecorder failed on all candidates, fallback to AVAudioEngine", log: log, type: .default)
            try startWithAVAudioEngine(url: url, session: session)
            return
        } catch {
            if retryCount < Self.maxRetryCount {
                retryCount += 1
                os_log("start failed, retry=%{public}d, error=%{public}@", log: log, type: .default, retryCount, error.localizedDescription)
                try attemptStart()
                return
            }
            throw VoxError.recordingFailed(error.localizedDescription)
        }
    }

    /// AVAudioRecorder 路径启动（成功返回 true，失败返回 false）
    private func startWithAVAudioRecorder(url: URL, session: AVAudioSession) throws -> Bool {
        // 候选参数：先 16k PCM（与现有 ASR 协议一致），再 44.1k PCM 兜底。
        let settingsCandidates: [[String: Any]] = [
            [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: Constants.Audio.sampleRate,
                AVNumberOfChannelsKey: Constants.Audio.channels,
                AVLinearPCMBitDepthKey: Constants.Audio.bitDepth,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ],
            [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: Constants.Audio.channels,
                AVLinearPCMBitDepthKey: Constants.Audio.bitDepth,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        ]

        var lastStartError: String = "unknown"

        for (idx, settings) in settingsCandidates.enumerated() {
            do {
                let recorder = try AVAudioRecorder(url: url, settings: settings)
                recorder.delegate = self
                recorder.isMeteringEnabled = true

                guard recorder.prepareToRecord() else {
                    lastStartError = "prepareToRecord returned false (candidate=\(idx), \(sessionSnapshot(session)))"
                    os_log("%{public}@", log: log, type: .error, lastStartError)
                    continue
                }

                guard recorder.record() else {
                    let snapshot = sessionSnapshot(session)
                    lastStartError = "record() returned false (candidate=\(idx), \(snapshot))"
                    os_log("%{public}@", log: log, type: .error, lastStartError)
                    continue
                }

                self.audioRecorder = recorder
                self.audioFile = nil
                self.recordingURL = url
                self.activeBackend = .recorder
                self.isRecording = true
                self.silenceDetector.reset()

                os_log("recording started by AVAudioRecorder: %{public}@", log: log, type: .info, url.path)
                startMeterTimer()
                startTimeoutTimer()
                return true
            } catch {
                lastStartError = "init/record error (candidate=\(idx)): \(describeError(error)), \(sessionSnapshot(session))"
                os_log("%{public}@", log: log, type: .error, lastStartError)
            }
        }

        os_log("AVAudioRecorder all candidates failed: %{public}@", log: log, type: .error, lastStartError)
        return false
    }

    /// AVAudioEngine fallback 启动（用于规避键盘扩展下 AVAudioRecorder.record() 返回 false）
    private func startWithAVAudioEngine(url: URL, session: AVAudioSession) throws {
        // 先清理旧 tap / 状态
        audioEngine.stop()
        if engineTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            engineTapInstalled = false
        }
        audioFile = nil
        latestEnginePeakPower = -160.0

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // 保持文件扩展名为 .wav，并使用 inputFormat.settings 避免 write(from:) 因格式不匹配失败
        // （键盘扩展环境下稳定性优先；ASR 可接受常见 WAV/PCM 采样率）
        let fileSettings = inputFormat.settings

        let file = try AVAudioFile(forWriting: url, settings: fileSettings)
        self.audioFile = file

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            // Tap 回调在实时音频线程，不做重操作
            guard let self else { return }

            // 更新电平（基于当前 buffer）
            let peak = Self.peakPowerFromBuffer(buffer)
            self.latestEnginePeakPower = peak

            do {
                try file.write(from: buffer)
            } catch {
                os_log("AVAudioEngine write failed: %{public}@", log: log, type: .error, self.describeError(error))
            }
        }

        engineTapInstalled = true
        audioEngine.prepare()

        var startError: Error?
        for delay in Self.engineStartDelaysUs {
            if delay > 0 { usleep(delay) }

            do {
                // 终极兜底：在音频队列中再次激活 session（规避 kAudioSessionNotActive / 'what'）
                try runOnAudioSessionQueue {
                    try session.setActive(true, options: [])
                }
                try audioEngine.start()

                self.audioRecorder = nil
                self.recordingURL = url
                self.activeBackend = .engine
                self.isRecording = true
                self.silenceDetector.reset()

                os_log("recording started by AVAudioEngine: %{public}@", log: log, type: .info, url.path)
                startMeterTimer()
                startTimeoutTimer()
                return
            } catch {
                startError = error
                os_log(
                    "AVAudioEngine start retry failed: delayUs=%{public}u error=%{public}@ snapshot=%{public}@",
                    log: log,
                    type: .error,
                    delay,
                    describeError(error),
                    sessionSnapshot(session)
                )
            }
        }

        if engineTapInstalled {
            inputNode.removeTap(onBus: 0)
            engineTapInstalled = false
        }
        audioFile = nil

        throw VoxError.recordingFailed("AVAudioEngine 启动失败: \(describeError(startError ?? NSError(domain: "AVAudioEngine", code: -1))) | \(sessionSnapshot(session))")
    }

    /// 键盘扩展录音会话配置（带多档 fallback）
    private func configureAudioSessionForKeyboardRecording(_ session: AVAudioSession) throws {
        // 实测：键盘扩展中 .record/.measurement 可能路由存在但 record() 仍 false。
        // 优先尝试 .playAndRecord/.default + mixWithOthers，再尝试更激进/保守组合。
        let candidates: [(AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = [
            (.playAndRecord, .default, [.mixWithOthers]),
            (.playAndRecord, .measurement, [.mixWithOthers]),
            (.record, .measurement, []),
            (.record, .default, [])
        ]

        var lastError: Error?

        for (idx, candidate) in candidates.enumerated() {
            do {
                try runOnAudioSessionQueue {
                    // 先清理旧状态，避免上一个宿主/会话残留
                    try? session.setActive(false, options: .notifyOthersOnDeactivation)
                    try session.setCategory(candidate.0, mode: candidate.1, options: candidate.2)
                    try? session.setPreferredSampleRate(Constants.Audio.sampleRate)
                    try? session.setPreferredInputNumberOfChannels(Constants.Audio.channels)
                    try? session.setPreferredIOBufferDuration(0.01)

                    var activateError: Error?
                    for delay in Self.activationRetryDelaysUs {
                        if delay > 0 { usleep(delay) }
                        do {
                            try session.setActive(true, options: [])
                            activateError = nil
                            break
                        } catch {
                            activateError = error
                            os_log(
                                "AudioSession activate retry failed: candidate=%{public}d delayUs=%{public}u error=%{public}@ snapshot=%{public}@",
                                log: log,
                                type: .default,
                                idx,
                                delay,
                                describeError(error),
                                sessionSnapshot(session)
                            )
                        }
                    }

                    if let activateError {
                        throw activateError
                    }
                }

                os_log(
                    "AudioSession active candidate=%{public}d category=%{public}@ mode=%{public}@ snapshot=%{public}@",
                    log: log,
                    type: .info,
                    idx,
                    candidate.0.rawValue,
                    candidate.1.rawValue,
                    sessionSnapshot(session)
                )
                return
            } catch {
                lastError = error
                os_log(
                    "AudioSession candidate=%{public}d failed: %{public}@ snapshot=%{public}@",
                    log: log,
                    type: .error,
                    idx,
                    describeError(error),
                    sessionSnapshot(session)
                )
            }
        }

        throw VoxError.recordingFailed("AudioSession 激活失败: \(describeError(lastError ?? NSError(domain: "AVAudioSession", code: -1))) | \(sessionSnapshot(session))")
    }

    /// 停止录音并返回音频文件 URL
    /// - Returns: 有效的录音文件 URL
    /// - Throws: VoxError 如果录音无效
    func stop() throws -> URL {
        stopMeterTimer()
        stopTimeoutTimer()

        guard isRecording else {
            throw VoxError.recordingFailed("没有活跃的录音会话")
        }

        switch activeBackend {
        case .recorder:
            audioRecorder?.stop()
            audioRecorder = nil

        case .engine:
            if engineTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                engineTapInstalled = false
            }
            audioEngine.stop()

            audioFile = nil

        case .none:
            throw VoxError.recordingFailed("没有可停止的录音后端")
        }

        self.activeBackend = .none
        self.isRecording = false

        // 释放 AudioSession（通知宿主 App 恢复音频）
        try? runOnAudioSessionQueue {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        guard let url = recordingURL else {
            throw VoxError.audioFileInvalid
        }

        // 检查文件大小
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attrs[.size] as? Int ?? 0
        guard fileSize >= Constants.Audio.minimumFileSize else {
            cleanupTempFile()
            throw VoxError.audioTooShort
        }

        // 检查是否有有效声音
        guard silenceDetector.hasDetectedSound else {
            cleanupTempFile()
            throw VoxError.audioEmpty
        }

        return url
    }

    /// 取消录音
    func cancel() {
        stopMeterTimer()
        stopTimeoutTimer()

        switch activeBackend {
        case .recorder:
            audioRecorder?.stop()
            audioRecorder = nil
        case .engine:
            if engineTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                engineTapInstalled = false
            }
            audioEngine.stop()
            audioFile = nil
        case .none:
            break
        }

        activeBackend = .none
        isRecording = false
        cleanupTempFile()
        try? runOnAudioSessionQueue {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - 录音路径

    /// 获取可写录音路径。优先 App Group tmp，失败回退系统 tmp。
    private func prepareWritableRecordingURL() throws -> URL {
        let fileManager = FileManager.default

        var candidates: [URL] = []
        if let groupTmp = AppGroup.tempDirectory {
            candidates.append(groupTmp)
        }
        candidates.append(fileManager.temporaryDirectory)

        var errors: [String] = []

        for dir in candidates {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

                // 用探针文件验证可写性（比 isWritableFile 更可靠）
                let probeURL = dir.appendingPathComponent(".vox_write_probe")
                try Data("ok".utf8).write(to: probeURL, options: .atomic)
                try? fileManager.removeItem(at: probeURL)

                let url = dir.appendingPathComponent(Constants.Audio.tempFileName)
                try? fileManager.removeItem(at: url) // 防止残留旧文件
                os_log("recording dir selected: %{public}@", log: log, type: .info, dir.path)
                return url
            } catch {
                errors.append("\(dir.path): \(error.localizedDescription)")
            }
        }

        throw VoxError.recordingFailed("无可写录音目录: \(errors.joined(separator: " | "))")
    }

    private func runOnAudioSessionQueue<T>(_ block: () throws -> T) throws -> T {
        if DispatchQueue.getSpecific(key: Self.audioSessionSpecificKey) != nil {
            return try block()
        }

        var output: Result<T, Error>!
        audioSessionQueue.sync {
            output = Result { try block() }
        }
        return try output.get()
    }

    private static let audioSessionSpecificKey = DispatchSpecificKey<UInt8>()

    override init() {
        super.init()
        audioSessionQueue.setSpecific(key: Self.audioSessionSpecificKey, value: 1)
    }

    private func sessionSnapshot(_ session: AVAudioSession) -> String {
        let category = session.category.rawValue
        let mode = session.mode.rawValue
        let sampleRate = String(format: "%.1f", session.sampleRate)
        let preferredSampleRate = String(format: "%.1f", session.preferredSampleRate)
        let ioBuffer = String(format: "%.4f", session.ioBufferDuration)
        let preferredIOBuffer = String(format: "%.4f", session.preferredIOBufferDuration)
        let inputAvailable = session.isInputAvailable
        let otherAudioPlaying = session.isOtherAudioPlaying

        let routeInputs = session.currentRoute.inputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")
        let routeOutputs = session.currentRoute.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")

        let availableInputs = (session.availableInputs ?? [])
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")

        return "category=\(category), mode=\(mode), sampleRate=\(sampleRate), prefSampleRate=\(preferredSampleRate), ioBuf=\(ioBuffer), prefIoBuf=\(preferredIOBuffer), inputAvailable=\(inputAvailable), otherAudioPlaying=\(otherAudioPlaying), routeIn=[\(routeInputs)], routeOut=[\(routeOutputs)], availableInputs=[\(availableInputs)]"
    }

    private func describeError(_ error: Error) -> String {
        let nsError = error as NSError
        let fourCC = fourCCString(for: nsError.code)
        return "domain=\(nsError.domain), code=\(nsError.code), fourCC=\(fourCC), desc=\(nsError.localizedDescription)"
    }

    /// 将可能的 OSStatus code 转为 fourCC（例如 2003329396 -> 'what'）
    private func fourCCString(for code: Int) -> String {
        guard code >= Int(Int32.min), code <= Int(Int32.max) else {
            return "n/a"
        }

        let u = UInt32(bitPattern: Int32(code))
        let chars: [CChar] = [
            CChar((u >> 24) & 0xff),
            CChar((u >> 16) & 0xff),
            CChar((u >> 8) & 0xff),
            CChar(u & 0xff),
            0
        ]

        if chars.prefix(4).allSatisfy({ $0 >= 32 && $0 <= 126 }) {
            return String(cString: chars)
        }
        return "n/a"
    }

    // MARK: - 电平采样

    private func startMeterTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: Constants.Audio.meterInterval, repeats: true) { [weak self] _ in
            self?.updateMeters()
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    /// 启动超时定时器（最长 60 秒自动停止）
    private func startTimeoutTimer() {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecordingDuration, repeats: false) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.onMaxDurationReached?()
        }
    }

    /// 停止超时定时器
    private func stopTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    private func updateMeters() {
        guard isRecording else { return }

        let peak: Float
        switch activeBackend {
        case .recorder:
            guard let recorder = audioRecorder, recorder.isRecording else { return }
            recorder.updateMeters()
            peak = recorder.peakPower(forChannel: 0)
        case .engine:
            peak = latestEnginePeakPower
        case .none:
            return
        }

        // dB 到 0.0~1.0 映射
        let minDB: Float = -60.0
        let normalizedLevel: Float
        if peak < minDB {
            normalizedLevel = 0.0
        } else if peak >= 0 {
            normalizedLevel = 1.0
        } else {
            normalizedLevel = (peak - minDB) / (0 - minDB)
        }

        // 通知回调
        onLevelUpdate?(normalizedLevel, peak)

        // 静音检测
        if silenceDetector.update(peakPower: peak) {
            onSilenceTimeout?()
        }
    }

    // MARK: - 文件清理

    /// 清理临时录音文件
    func cleanupTempFile() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    // MARK: - Helpers

    /// 从 PCM 浮点 buffer 估算峰值 dB
    private static func peakPowerFromBuffer(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return -160.0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return -160.0 }

        let channels = Int(buffer.format.channelCount)
        var maxSample: Float = 0.0

        for channel in 0..<channels {
            let samples = channelData[channel]
            for i in 0..<frameLength {
                let value = fabsf(samples[i])
                if value > maxSample {
                    maxSample = value
                }
            }
        }

        guard maxSample > 0 else { return -160.0 }
        let db = 20.0 * log10f(maxSample)
        return max(db, -160.0)
    }
}

// MARK: - AVAudioRecorderDelegate

extension KeyboardAudioRecorder: AVAudioRecorderDelegate {

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            isRecording = false
            activeBackend = .none
            onRecordingInterrupted?()
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        isRecording = false
        activeBackend = .none
        onRecordingInterrupted?()
    }
}
