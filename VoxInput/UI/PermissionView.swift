// PermissionView.swift
// VoxInput
//
// 麦克风权限申请与引导视图

import SwiftUI
import AVFoundation

/// 权限状态
enum PermissionState {
    /// 尚未请求
    case notDetermined
    /// 已授权
    case granted
    /// 已拒绝
    case denied
}

/// 麦克风权限引导视图
/// 首次使用时引导用户授权麦克风，拒绝后引导到系统设置
struct PermissionView: View {
    
    /// 权限状态
    @State private var permissionState: PermissionState = .notDetermined
    
    /// 授权完成回调
    var onPermissionGranted: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // 图标
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.red)
            
            // 标题
            Text("需要麦克风权限")
                .font(.title2)
                .fontWeight(.bold)
            
            // 说明文字
            Text("Vox Input 需要使用麦克风来录制语音，\n将语音转换为文字并复制到剪贴板。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // 操作按钮
            switch permissionState {
            case .notDetermined:
                // 请求权限按钮
                Button {
                    requestPermission()
                } label: {
                    Label("授权麦克风", systemImage: "mic.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.red, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 48)
                
            case .granted:
                // 已授权提示
                Label("已授权", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                
            case .denied:
                // 拒绝后引导到设置
                VStack(spacing: 16) {
                    Text("麦克风权限已被拒绝")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    
                    Button {
                        openSettings()
                    } label: {
                        Label("打开系统设置", systemImage: "gear")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 48)
                    
                    Text("请在设置中找到 Vox Input，开启麦克风权限")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            Spacer()
        }
        .onAppear {
            checkPermission()
        }
    }
    
    // MARK: - 权限操作
    
    /// 检查当前权限状态
    private func checkPermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined:
            permissionState = .notDetermined
        case .granted:
            permissionState = .granted
            onPermissionGranted()
        case .denied:
            permissionState = .denied
        @unknown default:
            permissionState = .notDetermined
        }
    }
    
    /// 请求麦克风权限
    private func requestPermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            Task { @MainActor in
                if granted {
                    permissionState = .granted
                    onPermissionGranted()
                } else {
                    permissionState = .denied
                }
            }
        }
    }
    
    /// 打开系统设置
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    PermissionView {
        print("权限已授权")
    }
}
