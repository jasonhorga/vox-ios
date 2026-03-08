// KeyboardView.swift
// VoxInputKeyboard

import SwiftUI

/// 键盘扩展主视图
struct KeyboardView: View {

    /// 键盘状态管理器
    let state: KeyboardState

    /// 是否需要显示地球键
    let needsGlobeKey: Bool

    /// 地球键回调（切换输入法）
    let onGlobeKeyTap: () -> Void

    /// 录音开始回调
    let onRecordStart: () -> Void

    /// 录音停止回调
    let onRecordStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .frame(maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 主内容区

    @ViewBuilder
    private var mainContent: some View {
        switch state.phase {
        case .idle:
            idleView
        case .recording:
            recordingView
        case .processing:
            processingView
        case .done(let text):
            doneView(text: text)
        case .error:
            idleView
        }
    }

    // MARK: - 空闲状态

    private var idleView: some View {
        VStack(spacing: 16) {
            if state.isSecureInput {
                secureInputHint
            } else {
                micActionControl

                Text(state.shouldWakeMainApp() ? "点击麦克风唤醒 Vox Input" : "点击开始说话")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 录音状态

    private var recordingView: some View {
        VStack(spacing: 12) {
            KeyboardWaveformView(isRecording: state.isRecordingForWaveform)
                .frame(height: 60)
                .padding(.horizontal, 24)

            micActionControl

            Text("录音中，点击结束")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
        }
    }

    // MARK: - 处理状态

    private var processingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(.blue)

            Text(state.statusMessage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 完成状态

    private func doneView(text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("已输入")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 麦克风交互控制（休眠时 Link，正常时 Button）

    @ViewBuilder
    private var micActionControl: some View {
        if state.shouldWakeMainApp() {
            Link(destination: URL(string: "voxinput://record?source=keyboard&mode=wakeup")!) {
                micButtonIcon(isActive: false)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded {
                    state.markWakingUp()
                }
            )
            .accessibilityLabel("点击唤醒 Vox Input")
        } else {
            let isActive = state.phase == .recording
            Button {
                if isActive {
                    onRecordStop()
                } else {
                    onRecordStart()
                }
            } label: {
                micButtonIcon(isActive: isActive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActive ? "录音中，点击结束" : "点击开始说话")
        }
    }

    private func micButtonIcon(isActive: Bool) -> some View {
        Circle()
            .fill(isActive ? Color.red : Color.blue)
            .frame(
                width: Constants.Keyboard.micButtonSize,
                height: Constants.Keyboard.micButtonSize
            )
            .overlay {
                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
    }

    // MARK: - 密码输入框提示

    private var secureInputHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("密码输入框")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Text("语音输入在密码框中不可用")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 底部工具栏

    private var bottomBar: some View {
        HStack {
            if needsGlobeKey {
                GlobeKeyView(action: onGlobeKeyTap)
            }

            Spacer()

            if !state.statusMessage.isEmpty && state.phase != .recording {
                Text(state.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if needsGlobeKey {
                Color.clear
                    .frame(width: 44, height: 40)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .frame(height: 44)
    }
}

/// beta.58: 波形视图 — 使用 TimelineView(.animation) 自驱动
/// 彻底解决杀后台/重开后 Task 和 Timer 死锁导致波形冻结的问题
/// SwiftUI 底层驱动渲染帧，只要 isRecording == true 就永不假死
struct KeyboardWaveformView: View {

    let isRecording: Bool

    /// 柱子数量
    private let barCount = Constants.Keyboard.waveformSampleCount

    var body: some View {
        if isRecording {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let barWidth = size.width / CGFloat(barCount) * 0.7
                    let barSpacing = size.width / CGFloat(barCount)
                    let centerY = size.height / 2

                    for i in 0..<barCount {
                        let fi = Double(i)

                        // 多层 sin/cos 叠加，模拟自然、不规则的声波
                        let wave1 = sin(t * 3.2 + fi * 0.45) * 0.3
                        let wave2 = cos(t * 5.7 + fi * 0.7) * 0.2
                        let wave3 = sin(t * 1.8 + fi * 1.2) * 0.15
                        let wave4 = cos(t * 8.3 + fi * 0.3) * 0.1

                        // 归一化到 0.05 ~ 0.85 范围，保证视觉下限
                        let raw = 0.4 + wave1 + wave2 + wave3 + wave4
                        let level = CGFloat(min(max(raw, 0.05), 0.85))

                        let barHeight = max(2, level * size.height * 0.8)
                        let x = CGFloat(i) * barSpacing + barSpacing * 0.15
                        let y = centerY - barHeight / 2

                        let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                        let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                        let color = level > 0.5 ? Color.red.opacity(0.8) : Color.blue.opacity(0.7)
                        context.fill(path, with: .color(color))
                    }
                }
            }
        } else {
            // 非录音状态：静态空白（节省 GPU 帧）
            Color.clear
        }
    }
}
