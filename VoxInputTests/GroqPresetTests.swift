// GroqPresetTests.swift
// VoxInputTests
//
// 钉住 Groq 推荐预设：转写端点能正确推导出 chat completions 端点，
// 这样换成 Groq 后「智能整理/翻译」后处理才不会把请求发到转写端点上。

import XCTest
@testable import VoxInput

final class GroqPresetTests: XCTestCase {

    /// Groq 转写端点 → chat completions 端点
    func testGroqTranscriptionURLDerivesChatURL() {
        let chat = PostProcessor.chatCompletionsURL(fromTranscriptionURL: Constants.Network.groqTranscriptionURL)
        XCTAssertEqual(chat, "https://api.groq.com/openai/v1/chat/completions")
    }

    /// OpenAI 转写端点 → chat completions 端点（不能因为 Groq 改动而回归）
    func testOpenAIWhisperURLDerivesChatURL() {
        let chat = PostProcessor.chatCompletionsURL(
            fromTranscriptionURL: "https://api.openai.com/v1/audio/transcriptions"
        )
        XCTAssertEqual(chat, "https://api.openai.com/v1/chat/completions")
    }

    /// 已经是 chat 端点时保持不变（幂等）
    func testAlreadyChatURLUnchanged() {
        let url = "https://api.groq.com/openai/v1/chat/completions"
        XCTAssertEqual(PostProcessor.chatCompletionsURL(fromTranscriptionURL: url), url)
    }

    /// 预设常量是 Groq 端点 + 合理的模型名
    func testGroqPresetConstants() {
        XCTAssertTrue(Constants.Network.groqTranscriptionURL.contains("api.groq.com"))
        XCTAssertTrue(Constants.Network.groqTranscriptionURL.hasSuffix("/audio/transcriptions"))
        XCTAssertFalse(Constants.Network.groqTranscriptionModel.isEmpty)
        XCTAssertFalse(Constants.Network.groqChatModel.isEmpty)
    }
}
