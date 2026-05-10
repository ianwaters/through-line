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
    @MainActor
    init() {
        // Eagerly initialise the sync monitor so its NSPersistentCloudKitContainer
        // event observer is attached before the first sync events fire.
        _ = CloudSyncMonitor.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(PersistenceController.shared)
        #if DEBUG && os(macOS)
        .commands {
            CommandMenu("Debug") {
                Button("Seed CloudKit Schema…") {
                    Task { @MainActor in
                        let result = await SchemaSeeder.seed(into: PersistenceController.shared.mainContext)
                        print("[SchemaSeeder] \(result)")
                        SchemaDebugAlerts.show(title: "Schema seed result", message: result)
                    }
                }
                Button("Remove Schema Seed Records") {
                    let result = SchemaSeeder.cleanup(from: PersistenceController.shared.mainContext)
                    print("[SchemaSeeder] \(result)")
                    SchemaDebugAlerts.show(title: "Schema seed cleanup", message: result)
                }
            }
        }
        #endif

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
