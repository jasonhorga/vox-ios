// AppGroup.swift
// Shared
//
// App Group 常量与共享容器访问

import Foundation

/// App Group 共享配置
/// 主 App 和键盘扩展通过 App Group 共享 UserDefaults 和文件容器
enum AppGroup {
    
    /// App Group 标识符
    static let identifier = "group.com.jasonhorga.vox"
    
    /// Keychain Access Group（用于跨 Target 共享密钥）
    static let keychainAccessGroup = "com.jasonhorga.vox.shared"
    
    /// 键盘扩展 Bundle ID
    static let keyboardBundleID = "com.jasonhorga.vox.keyboard"
    
    /// 共享 UserDefaults
    /// 主 App 和键盘扩展均通过此实例读写配置
    static var sharedDefaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: identifier) else {
            // 如果 App Group 未正确配置，回退到 standard（不应发生）
            assertionFailure("App Group UserDefaults 初始化失败，请检查 Entitlements 配置")
            return UserDefaults.standard
        }
        return defaults
    }
    
    /// 共享文件容器 URL
    /// 用于存放需要跨 Target 访问的文件（如临时音频文件）
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
    
    /// 共享临时目录
    static var tempDirectory: URL? {
        containerURL?.appendingPathComponent("tmp", isDirectory: true)
    }
}
