// KeyboardViewController.swift
// VoxInputKeyboard
//
// 键盘扩展入口：UIInputViewController 子类
// 管理键盘生命周期、权限检查、SwiftUI 视图嵌入、文字注入

import UIKit
import SwiftUI

/// 键盘扩展主控制器
/// 职责：
/// 1. 嵌入 SwiftUI KeyboardView
/// 2. 管理 needsInputModeSwitchKey 地球键
/// 3. 检查 hasFullAccess
/// 4. 通过 textDocumentProxy.insertText() 注入文字
/// 5. 检测 secureTextEntry 密码框场景
class KeyboardViewController: UIInputViewController {

    // MARK: - 状态

    /// 键盘状态管理器
    private let keyboardState = KeyboardState()

    /// SwiftUI 宿主控制器
    private var hostingController: UIHostingController<AnyView>?

    /// 高度约束（用于动态调整键盘高度）
    private var heightConstraint: NSLayoutConstraint?

    /// 根据设备屏幕计算的自适应键盘高度
    private var adaptiveKeyboardHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        let bottomInset = view.safeAreaInsets.bottom
        return Constants.Keyboard.adaptiveHeight(screenHeight: screenHeight, bottomSafeArea: bottomInset)
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboardView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkEnvironment()
        Task { @MainActor in
            keyboardState.activate()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 再次检查，确保状态最新
        checkEnvironment()

        // 安全区域在 viewDidAppear 后才准确，刷新键盘高度
        updateKeyboardHeight()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Task { @MainActor in
            keyboardState.deactivate()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardHeight()
    }

    /// 根据当前设备屏幕和安全区域刷新键盘高度
    private func updateKeyboardHeight() {
        let newHeight = adaptiveKeyboardHeight
        if heightConstraint?.constant != newHeight {
            heightConstraint?.constant = newHeight
        }
    }

    // MARK: - 输入上下文变化

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // 检测密码输入框
        let isSecure = textDocumentProxy.isSecureTextEntry ?? false
        Task { @MainActor in
            keyboardState.updateSecureInputState(isSecure)
        }
    }

    // MARK: - 视图设置

    /// 设置 SwiftUI 键盘视图
    private func setupKeyboardView() {
        keyboardState.bindHandlers(
            openApp: { [weak self] url in
                self?.openURLViaResponderChain(url) ?? false
            },
            insertText: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            }
        )

        let state = keyboardState
        let needsGlobe = needsInputModeSwitchKey

        // 创建键盘视图，根据权限状态显示不同内容
        let keyboardView = KeyboardContentView(
            state: state,
            needsGlobeKey: needsGlobe,
            onGlobeKeyTap: { [weak self] in
                self?.advanceToNextInputMode()
            },
            onRecordStart: { [weak self] in
                self?.handleRecordStart()
            },
            onRecordStop: { [weak self] in
                self?.handleRecordStop()
            }
        )

        let hostVC = UIHostingController(rootView: AnyView(keyboardView))
        hostVC.view.translatesAutoresizingMaskIntoConstraints = false
        hostVC.view.backgroundColor = .clear

        // 移除 UIHostingController 的安全区域额外间距
        hostVC.additionalSafeAreaInsets = .zero

        addChild(hostVC)
        view.addSubview(hostVC.view)
        hostVC.didMove(toParent: self)

        let height = hostVC.view.heightAnchor.constraint(equalToConstant: adaptiveKeyboardHeight)

        NSLayoutConstraint.activate([
            hostVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height
        ])

        self.heightConstraint = height
        self.hostingController = hostVC
    }

    // MARK: - 环境检查

    /// 检查权限环境并更新状态
    private func checkEnvironment() {
        let systemFullAccess = self.hasFullAccess
        Task { @MainActor in
            // 检查权限环境（Full Access + 麦克风）
            keyboardState.checkEnvironment(systemHasFullAccess: systemFullAccess)

            // 检查密码输入框
            keyboardState.updateSecureInputState(textDocumentProxy.isSecureTextEntry ?? false)
        }
    }

    // MARK: - 主 App 跳转录音

    /// 处理录音开始（改为拉起主 App）
    private func handleRecordStart() {
        Task { @MainActor in
            keyboardState.inputContextHint = textDocumentProxy.documentContextBeforeInput
            _ = keyboardState.startRecording()
        }
    }

    /// 处理录音停止（发送 stop 指令给守护进程）
    private func handleRecordStop() {
        Task { @MainActor in
            keyboardState.stopRecording()
        }
    }

    /// 使用 UIResponder 链尝试打开 URL（键盘扩展不可直接用 UIApplication.shared.open）
    private func openURLViaResponderChain(_ url: URL) -> Bool {
        let selector = Selector(("openURL:"))

        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }

        SharedLogger.error("无法通过 responder chain 打开 URL: \(url.absoluteString)")
        return false
    }

}

// MARK: - 键盘内容视图（根据权限状态切换）

/// 键盘内容包装视图
/// 仅在 Full Access 未开启时显示引导；其余场景都允许进入主流程
private struct KeyboardContentView: View {

    let state: KeyboardState
    let needsGlobeKey: Bool
    let onGlobeKeyTap: () -> Void
    let onRecordStart: () -> Void
    let onRecordStop: () -> Void

    var body: some View {
        Group {
            if !state.hasFullAccess {
                // Full Access 未开启
                VStack {
                    FullAccessGuideView()
                    if needsGlobeKey {
                        HStack {
                            GlobeKeyView(action: onGlobeKeyTap)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                    }
                }
            } else {
                // 正常键盘 UI
                KeyboardView(
                    state: state,
                    needsGlobeKey: needsGlobeKey,
                    onGlobeKeyTap: onGlobeKeyTap,
                    onRecordStart: onRecordStart,
                    onRecordStop: onRecordStop
                )
            }
        }
        .frame(maxHeight: .infinity)
    }
}
