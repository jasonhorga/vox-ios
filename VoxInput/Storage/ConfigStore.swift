// ConfigStore.swift
// VoxInput
//
// 配置存储管理（UserDefaults 读写）

import Foundation
import Observation

/// ASR 提供商类型
enum ASRProviderType: String, CaseIterable, Codable {
    case qwen = "qwen"
    case whisper = "whisper"
}

/// 应用配置存储
/// 使用 UserDefaults 持久化配置（后续 Sprint 迁移到 App Group 共享容器）
@Observable
final class ConfigStore {
    
    // MARK: - 单例
    
    static let shared = ConfigStore()
    
    // MARK: - 存储后端
    
    private let defaults: UserDefaults
    
    // MARK: - 配置项
    
    /// 当前 ASR 提供商
    var asrProvider: ASRProviderType {
        didSet { save(asrProvider.rawValue, forKey: .asrProvider) }
    }
    
    /// Qwen ASR API Key
    var qwenAPIKey: String {
        didSet { save(qwenAPIKey, forKey: .qwenAPIKey) }
    }
    
    /// Whisper API Key
    var whisperAPIKey: String {
        didSet { save(whisperAPIKey, forKey: .whisperAPIKey) }
    }
    
    /// Whisper API 自定义 URL（兼容 API）
    var whisperBaseURL: String {
        didSet { save(whisperBaseURL, forKey: .whisperBaseURL) }
    }
    
    /// Whisper 模型名称
    var whisperModel: String {
        didSet { save(whisperModel, forKey: .whisperModel) }
    }
    
    /// 是否已完成首次设置
    var hasCompletedSetup: Bool {
        didSet { save(hasCompletedSetup, forKey: .hasCompletedSetup) }
    }
    
    /// ASR 识别语言（默认自动检测）
    var language: String {
        didSet { save(language, forKey: .language) }
    }
    
    // MARK: - 存储键
    
    private enum Key: String {
        case asrProvider = "vox.asr.provider"
        case qwenAPIKey = "vox.asr.qwen.apikey"
        case whisperAPIKey = "vox.asr.whisper.apikey"
        case whisperBaseURL = "vox.asr.whisper.baseurl"
        case whisperModel = "vox.asr.whisper.model"
        case hasCompletedSetup = "vox.app.hasCompletedSetup"
        case language = "vox.asr.language"
    }
    
    // MARK: - 初始化
    
    private init() {
        // Sprint 0 使用标准 UserDefaults，Sprint 1 迁移到 App Group
        self.defaults = UserDefaults.standard
        
        // 从 UserDefaults 加载配置，提供默认值
        self.asrProvider = ASRProviderType(rawValue: defaults.string(forKey: Key.asrProvider.rawValue) ?? "") ?? .qwen
        self.qwenAPIKey = defaults.string(forKey: Key.qwenAPIKey.rawValue) ?? ""
        self.whisperAPIKey = defaults.string(forKey: Key.whisperAPIKey.rawValue) ?? ""
        self.whisperBaseURL = defaults.string(forKey: Key.whisperBaseURL.rawValue) ?? Constants.Network.whisperDefaultURL
        self.whisperModel = defaults.string(forKey: Key.whisperModel.rawValue) ?? "whisper-1"
        self.hasCompletedSetup = defaults.bool(forKey: Key.hasCompletedSetup.rawValue)
        self.language = defaults.string(forKey: Key.language.rawValue) ?? "auto"
    }
    
    // MARK: - 计算属性
    
    /// 当前选择的 ASR 提供商是否有有效的 API Key
    var hasValidAPIKey: Bool {
        switch asrProvider {
        case .qwen:
            return !qwenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .whisper:
            return !whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    // MARK: - 私有方法
    
    /// 保存字符串值
    private func save(_ value: String, forKey key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
    
    /// 保存布尔值
    private func save(_ value: Bool, forKey key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
    
    /// 重置所有配置为默认值
    func resetAll() {
        asrProvider = .qwen
        qwenAPIKey = ""
        whisperAPIKey = ""
        whisperBaseURL = Constants.Network.whisperDefaultURL
        whisperModel = "whisper-1"
        hasCompletedSetup = false
        language = "auto"
    }
}
