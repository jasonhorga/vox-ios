// KeyboardView.swift
// VoxInputKeyboard
//
// 键盘扩展主 UI：麦克风按钮 + 波形 + 状态显示
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
    
    /// 唤醒主 App 回调
    let onWakeupApp: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // 主内容区
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 底部工具栏（地球键 + 状态文本）
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
        case .error(let message):
            errorView(message: message)
        }
    }
    
    // MARK: - 空闲状态
    
    private var idleView: some View {
        VStack(spacing: 16) {
            if state.isSecureInput {
                // 密码输入框提示
                secureInputHint
            } else if state.needsAppWakeup, let wakeupAction = onWakeupApp {
                // 需要唤醒主 App 的错误场景
                wakeupButton(action: wakeupAction)
            } else {
                // 麦克风按钮
                micButton
                
                Text("按住说话")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - 录音状态
    
    private var recordingView: some View {
        VStack(spacing: 12) {
            // 波形显示
            KeyboardWaveformView(levels: state.levelHistory)
                .frame(height: 60)
                .padding(.horizontal, 24)
            
            // 录音中按钮（带脉冲动画）
            micButton
            
            Text("松开结束录音")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - 处理状态
    
    private var processingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            
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
    
    // MARK: - 错误状态
    
    /// beta.37 重写：错误状态视图
    /// - 如果 openURL 全部失败 (openURLDidFail)：显示手动跳转引导
    /// - 如果需要唤醒但还没试过/还有机会：显示唤醒按钮
    /// - 其他错误：只显示错误信息
    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            if state.openURLDidFail {
                // beta.37: 所有自动策略失败，显示手动跳转引导
                manualWakeupGuide
            } else {
                // 普通错误 + 可选唤醒按钮
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if state.needsAppWakeup, let wakeupAction = onWakeupApp {
                    Button(action: wakeupAction) {
                        Text("🚀 立即唤醒")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    // MARK: - beta.37: 手动跳转引导视图
    
    /// 当所有自动 openURL 策略失败时，显示清晰的手动跳转引导
    /// 用户需要：1. 打开 Vox Input 应用  2. 等待激活  3. 返回这里重新录音
    private var manualWakeupGuide: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 28))
                .foregroundStyle(.blue)
            
            Text("需要唤醒 Vox Input")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 6) {
                Label("打开 Vox Input 应用", systemImage: "1.circle.fill")
                    .font(.system(size: 13))
                Label("等待显示\u{201C}后台语音守护已就绪\u{201D}", systemImage: "2.circle.fill")
                    .font(.system(size: 13))
                Label("返回这里，再次按住说话", systemImage: "3.circle.fill")
                    .font(.system(size: 13))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            
            // 再试一次按钮（用户可能切换完回来了）
            HStack(spacing: 12) {
                if let wakeupAction = onWakeupApp {
                    Button(action: wakeupAction) {
                        Text("🔄 再试一次")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
                
                Button {
                    // 重置状态到 idle，让用户可以重新按住说话
                    Task { @MainActor in
                        state.resetToIdle()
                    }
                } label: {
                    Text("✅ 已打开，重新录音")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 4)
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
    
    // MARK: - 唤醒按钮
    
    private func wakeupButton(action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Text("🚀")
                        .font(.system(size: 24))
                    Text("唤醒")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.orange)
                .clipShape(Capsule())
            }
            
            Text("后台服务已休眠，点击唤醒")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - 麦克风按钮
    
    private var micButton: some View {
        let isActive = state.phase == .recording
        
        return Circle()
            .fill(isActive ? Color.red : Color.blue)
            .frame(
                width: Constants.Keyboard.micButtonSize,
                height: Constants.Keyboard.micButtonSize
            )
            .overlay {
                Image(systemName: isActive ? "mic.fill" : "mic")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isActive ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isActive)
            .shadow(color: isActive ? .red.opacity(0.3) : .blue.opacity(0.2), radius: 8)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if state.phase == .idle {
                            onRecordStart()
                        }
                    }
                    .onEnded { _ in
                        if state.phase == .recording {
                            onRecordStop()
                        }
                    }
            )
            .accessibilityLabel(isActive ? "松开结束录音" : "按住开始录音")
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

// MARK: - 键盘波形视图

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
                
                let opacity = 0.3 + Double(level) * 0.7
                context.fill(path, with: .color(.blue.opacity(opacity)))
            }
        }
    }
}
