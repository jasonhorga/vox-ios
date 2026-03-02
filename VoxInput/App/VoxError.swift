// VoxError.swift
// VoxInput
//
// 统一错误类型枚举

import Foundation

/// Vox 统一错误类型
enum VoxError: LocalizedError {
    
    // MARK: - 权限错误
    
    /// 麦克风权限被拒绝
    case microphonePermissionDenied
    /// 语音识别权限被拒绝
    case speechPermissionDenied
    
    // MARK: - 录音错误
    
    /// 录音启动失败
    case recordingFailed(String)
    /// 录音内容为空（全静音）
    case audioEmpty
    /// 录音时间过短
    case audioTooShort
    /// 音频文件不存在或无法读取
    case audioFileInvalid
    
    // MARK: - ASR 错误
    
    /// ASR 请求超时
    case asrTimeout
    /// ASR 返回空结果
    case asrEmptyResult
    /// ASR 网络请求失败
    case asrNetworkError(String)
    /// ASR API 返回错误
    case asrAPIError(String)
    
    // MARK: - 网络错误
    
    /// 网络不可用
    case networkUnavailable
    
    // MARK: - 配置错误
    
    /// API Key 未配置
    case apiKeyMissing
    /// 配置加载失败
    case configLoadFailed(String)
    
    // MARK: - 剪贴板错误
    
    /// 剪贴板写入失败
    case clipboardFailed
    
    // MARK: - 通用错误
    
    /// 未知错误
    case unknown(String)
    
    // MARK: - LocalizedError
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "麦克风权限未授权，请在系统设置中开启"
        case .speechPermissionDenied:
            return "语音识别权限未授权"
        case .recordingFailed(let detail):
            return "录音启动失败：\(detail)"
        case .audioEmpty:
            return "未检测到有效语音"
        case .audioTooShort:
            return "录音过短，请至少说 0.5 秒"
        case .audioFileInvalid:
            return "音频文件无效"
        case .asrTimeout:
            return "语音识别超时，请重试"
        case .asrEmptyResult:
            return "未识别到有效文字"
        case .asrNetworkError(let detail):
            return "语音识别网络错误：\(detail)"
        case .asrAPIError(let detail):
            return "语音识别服务错误：\(detail)"
        case .networkUnavailable:
            return "网络不可用，请检查网络连接"
        case .apiKeyMissing:
            return "API Key 未配置，请在设置中添加"
        case .configLoadFailed(let detail):
            return "配置加载失败：\(detail)"
        case .clipboardFailed:
            return "剪贴板写入失败"
        case .unknown(let detail):
            return "未知错误：\(detail)"
        }
    }
    
    /// 用户友好的简短描述（适合 Toast 显示）
    var shortDescription: String {
        switch self {
        case .microphonePermissionDenied:
            return "请开启麦克风权限"
        case .speechPermissionDenied:
            return "请开启语音识别权限"
        case .recordingFailed:
            return "录音失败"
        case .audioEmpty:
            return "未检测到语音"
        case .audioTooShort:
            return "录音过短"
        case .audioFileInvalid:
            return "音频文件无效"
        case .asrTimeout:
            return "识别超时"
        case .asrEmptyResult:
            return "未识别到文字"
        case .asrNetworkError:
            return "网络错误"
        case .asrAPIError:
            return "识别服务错误"
        case .networkUnavailable:
            return "网络不可用"
        case .apiKeyMissing:
            return "请配置 API Key"
        case .configLoadFailed:
            return "配置错误"
        case .clipboardFailed:
            return "剪贴板写入失败"
        case .unknown:
            return "未知错误"
        }
    }
}
