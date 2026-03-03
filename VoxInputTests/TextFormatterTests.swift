// TextFormatterTests.swift
// VoxInputTests
//
// TextFormatter 单元测试

import XCTest
@testable import VoxInput

final class TextFormatterTests: XCTestCase {

    // MARK: - 中文标点规范化

    func testChinesePunctuationNormalization_comma() {
        // CJK 字符后的英文逗号应转为中文逗号
        let input = "你好,世界"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "你好，世界")
    }

    func testChinesePunctuationNormalization_period() {
        let input = "你好.世界"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "你好。世界")
    }

    func testChinesePunctuationNormalization_questionMark() {
        let input = "你好?"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "你好？")
    }

    func testChinesePunctuationNormalization_exclamationMark() {
        let input = "你好!"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "你好！")
    }

    func testChinesePunctuationNormalization_colon() {
        let input = "提示:请输入"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "提示：请输入")
    }

    func testChinesePunctuationNormalization_semicolon() {
        let input = "第一;第二"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "第一；第二")
    }

    func testChinesePunctuationNormalization_allTypes() {
        let input = "你好,世界.再见?是的!提示:请;好"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "你好，世界。再见？是的！提示：请；好")
    }

    func testDuplicateChinesePunctuationDedup() {
        // 连续相同中文标点应去重
        let input = "你好，，世界"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "你好，世界")
    }

    func testTripleChinesePunctuationDedup() {
        let input = "你好！！！世界"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "你好！世界")
    }

    // MARK: - 中英混合空格

    func testCJKSpacing_chineseFollowedByEnglish() {
        let input = "你好world"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "你好 world")
    }

    func testCJKSpacing_englishFollowedByChinese() {
        let input = "hello世界"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "hello 世界")
    }

    func testCJKSpacing_chineseWithNumbers() {
        let input = "第3章"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "第 3 章")
    }

    func testCJKSpacing_mixedSentence() {
        let input = "使用Swift开发iOS应用"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "使用 Swift 开发 iOS 应用")
    }

    func testCJKSpacing_alreadyHasSpaces() {
        // 已有空格的不应重复添加
        let input = "使用 Swift 开发"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "使用 Swift 开发")
    }

    // MARK: - 纯英文不加多余空格

    func testPureEnglish_noExtraSpaces() {
        let input = "Hello World"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "Hello World")
    }

    func testPureEnglish_collapsesMultipleSpaces() {
        let input = "Hello   World"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "Hello World")
    }

    func testPureEnglish_noModification() {
        let input = "This is a test sentence."
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "This is a test sentence.")
    }

    func testPureEnglish_preservesPunctuation() {
        let input = "Hello, World! How are you?"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "Hello, World! How are you?")
    }

    // MARK: - 空字符串

    func testEmptyString() {
        let result = TextFormatter.format("")
        XCTAssertEqual(result, "")
    }

    func testWhitespaceOnly() {
        let result = TextFormatter.format("   ")
        XCTAssertEqual(result, "")
    }

    func testNewlineOnly() {
        let result = TextFormatter.format("\n\n")
        XCTAssertEqual(result, "")
    }

    // MARK: - 纯标点

    func testPureChinesePunctuation() {
        let input = "，。！"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "，。！")
    }

    func testPureEnglishPunctuation() {
        // 英文标点前无 CJK 字符，不应转换
        let input = ",.!?"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, ",.!?")
    }

    // MARK: - 边界情况

    func testLeadingTrailingWhitespace() {
        let input = "  你好世界  "
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "你好世界")
    }

    func testSingleChineseCharacter() {
        let input = "好"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "好")
    }

    func testSingleEnglishWord() {
        let input = "Hello"
        let result = TextFormatter.format(input)
        XCTAssertEqual(result, "Hello")
    }
}
