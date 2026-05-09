import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Binding var tab: AppTab

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Folder.sortOrder)]) private var folders: [Folder]

    @State private var renamingFolder: Folder?
    @State private var renameText: String = ""
    @State private var deletingFolder: Folder?
    @State private var showingSettingsSheet: Bool = false

    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Home", systemImage: "house")
                    .tag(SidebarSelection.home)
            }

            Section(tab.displayName) {
                Label("All", systemImage: "tray.full")
                    .tag(SidebarSelection.allNotes)

                ForEach(folders) { folder in
                    Label(folder.name.isEmpty ? "Untitled" : folder.name, systemImage: "folder")
                        .tag(SidebarSelection.folder(folder.id))
                        .contextMenu {
                            Button("Rename") { startRename(folder) }
                            Button("Duplicate") { duplicate(folder) }
                            Divider()
                            Button("Delete", role: .destructive) { deletingFolder = folder }
                        }
                }
                .onMove(perform: moveFolders)
            }
        }
        .navigationTitle("RollingTodo")
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Tab", selection: $tab) {
                ForEach(AppTab.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: openSettingsTapped) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")

                Button(action: createFolder) {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
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
        .alert("Rename Folder", isPresented: renameBinding) {
            TextField("Folder name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingFolder = nil }
            Button("Save", action: commitRename)
        }
        .confirmationDialog(
            deletingFolder.map { "Delete \"\($0.name.isEmpty ? "Untitled" : $0.name)\"?" } ?? "",
            isPresented: deleteBinding,
            titleVisibility: .visible,
            presenting: deletingFolder
        ) { folder in
            Button("Delete", role: .destructive) { deleteFolder(folder) }
            Button("Cancel", role: .cancel) { deletingFolder = nil }
        } message: { folder in
            let count = folder.notes?.count ?? 0
            if count > 0 {
                Text("This will permanently delete the folder and \(count) note\(count == 1 ? "" : "s"). This can't be undone.")
            } else {
                Text("This can't be undone.")
            }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deletingFolder != nil },
            set: { if !$0 { deletingFolder = nil } }
        )
    }

    private func openSettingsTapped() {
        #if os(macOS)
        openSettings()
        #else
        showingSettingsSheet = true
        #endif
    }

    private func createFolder() {
        let next = (folders.map(\.sortOrder).max() ?? -1) + 1
        let f = Folder(name: "New Folder", sortOrder: next)
        context.insert(f)
        try? context.save()
        selection = .folder(f.id)
        startRename(f)
    }

    private func startRename(_ f: Folder) {
        renameText = f.name
        renamingFolder = f
    }

    private func commitRename() {
        guard let f = renamingFolder else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        f.name = trimmed.isEmpty ? "Untitled" : trimmed
        try? context.save()
        renamingFolder = nil
    }

    private func duplicate(_ original: Folder) {
        let next = (folders.map(\.sortOrder).max() ?? -1) + 1
        let copy = Folder(name: original.name + " Copy", sortOrder: next)
        context.insert(copy)
        try? context.save()
    }

    private func deleteFolder(_ f: Folder) {
        if case .folder(let id) = selection, id == f.id {
            selection = .allNotes
        }
        context.delete(f)
        try? context.save()
        deletingFolder = nil
    }

    private func moveFolders(from offsets: IndexSet, to target: Int) {
        var reordered = folders
        reordered.move(fromOffsets: offsets, toOffset: target)
        for (i, f) in reordered.enumerated() {
            f.sortOrder = i
        }
        try? context.save()
    }
}

#Preview {
    @Previewable @State var sel: SidebarSelection? = .home
    @Previewable @State var tab: AppTab = .notes
    return NavigationSplitView {
        SidebarView(selection: $sel, tab: $tab)
    } detail: {
        Text("Detail")
    }
    .modelContainer(PersistenceController.preview)
}
