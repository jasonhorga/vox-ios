// ConfigStore.swift
// VoxInput
//
// 配置存储管理（委托给 SharedConfigStore）
// Sprint 1: 从 UserDefaults.standard 迁移到 App Group + Keychain

import Foundation
import Observation

/// 应用配置存储
/// Sprint 1: 作为 SharedConfigStore 的薄包装层，保持向后兼容
/// 主 App 入口调用 migrateIfNeeded() 完成从旧版 UserDefaults 的一次性迁移
@Observable
final class ConfigStore {
    
    // MARK: - 单例
    
    static let shared = ConfigStore()
    
    // MARK: - 底层存储
    
    private let store = SharedConfigStore.shared
    
    // MARK: - 配置项（代理到 SharedConfigStore）
    
    /// 当前 ASR 提供商
    var asrProvider: ASRProviderType {
        get { store.asrProvider }
        set { store.asrProvider = newValue }
    }
    
    /// Qwen ASR API Key（Keychain 存储）
    var qwenAPIKey: String {
        get { store.qwenAPIKey }
        set { store.qwenAPIKey = newValue }
    }
    
    /// Whisper API Key（Keychain 存储）
    var whisperAPIKey: String {
        get { store.whisperAPIKey }
        set { store.whisperAPIKey = newValue }
    }
    
    /// Whisper API 自定义 URL（兼容 API）
    var whisperBaseURL: String {
        get { store.whisperBaseURL }
        set { store.whisperBaseURL = newValue }
    }
    
    /// Whisper 模型名称
    var whisperModel: String {
        get { store.whisperModel }
        set { store.whisperModel = newValue }
    }
    
    /// 是否已完成首次设置
    var hasCompletedSetup: Bool {
        get { store.hasCompletedSetup }
        set { store.hasCompletedSetup = newValue }
    }
    
    /// ASR 识别语言（默认自动检测）
    var language: String {
        get { store.language }
        set { store.language = newValue }
    }
    
    /// 翻译模式（Sprint 2）
    var translationMode: TranslationMode {
        get { store.translationMode }
        set { store.translationMode = newValue }
    }
    
    // MARK: - 初始化
    
    private init() {}
    
    // MARK: - 计算属性
    
    /// 当前选择的 ASR 提供商是否有有效的 API Key
    var hasValidAPIKey: Bool {
        store.hasValidAPIKey
    }
    
    // MARK: - 数据迁移
    
    /// 从旧版 UserDefaults.standard 迁移到 App Group + Keychain
    /// 在 App 启动时调用一次
    func migrateIfNeeded() {
        store.migrateFromStandardDefaults()
    }
    
    /// 重置所有配置为默认值
    func resetAll() {
        store.resetAll()
    }
}
