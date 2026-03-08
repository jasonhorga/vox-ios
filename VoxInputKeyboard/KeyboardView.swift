// KeyboardView.swift
// VoxInputKeyboard
//
// beta.50: 键盘扩展主 UI — Method D 唯一真理 + Tap to Toggle + 视觉升级
// SwiftUI 实现，嵌入 UIInputViewController 中

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
    
    /// 呼吸动画状态
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 主内容区
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 底部工具栏（地球键 + 状态文本）
            bottomBar
        }
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground).opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
        case .error(let message):
            errorView(message: message)
        }
    }
    
    // MARK: - 空闲状态 (beta.50: Method D Link + 正常麦克风)
    
    private var idleView: some View {
        VStack(spacing: 16) {
            if state.isSecureInput {
                secureInputHint
            } else if state.shouldWakeMainApp() {
                // 后台休眠 → SwiftUI Link 伪装成唤醒按钮
                wakeupLinkButton
                
                Text("后台已休眠，点击唤醒")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                // 正常麦克风按钮 (tap to toggle)
                micButton
                
                Text("点击开始说话")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - 录音状态 (beta.50: tap to stop)
    
    private var recordingView: some View {
        VStack(spacing: 12) {
            // 波形显示
            KeyboardWaveformView(levels: state.levelHistory)
                .frame(height: 60)
                .padding(.horizontal, 24)
            
            // 录音中按钮（带呼吸动画）
            micButton
            
            Text("录音中，点击结束")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red.opacity(0.8))
        }
    }
    
    // MARK: - 处理状态
    
    private var processingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(.indigo)
            
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
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
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
    
    // MARK: - 错误状态 (beta.50: 简洁唤醒引导)
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            if state.openURLDidFail {
                // 后台休眠 → SwiftUI Link 唤醒引导
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("后台服务已休眠")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                
                // beta.50: 唯一跳转方式 — SwiftUI Link (Method D)
                Link(destination: URL(string: "voxinput://record?source=keyboard&mode=wakeup")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text("点击唤醒 Vox Input")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [.orange, .red.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .orange.opacity(0.3), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                
                Button {
                    Task { @MainActor in
                        state.resetToIdle()
                    }
                } label: {
                    Text("✅ 已唤醒，重新录音")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.blue)
                }
            } else {
                // 普通错误
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
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
    
    // MARK: - beta.50: SwiftUI Link 唤醒按钮（伪装成麦克风 + 闪电）
    
    private var wakeupLinkButton: some View {
        Link(destination: URL(string: "voxinput://record?source=keyboard&mode=wakeup")!) {
            ZStack {
                // 外圈光晕
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.orange.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: Constants.Keyboard.micButtonSize * 0.4,
                            endRadius: Constants.Keyboard.micButtonSize * 0.7
                        )
                    )
                    .frame(
                        width: Constants.Keyboard.micButtonSize + 20,
                        height: Constants.Keyboard.micButtonSize + 20
                    )
                
                // 主按钮
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.red.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(
                        width: Constants.Keyboard.micButtonSize,
                        height: Constants.Keyboard.micButtonSize
                    )
                    .shadow(color: .orange.opacity(0.4), radius: 12, y: 4)
                
                // 麦克风 + 闪电图标
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.yellow)
                        .offset(x: 8, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 麦克风按钮 (beta.50: Tap to Toggle + 渐变视觉)
    
    private var micButton: some View {
        let isActive = state.phase == .recording
        
        return Button {
            if isActive {
                onRecordStop()
            } else {
                onRecordStart()
            }
        } label: {
            ZStack {
                // 录音时的外圈呼吸光晕
                if isActive {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.red.opacity(0.25),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: Constants.Keyboard.micButtonSize * 0.3,
                                endRadius: Constants.Keyboard.micButtonSize * 0.75
                            )
                        )
                        .frame(
                            width: Constants.Keyboard.micButtonSize + 24,
                            height: Constants.Keyboard.micButtonSize + 24
                        )
                        .scaleEffect(isPulsing ? 1.2 : 0.9)
                }
                
                // 主按钮
                Circle()
                    .fill(
                        isActive
                            ? LinearGradient(
                                colors: [Color.red, Color.orange.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                colors: [Color.indigo, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                    )
                    .frame(
                        width: Constants.Keyboard.micButtonSize,
                        height: Constants.Keyboard.micButtonSize
                    )
                    .shadow(
                        color: isActive ? .red.opacity(0.35) : .indigo.opacity(0.3),
                        radius: isActive ? 14 : 10,
                        y: 4
                    )
                    .scaleEffect(isActive && isPulsing ? 1.08 : 1.0)
                
                // 麦克风图标
                Image(systemName: isActive ? "mic.fill" : "mic")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "录音中，点击结束" : "点击开始说话")
        .onChange(of: isActive) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isPulsing = false
                }
            }
        }
    }
    
    // MARK: - 底部工具栏
    
    private var bottomBar: some View {
        HStack {
            // 地球键（条件显示）
            if needsGlobeKey {
                GlobeKeyView(action: onGlobeKeyTap)
            }
            
            Spacer()
            
            // 状态文本
            if !state.statusMessage.isEmpty && state.phase != .recording {
                Text(state.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            // 占位（保持对称）
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

// MARK: - 键盘波形视图 (beta.50: 渐变色波形)

/// 简化版波形视图（键盘扩展专用，减少采样点）
struct KeyboardWaveformView: View {
    
    let levels: [Float]
    
    var body: some View {
        Canvas { context, size in
            let barCount = Constants.Keyboard.waveformSampleCount
            let barWidth = size.width / CGFloat(barCount) * 0.7
            let barSpacing = size.width / CGFloat(barCount)
            let centerY = size.height / 2
            
            for i in 0..<barCount {
                let level: Float
                if i < levels.count {
                    level = levels[i]
                } else {
                    level = 0.0
                }
                
                let barHeight = max(2, CGFloat(level) * size.height * 0.8)
                let x = CGFloat(i) * barSpacing + barSpacing * 0.15
                let y = centerY - barHeight / 2
                
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                
                // beta.50: 渐变色波形（从 indigo 到 red，根据电平强度）
                let intensity = Double(level)
                let color = Color(
                    red: 0.3 + intensity * 0.5,
                    green: 0.2 + (1 - intensity) * 0.3,
                    blue: 0.8 - intensity * 0.4
                ).opacity(0.4 + intensity * 0.6)
                context.fill(path, with: .color(color))
            }
        }
    }
}
