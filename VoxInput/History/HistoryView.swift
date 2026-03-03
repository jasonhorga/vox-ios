// HistoryView.swift
// VoxInput
//
// 历史记录列表：搜索、点击复制、左滑删除、清空全部

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
                HistoryRowView(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        copyToClipboard(item.text)
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
}

// MARK: - 行视图

/// 单条历史记录行
private struct HistoryRowView: View {
    let item: HistoryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text)
                .font(.body)
                .lineLimit(3)
            
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
