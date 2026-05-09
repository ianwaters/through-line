import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager

    @State private var sidebarSelection: SidebarSelection? = .home
    @State private var tab: AppTab = .notes
    @State private var noteSelection: UUID?

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
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.preview)
}
