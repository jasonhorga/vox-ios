// SilenceDetector.swift
// Shared
//
// 静音检测器：连续静音超过阈值时触发回调

import Foundation

/// 静音检测器
/// 通过持续监测音频电平，判断是否连续静音超过指定时长
final class SilenceDetector {
    
    // MARK: - 配置
    
    /// 静音阈值（dB），峰值电平低于此值视为静音
    private let thresholdDB: Float
    
    /// 静音超时时间（秒）
    private let timeout: TimeInterval
    
    // MARK: - 状态
    
    /// 静音开始时间
    private var silenceStartTime: Date?
    
    /// 是否曾检测到有效声音（非静音）
    private(set) var hasDetectedSound: Bool = false
    
    /// 静音超时回调
    var onSilenceTimeout: (() -> Void)?
    
    // MARK: - 初始化
    
    /// 初始化静音检测器
    /// - Parameters:
    ///   - thresholdDB: 静音阈值，默认 -50 dB
    ///   - timeout: 静音超时，默认 3 秒
    init(
        thresholdDB: Float = Constants.Audio.silenceThresholdDB,
        timeout: TimeInterval = Constants.Audio.silenceTimeout
    ) {
        self.thresholdDB = thresholdDB
        self.timeout = timeout
    }
    
    // MARK: - 公开方法
    
    /// 重置检测器状态（录音开始时调用）
    func reset() {
        silenceStartTime = nil
        hasDetectedSound = false
    }
    
    /// 更新音频电平
    /// - Parameter peakPower: 当前峰值电平（dB）
    /// - Returns: 是否应该停止录音
    @discardableResult
    func update(peakPower: Float) -> Bool {
        let isSilent = peakPower < thresholdDB
        
        if isSilent {
            // 当前是静音
            if silenceStartTime == nil {
                silenceStartTime = Date()
            }
            
            // 只有在曾经检测到声音后才触发超时（避免一开始就静音立即停止）
            if hasDetectedSound, let startTime = silenceStartTime {
                let silenceDuration = Date().timeIntervalSince(startTime)
                if silenceDuration >= timeout {
                    onSilenceTimeout?()
                    return true
                }
            }
        } else {
            // 有声音，重置静音计时
            hasDetectedSound = true
            silenceStartTime = nil
        }
        
        return false
    }
    
    /// 获取当前连续静音时长（秒）
    var currentSilenceDuration: TimeInterval {
        guard let startTime = silenceStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
}
