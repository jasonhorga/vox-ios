// Constants.swift
// VoxInput
//
// 全局常量定义

import Foundation

/// 应用全局常量
enum Constants {
    
    // MARK: - 应用信息
    
    /// 应用名称
    static let appName = "Vox Input"
    /// Bundle ID
    static let bundleID = "com.jasonhorga.voxinput"
    
    // MARK: - 录音参数
    
    enum Audio {
        /// 采样率：16kHz（ASR 标准）
        static let sampleRate: Double = 16000.0
        /// 位深度：16bit
        static let bitDepth: Int = 16
        /// 声道数：单声道
        static let channels: Int = 1
        /// 电平采样间隔（秒）
        static let meterInterval: TimeInterval = 0.1
        /// 最小有效录音文件大小（字节），约 0.5 秒
        static let minimumFileSize: Int = 16000
        /// 静音检测阈值（dB），peakPower 高于此值视为有声
        static let silenceThresholdDB: Float = -50.0
        /// 静音超时时间（秒），连续静音超过此时间自动停止
        static let silenceTimeout: TimeInterval = 3.0
        /// 录音临时文件名
        static let tempFileName = "vox_recording.wav"
    }
    
    // MARK: - ASR 参数
    
    enum ASR {
        /// ASR 请求超时时间（秒）
        static let timeout: TimeInterval = 25.0
        /// 最大重试次数
        static let maxRetries: Int = 2
        /// 初始重试间隔（秒）
        static let initialRetryDelay: TimeInterval = 0.8
        /// 最小有效结果长度（字符）
        static let minimumResultLength: Int = 2
    }
    
    // MARK: - 网络
    
    enum Network {
        /// Qwen ASR (DashScope) API 地址
        static let qwenBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        /// Whisper API 默认地址
        static let whisperDefaultURL = "https://api.openai.com/v1/audio/transcriptions"
    }
    
    // MARK: - 剪贴板
    
    enum Clipboard {
        /// 剪贴板内容过期时间（秒），5 分钟
        static let expirationInterval: TimeInterval = 300.0
    }
    
    // MARK: - UI
    
    enum UI {
        /// 波形采样点数量
        static let waveformSampleCount: Int = 40
        /// 结果 Toast 显示时长（秒）
        static let toastDuration: TimeInterval = 3.0
        /// 按钮大小
        static let recordButtonSize: CGFloat = 80.0
    }
}
