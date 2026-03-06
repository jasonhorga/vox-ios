// MainView.swift
// VoxInput
//
// 主录音界面：大按钮 + 波形 + 状态 + 结果展示
// 按住录音，松开停止

import SwiftUI

/// 主视图
struct MainView: View {

    /// 后台音频守护进程（由 VoxInputApp 注入）
    let daemonService: AudioDaemonService

    /// 全局状态
    @State private var appState = AppState()

    /// 是否显示设置页
    @State private var showSettings = false

    /// 是否需要显示权限引导
    @State private var showPermission = false

    /// 是否显示历史记录
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    // 状态文字
                    statusSection

                    // 波形视图
                    waveformSection

                    // 录音按钮
                    recordButton

                    // 结果展示
                    resultSection

                    Spacer()

                    // 底部提示
                    bottomHint
                }
                .padding()
            }
            .navigationTitle("Vox Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showHistory) {
                HistoryView()
            }
            .sheet(isPresented: $showPermission) {
                PermissionView {
                    showPermission = false
                }
            }
            .alert("错误", isPresented: $appState.showError) {
                Button("确定", role: .cancel) {}

                // 如果是权限问题，提供打开设置的选项
                if case .microphonePermissionDenied = appState.lastError {
                    Button("打开设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } message: {
                Text(appState.lastError?.errorDescription ?? "未知错误")
            }
            .onAppear {
                checkInitialState()
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
        }
    }

    // MARK: - 子视图

    /// 状态文字区域
    private var statusSection: some View {
        VStack(spacing: 8) {
            // 状态图标
            switch appState.recordingState {
            case .idle:
                Image(systemName: "mic.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            case .recording:
                Image(systemName: "mic.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: true)
            case .processing:
                ProgressView()
                    .controlSize(.large)
            }

            // 状态文字
            if !appState.statusMessage.isEmpty {
                Text(appState.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.recordingState)
        .frame(height: 80)
    }

    /// 波形视图区域
    private var waveformSection: some View {
        WaveformView(
            levels: appState.audioRecorder.levelHistory,
            isRecording: appState.recordingState == .recording,
            barColor: .red
        )
        .padding(.horizontal)
        .opacity(appState.recordingState == .recording ? 1 : 0.3)
        .animation(.easeInOut(duration: 0.3), value: appState.recordingState)
    }

    /// 录音按钮
    /// 按住开始录音，松开停止
    private var recordButton: some View {
        let isRecording = appState.recordingState == .recording
        let isProcessing = appState.recordingState == .processing

        return Button {
            // 点击切换模式（tap toggle）
            Task {
                await appState.toggleRecording()
            }
        } label: {
            ZStack {
                // 外圈
                Circle()
                    .fill(isRecording ? Color.red.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: Constants.UI.recordButtonSize + 20,
                           height: Constants.UI.recordButtonSize + 20)

                // 内圈
                Circle()
                    .fill(isRecording ? Color.red : Color.red.opacity(0.8))
                    .frame(width: Constants.UI.recordButtonSize,
                           height: Constants.UI.recordButtonSize)
                    .scaleEffect(isRecording ? 1.1 : 1.0)

                // 图标
                if isRecording {
                    // 录音中显示方块（停止图标）
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.5 : 1.0)
        .animation(.spring(response: 0.3), value: isRecording)
        .sensoryFeedback(.impact(flexibility: .solid), trigger: isRecording)
        .simultaneousGesture(
            // 长按手势：按住录音，松开停止
            LongPressGesture(minimumDuration: 0.2)
                .onEnded { _ in
                    if appState.recordingState == .idle {
                        Task {
                            await appState.startRecording()
                        }
                    }
                }
        )
    }

    /// 结果展示区域
    private var resultSection: some View {
        Group {
            if let result = appState.lastResult, appState.showResult {
                VStack(spacing: 12) {
                    Text(result)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    HStack {
                        Image(systemName: "doc.on.clipboard.fill")
                            .foregroundStyle(.green)
                        Text("已复制到剪贴板")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal)
            }
        }
        .animation(.spring(response: 0.4), value: appState.showResult)
        .frame(minHeight: 60)
    }

    /// 底部提示
    private var bottomHint: some View {
        Group {
            if !appState.hasAPIKey {
                Label("请先在设置中配置 API Key", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !appState.isNetworkAvailable {
                Label("离线模式（Apple 本地识别）", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("点击按钮开始录音，再次点击停止")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - 初始状态检查

    /// 检查初始状态（权限、配置等）
    private func checkInitialState() {
        // 检查麦克风权限
        switch appState.audioRecorder.permissionStatus {
        case .undetermined:
            showPermission = true
        case .denied:
            showPermission = true
        case .granted:
            break
        @unknown default:
            break
        }
    }

    /// 处理 URL Scheme（voxinput://record）
    /// beta.27: 仅用于"极速闪跳"唤醒主 App 守护进程，不再在前台直接代替键盘录音
    /// beta.31: 关键修复 — 趁 App 还在前台时立刻激活音频会话，解决后台转换时序竞争
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "voxinput" else { return }
        guard url.host?.lowercased() == "record" else { return }

        // 关键修复：趁 App 还在前台（URL Scheme 刚打开），立刻激活音频会话
        // 这样当 App 退入后台时，音频会话已经激活，录音不会被系统拒绝
        // 解决 OSStatus 560557684 时序竞争问题
        daemonService.primeForBackgroundRecording()
        appState.markDaemonWokenByKeyboard()
    }
}

#Preview {
    MainView(daemonService: AudioDaemonService())
}
