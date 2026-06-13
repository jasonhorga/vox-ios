// AudioConstantsTests.swift
// VoxInputTests
//
// 钉住 M3/M7 的意图：两条录音路径的临时文件名必须不同；录音时长有上限。

import XCTest
@testable import VoxInput

final class AudioConstantsTests: XCTestCase {

    /// M3: 主 App 直录路径与守护进程必须用不同的临时文件名，避免并发互踩
    func testRecorderTempFileNamesAreDistinct() {
        XCTAssertNotEqual(Constants.Audio.tempFileName, Constants.Audio.daemonTempFileName)
        XCTAssertFalse(Constants.Audio.tempFileName.isEmpty)
        XCTAssertFalse(Constants.Audio.daemonTempFileName.isEmpty)
    }

    /// M7: 录音时长上限被收紧到一个有界、合理的值（整段进内存，不能无限长）
    func testMaxRecordingDurationIsBounded() {
        XCTAssertGreaterThan(Constants.Audio.maxRecordingDuration, 0)
        XCTAssertLessThanOrEqual(Constants.Audio.maxRecordingDuration, 600)
    }
}
