// FullAccessGuideView.swift
// VoxInputKeyboard
//
// Full Access（Open Access）未开启时的引导 UI

import SwiftUI

/// Full Access 引导视图
/// 当用户未在系统设置中开启 "允许完全访问" 时显示
struct FullAccessGuideView: View {
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            
            Text("需要开启「完全访问」")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            
            Text("请前往系统设置开启完全访问权限，以使用语音输入功能")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            HStack(spacing: 4) {
                Text("设置")
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                Text("通用")
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                Text("键盘")
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                Text("Vox Input")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.blue)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
