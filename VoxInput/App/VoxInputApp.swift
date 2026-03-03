// VoxInputApp.swift
// VoxInput
//
// 应用入口

import SwiftUI

/// Vox Input 应用入口
@main
struct VoxInputApp: App {
    
    init() {
        // Sprint 1: 从旧版 UserDefaults.standard 迁移到 App Group + Keychain
        ConfigStore.shared.migrateIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
