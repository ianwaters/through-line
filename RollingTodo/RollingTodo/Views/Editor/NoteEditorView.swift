import SwiftUI
import SwiftData

struct NoteEditorView: View {
    let noteID: UUID?
    @Query private var noteResults: [Note]

    init(noteID: UUID?) {
        self.noteID = noteID
        if let id = noteID {
            self._noteResults = Query(filter: #Predicate<Note> { $0.id == id })
        } else {
            self._noteResults = Query(filter: #Predicate<Note> { _ in false })
        }
    }

    var body: some View {
        if let note = noteResults.first {
            NoteEditorContent(note: note)
                .id(note.id)
        } else {
            ContentUnavailableView(
                "No Note Selected",
                systemImage: "note",
                description: Text("Pick a note from the list, or create a new one with ⌘N.")
            )
        }
    }
}

private struct NoteEditorContent: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var context

    @State private var mode: EditorMode = .edit
    @State private var showInspector: Bool = false
    @State private var saveTask: Task<Void, Never>?

    enum EditorMode: String, CaseIterable, Identifiable {
        case edit, preview, split
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .edit: "Edit"
            case .preview: "Preview"
            case .split: "Split"
            }
        }
        var sfSymbol: String {
            switch self {
            case .edit: "pencil"
            case .preview: "eye"
            case .split: "rectangle.split.2x1"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $note.title)
                .font(.largeTitle.bold())
                .textFieldStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            if note.todoEnabled {
                TodoListSection(note: note)
                Divider()
            }

            switch mode {
            case .edit:
                TextEditor(text: $note.bodyMarkdown)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
            case .preview:
                ScrollView {
                    MarkdownView(text: note.bodyMarkdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            case .split:
                HStack(spacing: 0) {
                    TextEditor(text: $note.bodyMarkdown)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                    Divider()
                    ScrollView {
                        MarkdownView(text: note.bodyMarkdown)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Mode", selection: $mode) {
                    ForEach(EditorMode.allCases) { m in
                        Image(systemName: m.sfSymbol).tag(m)
                            .help(m.displayName)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle inspector")
            }
        }
        .inspector(isPresented: $showInspector) {
            TodoInspector(note: note)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .onChange(of: note.title) { _, _ in scheduleSave() }
        .onChange(of: note.bodyMarkdown) { _, _ in scheduleSave() }
        .onDisappear {
            saveTask?.cancel()
            flushSave()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            flushSave()
        }
        saveTask = task
    }

    private func flushSave() {
        note.modifiedDate = .now
        try? context.save()
    }
}

#Preview("With note") {
    @Previewable @State var noteID: UUID?
    let container = PersistenceController.preview
    let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.title == "Ship v1 to TestFlight" })
    let note = try! container.mainContext.fetch(descriptor).first!
    return NavigationStack {
        NoteEditorView(noteID: note.id)
    }
    .modelContainer(container)
}

#Preview("Empty") {
    NavigationStack {
        NoteEditorView(noteID: nil)
    }
    .modelContainer(PersistenceController.preview)
}
