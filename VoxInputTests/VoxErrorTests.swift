// VoxErrorTests.swift
// VoxInputTests
//
// VoxError 单元测试

import XCTest
@testable import VoxInput

final class VoxErrorTests: XCTestCase {

    // MARK: - 所有错误类型的 localizedDescription 不为空

    /// 所有错误 case（包括关联值的），用于遍历测试
    private var allErrors: [VoxError] {
        [
            .microphonePermissionDenied,
            .speechPermissionDenied,
            .recordingFailed("test detail"),
            .audioEmpty,
            .audioTooShort,
            .audioFileInvalid,
            .asrTimeout,
            .asrEmptyResult,
            .asrNetworkError("network detail"),
            .asrAPIError("api detail"),
            .networkUnavailable,
            .apiKeyMissing,
            .configLoadFailed("config detail"),
            .clipboardFailed,
            .unknown("unknown detail"),
        ]
    }

    func testAllErrors_errorDescriptionNotEmpty() {
        for error in allErrors {
            let description = error.errorDescription
            XCTAssertNotNil(description, "errorDescription 不应为 nil: \(error)")
            XCTAssertFalse(description!.isEmpty, "errorDescription 不应为空字符串: \(error)")
        }
    }

    func testAllErrors_shortDescriptionNotEmpty() {
        for error in allErrors {
            let description = error.shortDescription
            XCTAssertFalse(description.isEmpty, "shortDescription 不应为空字符串: \(error)")
        }
    }

    // MARK: - 错误类型枚举完整性

    func testErrorEnumCompleteness() {
        // 验证所有已知 case 都在 allErrors 列表中
        // 通过 switch 穷举确保覆盖所有 case
        for error in allErrors {
            switch error {
            case .microphonePermissionDenied: break
            case .speechPermissionDenied: break
            case .recordingFailed: break
            case .audioEmpty: break
            case .audioTooShort: break
            case .audioFileInvalid: break
            case .asrTimeout: break
            case .asrEmptyResult: break
            case .asrNetworkError: break
            case .asrAPIError: break
            case .networkUnavailable: break
            case .apiKeyMissing: break
            case .configLoadFailed: break
            case .clipboardFailed: break
            case .unknown: break
            }
            // 如果编译通过，说明 switch 穷举了所有 case
        }
    }

    // MARK: - 特定错误类型描述验证

    func testMicrophonePermissionDenied_description() {
        let error = VoxError.microphonePermissionDenied
        XCTAssertTrue(error.errorDescription!.contains("麦克风"))
        XCTAssertTrue(error.shortDescription.contains("麦克风"))
    }

    func testSpeechPermissionDenied_description() {
        let error = VoxError.speechPermissionDenied
        XCTAssertTrue(error.errorDescription!.contains("语音识别"))
        XCTAssertTrue(error.shortDescription.contains("语音识别"))
    }

    func testRecordingFailed_includesDetail() {
        let detail = "模拟器无法录音"
        let error = VoxError.recordingFailed(detail)
        XCTAssertTrue(error.errorDescription!.contains(detail))
    }

    func testASRNetworkError_includesDetail() {
        let detail = "Connection refused"
        let error = VoxError.asrNetworkError(detail)
        XCTAssertTrue(error.errorDescription!.contains(detail))
    }

    func testASRAPIError_includesDetail() {
        let detail = "Invalid API Key"
        let error = VoxError.asrAPIError(detail)
        XCTAssertTrue(error.errorDescription!.contains(detail))
    }

    func testConfigLoadFailed_includesDetail() {
        let detail = "文件不存在"
        let error = VoxError.configLoadFailed(detail)
        XCTAssertTrue(error.errorDescription!.contains(detail))
    }

    func testUnknownError_includesDetail() {
        let detail = "unexpected nil"
        let error = VoxError.unknown(detail)
        XCTAssertTrue(error.errorDescription!.contains(detail))
    }

    // MARK: - LocalizedError 协议

    func testConformsToLocalizedError() {
        let error: any LocalizedError = VoxError.apiKeyMissing
        XCTAssertNotNil(error.errorDescription)
    }

    func testConformsToError() {
        let error: any Error = VoxError.networkUnavailable
        XCTAssertFalse(error.localizedDescription.isEmpty)
    }
}
