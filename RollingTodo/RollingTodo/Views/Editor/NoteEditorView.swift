import SwiftUI
import SwiftData

struct NoteEditorView: View {
    let noteID: UUID?
    @Query private var noteResults: [Note]
    @Environment(UnlockSession.self) private var unlockSession

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
            if note.isLocked && !unlockSession.isUnlocked(note.id) {
                LockedNoteView(note: note)
                    .id(note.id)
            } else {
                NoteEditorContent(note: note)
                    .id(note.id)
            }
        } else {
            Color.clear
        }
    }
}

private struct LockedNoteView: View {
    let note: Note
    @Environment(UnlockSession.self) private var unlockSession
    @State private var attempting: Bool = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.7))
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.bottom, 6)

            VStack(spacing: 8) {
                Text("Sealed")
                    .eyebrowStyle()
                Text(note.title.isEmpty ? "Locked Note" : note.title)
                    .font(.editorialDisplay(26, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                Text("Unlock with biometrics or your device passcode.")
                    .font(.editorialItalic(14))
                    .foregroundStyle(Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button {
                Task { await unlock() }
            } label: {
                Label(attempting ? "Unlocking…" : "Unlock", systemImage: "lock.open")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(attempting)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .onAppear {
            Task { await unlock() }
        }
    }

    private func unlock() async {
        guard !attempting else { return }
        attempting = true
        defer { attempting = false }
        let ok = await unlockSession.authenticate(reason: "Unlock \"\(note.title.isEmpty ? "this note" : note.title)\"")
        if ok { unlockSession.unlock(note.id) }
    }
}

private struct NoteEditorContent: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var context

    @AppStorage("editorMode") private var mode: EditorMode = .edit
    @AppStorage("inspectorVisible") private var showInspector: Bool = false
    @State private var saveTask: Task<Void, Never>?
    @State private var savedAt: Date?
    @State private var ticker: Date = .now
    @State private var intelligence = IntelligenceService.shared
    @State private var suggestingTitle: Bool = false

    private var titleLooksUnset: Bool {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "New Note" || trimmed == "Untitled"
    }

    private var canSuggestTitle: Bool {
        intelligence.isAvailable
            && titleLooksUnset
            && !note.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(note.modifiedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .eyebrowStyle(tint: Color.inkMuted)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("Untitled", text: $note.title)
                        .font(.editorialDisplay(34, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .textFieldStyle(.plain)

                    if canSuggestTitle {
                        Button(action: suggestTitle) {
                            if suggestingTitle {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "wand.and.sparkles")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(suggestingTitle)
                        .help("Suggest a title from the body")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 18)

            Rectangle()
                .fill(Color.inkHairline)
                .frame(height: 0.5)

            if note.todoEnabled {
                TodoListSection(note: note)
                Rectangle()
                    .fill(Color.inkHairline)
                    .frame(height: 0.5)
            }

            switch mode {
            case .edit:
                TextEditor(text: $note.bodyMarkdown)
                    .font(.system(size: 15, design: .serif))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            case .preview:
                ScrollView {
                    MarkdownView(text: note.bodyMarkdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                }
            case .split:
                HStack(spacing: 0) {
                    TextEditor(text: $note.bodyMarkdown)
                        .font(.system(size: 15, design: .serif))
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    Rectangle()
                        .fill(Color.inkHairline)
                        .frame(width: 0.5)
                    ScrollView {
                        MarkdownView(text: note.bodyMarkdown)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let savedAt {
                    SavedIndicator(savedAt: savedAt, now: ticker)
                }

                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Toggle inspector")
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                ticker = .now
            }
        }
        .inspector(isPresented: $showInspector) {
            TodoInspector(note: note, mode: $mode)
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
        note.refreshTags()
        note.modifiedDate = .now
        try? context.save()
        savedAt = .now
        ticker = .now
    }

    private func suggestTitle() {
        guard !suggestingTitle else { return }
        suggestingTitle = true
        Task { @MainActor in
            defer { suggestingTitle = false }
            if let suggestion = await intelligence.suggestTitle(for: note.bodyMarkdown) {
                note.title = suggestion
            }
        }
    }
}

private struct SavedIndicator: View {
    let savedAt: Date
    let now: Date

    private var label: String {
        let elapsed = now.timeIntervalSince(savedAt)
        if elapsed < 5 { return "Saved" }
        if elapsed < 60 { return "Saved \(Int(elapsed))s ago" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "Saved \(minutes)m ago" }
        return "Saved \(savedAt.formatted(.dateTime.hour().minute()))"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help("Last saved \(savedAt.formatted(date: .abbreviated, time: .standard))")
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
