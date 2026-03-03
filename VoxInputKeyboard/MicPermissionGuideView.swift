// MicPermissionGuideView.swift
// VoxInputKeyboard
//
// 麦克风权限未授权时的引导 UI
// 键盘扩展无法弹出系统权限对话框，需引导用户在主 App 中授权

import SwiftUI

/// 麦克风权限引导视图
/// 键盘扩展中无法请求麦克风权限，需要引导用户打开主 App 完成授权
struct MicPermissionGuideView: View {
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.system(size: 36))
                .foregroundStyle(.red)
            
            Text("需要麦克风权限")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            
            Text("请打开 Vox Input 主应用，授权麦克风权限后即可使用语音输入")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            HStack(spacing: 4) {
                Image(systemName: "app.badge")
                    .font(.system(size: 12))
                Text("打开 Vox Input App 完成授权")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.blue)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
