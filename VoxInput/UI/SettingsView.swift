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
                    } header: {
                        Text("Whisper API 配置")
                    } footer: {
                        Text("支持 OpenAI Whisper 及兼容接口（Groq 等）")
                    }
                }
                
                // MARK: - 翻译模式
                Section {
                    Picker("翻译模式", selection: $config.translationMode) {
                        ForEach(TranslationMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } header: {
                    Text("后处理")
                } footer: {
                    Text("识别完成后自动翻译为目标语言（需要消耗额外 API 调用）")
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
    
    /// 从 ConfigStore 加载当前值
    private func loadCurrentValues() {
        qwenKeyInput = config.qwenAPIKey
        qwenModelInput = config.qwenModel
        whisperKeyInput = config.whisperAPIKey
        whisperURLInput = config.whisperBaseURL
        whisperModelInput = config.whisperModel
    }
    
    /// 保存设置到 ConfigStore
    private func saveSettings() {
        config.qwenAPIKey = qwenKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQwenModel = qwenModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        config.qwenModel = trimmedQwenModel.isEmpty ? "qwen-omni-turbo" : trimmedQwenModel
        config.whisperAPIKey = whisperKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        config.whisperBaseURL = whisperURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        config.whisperModel = whisperModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
