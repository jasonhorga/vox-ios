// GlobeKeyView.swift
// VoxInputKeyboard
//
// 地球键（切换输入法按钮）
// 遵循 Apple HIG：当 needsInputModeSwitchKey 为 true 时显示

import SwiftUI

/// 地球键视图
/// 用于切换到下一个输入法，键盘扩展必须提供此功能
struct GlobeKeyView: View {
    
    /// 切换输入法的回调（由 KeyboardViewController 提供）
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "globe")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换输入法")
        .accessibilityHint("切换到下一个键盘")
    }
}
