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
        case qwenAPIKey = "com.jasonhorga.voxinput.qwen.apikey"
        case whisperAPIKey = "com.jasonhorga.voxinput.whisper.apikey"
    }
    
    // MARK: - 读取
    
    /// 从 Keychain 读取字符串
    /// - Parameter key: 存储键名
    /// - Returns: 存储的字符串值，不存在时返回 nil
    static func read(key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessGroup as String: AppGroup.keychainAccessGroup,
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
        // 先删除已有条目
        delete(key: key)
        
        guard let data = value.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessGroup as String: AppGroup.keychainAccessGroup,
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessGroup as String: AppGroup.keychainAccessGroup
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - 批量操作
    
    /// 检查 Keychain 中是否存在指定键
    static func exists(key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessGroup as String: AppGroup.keychainAccessGroup,
            kSecReturnData as String: false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
