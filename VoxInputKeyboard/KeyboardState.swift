// KeyboardState.swift
// VoxInputKeyboard
//
// 键盘扩展状态机：Remote Control + App Group IPC

import Foundation
import Observation
import AVFoundation

/// 键盘扩展状态
enum KeyboardPhase: Equatable {
    case idle
    case recording
    case processing
    case done(String)
    case error(String)
}

@Observable
@MainActor
final class KeyboardState {

    // MARK: - Observable State

    private(set) var phase: KeyboardPhase = .idle
    private(set) var statusMessage: String = ""

    /// 当前音频电平（键盘不再本地录音，保留占位）
    private(set) var currentLevel: Float = 0.0
    /// 电平历史（保留占位，兼容旧 UI）
    private(set) var levelHistory: [Float] = []

    private(set) var hasFullAccess: Bool = false
    private(set) var hasMicPermission: Bool = false
    private(set) var isSecureInput: Bool = false

    var inputContextHint: String?

    /// 当前 IPC 守护进程状态字符串
    private(set) var daemonState: String = "dead"

    /// 最近一次 daemon 错误
    private(set) var daemonErrorMessage: String?

    // MARK: - IPC Internals

    private let defaults = AppGroup.sharedDefaults
    let config = SharedConfigStore.shared

    private var ipcTimer: Timer?
    private var lastResultID: Int = 0
    private var lastHeartbeatAt: TimeInterval = 0

    private var openAppHandler: ((URL) -> Bool)?
    private var insertTextHandler: ((String) -> Void)?

    // MARK: - Wiring

    /// 由 ViewController 注入桥接能力
    func bindHandlers(openApp: @escaping (URL) -> Bool, insertText: @escaping (String) -> Void) {
        self.openAppHandler = openApp
        self.insertTextHandler = insertText
    }

    // MARK: - Lifecycle

    func activate() {
        config.reload()
        checkEnvironment()
        startIPCMonitoringIfNeeded()
        updateFromIPC()
    }

    func deactivate() {
        ipcTimer?.invalidate()
        ipcTimer = nil
    }

    // MARK: - Environment

    func checkEnvironment(systemHasFullAccess: Bool? = nil) {
        if let value = systemHasFullAccess {
            hasFullAccess = value
        } else {
            hasFullAccess = checkFullAccess()
        }

        hasMicPermission = checkMicPermission()
        SharedLogger.info("环境检查: fullAccess=\(hasFullAccess), mic=\(hasMicPermission)")
    }

    func updateSecureInputState(_ isSecure: Bool) {
        isSecureInput = isSecure
        if isSecure {
            statusMessage = "密码输入框，语音输入不可用"
        }
    }

    // MARK: - Recording (Remote Control)

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

        // 守护进程睡眠或心跳超时 -> 极速闪跳唤醒
        if shouldWakeMainApp() {
            phase = .processing
            statusMessage = "正在唤醒 Vox Input..."
            let opened = openMainAppForWakeup()
            if !opened {
                phase = .error("无法打开 Vox Input")
                statusMessage = "打开 Vox Input 失败，请手动打开应用"
                scheduleReset()
                return false
            }
        }

        sendCommand(.start)
        phase = .recording
        statusMessage = "录音中..."
        return true
    }

    func stopRecording() {
        guard phase == .recording else { return }
        sendCommand(.stop)
        phase = .processing
        statusMessage = "识别中..."
    }

    func cancelRecording() {
        sendCommand(.cancel)
        phase = .idle
        statusMessage = ""
        currentLevel = 0
    }

    // MARK: - IPC Polling

    private func startIPCMonitoringIfNeeded() {
        guard ipcTimer == nil else { return }

        ipcTimer = Timer.scheduledTimer(withTimeInterval: Constants.Keyboard.ipcPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFromIPC()
            }
        }
    }

    private func updateFromIPC() {
        let state = defaults.string(forKey: AppGroup.ipcStateKey) ?? "dead"
        daemonState = state
        daemonErrorMessage = defaults.string(forKey: AppGroup.ipcErrorKey)
        lastHeartbeatAt = defaults.double(forKey: AppGroup.ipcHeartbeatKey)

        if let inserted = consumeResultIfNeeded() {
            insertTextHandler?(inserted)
            phase = .done("已输入：\(inserted)")
            statusMessage = "已注入文本"
            scheduleReset()
            return
        }

        syncPhaseWithDaemonState(state)
    }

    private func syncPhaseWithDaemonState(_ state: String) {
        switch state {
        case "recording":
            phase = .recording
            statusMessage = "录音中..."
        case "processing":
            phase = .processing
            statusMessage = "识别中..."
        case "error":
            let message = daemonErrorMessage ?? "识别失败"
            phase = .error(message)
            statusMessage = message
            scheduleReset()
        case "idle":
            if case .recording = phase {
                phase = .processing
                statusMessage = "识别中..."
            }
        case "sleeping", "dead":
            if case .recording = phase {
                phase = .error("守护进程已休眠")
                statusMessage = "守护进程已休眠，请重试"
                scheduleReset()
            }
        default:
            break
        }
    }

    private func consumeResultIfNeeded() -> String? {
        let resultID = defaults.integer(forKey: AppGroup.ipcResultIDKey)
        guard resultID > 0, resultID != lastResultID else { return nil }

        lastResultID = resultID
        guard let text = defaults.string(forKey: AppGroup.ipcResultKey), !text.isEmpty else {
            return nil
        }

        defaults.removeObject(forKey: AppGroup.ipcResultKey)
        defaults.synchronize()
        return text
    }

    // MARK: - Command / Wakeup

    private enum IPCCommand: String {
        case start
        case stop
        case cancel
    }

    private func sendCommand(_ command: IPCCommand) {
        let nextID = defaults.integer(forKey: AppGroup.ipcCommandIDKey) + 1
        defaults.set(command.rawValue, forKey: AppGroup.ipcCommandKey)
        defaults.set(nextID, forKey: AppGroup.ipcCommandIDKey)
        defaults.set(Date().timeIntervalSince1970, forKey: AppGroup.ipcCommandAtKey)
        defaults.synchronize()
    }

    private func shouldWakeMainApp() -> Bool {
        if daemonState == "sleeping" || daemonState == "dead" || daemonState.isEmpty {
            return true
        }

        guard lastHeartbeatAt > 0 else { return true }
        let delta = Date().timeIntervalSince1970 - lastHeartbeatAt
        return delta > Constants.Daemon.heartbeatTimeout
    }

    private func openMainAppForWakeup() -> Bool {
        guard let handler = openAppHandler,
              let url = URL(string: "voxinput://record?source=keyboard&mode=wakeup")
        else {
            return false
        }
        return handler(url)
    }

    // MARK: - Permission checks

    private func checkFullAccess() -> Bool {
        let defaults = AppGroup.sharedDefaults
        defaults.set(true, forKey: "vox.keyboard.accessCheck")
        return defaults.synchronize()
    }

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

    // MARK: - Utils

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
