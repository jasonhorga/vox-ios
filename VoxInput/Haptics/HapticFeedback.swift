// HapticFeedback.swift
// VoxInput
//
// 触觉反馈管理（4 种反馈类型）

import UIKit

/// 触觉反馈管理器
/// 提供录音开始、停止、成功、错误四种触觉反馈
final class HapticFeedback {
    
    // MARK: - 单例
    
    static let shared = HapticFeedback()
    
    // MARK: - 反馈生成器
    
    /// 冲击反馈（录音开始/停止）
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    /// 通知反馈（成功/错误）
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    // MARK: - 初始化
    
    private init() {
        // 预热反馈引擎，减少首次触发延迟
        prepareAll()
    }
    
    // MARK: - 公开方法
    
    /// 录音开始反馈：中等冲击
    func recordStart() {
        impactGenerator.impactOccurred(intensity: 0.8)
        prepareAll()
    }
    
    /// 录音停止反馈：轻度冲击
    func recordStop() {
        impactGenerator.impactOccurred(intensity: 0.5)
        prepareAll()
    }
    
    /// 处理成功反馈：成功通知
    func success() {
        notificationGenerator.notificationOccurred(.success)
        prepareAll()
    }
    
    /// 错误反馈：错误通知
    func error() {
        notificationGenerator.notificationOccurred(.error)
        prepareAll()
    }
    
    // MARK: - 私有方法
    
    /// 预热所有反馈生成器
    private func prepareAll() {
        impactGenerator.prepare()
        notificationGenerator.prepare()
    }
}
