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

    /// beta.46: 通过 UIResponder chain 打开 URL（双层策略）
    ///
    /// 策略 1: 遍历 UIResponder chain，用 open(_:options:completionHandler:) 新方法
    ///         此方法在 iOS 17/18 中未被扩展沙盒封堵（openURL: 旧方法在 iOS 18 中被封）
    /// 策略 2: 回退到 openURL:（旧方法，iOS 17 可用）
    /// 策略 3: extensionContext fallback
    ///
    /// 与旧版代码的关键区别：
    /// - 旧版直接用 NSClassFromString("UIApplication") 拿 class → sharedApplication 拿 singleton → openURL:
    /// - 新版通过 UIResponder chain 遍历找到 UIApplication 实例，更自然的 UIKit 调用路径
    /// - 优先使用 open:options:completionHandler: 新 selector
    private func openURLViaResponderChain(_ url: URL) -> Bool {
        // 诊断日志：打印 responder chain 帮助排查
        logResponderChain()
        
        // 策略 1: UIResponder chain + openURL:options:completionHandler:（iOS 17+ 推荐）
        // Swift:  UIApplication.open(_ url: URL, options: [...], completionHandler: ...)
        // ObjC:   -[UIApplication openURL:options:completionHandler:]
        // 需要用 IMP cast 来调用 3 参数 ObjC 方法（perform 最多支持 2 个参数）
        let newSelector = NSSelectorFromString("openURL:options:completionHandler:")
        
        var responder: UIResponder? = self as UIResponder
        while let r = responder {
            if r.responds(to: newSelector) {
                // 使用 method(for:) + unsafeBitCast 调用 3 参数方法
                // ObjC 签名: -(void)openURL:(NSURL*)url options:(NSDictionary*)opts completionHandler:(void(^)(BOOL))cb
                typealias OpenURLIMP = @convention(c) (AnyObject, Selector, Any, Any, Any?) -> Void
                let imp = unsafeBitCast(r.method(for: newSelector), to: OpenURLIMP.self)
                imp(r, newSelector, url as Any, [:] as NSDictionary, nil)
                SharedLogger.info("[openURL] ✅ beta.46 策略1成功: UIResponder chain → \(type(of: r)).openURL:options:completionHandler:")
                return true
            }
            responder = r.next
        }
        SharedLogger.info("[openURL] 策略1 未找到 responder，尝试策略2...")
        
        // 策略 2: UIResponder chain + openURL:（旧方法，iOS 17 仍可用）
        let oldSelector = NSSelectorFromString("openURL:")
        responder = self as UIResponder
        while let r = responder {
            if r.responds(to: oldSelector) {
                r.perform(oldSelector, with: url)
                SharedLogger.info("[openURL] ✅ beta.46 策略2成功: UIResponder chain → \(type(of: r)).openURL:")
                return true
            }
            responder = r.next
        }
        SharedLogger.info("[openURL] 策略2 未找到 responder，尝试策略3...")
        
        // 策略 3: extensionContext fallback（不太可能在键盘扩展中有效，但留作最后手段）
        if let context = extensionContext {
            let ctxSelector = NSSelectorFromString("openURL:completionHandler:")
            if context.responds(to: ctxSelector) {
                context.perform(ctxSelector, with: url, with: nil)
                SharedLogger.info("[openURL] ✅ beta.46 策略3成功: extensionContext.openURL:")
                return true
            }
        }
        
        SharedLogger.error("[openURL] ❌ beta.46: 所有策略均失败 url=\(url.absoluteString)")
        return false
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
