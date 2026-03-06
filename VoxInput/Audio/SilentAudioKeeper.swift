// SilentAudioKeeper.swift
// VoxInput
//
// 后台保活：循环播放静音 PCM，维持 AudioSession 活跃

import AVFoundation
import Foundation

@MainActor
final class SilentAudioKeeper {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private var isRunning = false
    private var hasAttachedPlayer = false

    private let bufferDuration: TimeInterval = 1.0
    private let sampleRate: Double = Constants.Audio.sampleRate

    func startIfNeeded() throws {
        guard !isRunning else { return }

        try configureSession()

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(Constants.Audio.channels),
            interleaved: false
        )

        guard let format else {
            throw VoxError.recordingFailed("静音保活音频格式创建失败")
        }

        if !hasAttachedPlayer {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            hasAttachedPlayer = true
        }

        let frameCount = AVAudioFrameCount(sampleRate * bufferDuration)
        guard let silentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw VoxError.recordingFailed("静音缓冲区创建失败")
        }
        silentBuffer.frameLength = frameCount

        if let channels = silentBuffer.floatChannelData {
            for channelIndex in 0 ..< Int(format.channelCount) {
                channels[channelIndex].initialize(repeating: 0, count: Int(frameCount))
            }
        }

        player.volume = 0.0
        player.scheduleBuffer(silentBuffer, at: nil, options: [.loops], completionHandler: nil)

        if !engine.isRunning {
            try engine.start()
        }
        if !player.isPlaying {
            player.play()
        }

        isRunning = true
    }

    func stop() {
        guard isRunning else { return }

        if player.isPlaying {
            player.stop()
        }
        engine.stop()
        isRunning = false
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setActive(true, options: [])
    }
}
