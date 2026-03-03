// NetworkMonitor.swift
// Shared
//
// 网络状态监控（基于 NWPathMonitor）

import Foundation
import Network
import Observation

/// 网络状态监控器
/// 使用 NWPathMonitor 监听网络连接状态变化，供 ASR 降级判断
@Observable
final class NetworkMonitor {
    
    // MARK: - 可观察属性
    
    /// 当前是否有网络连接
    private(set) var isConnected: Bool = true
    
    /// 当前连接类型
    private(set) var connectionType: ConnectionType = .unknown
    
    /// 网络连接类型
    enum ConnectionType {
        case wifi
        case cellular
        case wired
        case unknown
    }
    
    // MARK: - 私有属性
    
    /// 系统网络路径监控器
    private let monitor = NWPathMonitor()
    
    /// 专用监控队列
    private let queue = DispatchQueue(label: "com.jasonhorga.vox.networkmonitor", qos: .utility)
    
    // MARK: - 初始化
    
    init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - 公开方法
    
    /// 开始监控网络状态
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            // 回到主线程更新可观察属性
            Task { @MainActor in
                self?.isConnected = (path.status == .satisfied)
                self?.connectionType = self?.getConnectionType(from: path) ?? .unknown
            }
        }
        monitor.start(queue: queue)
    }
    
    /// 停止监控
    func stopMonitoring() {
        monitor.cancel()
    }
    
    // MARK: - 私有方法
    
    /// 从 NWPath 获取连接类型
    private func getConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wired
        } else {
            return .unknown
        }
    }
}
