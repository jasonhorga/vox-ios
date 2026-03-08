// HistoryItem.swift
// VoxInput
//
// 历史记录数据模型
// Sprint 3: 添加音频文件路径，支持未识别音频的兜底存储与重试

import Foundation

/// 单条历史记录
struct HistoryItem: Codable, Identifiable, Equatable {
    
    /// 唯一标识
    let id: UUID
    
    /// 转写文本（未识别时为空字符串）
    let text: String
    
    /// 创建时间
    let timestamp: Date
    
    /// 使用的 ASR 提供商名称
    let provider: String
    
    /// 音频文件路径（仅用于未识别的音频记录）
    let audioFilePath: String?
    
    /// 是否是未识别的音频记录
    var isUnrecognized: Bool {
        audioFilePath != nil && text.isEmpty
    }
    
    init(id: UUID = UUID(), text: String, timestamp: Date = Date(), provider: String, audioFilePath: String? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.provider = provider
        self.audioFilePath = audioFilePath
    }
}
