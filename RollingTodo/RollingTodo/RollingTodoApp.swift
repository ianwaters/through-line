//
//  RollingTodoApp.swift
//  RollingTodo
//
//  Created by Ian Waters on 09/05/2026.
//

import SwiftUI
import SwiftData

@main
struct RollingTodoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(PersistenceController.shared)

        #if os(macOS)
        Settings {
            SettingsView()
        }
        .modelContainer(PersistenceController.shared)

        MenuBarExtra("RollingTodo", systemImage: "checklist") {
            QuickCaptureView()
                .modelContainer(PersistenceController.shared)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
