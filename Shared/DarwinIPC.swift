// DarwinIPC.swift
// Shared
//
// Darwin Notification Center 封装（主 App 与键盘扩展可跨进程广播）

import Foundation

private func darwinNotificationCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let observer else { return }
    let box = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
    box.handleNotification()
}

enum AppGroupDarwinNotification: String {
    /// 键盘 -> 主 App：请求立即唤醒并启动录音
    case wakeUpAndRecord = "com.jasonhorga.vox.ipc.wake_up_and_record"
    /// 主 App -> 键盘：状态/结果更新
    case daemonStateDidChange = "com.jasonhorga.vox.ipc.state_did_change"

    fileprivate var cfName: CFNotificationName {
        CFNotificationName(rawValue: rawValue as CFString)
    }

    func post() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, cfName, nil, nil, true)
    }
}

final class DarwinNotificationObserver {

    private let name: AppGroupDarwinNotification
    private let handler: () -> Void
    private var isStarted = false

    init(name: AppGroupDarwinNotification, handler: @escaping () -> Void) {
        self.name = name
        self.handler = handler
    }

    func start() {
        guard !isStarted else { return }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            pointer,
            darwinNotificationCallback,
            name.cfName.rawValue,
            nil,
            .deliverImmediately
        )
        isStarted = true
    }

    func stop() {
        guard isStarted else { return }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, pointer, name.cfName, nil)
        isStarted = false
    }

    fileprivate func handleNotification() {
        handler()
    }

    deinit {
        stop()
    }
}
