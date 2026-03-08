// HistoryView.swift
// VoxInput
//
// 历史记录列表：搜索、点击复制、左滑删除、清空全部
// Sprint 3: 支持未识别音频的展示与手动重试 ASR

import SwiftUI

/// 历史记录视图
struct HistoryView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    /// 历史记录管理器
    private let historyManager = HistoryManager.shared
    
    /// 搜索关键词
    @State private var searchText: String = ""
    
    /// 是否显示清空确认
    @State private var showClearConfirmation: Bool = false
    
    /// 复制成功提示
    @State private var showCopyToast: Bool = false
    
    /// Sprint 3: 当前正在重试识别的记录 ID
    @State private var retryingItemID: UUID?
    
    /// 过滤后的记录
    private var filteredItems: [HistoryItem] {
        historyManager.search(searchText)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if historyManager.items.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if !historyManager.items.isEmpty {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索历史记录")
            .confirmationDialog("确认清空", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("清空所有记录", role: .destructive) {
                    historyManager.clearAll()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作不可撤销")
            }
            .overlay {
                if showCopyToast {
                    VStack {
                        Spacer()
                        Text("已复制到剪贴板")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.green, in: Capsule())
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .padding(.bottom, 32)
                    .animation(.easeInOut, value: showCopyToast)
                }
            }
        }
    }
    
    // MARK: - 子视图
    
    /// 空状态
    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无历史记录", systemImage: "clock")
        } description: {
            Text("完成语音转写后，结果会自动保存在这里")
        }
    }
    
    /// 历史记录列表
    private var historyList: some View {
        List {
            ForEach(filteredItems) { item in
                HistoryRowView(
                    item: item,
                    isRetrying: retryingItemID == item.id,
                    onRetry: { retryTranscription(for: item) }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if !item.isUnrecognized {
                        copyToClipboard(item.text)
                    }
                }
            }
            .onDelete { offsets in
                // 需要映射到实际 items 的索引
                let itemsToDelete = offsets.map { filteredItems[$0] }
                for item in itemsToDelete {
                    historyManager.delete(item)
                }
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - 操作
    
    /// 复制文本到剪贴板
    private func copyToClipboard(_ text: String) {
        try? ClipboardOutput.copy(text)
        
        withAnimation {
            showCopyToast = true
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation {
                    showCopyToast = false
                }
            }
        }
    }
    
    /// Sprint 3: 手动重试 ASR 识别
    private func retryTranscription(for item: HistoryItem) {
        guard let audioPath = item.audioFilePath else { return }
        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else { return }
        
        retryingItemID = item.id
        
        Task {
            do {
                let text = try await ASRFactory.transcribe(
                    audioURL: audioURL,
                    config: .shared,
                    networkAvailable: NetworkMonitor().isConnected
                )
                let formatted = TextFormatter.format(text)
                historyManager.updateText(for: item.id, text: formatted, provider: "重试识别")
            } catch {
                // 重试也失败了，保持原样
                SharedLogger.error("重试 ASR 失败: \(error.localizedDescription)")
            }
            retryingItemID = nil
        }
    }
}

// MARK: - 行视图

/// 单条历史记录行
/// Sprint 3: 支持未识别音频的展示与"转文字"重试按钮
private struct HistoryRowView: View {
    let item: HistoryItem
    let isRetrying: Bool
    let onRetry: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.isUnrecognized {
                // 未识别音频：显示波形图标和重试按钮
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.orange)
                    Text("音频记录（未识别）")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                
                if isRetrying {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在识别...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        onRetry()
                    } label: {
                        Label("转文字", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue)
                }
            } else {
                // 正常文本记录
                Text(item.text)
                    .font(.body)
                    .lineLimit(3)
            }
            
            HStack {
                Text(item.provider)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
                
                Spacer()
                
                Text(item.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HistoryView()
}
