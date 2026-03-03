// ConfigStoreTests.swift
// VoxInputTests
//
// ConfigStore / SharedConfigStore 单元测试
// 注意：ConfigStore 是 SharedConfigStore 的薄包装层，
// 两者均为单例且依赖 App Group + Keychain。
// 测试通过 ConfigStore.shared 进行，测试前后重置为默认值。

import XCTest
@testable import VoxInput

final class ConfigStoreTests: XCTestCase {

    private var config: ConfigStore!

    override func setUp() {
        super.setUp()
        config = ConfigStore.shared
        // 重置为默认值，确保测试隔离
        config.resetAll()
    }

    override func tearDown() {
        // 恢复默认值
        config.resetAll()
        config = nil
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
}
