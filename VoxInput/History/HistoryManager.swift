// HistoryManager.swift
// VoxInput
//
// 历史记录管理器：App Group UserDefaults 存储，最多 100 条，FIFO 淘汰

import Foundation
import Observation

/// 历史记录管理器
/// 使用 App Group UserDefaults 存储，主 App 和键盘扩展共享
@Observable
final class HistoryManager {
    
    // MARK: - 单例
    
    static let shared = HistoryManager()
    
    // MARK: - 常量
    
    /// 最大保存条数
    private static let maxItems = 100
    
    /// 存储键
    private static let storageKey = "vox.history.items"
    
    // MARK: - 可观察属性
    
    /// 所有历史记录（按时间倒序）
    private(set) var items: [HistoryItem] = []
    
    // MARK: - 私有属性
    
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - 初始化
    
    private init() {
        self.defaults = AppGroup.sharedDefaults
        loadItems()
    }
    
    /// 仅供测试使用的初始化方法，允许注入自定义 UserDefaults
    init(defaults: UserDefaults) {
        self.defaults = defaults
        loadItems()
    }
    
    // MARK: - 公开方法
    
    /// 添加一条历史记录
    /// - Parameters:
    ///   - text: 转写文本
    ///   - provider: ASR 提供商名称
    func add(text: String, provider: String) {
        let item = HistoryItem(text: text, provider: provider)
        items.insert(item, at: 0)
        
        // FIFO 淘汰：超过上限时移除最旧的
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }
        
        saveItems()
    }
    
    /// 删除指定历史记录
    /// - Parameter item: 要删除的记录
    func delete(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        saveItems()
    }
    
    /// 删除指定索引的历史记录
    /// - Parameter offsets: 索引集合
    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveItems()
    }
    
    /// 清空所有历史记录
    func clearAll() {
        items.removeAll()
        saveItems()
    }
    
    /// 搜索历史记录
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的历史记录
    func search(_ query: String) -> [HistoryItem] {
        guard !query.isEmpty else { return items }
        let lowercased = query.lowercased()
        return items.filter { $0.text.lowercased().contains(lowercased) }
    }
    
    // MARK: - 持久化
    
    private func loadItems() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        do {
            items = try decoder.decode([HistoryItem].self, from: data)
        } catch {
            // 数据损坏时清空
            items = []
        }
    }
    
    private func saveItems() {
        do {
            let data = try encoder.encode(items)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            // 编码失败时静默处理
        }
    }
}
