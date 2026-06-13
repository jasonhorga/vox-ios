// SharedConfigStore.swift
// Shared
//
// 共享配置存储（App Group UserDefaults + Keychain）
// 主 App 和键盘扩展共用

import Foundation
import Observation

/// 后台语音守护进程待机时长
/// - minutes(3): 3 分钟空闲后休眠
/// - minutes(10): 10 分钟空闲后休眠（默认）
/// - never: 永不自动休眠
enum DaemonStandbyDuration: String, CaseIterable, Codable {
    case minutes3 = "3m"
    case minutes10 = "10m"
    case never = "never"

    var displayName: String {
        switch self {
        case .minutes3: return "3 分钟后休眠（最省电）"
        case .minutes10: return "10 分钟后休眠"
        case .never: return "始终常驻（免跳转）"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .minutes3: return 3 * 60
        case .minutes10: return 10 * 60
        case .never: return nil
        }
    }
}

/// 共享配置存储
/// - 非敏感配置（ASR provider、URL 等）存储在 App Group UserDefaults
/// - 敏感数据（API Key）存储在 Keychain（共享 Access Group）
@Observable
final class SharedConfigStore {
    
    // MARK: - 单例
    
    static let shared = SharedConfigStore()
    
    // MARK: - 存储后端

    private let defaults: UserDefaults

    /// beta.61: reload()/批量加载期间置 true，阻止 didSet 把刚读出来的值又写回去。
    /// 修复 review H1：reload 触发 didSet 写回 Keychain，读失败时会把真实 key 抹成 ""。
    @ObservationIgnored private var isLoading = false

    // MARK: - 配置项（非敏感，存储在 App Group UserDefaults）
    
    /// 当前 ASR 提供商
    var asrProvider: ASRProviderType {
        didSet { saveString(asrProvider.rawValue, forKey: .asrProvider) }
    }
    
    /// Whisper API 自定义 URL（兼容 API）
    var whisperBaseURL: String {
        didSet { saveString(whisperBaseURL, forKey: .whisperBaseURL) }
    }
    
    /// Whisper 模型名称
    var whisperModel: String {
        didSet { saveString(whisperModel, forKey: .whisperModel) }
    }
    
    /// Qwen 模型名称
    var qwenModel: String {
        didSet { saveString(qwenModel, forKey: .qwenModel) }
    }

    /// 对话模型名称（智能整理/翻译后处理用，仅 Whisper 兼容端点）
    var chatModel: String {
        didSet { saveString(chatModel, forKey: .chatModel) }
    }

    /// 是否已完成首次设置
    var hasCompletedSetup: Bool {
        didSet { saveBool(hasCompletedSetup, forKey: .hasCompletedSetup) }
    }
    
    /// ASR 识别语言（默认自动检测）
    var language: String {
        didSet { saveString(language, forKey: .language) }
    }
    
    /// 翻译模式（Sprint 2）
    var translationMode: TranslationMode {
        didSet { saveString(translationMode.rawValue, forKey: .translationMode) }
    }

    /// beta.63: 智能整理（LLM 后处理）开关，默认开
    var smartCleanup: Bool {
        didSet { saveBool(smartCleanup, forKey: .smartCleanup) }
    }

    /// 后台语音守护进程待机时长
    var daemonStandbyDuration: DaemonStandbyDuration {
        didSet { saveString(daemonStandbyDuration.rawValue, forKey: .daemonStandbyDuration) }
    }
    
    // MARK: - API Key（敏感，存储在 Keychain）
    
    /// Qwen ASR API Key（Keychain 存储）
    var qwenAPIKey: String {
        didSet {
            guard !isLoading else { return }
            KeychainStore.write(value: qwenAPIKey, key: .qwenAPIKey)
        }
    }

    /// Whisper API Key（Keychain 存储）
    var whisperAPIKey: String {
        didSet {
            guard !isLoading else { return }
            KeychainStore.write(value: whisperAPIKey, key: .whisperAPIKey)
        }
    }
    
    // MARK: - 存储键
    
    private enum Key: String {
        case asrProvider = "vox.asr.provider"
        case whisperBaseURL = "vox.asr.whisper.baseurl"
        case whisperModel = "vox.asr.whisper.model"
        case qwenModel = "vox.asr.qwen.model"
        case chatModel = "vox.postprocess.chatModel"
        case hasCompletedSetup = "vox.app.hasCompletedSetup"
        case language = "vox.asr.language"
        case translationMode = "vox.postprocess.translationMode"
        case smartCleanup = "vox.postprocess.smartCleanup"
        case daemonStandbyDuration = "vox.daemon.standbyDuration"
    }
    
    // MARK: - 初始化
    
    private init() {
        // 使用 App Group UserDefaults
        self.defaults = AppGroup.sharedDefaults
        
        // 从 App Group UserDefaults 加载非敏感配置
        self.asrProvider = ASRProviderType(
            rawValue: defaults.string(forKey: Key.asrProvider.rawValue) ?? ""
        ) ?? .qwen
        
        self.whisperBaseURL = defaults.string(forKey: Key.whisperBaseURL.rawValue)
            ?? Constants.Network.whisperDefaultURL
        
        self.whisperModel = defaults.string(forKey: Key.whisperModel.rawValue)
            ?? "whisper-1"
        
        self.qwenModel = defaults.string(forKey: Key.qwenModel.rawValue)
            ?? "qwen-omni-turbo"

        self.chatModel = defaults.string(forKey: Key.chatModel.rawValue)
            ?? "gpt-4o-mini"

        self.hasCompletedSetup = defaults.bool(forKey: Key.hasCompletedSetup.rawValue)
        
        self.language = defaults.string(forKey: Key.language.rawValue) ?? "auto"
        
        self.translationMode = TranslationMode(
            rawValue: defaults.string(forKey: Key.translationMode.rawValue) ?? ""
        ) ?? .none

        // 默认开：键不存在时 object(forKey:) 为 nil → 取 true
        self.smartCleanup = defaults.object(forKey: Key.smartCleanup.rawValue) as? Bool ?? true

        self.daemonStandbyDuration = DaemonStandbyDuration(
            rawValue: defaults.string(forKey: Key.daemonStandbyDuration.rawValue) ?? ""
        ) ?? .minutes10

        // 从 Keychain 加载 API Key
        self.qwenAPIKey = KeychainStore.read(key: .qwenAPIKey) ?? ""
        self.whisperAPIKey = KeychainStore.read(key: .whisperAPIKey) ?? ""
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
    
    // MARK: - 数据迁移
    
    /// 从旧版 UserDefaults.standard 迁移数据到 App Group
    /// 在主 App 首次升级到 Sprint 1 时调用一次
    func migrateFromStandardDefaults() {
        let oldDefaults = UserDefaults.standard
        let migrationKey = "vox.migration.v1.completed"
        
        // 检查是否已迁移
        guard !defaults.bool(forKey: migrationKey) else { return }
        
        // 迁移非敏感配置
        if let provider = oldDefaults.string(forKey: Key.asrProvider.rawValue) {
            defaults.set(provider, forKey: Key.asrProvider.rawValue)
            if let type = ASRProviderType(rawValue: provider) {
                self.asrProvider = type
            }
        }
        
        if let url = oldDefaults.string(forKey: Key.whisperBaseURL.rawValue) {
            defaults.set(url, forKey: Key.whisperBaseURL.rawValue)
            self.whisperBaseURL = url
        }
        
        if let model = oldDefaults.string(forKey: Key.whisperModel.rawValue) {
            defaults.set(model, forKey: Key.whisperModel.rawValue)
            self.whisperModel = model
        }
        
        if let qwenModel = oldDefaults.string(forKey: Key.qwenModel.rawValue), !qwenModel.isEmpty {
            defaults.set(qwenModel, forKey: Key.qwenModel.rawValue)
            self.qwenModel = qwenModel
        }
        
        if let lang = oldDefaults.string(forKey: Key.language.rawValue) {
            defaults.set(lang, forKey: Key.language.rawValue)
            self.language = lang
        }

        if let standby = oldDefaults.string(forKey: Key.daemonStandbyDuration.rawValue),
           let duration = DaemonStandbyDuration(rawValue: standby) {
            defaults.set(duration.rawValue, forKey: Key.daemonStandbyDuration.rawValue)
            self.daemonStandbyDuration = duration
        }

        let setup = oldDefaults.bool(forKey: Key.hasCompletedSetup.rawValue)
        defaults.set(setup, forKey: Key.hasCompletedSetup.rawValue)
        self.hasCompletedSetup = setup
        
        // 迁移 API Key 到 Keychain
        let oldQwenKey = "vox.asr.qwen.apikey"
        let oldWhisperKey = "vox.asr.whisper.apikey"
        
        if let qwenKey = oldDefaults.string(forKey: oldQwenKey), !qwenKey.isEmpty {
            KeychainStore.write(value: qwenKey, key: .qwenAPIKey)
            self.qwenAPIKey = qwenKey
            // 清除旧存储中的明文 Key
            oldDefaults.removeObject(forKey: oldQwenKey)
        }
        
        if let whisperKey = oldDefaults.string(forKey: oldWhisperKey), !whisperKey.isEmpty {
            KeychainStore.write(value: whisperKey, key: .whisperAPIKey)
            self.whisperAPIKey = whisperKey
            oldDefaults.removeObject(forKey: oldWhisperKey)
        }
        
        // 标记迁移完成
        defaults.set(true, forKey: migrationKey)
    }
    
    // MARK: - 私有方法
    
    /// 从 App Group UserDefaults 和 Keychain 强制重载所有配置
    /// 用于确保跨进程（主 App ↔ 键盘扩展）读取最新数据
    func reload() {
        isLoading = true
        defer { isLoading = false }

        asrProvider = ASRProviderType(
            rawValue: defaults.string(forKey: Key.asrProvider.rawValue) ?? ""
        ) ?? .qwen
        
        whisperBaseURL = defaults.string(forKey: Key.whisperBaseURL.rawValue)
            ?? Constants.Network.whisperDefaultURL
        
        whisperModel = defaults.string(forKey: Key.whisperModel.rawValue)
            ?? "whisper-1"
        
        qwenModel = defaults.string(forKey: Key.qwenModel.rawValue)
            ?? "qwen-omni-turbo"

        chatModel = defaults.string(forKey: Key.chatModel.rawValue)
            ?? "gpt-4o-mini"

        hasCompletedSetup = defaults.bool(forKey: Key.hasCompletedSetup.rawValue)
        
        language = defaults.string(forKey: Key.language.rawValue) ?? "auto"
        
        translationMode = TranslationMode(
            rawValue: defaults.string(forKey: Key.translationMode.rawValue) ?? ""
        ) ?? .none

        smartCleanup = defaults.object(forKey: Key.smartCleanup.rawValue) as? Bool ?? true

        daemonStandbyDuration = DaemonStandbyDuration(
            rawValue: defaults.string(forKey: Key.daemonStandbyDuration.rawValue) ?? ""
        ) ?? .minutes10

        // beta.61: 仅在 Keychain 读取成功时覆盖内存值；读失败返回 nil 时保留原值，
        // 避免把真实 key 抹成 ""（配合 isLoading：reload 期间一律不写回 Keychain）。
        if let qwen = KeychainStore.read(key: .qwenAPIKey) { qwenAPIKey = qwen }
        if let whisper = KeychainStore.read(key: .whisperAPIKey) { whisperAPIKey = whisper }
    }

    private func saveString(_ value: String, forKey key: Key) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key.rawValue)
    }

    private func saveBool(_ value: Bool, forKey key: Key) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key.rawValue)
    }
    
    /// 重置所有配置为默认值
    func resetAll() {
        asrProvider = .qwen
        qwenAPIKey = ""
        whisperAPIKey = ""
        whisperBaseURL = Constants.Network.whisperDefaultURL
        whisperModel = "whisper-1"
        qwenModel = "qwen-omni-turbo"
        chatModel = "gpt-4o-mini"
        hasCompletedSetup = false
        language = "auto"
        translationMode = .none
        smartCleanup = true
        daemonStandbyDuration = .minutes10

        // 清除 Keychain
        KeychainStore.delete(key: .qwenAPIKey)
        KeychainStore.delete(key: .whisperAPIKey)
    }
}
