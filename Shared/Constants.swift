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
        /// 最大重试次数
        static let maxRetries: Int = 2
        // beta.61: 移除了 keyboardTimeout / keyboardMaxRetries——远控架构后键盘不再自行转写，二者已无引用（review L7）
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
        /// beta.53: 从 6.0s 减少到 1.5s，实现零延迟快速跳转
        static let heartbeatTimeout: TimeInterval = 1.5
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
        /// 键盘等待后台守护进程返回结果超时（秒）
        /// beta.62: 10s → 25s，作为失败兜底需覆盖 daemon 单次 ASR 最坏耗时(~25s URLSession)，
        /// 避免合法但偏慢的识别被键盘提前判超时丢弃（review M4）。正常结果 1–3s 事件驱动返回，不受影响。
        static let resultTimeout: TimeInterval = 25.0
        /// beta.61: 结果时效（秒）。早于此值的 IPC 结果视为陈旧、不再注入，
        /// 防止上一次会话的转写在之后、甚至在别的 App 输入框里被凭空插入（review H3）。
        static let resultStaleAfter: TimeInterval = 60.0
        /// 键盘等待守护进程启动确认超时（秒）
        /// beta.37: 从 2s 增加到 5s，给 daemon 更多重试时间
        /// beta.53: 从 5s 减少到 0.5s，实现零延迟快速跳转
        static let startupAckTimeout: TimeInterval = 0.5
        
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
