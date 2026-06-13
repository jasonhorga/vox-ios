// InMemorySecretStore.swift
// VoxInputTests
//
// 测试用内存密钥存储，注入 SharedConfigStore 以避免触碰真实 Keychain。

import Foundation
@testable import VoxInput

/// 内存版 SecretStore：测试隔离用，不读写真实 Keychain。
final class InMemorySecretStore: SecretStore {
    private var store: [String: String] = [:]

    /// 模拟 Keychain 读失败（read 始终返回 nil）。
    var failReads = false

    func read(_ key: KeychainStore.Key) -> String? {
        failReads ? nil : store[key.rawValue]
    }

    func write(_ value: String, for key: KeychainStore.Key) {
        store[key.rawValue] = value
    }

    func delete(_ key: KeychainStore.Key) {
        store[key.rawValue] = nil
    }
}
