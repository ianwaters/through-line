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
    @State private var intelligence = IntelligenceService.shared
    @State private var showingQuickCapture: Bool = false
    @State private var showingSettingsSheet: Bool = false
    @State private var showingAIComposer: Bool = false
    @AppStorage("focusModeEnabled") private var focusModeEnabled: Bool = false

    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    private var isHome: Bool { sidebarSelection == .home }

    private var isCompact: Bool {
        #if os(iOS)
        return hSizeClass == .compact
        #else
        return false
        #endif
    }

    @ViewBuilder
    private var homeView: some View {
        HomeScreenView { id in
            sidebarSelection = .allNotes
            noteSelection = id
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection, tab: $tab)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 240)
        } content: {
            Group {
                if isHome {
                    if isCompact {
                        homeView
                    } else {
                        Color.clear
                    }
                } else {
                    NoteListView(
                        sidebarSelection: sidebarSelection,
                        tab: tab,
                        noteSelection: $noteSelection,
                        searchText: $searchText,
                        focusModeEnabled: $focusModeEnabled,
                        intelligenceAvailable: intelligence.isAvailable,
                        onQuickCapture: { showingQuickCapture = true },
                        onAINote: { showingAIComposer = true },
                        onSettings: openSettingsTapped
                    )
                }
            }
            .navigationSplitViewColumnWidth(
                min: isHome ? 0 : 220,
                ideal: isHome ? 0 : 280,
                max: isHome ? 0 : 480
            )
        } detail: {
            Group {
                if isHome {
                    if isCompact {
                        Color.clear
                    } else {
                        homeView
                    }
                } else if noteSelection != nil {
                    NoteEditorView(
                        noteID: noteSelection,
                        focusModeEnabled: $focusModeEnabled,
                        intelligenceAvailable: intelligence.isAvailable,
                        onQuickCapture: { showingQuickCapture = true },
                        onAINote: { showingAIComposer = true },
                        onSettings: openSettingsTapped
                    )
                } else if tab == .archive {
                    ArchiveEmptyDetail()
                        .modifier(IOSPrimaryToolbarFallback(
                            focusModeEnabled: $focusModeEnabled,
                            intelligenceAvailable: intelligence.isAvailable,
                            onQuickCapture: { showingQuickCapture = true },
                            onAINote: { showingAIComposer = true },
                            onSettings: openSettingsTapped
                        ))
                } else {
                    EditorialEmpty(
                        eyebrow: "Editor",
                        title: "Choose a note",
                        detail: "Pick something from the list, or start fresh.",
                        symbol: "doc.text"
                    ) {
                        Button(action: createNewNote) {
                            Label("New Note", systemImage: "square.and.pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("n", modifiers: .command)
                        .padding(.top, 6)
                    }
                    .modifier(IOSPrimaryToolbarFallback(
                        focusModeEnabled: $focusModeEnabled,
                        intelligenceAvailable: intelligence.isAvailable,
                        onQuickCapture: { showingQuickCapture = true },
                        onAINote: { showingAIComposer = true },
                        onSettings: openSettingsTapped
                    ))
                }
            }
        }
        #if os(macOS)
        .toolbar {
            AppPrimaryToolbar(
                focusModeEnabled: $focusModeEnabled,
                onQuickCapture: { showingQuickCapture = true },
                onAINote: { showingAIComposer = true },
                onSettings: openSettingsTapped,
                intelligenceAvailable: intelligence.isAvailable
            )
        }
        // Hidden ⌘R shortcut — kicks CloudSyncMonitor's account-status round
        // trip, which is the closest thing to a "force sync" we have.
        // NSPersistentCloudKitContainer doesn't expose a public sync trigger,
        // but the network call wakes the daemon's scheduler and the
        // Settings → iCloud Sync section reflects the result via recheckPhase.
        .background {
            Button("Sync now", action: triggerManualSync)
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        #endif
        .sheet(isPresented: $showingQuickCapture) {
            QuickCaptureView()
        }
        .sheet(isPresented: $showingAIComposer) {
            AINoteComposerView { id in
                sidebarSelection = .allNotes
                noteSelection = id
            }
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
            CalendarEventsService.shared.start()
            MaintenanceService.shared.runIfDue(context: context)
            ShareOutbox.drain(into: context)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                MaintenanceService.shared.runIfDue(context: context)
                CalendarEventsService.shared.refreshIfDue()
                ShareOutbox.drain(into: context)
            } else {
                unlockSession.lockAll()
            }
        }
        .environment(unlockSession)
    }

    private func triggerManualSync() {
        Task { await CloudSyncMonitor.shared.refreshAccountStatus() }
    }

    private func openSettingsTapped() {
        #if os(macOS)
        openSettings()
        #else
        showingSettingsSheet = true
        #endif
    }

    private func createNewNote() {
        var folder: Folder? = nil
        var initialBody = ""
        if case .folder(let folderID) = sidebarSelection {
            folder = (try? context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.id == folderID })))?.first
        } else if case .tag(let tag) = sidebarSelection {
            initialBody = "#\(tag) "
        }

        let note = NoteCreator.create(
            in: context,
            title: "New Note",
            body: initialBody,
            folder: folder
        )
        noteSelection = note.id
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
