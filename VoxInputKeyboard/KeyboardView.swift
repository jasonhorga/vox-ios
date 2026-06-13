// KeyboardView.swift
// VoxInputKeyboard

import SwiftUI

private extension RecordButtonPhase {
    /// 键盘相位 → 按钮阶段。error 按待命呈现（错误文案另由 statusMessage 显示）。
    init(_ phase: KeyboardPhase) {
        switch phase {
        case .idle, .error: self = .idle
        case .recording:    self = .recording
        case .processing:   self = .processing
        case .done:         self = .done
        }
    }
}

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
            micActionControl

            Text("录音中，点击结束")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
        }
    }

    // MARK: - 处理状态

    private var processingView: some View {
        VStack(spacing: 12) {
            RecordButton(phase: .processing, size: Constants.Keyboard.micButtonSize)

            Text(state.statusMessage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 完成状态

    private func doneView(text: String) -> some View {
        VStack(spacing: 8) {
            RecordButton(phase: .done, size: Constants.Keyboard.micButtonSize)

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
                RecordButton(phase: .idle, size: Constants.Keyboard.micButtonSize)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded {
                    state.markWakingUp()
                }
            )
            .accessibilityLabel("点击唤醒 Vox Input")
        } else {
            Button {
                if state.phase == .recording {
                    onRecordStop()
                } else {
                    onRecordStart()
                }
            } label: {
                RecordButton(phase: RecordButtonPhase(state.phase), size: Constants.Keyboard.micButtonSize)
            }
            .buttonStyle(.plain)
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
