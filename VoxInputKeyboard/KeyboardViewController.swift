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
/// 3. 检查 hasFullAccess 和麦克风权限
/// 4. 通过 textDocumentProxy.insertText() 注入文字
/// 5. 检测 secureTextEntry 密码框场景
class KeyboardViewController: UIInputViewController {
    
    // MARK: - 状态
    
    /// 键盘状态管理器
    private let keyboardState = KeyboardState()
    
    /// SwiftUI 宿主控制器
    private var hostingController: UIHostingController<AnyView>?
    
    // MARK: - 生命周期
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboardView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkEnvironment()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 再次检查，确保状态最新
        checkEnvironment()
    }
    
    // MARK: - 输入上下文变化
    
    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
    }
    
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // 检测密码输入框
        let isSecure = textDocumentProxy.isSecureTextEntry
        Task { @MainActor in
            keyboardState.updateSecureInputState(isSecure)
        }
    }
    
    // MARK: - 视图设置
    
    /// 设置 SwiftUI 键盘视图
    private func setupKeyboardView() {
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
        
        NSLayoutConstraint.activate([
            hostVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // 设置键盘高度
            hostVC.view.heightAnchor.constraint(equalToConstant: Constants.Keyboard.defaultHeight)
        ])
        
        self.hostingController = hostVC
    }
    
    // MARK: - 环境检查
    
    /// 检查权限环境并更新状态
    private func checkEnvironment() {
        Task { @MainActor in
            // 更新 Full Access 状态（使用系统 API）
            keyboardState.hasFullAccess = hasFullAccess
            
            // 检查麦克风权限
            keyboardState.checkEnvironment()
            
            // 检查密码输入框
            keyboardState.updateSecureInputState(textDocumentProxy.isSecureTextEntry)
        }
    }
    
    // MARK: - 录音控制
    
    /// 处理录音开始（按下麦克风按钮）
    private func handleRecordStart() {
        Task { @MainActor in
            keyboardState.startRecording()
        }
    }
    
    /// 处理录音停止（松开麦克风按钮）
    private func handleRecordStop() {
        Task { @MainActor in
            let text = await keyboardState.stopRecording()
            
            // 将文字注入到当前输入框
            if let text, !text.isEmpty {
                self.textDocumentProxy.insertText(text)
            }
        }
    }
}

// MARK: - 键盘内容视图（根据权限状态切换）

/// 键盘内容包装视图
/// 根据 Full Access 和麦克风权限状态显示不同的 UI
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
            } else if !state.hasMicPermission {
                // 麦克风权限未授权
                VStack {
                    MicPermissionGuideView()
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
        .frame(height: Constants.Keyboard.defaultHeight)
    }
}
