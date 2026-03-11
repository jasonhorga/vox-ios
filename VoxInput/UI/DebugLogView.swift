// DebugLogView.swift
// VoxInput
//
// Debug 日志查看页面（长按设置按钮触发）

import SwiftUI

struct DebugLogView: View {
    @State private var logText: String = "加载中..."
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("bottom")
                }
                .onAppear {
                    loadLogs()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .navigationTitle("Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新") {
                        loadLogs()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("清除日志", role: .destructive) {
                        SharedLogger.clearLogs()
                        logText = "（日志已清除）"
                    }
                }
            }
        }
    }

    private func loadLogs() {
        let logs = SharedLogger.readRecentLogs(lineCount: 200) ?? "（无日志）"
        // 只显示 WakeupFlow 相关行 + 最近50行
        let lines = logs.components(separatedBy: "\n")
        let wakeupLines = lines.filter { $0.contains("WakeupFlow") }
        let recentLines = lines.suffix(50)
        let combined = wakeupLines + ["", "--- 最近50行 ---", ""] + recentLines
        logText = combined.joined(separator: "\n")
    }
}
