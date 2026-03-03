// HistoryItem.swift
// VoxInput
//
// 历史记录数据模型

import Foundation

/// 单条历史记录
struct HistoryItem: Codable, Identifiable, Equatable {
    
    /// 唯一标识
    let id: UUID
    
    /// 转写文本
    let text: String
    
    /// 创建时间
    let timestamp: Date
    
    /// 使用的 ASR 提供商名称
    let provider: String
    
    init(id: UUID = UUID(), text: String, timestamp: Date = Date(), provider: String) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.provider = provider
    }
}
