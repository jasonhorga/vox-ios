// VoxInputApp.swift
// VoxInput
//
// 应用入口

import SwiftUI

/// Vox Input 应用入口
@main
struct VoxInputApp: App {

    @Environment(\.scenePhase) private var scenePhase
    private let daemonService = AudioDaemonService()

    init() {
        // Sprint 1: 从旧版 UserDefaults.standard 迁移到 App Group + Keychain
        ConfigStore.shared.migrateIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .task {
                    daemonService.start()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active || newPhase == .background {
                        daemonService.start()
                    }
                }
        }
    }
}
