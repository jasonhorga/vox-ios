// KeyboardState.swift
// VoxInputKeyboard
//
// 键盘扩展状态机：改为「跳转主 App 录音」模式

import Foundation
import Observation
import AVFoundation

/// 键盘扩展状态
enum KeyboardPhase: Equatable {
    /// 空闲，等待用户操作
    case idle
    /// 正在录音（保留枚举值，兼容旧 UI）
    case recording
    /// 正在处理（当前用于「正在打开主 App」）
    case processing
    /// 操作完成
    case done(String)
    /// 发生错误
    case error(String)
}

/// 键盘扩展状态管理器
/// 录音能力已迁移到主 App，键盘仅负责：
/// 1) 权限/环境提示
/// 2) 拉起主 App
/// 3) 展示状态
@Observable
@MainActor
final class KeyboardState {

    // MARK: - 可观察状态

    /// 当前阶段
    private(set) var phase: KeyboardPhase = .idle

    /// 状态消息（显示在键盘 UI 上）
    private(set) var statusMessage: String = ""

    /// 当前音频电平（兼容旧 UI，占位）
    private(set) var currentLevel: Float = 0.0

    /// 电平历史（兼容旧 UI，占位）
    private(set) var levelHistory: [Float] = []

    /// 是否有 Full Access 权限
    private(set) var hasFullAccess: Bool = false

    /// 是否有麦克风权限（仅用于展示，不再阻断键盘侧流程）
    private(set) var hasMicPermission: Bool = false

    /// 是否在密码输入框中
    private(set) var isSecureInput: Bool = false

    /// 输入上下文提示（保留字段，供后续增强）
    var inputContextHint: String?

    // MARK: - 共享配置

    /// 共享配置（保留 reload）
    let config = SharedConfigStore.shared

    // MARK: - 状态更新

    /// 检查环境权限
    func checkEnvironment(systemHasFullAccess: Bool? = nil) {
        if let systemHasFullAccess {
            hasFullAccess = systemHasFullAccess
        } else {
            hasFullAccess = checkFullAccess()
        }

        // 键盘侧不再录音，该值仅用于 UI 诊断展示
        hasMicPermission = checkMicPermission()

        SharedLogger.info("环境检查: fullAccess=\(hasFullAccess), mic=\(hasMicPermission)")
    }

    /// 检测是否在密码输入框中
    func updateSecureInputState(_ isSecure: Bool) {
        isSecureInput = isSecure
        if isSecure {
            statusMessage = "密码输入框，语音输入不可用"
        }
    }

    // MARK: - 拉起主 App（替代键盘内录音）

    /// 开始流程：准备拉起主 App 录音
    /// - Returns: 是否通过前置校验
    @discardableResult
    func startRecording() -> Bool {
        config.reload()

        guard phase == .idle else { return false }

        guard !isSecureInput else {
            phase = .error("密码输入框不支持语音输入")
            statusMessage = "密码输入框不支持语音输入"
            scheduleReset()
            return false
        }

        guard hasFullAccess else {
            phase = .error("请先开启完全访问")
            statusMessage = "请在系统设置中开启“完全访问”"
            scheduleReset()
            return false
        }

        phase = .processing
        statusMessage = "正在打开 Vox Input..."
        SharedLogger.info("键盘侧开始主 App 跳转录音流程")
        return true
    }

    /// 完成主 App 拉起结果回传
    func finishOpenApp(opened: Bool) {
        if opened {
            phase = .done("请在 Vox Input 中完成录音")
            statusMessage = "已跳转主 App，请录音后返回"
        } else {
            phase = .error("无法打开 Vox Input")
            statusMessage = "打开 Vox Input 失败，请手动打开应用"
        }
        scheduleReset()
    }

    /// 键盘注入了主 App 回传文本后的状态更新
    func markPendingInputInserted(_ text: String) {
        phase = .done("已输入：\(text)")
        statusMessage = "已从 Vox Input 注入文本"
        scheduleReset()
    }

    /// 取消（重置）
    func cancelRecording() {
        phase = .idle
        statusMessage = ""
        currentLevel = 0.0
    }

    // MARK: - 权限检查

    /// 检查 Full Access（Open Access）权限
    private func checkFullAccess() -> Bool {
        let defaults = AppGroup.sharedDefaults
        defaults.set(true, forKey: "vox.keyboard.accessCheck")
        return defaults.synchronize()
    }

    /// 检查麦克风权限（仅用于诊断/展示）
    private func checkMicPermission() -> Bool {
        if #available(iOS 17.0, *) {
            let permission = AVAudioApplication.shared.recordPermission
            switch permission {
            case .granted:
                return true
            case .denied, .undetermined:
                return false
            @unknown default:
                return false
            }
        } else {
            let permission = AVAudioSession.sharedInstance().recordPermission
            switch permission {
            case .granted:
                return true
            case .denied, .undetermined:
                return false
            @unknown default:
                return false
            }
        }
    }

    // MARK: - 辅助方法

    /// 延迟重置状态到 idle
    private func scheduleReset() {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Constants.Keyboard.statusClearDelay * 1_000_000_000))
            if phase != .recording && phase != .processing {
                phase = .idle
                statusMessage = ""
            }
        }
    }
}
