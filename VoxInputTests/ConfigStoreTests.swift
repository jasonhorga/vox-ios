// ConfigStoreTests.swift
// VoxInputTests
//
// SharedConfigStore 单元测试。
// M1: 通过注入的 InMemorySecretStore + 隔离的 UserDefaults suite 进行测试，
// 不再触碰真实 App Group UserDefaults / Keychain（ConfigStore 仅为薄代理，不再测）。

import XCTest
@testable import VoxInput

final class ConfigStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var secrets: InMemorySecretStore!
    private var config: SharedConfigStore!

    override func setUp() {
        super.setUp()
        suiteName = "test.config.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        secrets = InMemorySecretStore()
        config = SharedConfigStore(defaults: defaults, secrets: secrets)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        config = nil
        secrets = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - ASR Provider 读写

    func testASRProvider_defaultIsQwen() {
        XCTAssertEqual(config.asrProvider, .qwen)
    }

    func testASRProvider_setToWhisper() {
        config.asrProvider = .whisper
        XCTAssertEqual(config.asrProvider, .whisper)
    }

    func testASRProvider_setBackToQwen() {
        config.asrProvider = .whisper
        config.asrProvider = .qwen
        XCTAssertEqual(config.asrProvider, .qwen)
    }

    // MARK: - API Key 读写

    func testQwenAPIKey_defaultIsEmpty() {
        XCTAssertEqual(config.qwenAPIKey, "")
    }

    func testQwenAPIKey_setAndGet() {
        config.qwenAPIKey = "sk-test-qwen-key-12345"
        XCTAssertEqual(config.qwenAPIKey, "sk-test-qwen-key-12345")
    }

    func testWhisperAPIKey_defaultIsEmpty() {
        XCTAssertEqual(config.whisperAPIKey, "")
    }

    func testWhisperAPIKey_setAndGet() {
        config.whisperAPIKey = "sk-test-whisper-key-67890"
        XCTAssertEqual(config.whisperAPIKey, "sk-test-whisper-key-67890")
    }

    // MARK: - 默认值

    func testDefaultValues_afterReset() {
        // 先修改一些值
        config.asrProvider = .whisper
        config.whisperBaseURL = "https://custom.api.com"
        config.whisperModel = "custom-model"
        config.hasCompletedSetup = true
        config.language = "zh"

        // 重置
        config.resetAll()

        // 验证所有值恢复默认
        XCTAssertEqual(config.asrProvider, .qwen)
        XCTAssertEqual(config.qwenAPIKey, "")
        XCTAssertEqual(config.whisperAPIKey, "")
        XCTAssertEqual(config.whisperModel, "whisper-1")
        XCTAssertEqual(config.hasCompletedSetup, false)
        XCTAssertEqual(config.language, "auto")
    }

    func testWhisperBaseURL_default() {
        XCTAssertEqual(config.whisperBaseURL, Constants.Network.whisperDefaultURL)
    }

    func testWhisperModel_default() {
        XCTAssertEqual(config.whisperModel, "whisper-1")
    }

    func testLanguage_default() {
        XCTAssertEqual(config.language, "auto")
    }

    func testHasCompletedSetup_default() {
        XCTAssertFalse(config.hasCompletedSetup)
    }

    // MARK: - hasValidAPIKey 计算属性

    func testHasValidAPIKey_qwenWithKey() {
        config.asrProvider = .qwen
        config.qwenAPIKey = "sk-valid-key"
        XCTAssertTrue(config.hasValidAPIKey)
    }

    func testHasValidAPIKey_qwenWithoutKey() {
        config.asrProvider = .qwen
        config.qwenAPIKey = ""
        XCTAssertFalse(config.hasValidAPIKey)
    }

    func testHasValidAPIKey_qwenWithWhitespaceOnlyKey() {
        config.asrProvider = .qwen
        config.qwenAPIKey = "   "
        XCTAssertFalse(config.hasValidAPIKey)
    }

    func testHasValidAPIKey_whisperWithKey() {
        config.asrProvider = .whisper
        config.whisperAPIKey = "sk-valid-key"
        XCTAssertTrue(config.hasValidAPIKey)
    }

    func testHasValidAPIKey_whisperWithoutKey() {
        config.asrProvider = .whisper
        config.whisperAPIKey = ""
        XCTAssertFalse(config.hasValidAPIKey)
    }

    // MARK: - 配置项读写

    func testWhisperBaseURL_setAndGet() {
        let customURL = "https://my-proxy.example.com/v1/audio/transcriptions"
        config.whisperBaseURL = customURL
        XCTAssertEqual(config.whisperBaseURL, customURL)
    }

    func testWhisperModel_setAndGet() {
        config.whisperModel = "whisper-large-v3"
        XCTAssertEqual(config.whisperModel, "whisper-large-v3")
    }

    func testHasCompletedSetup_setAndGet() {
        config.hasCompletedSetup = true
        XCTAssertTrue(config.hasCompletedSetup)
    }

    func testLanguage_setAndGet() {
        config.language = "zh-CN"
        XCTAssertEqual(config.language, "zh-CN")
    }

    // MARK: - H1 no-clobber：reload 在 Keychain 读失败时不抹空已有 key

    func testReloadDoesNotClobberKeyOnFailedKeychainRead() {
        let secrets = InMemorySecretStore()
        let cfg = SharedConfigStore(
            defaults: UserDefaults(suiteName: "test.clobber.\(UUID().uuidString)")!,
            secrets: secrets
        )
        cfg.qwenAPIKey = "sk-real-key"
        secrets.failReads = true        // 模拟 Keychain 读失败
        cfg.reload()
        XCTAssertEqual(cfg.qwenAPIKey, "sk-real-key")  // 读失败时内存值保留、未被抹空
    }
}
