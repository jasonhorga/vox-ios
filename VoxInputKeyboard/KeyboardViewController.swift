// KeyboardViewController.swift
// VoxInputKeyboard
//
// 键盘扩展入口：UIInputViewController 子类
// 管理键盘生命周期、权限检查、SwiftUI 视图嵌入、文字注入

import UIKit
import SwiftUI
import WebKit

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
            openApp: { [weak self] url in
                self?.openURLRobust(url) ?? false
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

    // MARK: - Robust URL Opening (iOS 17+ Keyboard Extension)

    /// 多策略打开 URL，确保键盘扩展在 iOS 17+ 下仍能可靠唤醒主 App
    /// 策略优先级：
    /// 1. NSExtensionContext 隐藏 API (openURL:completionHandler:)
    /// 2. UIResponder 链遍历找 UIApplication 调用 openURL:
    /// 3. WKWebView JavaScript 重定向（终极保底）
    private func openURLRobust(_ url: URL) -> Bool {
        // 策略 1: extensionContext 隐藏的 openURL:completionHandler:
        if openURLViaExtensionContext(url) {
            SharedLogger.info("[openURL] 策略1(extensionContext) 已触发: \(url.absoluteString)")
            return true
        }

        // 策略 2: UIResponder 链遍历
        if openURLViaResponderChain(url) {
            SharedLogger.info("[openURL] 策略2(responderChain) 已触发: \(url.absoluteString)")
            return true
        }

        // 策略 3: WKWebView JavaScript 重定向
        SharedLogger.info("[openURL] 策略1&2均失败，启用策略3(WKWebView): \(url.absoluteString)")
        openURLViaWebView(url)
        // WKWebView 异步执行，假定成功
        return true
    }

    /// 策略 1: 利用 NSExtensionContext 的隐藏 ObjC 方法 openURL:completionHandler:
    /// 这是 iOS 键盘扩展中最可靠的跳转方式
    private func openURLViaExtensionContext(_ url: URL) -> Bool {
        guard let context = extensionContext else {
            SharedLogger.error("[openURL] extensionContext 为 nil")
            return false
        }

        let selector = Selector(("openURL:completionHandler:"))
        guard context.responds(to: selector) else {
            SharedLogger.error("[openURL] extensionContext 不响应 openURL:completionHandler:")
            return false
        }

        // 使用 NSObject 的 perform 方法调用隐藏 API
        // openURL:(NSURL *)url completionHandler:(void (^)(BOOL))completionHandler
        context.perform(selector, with: url, with: nil)
        return true
    }

    /// 策略 2: 遍历 UIResponder 链找到 UIApplication 并调用 openURL:
    private func openURLViaResponderChain(_ url: URL) -> Bool {
        let selector = Selector(("openURL:"))

        var responder: UIResponder? = self
        while let current = responder {
            // 检查是否为 UIApplication 实例（避免在中间 responder 上误触发）
            if let application = current as? UIApplication ?? (NSStringFromClass(type(of: current)).contains("UIApplication") ? current : nil) {
                if application.responds(to: selector) {
                    application.perform(selector, with: url)
                    return true
                }
            }
            responder = current.next
        }

        SharedLogger.error("[openURL] responder chain 未找到 UIApplication")
        return false
    }

    /// 策略 3: 通过隐形 WKWebView 加载自定义 URL scheme
    /// 这是终极保底方案——WKWebView 直接 loadRequest 自定义 scheme
    private func openURLViaWebView(_ url: URL) {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 0.1, height: 0.1))
        webView.alpha = 0
        webView.isUserInteractionEnabled = false
        view.addSubview(webView)

        // 直接加载自定义 scheme URL，WKWebView 会触发系统 URL 处理
        webView.load(URLRequest(url: url))

        // 延迟移除 webView，给系统足够时间处理 URL scheme
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            webView.stopLoading()
            webView.removeFromSuperview()
        }
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
