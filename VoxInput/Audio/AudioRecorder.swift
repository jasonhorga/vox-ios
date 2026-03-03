// AudioRecorder.swift
// VoxInput
//
// 录音管理器：AVAudioSession + AVAudioRecorder + 电平采样

import AVFoundation
import Foundation
import Observation

/// 录音管理器
/// 封装 AVAudioSession 配置、AVAudioRecorder 录制、电平采样
@Observable
final class AudioRecorder: NSObject {
    
    // MARK: - 可观察属性
    
    /// 当前录音状态
    private(set) var isRecording: Bool = false
    
    /// 当前音频电平（归一化到 0.0 ~ 1.0，用于波形显示）
    private(set) var currentLevel: Float = 0.0
    
    /// 当前峰值电平（dB，用于静音检测）
    private(set) var peakPower: Float = -160.0
    
    /// 电平历史记录（用于波形绘制）
    private(set) var levelHistory: [Float] = []
    
    // MARK: - 私有属性
    
    /// 系统录音器
    private var audioRecorder: AVAudioRecorder?
    
    /// 电平采样定时器
    private var meterTimer: Timer?
    
    /// 静音检测器
    let silenceDetector = SilenceDetector()
    
    /// 录音文件临时路径
    private var recordingURL: URL?
    
    // MARK: - 录音文件路径
    
    /// 获取录音临时文件 URL
    private var tempRecordingURL: URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent(Constants.Audio.tempFileName)
    }
    
    // MARK: - 权限管理
    
    /// 检查麦克风权限状态
    var permissionStatus: AVAudioSession.RecordPermission {
        AVAudioSession.sharedInstance().recordPermission
    }
    
    /// 请求麦克风录音权限
    /// - Returns: 是否已授权
    func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
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
    /// - Throws: VoxError 如果启动失败
    func start() throws {
        retryCount = 0
        try attemptStart()
    }
    
    /// 尝试启动录音
    private func attemptStart() throws {
        // 清理可能存在的旧录音文件
        cleanupTempFile()
        
        let session = AVAudioSession.sharedInstance()
        
        do {
            // 配置 AudioSession：录音模式 + 测量模式（获取准确电平）
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            if retryCount < Self.maxRetryCount {
                retryCount += 1
                try attemptStart()
                return
            }
            throw VoxError.recordingFailed("AudioSession 配置失败: \(error.localizedDescription)")
        }
        
        // 录音参数：16kHz / 16bit / Mono / WAV
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
            recorder.isMeteringEnabled = true  // 启用电平检测
            
            guard recorder.record() else {
                if retryCount < Self.maxRetryCount {
                    retryCount += 1
                    try attemptStart()
                    return
                }
                throw VoxError.recordingFailed("录音启动失败")
            }
            
            self.audioRecorder = recorder
            self.recordingURL = url
            self.isRecording = true
            
            // 重置状态
            self.levelHistory = []
            self.silenceDetector.reset()
            
            // 启动电平采样定时器
            startMeterTimer()
            
            // 启动超时定时器（最长 60 秒）
            startTimeoutTimer()
            
        } catch let error as VoxError {
            throw error
        } catch {
            if retryCount < Self.maxRetryCount {
                retryCount += 1
                try attemptStart()
                return
            }
            throw VoxError.recordingFailed(error.localizedDescription)
        }
    }
    
    /// 停止录音
    /// - Returns: 录音文件 URL（如果有效）
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
        self.currentLevel = 0.0
        self.peakPower = -160.0
        
        // 释放 AudioSession
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        guard let url = recordingURL else {
            throw VoxError.audioFileInvalid
        }
        
        // 检查文件大小
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
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
    
    /// 取消录音（不保存）
    func cancel() {
        stopMeterTimer()
        stopTimeoutTimer()
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        currentLevel = 0.0
        peakPower = -160.0
        cleanupTempFile()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    // MARK: - 电平采样
    
    /// 启动电平采样定时器
    private func startMeterTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: Constants.Audio.meterInterval, repeats: true) { [weak self] _ in
            self?.updateMeters()
        }
    }
    
    /// 停止电平采样定时器
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
    
    /// 更新电平读数
    private func updateMeters() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        
        recorder.updateMeters()
        
        // 获取峰值电平（dB，范围约 -160 ~ 0）
        let peak = recorder.peakPower(forChannel: 0)
        self.peakPower = peak
        
        // 将 dB 映射到 0.0 ~ 1.0（用于 UI 显示）
        // -160 dB → 0.0, 0 dB → 1.0，使用指数映射使低电平更敏感
        let minDB: Float = -60.0
        let normalizedLevel: Float
        if peak < minDB {
            normalizedLevel = 0.0
        } else if peak >= 0 {
            normalizedLevel = 1.0
        } else {
            normalizedLevel = (peak - minDB) / (0 - minDB)
        }
        
        self.currentLevel = normalizedLevel
        
        // 更新电平历史（保持固定长度用于波形绘制）
        levelHistory.append(normalizedLevel)
        if levelHistory.count > Constants.UI.waveformSampleCount {
            levelHistory.removeFirst()
        }
        
        // 静音检测
        silenceDetector.update(peakPower: peak)
    }
    
    // MARK: - 文件清理
    
    /// 清理临时录音文件
    func cleanupTempFile() {
        let url = tempRecordingURL
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            // 录音异常结束
            isRecording = false
            currentLevel = 0.0
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        isRecording = false
        currentLevel = 0.0
    }
}
