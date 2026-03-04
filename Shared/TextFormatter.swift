// TextFormatter.swift
// Shared
//
// 文本格式化器：CJK/ASCII 间距 + 标点规范化
// 与 macOS 版逻辑一致

import Foundation

/// 文本格式化器
/// 处理 ASR/LLM 输出文本的格式化：
/// 1. CJK 与 ASCII 之间添加空格
/// 2. 标点符号规范化（全角/半角）
/// 3. 多余空白清理
enum TextFormatter {
    
    /// 格式化文本
    /// - Parameter text: 原始文本
    /// - Returns: 格式化后的文本
    static func format(_ text: String) -> String {
        var result = text
        
        // 步骤 1：清理多余空白
        result = cleanWhitespace(result)
        
        // 步骤 2：CJK 与 ASCII 之间添加空格
        result = addCJKSpacing(result)
        
        // 步骤 3：标点规范化
        result = normalizePunctuation(result)
        
        // 步骤 4：最终清理
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return result
    }
    
    // MARK: - 清理多余空白
    
    /// 清理多余空白：多个空格合并为一个，去除首尾空白
    private static func cleanWhitespace(_ text: String) -> String {
        // 多个连续空格合并为一个
        let pattern = " {2,}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }
    
    // MARK: - CJK 间距
    
    /// 在 CJK 字符与 ASCII 字母/数字之间添加空格
    private static func addCJKSpacing(_ text: String) -> String {
        var result = text
        
        // CJK 字符范围（常用汉字 + 扩展）
        let cjk = "[\\u4e00-\\u9fff\\u3400-\\u4dbf\\uf900-\\ufaff]"
        // ASCII 字母和数字
        let ascii = "[A-Za-z0-9]"
        
        // CJK 后接 ASCII → 中间加空格
        if let regex = try? NSRegularExpression(pattern: "(\(cjk))(\(ascii))") {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1 $2")
        }
        
        // ASCII 后接 CJK → 中间加空格
        if let regex = try? NSRegularExpression(pattern: "(\(ascii))(\(cjk))") {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1 $2")
        }
        
        return result
    }
    
    // MARK: - 标点规范化
    
    /// 标点符号规范化
    /// - 中文语境中的英文标点 → 全角标点
    /// - 连续标点去重
    private static func normalizePunctuation(_ text: String) -> String {
        var result = text
        
        // CJK 字符后的英文逗号 → 中文逗号
        let cjk = "[\\u4e00-\\u9fff\\u3400-\\u4dbf]"
        
        let replacements: [(pattern: String, replacement: String)] = [
            // CJK 后的英文逗号 → 中文逗号
            ("(\(cjk)),", "$1，"),
            // CJK 后的英文句号 → 中文句号
            ("(\(cjk))\\.", "$1。"),
            // CJK 后的英文问号 → 中文问号
            ("(\(cjk))\\?", "$1？"),
            // CJK 后的英文叹号 → 中文叹号
            ("(\(cjk))!", "$1！"),
            // CJK 后的英文冒号 → 中文冒号
            ("(\(cjk)):", "$1："),
            // CJK 后的英文分号 → 中文分号
            ("(\(cjk));", "$1；"),
            // 连续相同中文标点去重
            ("([，。？！：；])\\1+", "$1"),
        ]
        
        for (pattern, replacement) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            }
        }
        
        return result
    }
}
