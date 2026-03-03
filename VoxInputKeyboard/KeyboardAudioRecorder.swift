// KeyboardAudioRecorder.swift
// VoxInputKeyboard
//
// 键盘扩展专用录音器
// 与主 App AudioRecorder 的关键区别：
//   - AVAudioSession 使用 .playAndRecord + .mixWithOthers（不中断宿主 App 音频）
//   - 更严格的内存控制
//   - 无 Observation 依赖（通过回调通知状态）

import AVFoundation
import Foundation

/// 键盘扩展专用录音管理器
/// 使用 .playAndRecord + .mixWithOthers 模式，避免中断宿主 App 音频
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
    
    /// 临时录音文件 URL
    private var tempRecordingURL: URL {
        // 优先使用 App Group 共享容器，回退到系统 temp
        let dir = AppGroup.tempDirectory ?? FileManager.default.temporaryDirectory
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        return dir.appendingPathComponent(Constants.Audio.tempFileName)
    }
    
    // MARK: - 录音控制
    
    /// 开始录音
    /// - Throws: VoxError 如果 AudioSession 配置或录音启动失败
    func start() throws {
        cleanupTempFile()
        
        let session = AVAudioSession.sharedInstance()
        
        do {
            // 键盘扩展关键配置：
            // .playAndRecord: 允许同时播放和录音
            // .mixWithOthers: 不中断宿主 App 的音频播放
            // .defaultToSpeaker: 确保扬声器输出
            // .allowBluetooth: 支持蓝牙耳机录音
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true, options: [])
        } catch {
            throw VoxError.recordingFailed("AudioSession 配置失败: \(error.localizedDescription)")
        }
        
        // 录音参数：与主 App 一致 16kHz / 16bit / Mono / WAV
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: Constants.Audio.sampleRate,
            AVNumberOfChannelsKey: Constants.Audio.channels,
            AVLinearPCMBitDepthKey: Constants.Audio.bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let url = tempRecordingURL
        
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            
            guard recorder.record() else {
                throw VoxError.recordingFailed("录音启动失败")
            }
            
            self.audioRecorder = recorder
            self.recordingURL = url
            self.isRecording = true
            self.silenceDetector.reset()
            
            startMeterTimer()
            
        } catch let error as VoxError {
            throw error
        } catch {
            throw VoxError.recordingFailed(error.localizedDescription)
        }
    }
    
    /// 停止录音并返回音频文件 URL
    /// - Returns: 有效的录音文件 URL
    /// - Throws: VoxError 如果录音无效
    func stop() throws -> URL {
        stopMeterTimer()
        
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
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        cleanupTempFile()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
