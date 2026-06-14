// SettingsView.swift
// VoxInput
//
// 设置页面：ASR 提供商配置 + API Key 管理

import SwiftUI

/// 设置视图
struct SettingsView: View {
    
    /// 配置存储
    @Bindable private var config = ConfigStore.shared
    
    /// 关闭回调
    @Environment(\.dismiss) private var dismiss
    
    /// API Key 输入临时状态（避免每次按键都写入 UserDefaults）
    @State private var qwenKeyInput: String = ""
    @State private var qwenModelInput: String = ""
    @State private var whisperKeyInput: String = ""
    @State private var whisperURLInput: String = ""
    @State private var whisperModelInput: String = ""
    @State private var chatModelInput: String = ""
    
    /// 显示保存成功提示
    @State private var showSaveConfirmation: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - ASR 提供商选择
                Section {
                    Picker("ASR 引擎", selection: $config.asrProvider) {
                        ForEach(ASRProviderType.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                } header: {
                    Text("语音识别")
                } footer: {
                    Text("选择语音转文字的 AI 引擎")
                }
                
                // MARK: - Qwen ASR 配置
                if config.asrProvider == .qwen {
                    Section {
                        SecureField("DashScope API Key", text: $qwenKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        
                        TextField("模型名称", text: $qwenModelInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Qwen ASR 配置")
                    } footer: {
                        Text("从阿里云 DashScope 控制台获取 API Key，可按需自定义模型名称")
                    }
                }
                
                // MARK: - Whisper API 配置
                if config.asrProvider == .whisper {
                    Section {
                        SecureField("API Key", text: $whisperKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        
                        TextField("API URL", text: $whisperURLInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        
                        TextField("模型名称", text: $whisperModelInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("对话模型（整理/翻译用）", text: $chatModelInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            applyGroqPreset()
                        } label: {
                            Label("使用 Groq 推荐配置（免费额度大）", systemImage: "sparkles")
                        }
                    } header: {
                        Text("Whisper API 配置")
                    } footer: {
                        Text("支持 OpenAI Whisper 及兼容接口（Groq 等）。"
                            + "对话模型用于智能整理/翻译后处理，需所选端点支持该 Chat 模型。\n\n"
                            + "推荐 Groq：转写又快又准、免费额度大（约 2000 次/天）。点上面按钮一键填入端点与模型，"
                            + "再到 \(Constants.Network.groqConsoleURL) 免费申请 API Key 填进上方即可。")
                    }
                }
                
                // MARK: - 后处理（智能整理 + 翻译）
                Section {
                    Toggle("智能整理", isOn: $config.smartCleanup)

                    Picker("翻译模式", selection: $config.translationMode) {
                        ForEach(TranslationMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } header: {
                    Text("后处理")
                } footer: {
                    Text("智能整理：用 AI 去掉口头禅、顺语序、按口述意图排版（需联网、消耗 API 调用，离线自动跳过）。翻译：识别完成后翻成目标语言。")
                }

                // MARK: - 免跳转 / 后台常驻
                Section {
                    Picker("后台常驻时长", selection: $config.daemonStandbyDuration) {
                        ForEach(DaemonStandbyDuration.allCases, id: \.self) { duration in
                            Text(duration.displayName).tag(duration)
                        }
                    }
                } header: {
                    Text("免跳转 / 后台常驻")
                } footer: {
                    Text("键盘要打开麦克风必须先切到主 App（iOS 的限制）。让主 App 在后台常驻得越久，"
                        + "越多次听写能「免跳转」——直接录、并自动切回输入框；代价是常驻期间系统麦克风指示灯常亮、更耗电。"
                        + "「始终常驻」跳转最少、最费电；较短时长更省电，但空闲超时后再用需切一次 App。")
                }
                
                // MARK: - 关于
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("最低 iOS")
                        Spacer()
                        Text("17.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("关于")
                }
                
                // MARK: - 重置
                Section {
                    Button(role: .destructive) {
                        config.resetAll()
                        loadCurrentValues()
                    } label: {
                        Label("重置所有设置", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveSettings()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                loadCurrentValues()
            }
            .overlay {
                // 保存成功提示
                if showSaveConfirmation {
                    VStack {
                        Spacer()
                        Text("设置已保存")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.green, in: Capsule())
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .padding(.bottom, 32)
                    .animation(.easeInOut, value: showSaveConfirmation)
                }
            }
        }
    }
    
    // MARK: - 数据操作
    
    /// 一键填入 Groq 推荐配置（端点 + 转写模型 + 对话模型）；API Key 仍需用户自行填写。
    /// 仅改输入框，未点「保存」不会落库。
    private func applyGroqPreset() {
        whisperURLInput = Constants.Network.groqTranscriptionURL
        whisperModelInput = Constants.Network.groqTranscriptionModel
        chatModelInput = Constants.Network.groqChatModel
    }

    /// 从 ConfigStore 加载当前值
    private func loadCurrentValues() {
        qwenKeyInput = config.qwenAPIKey
        qwenModelInput = config.qwenModel
        whisperKeyInput = config.whisperAPIKey
        whisperURLInput = config.whisperBaseURL
        whisperModelInput = config.whisperModel
        chatModelInput = config.chatModel
    }
    
    /// 保存设置到 ConfigStore
    private func saveSettings() {
        config.qwenAPIKey = qwenKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQwenModel = qwenModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        config.qwenModel = trimmedQwenModel.isEmpty ? "qwen-omni-turbo" : trimmedQwenModel
        config.whisperAPIKey = whisperKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        config.whisperBaseURL = whisperURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        config.whisperModel = whisperModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedChatModel = chatModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        config.chatModel = trimmedChatModel.isEmpty ? "gpt-4o-mini" : trimmedChatModel

        // 显示保存确认
        withAnimation {
            showSaveConfirmation = true
        }
        
        // 2 秒后隐藏并关闭
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation {
                    showSaveConfirmation = false
                }
                dismiss()
            }
        }
    }
}

// MARK: - ASRProviderType 显示名称

extension ASRProviderType {
    var displayName: String {
        switch self {
        case .qwen: return "Qwen ASR（通义千问）"
        case .whisper: return "Whisper API"
        }
    }
}

#Preview {
    SettingsView()
}
