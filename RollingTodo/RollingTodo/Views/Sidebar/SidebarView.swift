import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Binding var tab: AppTab

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Folder.sortOrder)]) private var folders: [Folder]
    @Query(filter: #Predicate<Note> { $0.archivedDate == nil }) private var activeNotes: [Note]

    @State private var renamingID: UUID?
    @State private var renameText: String = ""
    @FocusState private var renameFocus: UUID?

    @State private var deletingFolder: Folder?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Home", systemImage: "house")
                    .tag(SidebarSelection.home)
            }

            Section {
                Label("All", systemImage: "tray.full")
                    .tag(SidebarSelection.allNotes)

                ForEach(folders) { folder in
                    folderRow(folder)
                        .tag(SidebarSelection.folder(folder.id))
                        .contextMenu {
                            Button("Rename") { startRename(folder) }
                            Button("Duplicate") { duplicate(folder) }
                            Divider()
                            Button("Delete", role: .destructive) { deletingFolder = folder }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            moveDroppedNotes(noteIDs: items, toFolder: folder)
                            return true
                        }
                }
                .onMove(perform: moveFolders)
            } header: {
                Text(tab.displayName)
                    .eyebrowStyle(tint: Color.inkMuted)
            }

            if !tagsList.isEmpty {
                Section {
                    ForEach(tagsList, id: \.self) { tag in
                        Label("#\(tag)", systemImage: "tag")
                            .tag(SidebarSelection.tag(tag))
                    }
                } header: {
                    Text("Tags")
                        .eyebrowStyle(tint: Color.inkMuted)
                }
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
        }
        .toolbar {
            ToolbarItem {
                Button(action: createFolder) {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
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
        .onChange(of: renameFocus) { oldValue, newValue in
            if let oldID = oldValue, oldID != newValue, renamingID == oldID {
                commitRename(forID: oldID)
            }
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.tint)
                .frame(width: 16)

            if renamingID == folder.id {
                TextField("Folder name", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused($renameFocus, equals: folder.id)
                    .onSubmit { commitRename() }
                    #if os(macOS)
                    .onExitCommand { cancelRename() }
                    #endif
            } else {
                Text(folder.name.isEmpty ? "Untitled" : folder.name)
            }
        }
        .onTapGesture(count: 2) {
            startRename(folder)
        }
    }

    private var tagsList: [String] {
        var set = Set<String>()
        for n in activeNotes {
            for t in n.tags ?? [] { set.insert(t) }
        }
        return set.sorted()
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deletingFolder != nil },
            set: { if !$0 { deletingFolder = nil } }
        )
    }

    private func createFolder() {
        let next = (folders.map(\.sortOrder).max() ?? -1) + 1
        let f = Folder(name: "New Folder", sortOrder: next)
        context.insert(f)
        try? context.save()
        selection = .folder(f.id)
        startRename(f)
    }

    private func startRename(_ folder: Folder) {
        renameText = folder.name
        renamingID = folder.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            renameFocus = folder.id
        }
    }

    private func cancelRename() {
        renamingID = nil
        renameFocus = nil
    }

    private func commitRename() {
        guard let id = renamingID else { return }
        commitRename(forID: id)
    }

    private func commitRename(forID id: UUID) {
        guard let f = folders.first(where: { $0.id == id }) else {
            renamingID = nil
            return
        }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        f.name = trimmed.isEmpty ? "Untitled" : trimmed
        try? context.save()
        if renamingID == id { renamingID = nil }
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

    private func moveDroppedNotes(noteIDs: [String], toFolder folder: Folder) {
        let uuids = noteIDs.compactMap(UUID.init(uuidString:))
        guard !uuids.isEmpty else { return }
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { uuids.contains($0.id) })
        guard let notes = try? context.fetch(descriptor) else { return }
        for n in notes {
            n.folder = folder
            n.modifiedDate = .now
        }
        try? context.save()
    }
}

#Preview {
    @Previewable @State var sel: SidebarSelection? = .home
    @Previewable @State var tab: AppTab = .notes
    NavigationSplitView {
        SidebarView(selection: $sel, tab: $tab)
    } detail: {
        Text("Detail")
    }
    .modelContainer(PersistenceController.preview)
}
