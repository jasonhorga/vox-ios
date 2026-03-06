// KeychainStore.swift
// Shared
//
// Keychain 读写封装（跨 Target 共享 API Key）

import Foundation
import Security

/// Keychain 存储管理器
/// 通过共享 Access Group 在主 App 和键盘扩展之间安全共享 API Key
enum KeychainStore {
    
    // MARK: - Keychain 键名
    
    /// Keychain 存储的键名枚举
    enum Key: String {
        case qwenAPIKey = "com.jasonhorga.vox.qwen.apikey"
        case whisperAPIKey = "com.jasonhorga.vox.whisper.apikey"
    }
    
    // MARK: - Access Group 解析
    
    /// 兼容旧版（未带 TeamID 前缀）读取
    private static let legacyAccessGroup = "com.jasonhorga.vox.shared"
    
    /// 从当前进程 entitlement 中解析 keychain-access-groups
    private static var entitlementAccessGroups: [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil)
        else {
            return []
        }
        
        if let groups = value as? [String] {
            return groups
        }
        
        if let group = value as? String {
            return [group]
        }
        
        return []
    }
    
    /// 主读写 access group（优先 entitlement 里与本项目匹配的组）
    private static var primaryAccessGroup: String {
        if let matched = entitlementAccessGroups.first(where: { $0.hasSuffix("com.jasonhorga.vox.shared") }) {
            return matched
        }
        return legacyAccessGroup
    }
    
    /// 读取时按顺序尝试（先新后旧，保证向后兼容）
    private static var readAccessGroups: [String] {
        var groups = entitlementAccessGroups
        if !groups.contains(legacyAccessGroup) {
            groups.append(legacyAccessGroup)
        }
        if groups.isEmpty {
            groups = [legacyAccessGroup]
        }
        return groups
    }
    
    // MARK: - 读取
    
    /// 从 Keychain 读取字符串（支持向后兼容读取）
    /// - Parameter key: 存储键名
    /// - Returns: 存储的字符串值，不存在时返回 nil
    static func read(key: Key) -> String? {
        for group in readAccessGroups {
            if let value = readFromKeychain(key: key, accessGroup: group) {
                return value
            }
        }
        return nil
    }
    
    private static func readFromKeychain(key: Key, accessGroup: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        
        return string
    }
    
    // MARK: - 写入
    
    /// 将字符串写入 Keychain
    /// - Parameters:
    ///   - value: 要存储的字符串值
    ///   - key: 存储键名
    /// - Returns: 是否写入成功
    @discardableResult
    static func write(value: String, key: Key) -> Bool {
        // 先删除已有条目（新旧 group 都删，避免脏数据）
        _ = delete(key: key)
        
        guard let data = value.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessGroup as String: primaryAccessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - 删除
    
    /// 从 Keychain 删除指定条目
    /// - Parameter key: 存储键名
    @discardableResult
    static func delete(key: Key) -> Bool {
        var allSucceeded = true
        for group in readAccessGroups {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key.rawValue,
                kSecAttrAccessGroup as String: group
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                allSucceeded = false
            }
        }
        return allSucceeded
    }
    
    // MARK: - 批量操作
    
    /// 检查 Keychain 中是否存在指定键
    static func exists(key: Key) -> Bool {
        for group in readAccessGroups {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key.rawValue,
                kSecAttrAccessGroup as String: group,
                kSecReturnData as String: false,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            
            let status = SecItemCopyMatching(query as CFDictionary, nil)
            if status == errSecSuccess {
                return true
            }
        }
        return false
    }
}
