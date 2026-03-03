// SharedLogger.swift
// Shared
//
// 共享日志工具：将日志写入 App Group 容器的 log 文件
// 主 App 和键盘扩展均可写入，主 App 可读取键盘扩展日志用于调试

import Foundation
import os.log

/// 日志级别
enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

/// 共享日志记录器
/// 将日志同时输出到 os_log 和 App Group 共享文件
/// 方便主 App 查看键盘扩展的运行日志
enum SharedLogger {
    
    // MARK: - 常量
    
    /// 日志文件名
    private static let logFileName = "vox_debug.log"
    
    /// 日志文件最大大小（字节），超过后自动轮转
    private static let maxLogFileSize: Int = 512 * 1024  // 512 KB
    
    /// 轮转后保留的旧日志文件名
    private static let oldLogFileName = "vox_debug.old.log"
    
    /// 日期格式器
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()
    
    /// 系统日志（os_log）
    private static let osLog = OSLog(subsystem: Constants.bundleID, category: "VoxInput")
    
    /// 文件写入串行队列（避免并发写入冲突）
    private static let writeQueue = DispatchQueue(label: "com.jasonhorga.voxinput.logger", qos: .utility)
    
    // MARK: - 日志文件路径
    
    /// 日志文件 URL（位于 App Group 共享容器）
    static var logFileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(logFileName)
    }
    
    /// 旧日志文件 URL
    private static var oldLogFileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(oldLogFileName)
    }
    
    // MARK: - 便捷方法
    
    /// 记录 Debug 日志
    static func debug(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }
    
    /// 记录 Info 日志
    static func info(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }
    
    /// 记录 Warning 日志
    static func warning(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }
    
    /// 记录 Error 日志
    static func error(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }
    
    // MARK: - 核心方法
    
    /// 记录日志
    /// - Parameters:
    ///   - level: 日志级别
    ///   - message: 日志内容
    ///   - file: 源文件（自动填充）
    ///   - function: 函数名（自动填充）
    ///   - line: 行号（自动填充）
    static func log(level: LogLevel, message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        // 1. 输出到系统 os_log
        let osLogType: OSLogType
        switch level {
        case .debug:    osLogType = .debug
        case .info:     osLogType = .info
        case .warning:  osLogType = .default
        case .error:    osLogType = .error
        }
        os_log("%{public}@", log: osLog, type: osLogType, "[\(level.rawValue)] \(message)")
        
        // 2. 异步写入 App Group 日志文件
        writeQueue.async {
            writeToFile(level: level, message: message, file: file, function: function, line: line)
        }
    }
    
    // MARK: - 文件操作
    
    /// 将日志写入文件
    private static func writeToFile(level: LogLevel, message: String, file: String, function: String, line: Int) {
        guard let fileURL = logFileURL else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        // 提取文件名（去掉模块前缀）
        let fileName = file.components(separatedBy: "/").last ?? file
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)\n"
        
        guard let data = logLine.data(using: .utf8) else { return }
        
        let fm = FileManager.default
        
        // 如果文件不存在，创建新文件
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: data)
            return
        }
        
        // 检查文件大小，必要时轮转
        if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int,
           size > maxLogFileSize {
            rotateLogFile()
        }
        
        // 追加写入
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }
    
    /// 日志文件轮转：当前日志 → old，新建空日志
    private static func rotateLogFile() {
        guard let fileURL = logFileURL, let oldURL = oldLogFileURL else { return }
        let fm = FileManager.default
        
        // 删除旧的 old 文件
        try? fm.removeItem(at: oldURL)
        // 当前文件重命名为 old
        try? fm.moveItem(at: fileURL, to: oldURL)
    }
    
    // MARK: - 读取日志（主 App 使用）
    
    /// 读取全部日志内容（主 App 查看键盘扩展日志）
    /// - Returns: 日志文本，nil 表示无日志
    static func readLogs() -> String? {
        guard let fileURL = logFileURL else { return nil }
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }
    
    /// 读取最近 N 行日志
    /// - Parameter lineCount: 行数
    /// - Returns: 最近的日志行
    static func readRecentLogs(lineCount: Int = 100) -> String? {
        guard let content = readLogs() else { return nil }
        let lines = content.components(separatedBy: "\n")
        let recent = lines.suffix(lineCount)
        return recent.joined(separator: "\n")
    }
    
    /// 清除所有日志文件
    static func clearLogs() {
        writeQueue.async {
            let fm = FileManager.default
            if let url = logFileURL {
                try? fm.removeItem(at: url)
            }
            if let url = oldLogFileURL {
                try? fm.removeItem(at: url)
            }
        }
    }
}
