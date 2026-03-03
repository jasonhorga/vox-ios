// HistoryManagerTests.swift
// VoxInputTests
//
// HistoryManager 单元测试

import XCTest
@testable import VoxInput

final class HistoryManagerTests: XCTestCase {

    /// 测试专用 UserDefaults suite 名称
    private let suiteName = "com.voxinput.tests.history"

    /// 被测对象
    private var manager: HistoryManager!

    /// 测试专用 UserDefaults
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)!
        // 清除测试 suite 中所有残留数据
        testDefaults.removePersistentDomain(forName: suiteName)
        manager = HistoryManager(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        manager = nil
        super.tearDown()
    }

    // MARK: - 添加条目

    func testAddSingleItem() {
        manager.add(text: "你好世界", provider: "qwen")

        XCTAssertEqual(manager.items.count, 1)
        XCTAssertEqual(manager.items.first?.text, "你好世界")
        XCTAssertEqual(manager.items.first?.provider, "qwen")
    }

    func testAddMultipleItems_newestFirst() {
        manager.add(text: "第一条", provider: "qwen")
        manager.add(text: "第二条", provider: "whisper")
        manager.add(text: "第三条", provider: "qwen")

        XCTAssertEqual(manager.items.count, 3)
        // 最新的在最前面
        XCTAssertEqual(manager.items[0].text, "第三条")
        XCTAssertEqual(manager.items[1].text, "第二条")
        XCTAssertEqual(manager.items[2].text, "第一条")
    }

    // MARK: - FIFO 淘汰（超过 100 条）

    func testFIFOEviction_at100Items() {
        // 添加 100 条
        for i in 1...100 {
            manager.add(text: "条目 \(i)", provider: "qwen")
        }
        XCTAssertEqual(manager.items.count, 100)

        // 添加第 101 条，最旧的应被淘汰
        manager.add(text: "条目 101", provider: "qwen")
        XCTAssertEqual(manager.items.count, 100)

        // 最新的在最前面
        XCTAssertEqual(manager.items.first?.text, "条目 101")
        // 最旧的（条目 1）应被移除，最后一条应该是条目 2
        XCTAssertEqual(manager.items.last?.text, "条目 2")
    }

    func testFIFOEviction_preservesOrder() {
        for i in 1...105 {
            manager.add(text: "条目 \(i)", provider: "qwen")
        }
        XCTAssertEqual(manager.items.count, 100)
        // 应保留条目 6~105（最旧的 5 条被淘汰）
        XCTAssertEqual(manager.items.first?.text, "条目 105")
        XCTAssertEqual(manager.items.last?.text, "条目 6")
    }

    // MARK: - 搜索过滤

    func testSearch_matchesSubstring() {
        manager.add(text: "Hello World", provider: "qwen")
        manager.add(text: "你好世界", provider: "qwen")
        manager.add(text: "Hello Swift", provider: "whisper")

        let results = manager.search("Hello")
        XCTAssertEqual(results.count, 2)
    }

    func testSearch_caseInsensitive() {
        manager.add(text: "Hello World", provider: "qwen")
        manager.add(text: "hello swift", provider: "whisper")

        let results = manager.search("HELLO")
        XCTAssertEqual(results.count, 2)
    }

    func testSearch_emptyQuery_returnsAll() {
        manager.add(text: "条目 1", provider: "qwen")
        manager.add(text: "条目 2", provider: "qwen")

        let results = manager.search("")
        XCTAssertEqual(results.count, 2)
    }

    func testSearch_noMatch() {
        manager.add(text: "你好世界", provider: "qwen")

        let results = manager.search("不存在的文本")
        XCTAssertEqual(results.count, 0)
    }

    func testSearch_chineseText() {
        manager.add(text: "语音识别测试", provider: "qwen")
        manager.add(text: "文字输入", provider: "whisper")
        manager.add(text: "语音转文字", provider: "qwen")

        let results = manager.search("语音")
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - 删除单条

    func testDeleteSingleItem() {
        manager.add(text: "条目 1", provider: "qwen")
        manager.add(text: "条目 2", provider: "qwen")
        manager.add(text: "条目 3", provider: "qwen")

        let itemToDelete = manager.items[1] // "条目 2"
        manager.delete(itemToDelete)

        XCTAssertEqual(manager.items.count, 2)
        XCTAssertFalse(manager.items.contains(where: { $0.text == "条目 2" }))
    }

    func testDeleteByIndexSet() {
        manager.add(text: "条目 1", provider: "qwen")
        manager.add(text: "条目 2", provider: "qwen")
        manager.add(text: "条目 3", provider: "qwen")

        manager.delete(at: IndexSet(integer: 0)) // 删除最新的 "条目 3"

        XCTAssertEqual(manager.items.count, 2)
        XCTAssertEqual(manager.items[0].text, "条目 2")
    }

    // MARK: - 清空全部

    func testClearAll() {
        for i in 1...10 {
            manager.add(text: "条目 \(i)", provider: "qwen")
        }
        XCTAssertEqual(manager.items.count, 10)

        manager.clearAll()
        XCTAssertEqual(manager.items.count, 0)
        XCTAssertTrue(manager.items.isEmpty)
    }

    func testClearAll_emptyHistory() {
        // 空历史记录清空不应崩溃
        manager.clearAll()
        XCTAssertEqual(manager.items.count, 0)
    }

    // MARK: - 持久化（写入后重新读取）

    func testPersistence_dataPreservedAfterReload() {
        manager.add(text: "持久化测试 1", provider: "qwen")
        manager.add(text: "持久化测试 2", provider: "whisper")

        // 用同一个 UserDefaults 创建新 manager 实例，模拟 App 重启
        let reloadedManager = HistoryManager(defaults: testDefaults)

        XCTAssertEqual(reloadedManager.items.count, 2)
        XCTAssertEqual(reloadedManager.items[0].text, "持久化测试 2")
        XCTAssertEqual(reloadedManager.items[1].text, "持久化测试 1")
    }

    func testPersistence_clearAllRemovesFromDisk() {
        manager.add(text: "将被清除", provider: "qwen")
        manager.clearAll()

        let reloadedManager = HistoryManager(defaults: testDefaults)
        XCTAssertTrue(reloadedManager.items.isEmpty)
    }

    func testPersistence_deleteRemovesFromDisk() {
        manager.add(text: "保留", provider: "qwen")
        manager.add(text: "将被删除", provider: "qwen")

        let itemToDelete = manager.items.first! // "将被删除"（最新的）
        manager.delete(itemToDelete)

        let reloadedManager = HistoryManager(defaults: testDefaults)
        XCTAssertEqual(reloadedManager.items.count, 1)
        XCTAssertEqual(reloadedManager.items[0].text, "保留")
    }
}
