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

    /// 临时 WKWebView（策略3保底用，延迟清理）
    private var pendingWebView: WKWebView?

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
    ///
    /// beta.37 重写：
    /// - 策略 1: extensionContext 的 openURL:completionHandler: (带 completion 回调检测)
    /// - 策略 2: UIApplication.shared 通过 ObjC runtime 获取并调用 openURL:
    /// - 策略 3: WKWebView JavaScript 重定向（终极保底）
    /// - 策略 4: 标记 URL 打开失败，让 UI 层显示可点击的 deeplink
    ///
    /// 关键改进：
    /// - 所有策略在主线程 + 用户交互上下文中调用
    /// - 策略 1 使用 NSInvocation 正确传递 completion block
    /// - 策略失败时立即 fallback 而不是静默吞掉
    private func openURLRobust(_ url: URL) -> Bool {
        SharedLogger.info("[openURL] 开始多策略打开: \(url.absoluteString)")

        // 策略 1: extensionContext 的 openURL:completionHandler:
        // 使用 completion handler 检测是否真正成功
        if openURLViaExtensionContext(url) {
            SharedLogger.info("[openURL] 策略1(extensionContext) 已触发: \(url.absoluteString)")
            return true
        }

        // 策略 2: 通过 ObjC runtime 获取 UIApplication.shared 并调 openURL:
        if openURLViaSharedApplication(url) {
            SharedLogger.info("[openURL] 策略2(UIApplication.shared) 已触发: \(url.absoluteString)")
            return true
        }

        // 策略 3: WKWebView 加载 custom scheme URL
        SharedLogger.info("[openURL] 策略1&2均失败，启用策略3(WKWebView): \(url.absoluteString)")
        openURLViaWebView(url)
        
        // 策略 3 是异步的，延迟检查是否成功
        // 同时标记需要显示手动 fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            // 如果 1.5 秒后键盘仍处于 wakeup 等待状态，说明所有策略都失败了
            // 让 state 层切换到手动跳转 UI
            self?.keyboardState.markOpenURLFailed()
        }
        
        return true
    }

    /// 策略 1: 利用 NSExtensionContext 的 openURL:completionHandler:
    ///
    /// beta.37 改进：
    /// - 通过 completion handler 检测实际结果
    /// - 确保在主线程调用
    /// - 详细日志记录
    private func openURLViaExtensionContext(_ url: URL) -> Bool {
        guard let context = extensionContext else {
            SharedLogger.error("[openURL] extensionContext 为 nil — 键盘可能正在被释放")
            return false
        }

        let selector = NSSelectorFromString("openURL:completionHandler:")
        guard context.responds(to: selector) else {
            SharedLogger.error("[openURL] extensionContext 不响应 openURL:completionHandler: (iOS版本不支持?)")
            return false
        }

        // beta.37: 使用 completion handler 检测结果
        // 注意：虽然是"隐藏 API"，但我们传入真正的 completion block 来检测是否成功
        let completionBlock: @convention(block) (Bool) -> Void = { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    SharedLogger.info("[openURL] 策略1 completion: 成功")
                } else {
                    SharedLogger.error("[openURL] 策略1 completion: 失败（系统拒绝或 URL 无效）")
                    // 触发手动 fallback
                    self?.keyboardState.markOpenURLFailed()
                }
            }
        }

        // 使用 perform(_:with:with:) 传递 URL 和 completion block
        // completionBlock 作为 ObjC block object 传递
        let blockAsObject = unsafeBitCast(completionBlock, to: AnyObject.self)
        context.perform(selector, with: url, with: blockAsObject)
        return true
    }

    /// 策略 2: 通过 ObjC runtime 获取 UIApplication.shared 并调用 openURL:
    ///
    /// 在键盘扩展中，UIApplication 不能直接通过 Swift 访问，
    /// 但 ObjC runtime 可以动态获取。此方法在 iOS 17+ 部分设备上有效。
    /// 策略 2: 遍历 UIResponder 链找到能处理 openURL: 的对象
    ///
    /// beta.37 改进：不再假设能找到 UIApplication（键盘扩展中不存在），
    /// 而是遍历所有 responder 找任何能响应 openURL: 的对象。
    /// 在某些 iOS 版本中，UIInputWindowController 或宿主进程的某个 responder
    /// 可能响应 openURL:。
    private func openURLViaSharedApplication(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")

        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                // 检查是否为我们自己（UIInputViewController 本身不处理 openURL）
                if !(current is KeyboardViewController) {
                    current.perform(selector, with: url)
                    SharedLogger.info("[openURL] 策略2: 通过 responder chain 中的 \(type(of: current)) 调用 openURL:")
                    return true
                }
            }
            responder = current.next
        }

        SharedLogger.error("[openURL] 策略2: responder chain 中无对象响应 openURL:")
        return false
    }

    /// 策略 3: 通过隐形 WKWebView 加载自定义 URL scheme
    /// 这是终极保底方案——WKWebView 直接 loadRequest 自定义 scheme
    ///
    /// beta.37 改进：
    /// - 使用 JavaScript window.location 重定向而非直接 loadRequest
    /// - 添加 about:blank 基础页面先加载，再 JS 跳转
    private func openURLViaWebView(_ url: URL) {
        // 清理之前的 webView
        pendingWebView?.stopLoading()
        pendingWebView?.removeFromSuperview()
        
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 0.1, height: 0.1), configuration: config)
        webView.alpha = 0
        webView.isUserInteractionEnabled = false
        view.addSubview(webView)
        pendingWebView = webView

        // 方法 A: 直接加载 custom scheme URL
        webView.load(URLRequest(url: url))
        
        // 方法 B: 0.5秒后用 JavaScript 再试一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak webView] in
            let js = "window.location.href = '\(url.absoluteString)';"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        // 延迟清理 webView
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.pendingWebView?.stopLoading()
            self?.pendingWebView?.removeFromSuperview()
            self?.pendingWebView = nil
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
