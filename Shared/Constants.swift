// Constants.swift
// Shared
//
// 全局常量定义

import Foundation

/// 应用全局常量
enum Constants {
    
    // MARK: - 应用信息
    
    /// 应用名称
    static let appName = "Vox Input"
    /// 主 App Bundle ID
    static let bundleID = "com.jasonhorga.vox"
    /// 键盘扩展 Bundle ID
    static let keyboardBundleID = "com.jasonhorga.vox.keyboard"
    /// App Group ID
    static let appGroupID = "group.com.jasonhorga.vox"
    /// Keychain Access Group
    static let keychainAccessGroup = "com.jasonhorga.vox.shared"
    
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
        /// ASR 请求超时时间（秒）- 主 App
        static let timeout: TimeInterval = 25.0
        /// ASR 请求超时时间（秒）- 键盘扩展（更短以节省内存）
        static let keyboardTimeout: TimeInterval = 15.0
        /// 最大重试次数
        static let maxRetries: Int = 2
        /// 键盘扩展最大重试次数（更少以避免超时）
        static let keyboardMaxRetries: Int = 1
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
        /// 按钮大小（主 App）
        static let recordButtonSize: CGFloat = 80.0
    }
    
    // MARK: - Daemon IPC

    enum Daemon {
        /// IPC 命令轮询间隔（秒）
        static let commandPollInterval: TimeInterval = 0.20
        /// 心跳刷新间隔（秒）
        static let heartbeatInterval: TimeInterval = 1.0
        /// 键盘侧判定主 App 无响应超时（秒）
        static let heartbeatTimeout: TimeInterval = 6.0
    }

    // MARK: - 键盘扩展

    enum Keyboard {
        /// 键盘扩展默认高度（fallback）
        static let defaultHeight: CGFloat = 260.0
        /// 小屏设备键盘高度（iPhone SE / mini，屏幕高度 ≤ 736pt）
        static let compactHeight: CGFloat = 230.0
        /// 大屏设备键盘高度（Pro Max / Plus，屏幕高度 ≥ 896pt）
        static let expandedHeight: CGFloat = 290.0
        /// 麦克风按钮大小
        static let micButtonSize: CGFloat = 64.0
        /// 波形采样点数量（比主 App 少以节省内存）
        static let waveformSampleCount: Int = 30
        /// 键盘扩展内存峰值目标（字节）
        static let memoryLimit: Int = 60 * 1024 * 1024  // 60MB
        /// 状态消息自动清除延迟（秒）
        static let statusClearDelay: TimeInterval = 2.0
        /// 键盘轮询 IPC 状态间隔（秒）
        static let ipcPollInterval: TimeInterval = 0.20
        
        /// 根据屏幕高度和安全区域动态计算键盘高度
        /// - Parameters:
        ///   - screenHeight: UIScreen.main.bounds.height
        ///   - bottomSafeArea: 底部安全区域 inset（有 Home Indicator 的设备 > 0）
        /// - Returns: 适合当前设备的键盘高度
        static func adaptiveHeight(screenHeight: CGFloat, bottomSafeArea: CGFloat = 0) -> CGFloat {
            // iPhone SE / 8 / mini 等小屏设备
            if screenHeight <= 736 {
                return compactHeight
            }
            // iPhone Pro Max / Plus 等大屏设备
            if screenHeight >= 896 {
                return expandedHeight
            }
            // 标准尺寸设备
            return defaultHeight
        }
    }
}
