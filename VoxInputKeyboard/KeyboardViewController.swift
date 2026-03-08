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
        if hostingController == nil {
            setupKeyboardView()
        }
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
        cleanupHostingController()
    }

    deinit {
        cleanupHostingController()
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

    private func cleanupHostingController() {
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil
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
            openApp: { [weak self] url, method in
                self?.openApp(url: url, method: method) ?? false
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
            },
            onWakeupApp: { [weak self] in
                self?.handleWakeupApp()
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
    
    /// 处理唤醒主 App（用于特定错误场景）
    private func handleWakeupApp() {
        Task { @MainActor in
            keyboardState.wakeupAppFromError()
        }
    }

    // MARK: - URL Opening

    /// Debug 实验室：按方法标识选择 URL 跳转策略
    /// - Parameters:
    ///   - url: 目标 URL
    ///   - method: "A"=Context, "B"=Responder, "C"=SharedApp
    private func openApp(url: URL, method: String) -> Bool {
        switch method.uppercased() {
        case "A":
            return openURLViaContext(url)
        case "C":
            return openURLViaSharedApplication(url)
        case "B":
            fallthrough
        default:
            return openURLViaResponder(url)
        }
    }

    /// 方法 A: 仅使用 extensionContext.openURL:completionHandler:
    private func openURLViaContext(_ url: URL) -> Bool {
        guard let context = extensionContext else { return false }
        let selector = NSSelectorFromString("openURL:completionHandler:")
        guard context.responds(to: selector) else { return false }
        context.perform(selector, with: url, with: nil)
        SharedLogger.info("[openURL] 方法A成功: extensionContext")
        return true
    }

    /// 方法 B: 仅遍历 UIResponder 调用 openURL:
    private func openURLViaResponder(_ url: URL) -> Bool {
        logResponderChain()
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self as UIResponder
        while let current = responder {
            if current !== self, current.responds(to: selector) {
                current.perform(selector, with: url)
                SharedLogger.info("[openURL] 方法B成功: UIResponder")
                return true
            }
            responder = current.next
        }
        SharedLogger.error("[openURL] 方法B失败: 未找到可用 responder")
        return false
    }

    /// 方法 C: 仅使用 UIApplication.shared perform(openURL:)
    private func openURLViaSharedApplication(_ url: URL) -> Bool {
        guard let appClass = NSClassFromString("UIApplication") as? NSObject.Type else {
            SharedLogger.error("[openURL] 方法C失败: UIApplication class 不可用")
            return false
        }
        let sharedSelector = NSSelectorFromString("sharedApplication")
        guard appClass.responds(to: sharedSelector),
              let app = appClass.perform(sharedSelector)?.takeUnretainedValue() as? NSObject
        else {
            SharedLogger.error("[openURL] 方法C失败: sharedApplication 不可用")
            return false
        }

        let openSelector = NSSelectorFromString("openURL:")
        guard app.responds(to: openSelector) else {
            SharedLogger.error("[openURL] 方法C失败: openURL selector 不可用")
            return false
        }

        app.perform(openSelector, with: url)
        SharedLogger.info("[openURL] 方法C成功: UIApplication.shared")
        return true
    }

    /// 诊断：打印完整的 UIResponder chain（帮助排查跳转失败）
    private func logResponderChain() {
        var chain: [String] = []
        var r: UIResponder? = self
        while let current = r {
            chain.append(String(describing: type(of: current)))
            r = current.next
        }
        SharedLogger.info("[openURL] Responder chain: \(chain.joined(separator: " → "))")
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
    let onWakeupApp: () -> Void
    
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
                    onRecordStop: onRecordStop,
                    onWakeupApp: onWakeupApp
                )
            }
        }
        .frame(maxHeight: .infinity)
    }
}
