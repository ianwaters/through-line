import SwiftUI
import SwiftData

struct NoteListView: View {
    let sidebarSelection: SidebarSelection?
    let tab: AppTab
    @Binding var noteSelection: UUID?
    @Binding var searchText: String

    var body: some View {
        switch sidebarSelection {
        case .none, .home:
            // .home is unreachable here — ContentView swaps to a 2-column layout
            // when on Home, so this column never renders. .none is the launch sliver.
            EditorialEmpty(
                eyebrow: "Sidebar",
                title: "Pick a destination",
                detail: "Choose a folder or tag from the sidebar.",
                symbol: "sidebar.left"
            )
        case .allNotes:
            FilteredNoteListView(tab: tab, scope: .all, noteSelection: $noteSelection, searchText: $searchText)
                .id("\(tab.rawValue)-all")
        case .folder(let id):
            FilteredNoteListView(tab: tab, scope: .folder(id), noteSelection: $noteSelection, searchText: $searchText)
                .id("\(tab.rawValue)-folder-\(id)")
        case .tag(let t):
            FilteredNoteListView(tab: tab, scope: .tag(t), noteSelection: $noteSelection, searchText: $searchText)
                .id("\(tab.rawValue)-tag-\(t)")
        }
    }
}

struct FilteredNoteListView: View {
    let tab: AppTab
    let scope: NoteListScope
    @Binding var noteSelection: UUID?
    @Binding var searchText: String

    @Environment(\.modelContext) private var context
    @Query private var notes: [Note]
    @Query private var folderResults: [Folder]

    @State private var renamingID: UUID?
    @State private var renameText: String = ""
    @FocusState private var renameFocus: UUID?

    @State private var sort: NoteSortOrder = .manual
    @AppStorage("dueTodayIsUrgent") private var dueTodayIsUrgent: Bool = false
    @AppStorage("focusModeEnabled") private var focusModeEnabled: Bool = false
    @AppStorage("focusDueWindow") private var focusDueWindow: FocusDueWindow = .thisWeek
    @AppStorage("focusPriorityFloor") private var focusPriorityFloor: FocusPriorityFloor = .highOrUrgent

    private var sortKey: String {
        let scopeKey: String = switch scope {
        case .all: "all"
        case .folder(let id): "folder-\(id.uuidString)"
        case .tag(let t): "tag-\(t)"
        }
        return "noteSort.\(tab.rawValue).\(scopeKey)"
    }

    init(tab: AppTab, scope: NoteListScope, noteSelection: Binding<UUID?>, searchText: Binding<String>) {
        self.tab = tab
        self.scope = scope
        self._noteSelection = noteSelection
        self._searchText = searchText

        let archived = tab == .archive
        let predicate: Predicate<Note>

        switch scope {
        case .folder(let folderID):
            if archived {
                predicate = #Predicate<Note> { $0.archivedDate != nil && $0.folder?.id == folderID }
            } else {
                predicate = #Predicate<Note> { $0.archivedDate == nil && $0.folder?.id == folderID }
            }
        case .all, .tag:
            if archived {
                predicate = #Predicate<Note> { $0.archivedDate != nil }
            } else {
                predicate = #Predicate<Note> { $0.archivedDate == nil }
            }
        }

        self._notes = Query(filter: predicate)

        switch scope {
        case .folder(let folderID):
            self._folderResults = Query(filter: #Predicate<Folder> { $0.id == folderID })
        default:
            self._folderResults = Query()
        }
    }

    private var currentFolder: Folder? {
        if case .folder = scope { return folderResults.first }
        return nil
    }

    private var navTitle: String {
        switch scope {
        case .folder:
            return currentFolder?.name.isEmpty == false ? currentFolder!.name : "Folder"
        case .tag(let t):
            return "#\(t)"
        case .all:
            return tab == .archive ? "All Archived" : "All Notes"
        }
    }

    private var scopedNotes: [Note] {
        switch scope {
        case .tag(let t):
            return notes.filter { $0.tags?.contains(t) == true }
        case .all, .folder:
            return notes
        }
    }

    private var filteredNotes: [Note] {
        let base = scopedNotes
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        let needle = trimmed.lowercased()
        return base.filter {
            $0.title.lowercased().contains(needle) ||
            $0.bodyMarkdown.lowercased().contains(needle)
        }
    }

    private var sortedNotes: [Note] {
        let base = filteredNotes
        let pinned = base.filter(\.isPinned).sorted {
            ($0.pinnedDate ?? .distantPast) > ($1.pinnedDate ?? .distantPast)
        }
        let unpinned = base.filter { !$0.isPinned }
        return pinned + applySortOrder(unpinned)
    }

    private var focusActive: Bool {
        focusModeEnabled && tab != .archive
    }

    private var displayedNotes: [Note] {
        guard focusActive else { return sortedNotes }
        return sortedNotes.filter(passesFocus)
    }

    private func passesFocus(_ note: Note) -> Bool {
        if note.isPinned { return true }
        guard note.todoEnabled else { return false }
        guard note.status != .done, note.status != .cancelled else { return false }
        if focusPriorityFloor.passes(note.priority) { return true }
        if let due = note.dueDate, focusDueWindow.includes(due) { return true }
        return false
    }

    private func applySortOrder(_ notes: [Note]) -> [Note] {
        switch sort {
        case .manual:
            return notes.sorted { $0.sortOrder < $1.sortOrder }
        case .alphabetical:
            return notes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .priority:
            return notes.sorted(by: priorityOrdering)
        case .dueDate:
            return notes.sorted(by: dueDateOrdering)
        case .modifiedDate:
            return notes.sorted { $0.modifiedDate > $1.modifiedDate }
        case .createdDate:
            return notes.sorted { $0.createdDate > $1.createdDate }
        }
    }

    var body: some View {
        Group {
            if displayedNotes.isEmpty {
                emptyState
            } else {
                List(selection: $noteSelection) {
                    if focusActive {
                        focusBanner
                            .listRowInsets(.init(top: 0, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(displayedNotes) { note in
                        rowContainer(for: note)
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
        .safeAreaInset(edge: .top, spacing: 0) {
            NoteSearchField(text: $searchText, prompt: tab == .archive ? "Search archive" : "Search notes")
        }
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
        .onChange(of: renameFocus) { oldValue, newValue in
            if let oldID = oldValue, oldID != newValue, renamingID == oldID {
                commitRename(forID: oldID)
            }
        }
    }

    @ViewBuilder
    private func rowContainer(for note: Note) -> some View {
        Group {
            if renamingID == note.id {
                renameRow(for: note)
            } else {
                NoteRow(note: note, isSelected: noteSelection == note.id)
            }
        }
        .tag(note.id)
        .draggable(note.id.uuidString)
        .contextMenu {
            Button(note.isPinned ? "Unpin" : "Pin to Top",
                   systemImage: note.isPinned ? "pin.slash" : "pin.fill") {
                togglePin(note)
            }
            Button("Rename") { startRename(note) }
            Button("Duplicate") { duplicate(note) }
            Button(note.isArchived ? "Unarchive" : "Archive", systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox") {
                toggleArchive(note)
            }
            Divider()
            Button("Delete", role: .destructive) { delete(note) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { delete(note) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { toggleArchive(note) } label: {
                Label(note.isArchived ? "Unarchive" : "Archive",
                      systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading) {
            Button { startRename(note) } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func renameRow(for note: Note) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .foregroundStyle(.tint)
                .font(.body)
                .frame(width: 18)
            TextField("Title", text: $renameText)
                .textFieldStyle(.plain)
                .focused($renameFocus, equals: note.id)
                .onSubmit { commitRename() }
                #if os(macOS)
                .onExitCommand { cancelRename() }
                #endif
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var emptyState: some View {
        if focusActive && !sortedNotes.isEmpty {
            EditorialEmpty(
                eyebrow: "In focus",
                title: "Clear sky",
                detail: "Nothing's due \(focusDueWindow.displayName.lowercased()) or at \(focusPriorityFloor.displayName.lowercased()) priority.",
                symbol: "scope"
            )
        } else if !searchText.isEmpty {
            EditorialEmpty(
                eyebrow: "No matches",
                title: "Nothing found",
                detail: "Try a different word.",
                symbol: "magnifyingglass"
            )
        } else if tab == .archive {
            EditorialEmpty(
                eyebrow: "Archive",
                title: "Nothing tucked away",
                detail: "Notes you archive will land here for safekeeping.",
                symbol: "archivebox"
            )
        } else {
            EditorialEmpty(
                eyebrow: "Notes",
                title: "A blank page",
                detail: "Press ⌘N to begin.",
                symbol: "doc.text"
            )
        }
    }

    private var focusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Focus")
                .eyebrowStyle()
            Text("·")
                .font(.system(size: 10))
                .foregroundStyle(Color.inkMuted)
            Text("\(focusDueWindow.displayName.lowercased()) or \(focusPriorityFloor.displayName.lowercased())")
                .font(.editorialItalic(12))
                .foregroundStyle(Color.inkSoft)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color.accentColor.opacity(0.06)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(height: 0.5)
                }
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

    // MARK: - Rename

    private func startRename(_ n: Note) {
        renameText = n.title
        renamingID = n.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            renameFocus = n.id
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
        guard let n = notes.first(where: { $0.id == id }) else {
            renamingID = nil
            return
        }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        n.title = trimmed.isEmpty ? "Untitled" : trimmed
        n.modifiedDate = .now
        try? context.save()
        if renamingID == id { renamingID = nil }
    }

    // MARK: - Mutations

    private func createNote() {
        let next = (notes.map(\.sortOrder).max() ?? -1) + 1
        let initialBody: String
        if case .tag(let t) = scope {
            initialBody = "#\(t) "
        } else {
            initialBody = ""
        }
        let n = Note(title: "New Note", folder: currentFolder, sortOrder: next)
        n.bodyMarkdown = initialBody
        n.refreshTags()
        context.insert(n)
        try? context.save()
        noteSelection = n.id
        startRename(n)
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

    private func togglePin(_ n: Note) {
        n.pinnedDate = n.isPinned ? nil : .now
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
