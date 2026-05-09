import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager

    @State private var sidebarSelection: SidebarSelection? = .home
    @State private var tab: AppTab = .notes
    @State private var noteSelection: UUID?
    @State private var searchText: String = ""
    @State private var unlockSession = UnlockSession()
    @State private var showingQuickCapture: Bool = false
    @State private var showingSettingsSheet: Bool = false
    @AppStorage("focusModeEnabled") private var focusModeEnabled: Bool = false

    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    private var isHome: Bool { sidebarSelection == .home }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection, tab: $tab)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 240)
        } content: {
            Group {
                if isHome {
                    Color.clear
                } else {
                    NoteListView(
                        sidebarSelection: sidebarSelection,
                        tab: tab,
                        noteSelection: $noteSelection,
                        searchText: $searchText
                    )
                }
            }
            .navigationSplitViewColumnWidth(
                min: isHome ? 0 : 220,
                ideal: isHome ? 0 : 280,
                max: isHome ? 0 : 480
            )
        } detail: {
            if isHome {
                HomeScreenView { id in
                    sidebarSelection = .allNotes
                    noteSelection = id
                }
            } else if noteSelection != nil {
                NoteEditorView(noteID: noteSelection)
            } else if tab == .archive {
                ArchiveEmptyDetail()
            } else {
                EditorialEmpty(
                    eyebrow: "Editor",
                    title: "Choose a note",
                    detail: "Pick something from the list, or press ⌘N to start fresh.",
                    symbol: "doc.text"
                )
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
        .onChange(of: sidebarSelection) { oldValue, _ in
            // Skip the auto-clear when navigating away from Home — that path
            // is the jump-from-Recent flow which has just set noteSelection
            // to the note the user wants to view. Without this guard, the
            // race would clear it back to nil.
            if oldValue == .home { return }
            noteSelection = nil
        }
        .onChange(of: tab) { _, _ in
            noteSelection = nil
        }
        .onAppear {
            context.undoManager = undoManager
            CloudSettingsSync.shared.start()
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

private struct ArchiveEmptyDetail: View {
    @Query(filter: #Predicate<Note> { $0.archivedDate != nil }) private var archived: [Note]

    var body: some View {
        if archived.isEmpty {
            EditorialEmpty(
                eyebrow: "Archive",
                title: "Nothing tucked away",
                detail: "Notes you archive will land here for safekeeping.",
                symbol: "archivebox"
            )
        } else {
            Color.clear
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.preview)
}
