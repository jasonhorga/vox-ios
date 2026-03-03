// ASRProviderType.swift
// Shared
//
// ASR 提供商类型枚举（主 App 和键盘扩展共用）

import Foundation

/// ASR 提供商类型
enum ASRProviderType: String, CaseIterable, Codable {
    case qwen = "qwen"
    case whisper = "whisper"
}
