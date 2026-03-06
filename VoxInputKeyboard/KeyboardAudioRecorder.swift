// KeyboardAudioRecorder.swift
// VoxInputKeyboard
//
// 键盘扩展专用录音器
// 与主 App AudioRecorder 的关键区别：
//   - AVAudioSession 在 extension 场景下做更保守的 fallback
//   - 录音路径优先 App Group，并显式验证可写
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
    
    // MARK: - 稳定性常量
    
    /// 最长录音时间（秒），超时自动停止
    private static let maxRecordingDuration: TimeInterval = 60.0
    
    /// 录音失败最大重试次数
    private static let maxRetryCount: Int = 2
    
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
                    lastStartError = "prepareToRecord returned false (candidate=\(idx))"
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
                self.recordingURL = url
                self.isRecording = true
                self.silenceDetector.reset()

                os_log("recording started: %{public}@", log: log, type: .info, url.path)
                startMeterTimer()
                startTimeoutTimer()
                return
            } catch {
                lastStartError = "init/record error (candidate=\(idx)): \(error.localizedDescription)"
                os_log("%{public}@", log: log, type: .error, lastStartError)
            }
        }

        if retryCount < Self.maxRetryCount {
            retryCount += 1
            try attemptStart()
            return
        }

        throw VoxError.recordingFailed(lastStartError)
    }

    /// 键盘扩展录音会话配置（带 fallback）
    /// 说明：优先 .record，失败后回退到 .playAndRecord + mixWithOthers
    private func configureAudioSessionForKeyboardRecording(_ session: AVAudioSession) throws {
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try? session.setPreferredSampleRate(Constants.Audio.sampleRate)
            try? session.setPreferredInputNumberOfChannels(Constants.Audio.channels)
            try session.setActive(true, options: [])
            os_log("AudioSession active with .record/.measurement", log: log, type: .info)
            return
        } catch {
            os_log(".record failed, fallback to .playAndRecord: %{public}@", log: log, type: .default, error.localizedDescription)
        }

        do {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
            try? session.setPreferredSampleRate(Constants.Audio.sampleRate)
            try? session.setPreferredInputNumberOfChannels(Constants.Audio.channels)
            try session.setActive(true, options: [])
            os_log("AudioSession active with fallback .playAndRecord", log: log, type: .info)
        } catch {
            throw VoxError.recordingFailed("AudioSession 激活失败: \(error.localizedDescription)")
        }
    }

    /// 停止录音并返回音频文件 URL
    /// - Returns: 有效的录音文件 URL
    /// - Throws: VoxError 如果录音无效
    func stop() throws -> URL {
        stopMeterTimer()
        stopTimeoutTimer()
        
        guard let recorder = audioRecorder else {
            throw VoxError.recordingFailed("没有活跃的录音会话")
        }
        
        recorder.stop()
        self.audioRecorder = nil
        self.isRecording = false
        
        // 释放 AudioSession（通知宿主 App 恢复音频）
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
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
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        cleanupTempFile()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    private func sessionSnapshot(_ session: AVAudioSession) -> String {
        let category = session.category.rawValue
        let mode = session.mode.rawValue
        let inputCount = session.currentRoute.inputs.count
        let outputCount = session.currentRoute.outputs.count
        return "category=\(category), mode=\(mode), routeIn=\(inputCount), routeOut=\(outputCount)"
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
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        
        recorder.updateMeters()
        let peak = recorder.peakPower(forChannel: 0)
        
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
}

// MARK: - AVAudioRecorderDelegate

extension KeyboardAudioRecorder: AVAudioRecorderDelegate {
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            isRecording = false
            onRecordingInterrupted?()
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        isRecording = false
        onRecordingInterrupted?()
    }
}
