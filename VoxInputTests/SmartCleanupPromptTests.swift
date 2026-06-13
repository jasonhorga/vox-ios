import XCTest
@testable import VoxInput

final class SmartCleanupPromptTests: XCTestCase {
    func testCleanupOnly() {
        let p = PostProcessor.systemPrompt(cleanup: true, translation: .none)
        XCTAssertTrue(p.contains("填充词"))
        XCTAssertFalse(p.contains("翻译"))
        XCTAssertTrue(p.contains("只输出最终文本"))
    }
    func testCleanupPlusTranslate() {
        let p = PostProcessor.systemPrompt(cleanup: true, translation: .toEnglish)
        XCTAssertTrue(p.contains("填充词"))
        XCTAssertTrue(p.contains("翻译成英文"))
    }
    func testTranslateOnly() {
        let p = PostProcessor.systemPrompt(cleanup: false, translation: .toChinese)
        XCTAssertFalse(p.contains("填充词"))
        XCTAssertTrue(p.contains("翻译成中文"))
    }
}
