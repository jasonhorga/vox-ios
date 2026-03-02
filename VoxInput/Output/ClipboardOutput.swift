// ClipboardOutput.swift
// VoxInput
//
// 剪贴板输出：UIPasteboard 写入 + 过期时间

import UIKit

/// 剪贴板输出管理
/// 将文本写入系统剪贴板，支持设置过期时间
enum ClipboardOutput {
    
    /// 将文本复制到剪贴板
    /// - Parameters:
    ///   - text: 要复制的文本
    ///   - expiration: 过期时间（秒），默认 5 分钟。nil 表示不过期
    /// - Throws: VoxError.clipboardFailed 如果写入失败
    static func copy(_ text: String, expiration: TimeInterval? = Constants.Clipboard.expirationInterval) throws {
        let pasteboard = UIPasteboard.general
        
        if let expiration = expiration {
            // 设置带过期时间的剪贴板内容
            let expirationDate = Date().addingTimeInterval(expiration)
            pasteboard.setItems(
                [[UIPasteboard.typeAutomatic: text]],
                options: [.expirationDate: expirationDate]
            )
        } else {
            // 普通写入（不过期）
            pasteboard.string = text
        }
        
        // 验证写入是否成功
        guard pasteboard.string == text else {
            throw VoxError.clipboardFailed
        }
        
        // 触觉反馈
        HapticFeedback.shared.success()
    }
    
    /// 读取剪贴板当前内容
    /// - Returns: 剪贴板文本，如果为空返回 nil
    static func read() -> String? {
        return UIPasteboard.general.string
    }
    
    /// 检查剪贴板是否有文本内容
    static var hasContent: Bool {
        return UIPasteboard.general.hasStrings
    }
}
