import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager

    @State private var sidebarSelection: SidebarSelection? = .home
    @State private var tab: AppTab = .notes
    @State private var noteSelection: UUID?
    @State private var unlockSession = UnlockSession()
    @State private var showingQuickCapture: Bool = false
    @State private var showingSettingsSheet: Bool = false
    @AppStorage("focusModeEnabled") private var focusModeEnabled: Bool = false

    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection, tab: $tab)
        } content: {
            NoteListView(
                sidebarSelection: sidebarSelection,
                tab: tab,
                noteSelection: $noteSelection
            )
        } detail: {
            if sidebarSelection == .home {
                HomeScreenView()
            } else {
                NoteEditorView(noteID: noteSelection)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { focusModeEnabled.toggle() } label: {
                    Label("Focus", systemImage: focusModeEnabled ? "scope" : "circle.dotted")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .help(focusModeEnabled ? "Turn off Focus (⇧⌘F)" : "Focus on what's due or urgent (⇧⌘F)")
                .foregroundStyle(focusModeEnabled ? Color.accentColor : Color.secondary)

                Button { showingQuickCapture = true } label: {
                    Label("Quick Capture", systemImage: "bolt.fill")
                }
                .keyboardShortcut("k", modifiers: .command)
                .help("Quick Capture (⌘K)")

                Button(action: openSettingsTapped) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .sheet(isPresented: $showingQuickCapture) {
            QuickCaptureView()
        }
        .sheet(isPresented: $showingSettingsSheet) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettingsSheet = false }
                        }
                    }
            }
        }
        .onChange(of: sidebarSelection) { _, _ in
            noteSelection = nil
        }
        .onChange(of: tab) { _, _ in
            noteSelection = nil
        }
        .onAppear {
            context.undoManager = undoManager
            MaintenanceService.shared.runIfDue(context: context)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                MaintenanceService.shared.runIfDue(context: context)
            } else {
                unlockSession.lockAll()
            }
        }
        .environment(unlockSession)
    }

    private func openSettingsTapped() {
        #if os(macOS)
        openSettings()
        #else
        showingSettingsSheet = true
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.preview)
}
