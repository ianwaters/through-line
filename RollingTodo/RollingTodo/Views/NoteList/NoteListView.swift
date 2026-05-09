import SwiftUI
import SwiftData

struct NoteListView: View {
    let sidebarSelection: SidebarSelection?
    let tab: AppTab
    @Binding var noteSelection: UUID?

    var body: some View {
        switch sidebarSelection {
        case .none:
            ContentUnavailableView(
                "Nothing Selected",
                systemImage: "sidebar.left",
                description: Text("Pick something from the sidebar.")
            )
        case .home:
            ContentUnavailableView(
                "Home is Open",
                systemImage: "house.fill",
                description: Text("The home screen is showing in the detail pane.")
            )
        case .allNotes:
            FilteredNoteListView(tab: tab, folderID: nil, noteSelection: $noteSelection)
                .id("\(tab.rawValue)-all")
        case .folder(let id):
            FilteredNoteListView(tab: tab, folderID: id, noteSelection: $noteSelection)
                .id("\(tab.rawValue)-\(id)")
        }
    }
}

struct FilteredNoteListView: View {
    let tab: AppTab
    let folderID: UUID?
    @Binding var noteSelection: UUID?

    @Environment(\.modelContext) private var context
    @Query private var notes: [Note]
    @Query private var folderResults: [Folder]

    @State private var renamingNote: Note?
    @State private var renameText: String = ""
    @State private var searchText: String = ""
    @State private var sort: NoteSortOrder = .manual
    @AppStorage("dueTodayIsUrgent") private var dueTodayIsUrgent: Bool = false

    private var sortKey: String {
        let f = folderID?.uuidString ?? "all"
        return "noteSort.\(tab.rawValue).\(f)"
    }

    init(tab: AppTab, folderID: UUID?, noteSelection: Binding<UUID?>) {
        self.tab = tab
        self.folderID = folderID
        self._noteSelection = noteSelection

        let archived = tab == .archive
        let predicate: Predicate<Note>

        if let folderID {
            if archived {
                predicate = #Predicate<Note> { $0.archivedDate != nil && $0.folder?.id == folderID }
            } else {
                predicate = #Predicate<Note> { $0.archivedDate == nil && $0.folder?.id == folderID }
            }
        } else {
            if archived {
                predicate = #Predicate<Note> { $0.archivedDate != nil }
            } else {
                predicate = #Predicate<Note> { $0.archivedDate == nil }
            }
        }

        self._notes = Query(filter: predicate)

        if let folderID {
            self._folderResults = Query(filter: #Predicate<Folder> { $0.id == folderID })
        } else {
            self._folderResults = Query()
        }
    }

    private var currentFolder: Folder? { folderID == nil ? nil : folderResults.first }

    private var navTitle: String {
        if let folder = currentFolder {
            return folder.name.isEmpty ? "Untitled" : folder.name
        }
        return tab == .archive ? "All Archived" : "All Notes"
    }

    private var filteredNotes: [Note] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return notes }
        let needle = trimmed.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(needle) ||
            $0.bodyMarkdown.lowercased().contains(needle)
        }
    }

    private var sortedNotes: [Note] {
        let base = filteredNotes
        switch sort {
        case .manual:
            return base.sorted { $0.sortOrder < $1.sortOrder }
        case .alphabetical:
            return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .priority:
            return base.sorted(by: priorityOrdering)
        case .dueDate:
            return base.sorted(by: dueDateOrdering)
        case .modifiedDate:
            return base.sorted { $0.modifiedDate > $1.modifiedDate }
        case .createdDate:
            return base.sorted { $0.createdDate > $1.createdDate }
        }
    }

    var body: some View {
        Group {
            if sortedNotes.isEmpty {
                emptyState
            } else {
                List(selection: $noteSelection) {
                    ForEach(sortedNotes) { note in
                        NoteRow(note: note)
                            .tag(note.id)
                            .contextMenu {
                                Button("Rename") { startRename(note) }
                                Button("Duplicate") { duplicate(note) }
                                Button(note.isArchived ? "Unarchive" : "Archive", systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox") {
                                    toggleArchive(note)
                                }
                                Divider()
                                Button("Delete", role: .destructive) { delete(note) }
                            }
                    }
                    .onMove { offsets, target in
                        guard sort == .manual else { return }
                        moveNotes(from: offsets, to: target)
                    }
                    .onDelete(perform: deleteNotes)
                }
            }
        }
        .navigationTitle(navTitle)
        .searchable(text: $searchText, prompt: tab == .archive ? "Search archive" : "Search notes")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(NoteSortOrder.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort order")

                Button(action: createNote) {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(tab == .archive)
            }
        }
        .onAppear(perform: loadSort)
        .onChange(of: sort) { _, _ in saveSort() }
        .alert("Rename Note", isPresented: renameBinding) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renamingNote = nil }
            Button("Save", action: commitRename)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if tab == .archive {
            ContentUnavailableView(
                "No Archived Notes",
                systemImage: "archivebox",
                description: Text("Notes you archive will land here.")
            )
        } else {
            ContentUnavailableView(
                "No Notes",
                systemImage: "note.text",
                description: Text("Tap + to create one.")
            )
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingNote != nil },
            set: { if !$0 { renamingNote = nil } }
        )
    }

    private func loadSort() {
        if let raw = UserDefaults.standard.string(forKey: sortKey),
           let s = NoteSortOrder(rawValue: raw) {
            sort = s
        }
    }

    private func saveSort() {
        UserDefaults.standard.set(sort.rawValue, forKey: sortKey)
    }

    // MARK: - Sort comparators

    private func priorityOrdering(_ a: Note, _ b: Note) -> Bool {
        let pa = effectivePriorityRank(a)
        let pb = effectivePriorityRank(b)
        if pa != pb { return pa > pb }
        return dueDateOrdering(a, b)
    }

    private func effectivePriorityRank(_ note: Note) -> Int {
        var rank = note.priority.rawValue
        if dueTodayIsUrgent, let due = note.dueDate, Calendar.current.isDateInToday(due), rank < Priority.urgent.rawValue {
            rank = Priority.urgent.rawValue
        }
        return rank
    }

    private func dueDateOrdering(_ a: Note, _ b: Note) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case (nil, nil): return a.modifiedDate > b.modifiedDate
        case (nil, _): return false
        case (_, nil): return true
        case let (.some(da), .some(db)): return da < db
        }
    }

    // MARK: - Mutations

    private func createNote() {
        let next = (notes.map(\.sortOrder).max() ?? -1) + 1
        let n = Note(title: "New Note", folder: currentFolder, sortOrder: next)
        context.insert(n)
        try? context.save()
        noteSelection = n.id
        startRename(n)
    }

    private func startRename(_ n: Note) {
        renameText = n.title
        renamingNote = n
    }

    private func commitRename() {
        guard let n = renamingNote else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        n.title = trimmed.isEmpty ? "Untitled" : trimmed
        n.modifiedDate = .now
        try? context.save()
        renamingNote = nil
    }

    private func duplicate(_ original: Note) {
        let next = (notes.map(\.sortOrder).max() ?? -1) + 1
        let copy = Note(title: original.title + " Copy", folder: original.folder, sortOrder: next)
        copy.bodyMarkdown = original.bodyMarkdown
        copy.todoEnabled = original.todoEnabled
        copy.priority = original.priority
        copy.status = original.status
        copy.labelColor = original.labelColor
        copy.dueDate = original.dueDate
        for item in original.todoItems ?? [] {
            let newItem = TodoItem(text: item.text, sortOrder: item.sortOrder)
            newItem.isDone = item.isDone
            context.insert(newItem)
            newItem.note = copy
        }
        context.insert(copy)
        try? context.save()
    }

    private func toggleArchive(_ n: Note) {
        n.archivedDate = n.isArchived ? nil : .now
        try? context.save()
    }

    private func delete(_ n: Note) {
        if noteSelection == n.id { noteSelection = nil }
        context.delete(n)
        try? context.save()
    }

    private func deleteNotes(at offsets: IndexSet) {
        for i in offsets {
            if noteSelection == sortedNotes[i].id { noteSelection = nil }
            context.delete(sortedNotes[i])
        }
        try? context.save()
    }

    private func moveNotes(from offsets: IndexSet, to target: Int) {
        var reordered = sortedNotes
        reordered.move(fromOffsets: offsets, toOffset: target)
        for (i, n) in reordered.enumerated() {
            n.sortOrder = i
        }
        try? context.save()
    }
}
