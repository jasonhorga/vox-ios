// DaemonCaptureSinkTests.swift
// VoxInputTests
//
// M6: 验证从守护录音器抽出的线程安全采集 sink——
// 软开关语义（未 begin 时 append 是 no-op）、转换+落盘逻辑仍正确、并发 append 不崩溃。

import XCTest
import AVFoundation
@testable import VoxInput

final class DaemonCaptureSinkTests: XCTestCase {

    private func makeFormat() -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
    }

    private func makeBuffer(_ format: AVAudioFormat, frames: AVAudioFrameCount = 1024) -> AVAudioPCMBuffer? {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        buffer?.frameLength = frames
        return buffer
    }

    private func makeOutputFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sink_test_\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        _ = try AVAudioFile(forWriting: url, settings: settings)
        return url
    }

    /// 未 begin 时 finish 返回默认值
    func testFinishWithoutBeginReturnsDefaults() {
        let sink = DaemonCaptureSink()
        let result = sink.finish()
        XCTAssertFalse(result.received)
        XCTAssertNil(result.runtimeError)
    }

    /// 软开关：未 begin（未采集）时 append 是安全 no-op，不记录任何音频
    func testAppendBeforeBeginIsNoOp() throws {
        guard let format = makeFormat(), let buffer = makeBuffer(format) else {
            return XCTFail("无法构造测试音频格式/缓冲区")
        }
        let sink = DaemonCaptureSink()
        sink.append(buffer)   // 未 begin → 不采集 → no-op
        XCTAssertFalse(sink.finish().received)
    }

    /// 重构后的转换+落盘逻辑仍能把音频写入文件（received=true、无错误）
    func testBeginAppendFinishCapturesAudio() throws {
        guard let format = makeFormat() else { return XCTFail("无法构造测试音频格式") }
        let url = try makeOutputFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        guard let converter = AVAudioConverter(from: format, to: format),
              let buffer = makeBuffer(format) else {
            return XCTFail("无法构造转换器/缓冲区")
        }

        let sink = DaemonCaptureSink()
        sink.begin(file: file, converter: converter, targetFormat: format, onError: nil)
        sink.append(buffer)
        let result = sink.finish()

        XCTAssertTrue(result.received)
        XCTAssertNil(result.runtimeError)
        // finish 后再 append 应为 no-op（已停止采集）
        sink.append(buffer)
        XCTAssertFalse(sink.finish().received)
    }

    /// 并发 append 不崩溃（lock 串行化写入）。CI 抓不到竞争，但能验证不会因并发而 crash。
    func testConcurrentAppendDoesNotCrash() throws {
        guard let format = makeFormat() else { return XCTFail("无法构造测试音频格式") }
        let url = try makeOutputFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        guard let converter = AVAudioConverter(from: format, to: format) else {
            return XCTFail("无法构造转换器")
        }

        let sink = DaemonCaptureSink()
        sink.begin(file: file, converter: converter, targetFormat: format, onError: nil)

        // 多线程同时 append（每次独立缓冲区），模拟音频线程与主线程并发访问
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            if let buffer = self.makeBuffer(format) {
                sink.append(buffer)
            }
        }

        XCTAssertTrue(sink.finish().received)
    }
}
