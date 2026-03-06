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

    /// 键盘扩展 Bundle ID
    static let keyboardBundleID = "com.jasonhorga.vox.keyboard"

    /// 键盘扩展待注入文本 Key（主 App 写入，键盘读取后清空）
    static let pendingInputKey = "vox.keyboard.pendingInput"

    /// 主 App 是否由键盘录音流程唤起（URL Scheme）
    static let keyboardRecordRequestKey = "vox.keyboard.recordRequest"

    // MARK: - Daemon IPC Keys

    /// 指令值：start / stop / cancel
    static let ipcCommandKey = "vox.ipc.command"
    /// 指令序列号（每次发指令递增，防止同值覆盖）
    static let ipcCommandIDKey = "vox.ipc.command_id"
    /// 指令发出时间戳（秒）
    static let ipcCommandAtKey = "vox.ipc.command_at"

    /// 守护进程状态：idle / recording / processing / error / sleeping / dead
    static let ipcStateKey = "vox.ipc.state"
    /// 状态附带错误信息
    static let ipcErrorKey = "vox.ipc.error"

    /// 识别结果文本
    static let ipcResultKey = "vox.ipc.result"
    /// 结果序列号（每次出新结果递增）
    static let ipcResultIDKey = "vox.ipc.result_id"

    /// 守护进程心跳时间戳（秒）
    static let ipcHeartbeatKey = "vox.ipc.heartbeat"
    /// 最后活跃时间戳（秒），用于 idle 自动休眠
    static let ipcLastActiveAtKey = "vox.ipc.last_active_at"

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
