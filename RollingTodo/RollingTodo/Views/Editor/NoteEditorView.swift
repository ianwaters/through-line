import SwiftUI
import SwiftData

struct NoteEditorView: View {
    let noteID: UUID?
    @Binding var focusModeEnabled: Bool
    let intelligenceAvailable: Bool
    let onQuickCapture: () -> Void
    let onAINote: () -> Void
    let onSettings: () -> Void

    @Query private var noteResults: [Note]
    @Environment(UnlockSession.self) private var unlockSession

    init(
        noteID: UUID?,
        focusModeEnabled: Binding<Bool>,
        intelligenceAvailable: Bool,
        onQuickCapture: @escaping () -> Void,
        onAINote: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.noteID = noteID
        self._focusModeEnabled = focusModeEnabled
        self.intelligenceAvailable = intelligenceAvailable
        self.onQuickCapture = onQuickCapture
        self.onAINote = onAINote
        self.onSettings = onSettings
        if let id = noteID {
            self._noteResults = Query(filter: #Predicate<Note> { $0.id == id })
        } else {
            self._noteResults = Query(filter: #Predicate<Note> { _ in false })
        }
    }

    var body: some View {
        Group {
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
        .modifier(IOSPrimaryToolbarFallback(
            focusModeEnabled: $focusModeEnabled,
            intelligenceAvailable: intelligenceAvailable,
            onQuickCapture: onQuickCapture,
            onAINote: onAINote,
            onSettings: onSettings
        ))
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
        let ok = await UnlockSession.authenticate(reason: "Unlock \"\(note.title.isEmpty ? "this note" : note.title)\"")
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
    @State private var detectTask: Task<Void, Never>?
    @State private var suggestedDueDate: Date?
    /// Set transiently when the user dismisses a suggestion. The same suggested
    /// date is suppressed for the rest of this editing session; a *different*
    /// detected date (re-typed later) re-surfaces the row.
    @State private var dismissedSuggestion: Date?

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
                    TextField("Untitled", text: $note.title, axis: .vertical)
                        .font(.editorialDisplay(34, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)

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
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 18)

            Rectangle()
                .fill(Color.inkHairline)
                .frame(height: 0.5)

            // .preview wraps the whole column in one ScrollView so the todo
            // list and rendered markdown share a single scroll axis. .edit and
            // .split each let their body editor scroll itself (TextEditor has
            // its own scroller — nesting it in an outer ScrollView produces
            // gesture conflicts and breaks newline-on-Return on macOS).
            switch mode {
            case .edit:
                if note.todoEnabled {
                    TodoListSection(note: note)
                    Rectangle()
                        .fill(Color.inkHairline)
                        .frame(height: 0.5)
                }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $note.bodyMarkdown)
                        .font(.system(size: 15, design: .serif))
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                    if note.bodyMarkdown.isEmpty {
                        // Offsets that align the placeholder with the
                        // TextEditor's first caret position. NSTextView /
                        // UITextView default to lineFragmentPadding = 5 on
                        // both platforms; UITextView additionally defaults
                        // to textContainerInset.top = 8 (NSTextView is 0),
                        // so iOS needs the extra vertical nudge.
                        Text("Start writing…")
                            .font(.system(size: 15, design: .serif))
                            .foregroundStyle(Color.inkMuted)
                            .padding(.leading, 5)
                            #if os(iOS)
                            .padding(.top, 8)
                            #endif
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            case .preview:
                ScrollView {
                    VStack(spacing: 0) {
                        if note.todoEnabled {
                            TodoListSection(note: note)
                            Rectangle()
                                .fill(Color.inkHairline)
                                .frame(height: 0.5)
                        }
                        MarkdownView(text: note.bodyMarkdown)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                    }
                }
            case .split:
                if note.todoEnabled {
                    TodoListSection(note: note)
                    Rectangle()
                        .fill(Color.inkHairline)
                        .frame(height: 0.5)
                }
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
            #if os(macOS)
            // SavedIndicator is mac-only — on iOS it crowds the nav bar and
            // pushes the inspector toggle into the unreliable "…" overflow.
            if let savedAt {
                ToolbarItem(placement: .primaryAction) {
                    SavedIndicator(savedAt: savedAt, now: ticker)
                }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
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
            TodoInspector(
                note: note,
                mode: $mode,
                suggestedDueDate: visibleSuggestion,
                onApplySuggestion: applySuggestedDueDate,
                onDismissSuggestion: dismissSuggestedDueDate
            )
            .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .onChange(of: note.title) { _, _ in
            scheduleSave()
            scheduleDateDetect()
        }
        .onChange(of: note.bodyMarkdown) { _, _ in
            scheduleSave()
            scheduleDateDetect()
        }
        .onChange(of: note.dueDate) { _, newValue in
            // If the user sets a due date manually (or via the suggestion),
            // the suggestion row should disappear immediately.
            if newValue != nil { suggestedDueDate = nil }
        }
        .onAppear {
            runDateDetect()
        }
        .onDisappear {
            saveTask?.cancel()
            detectTask?.cancel()
            flushSave()
        }
    }

    private var visibleSuggestion: Date? {
        guard note.dueDate == nil else { return nil }
        guard let s = suggestedDueDate else { return nil }
        if s == dismissedSuggestion { return nil }
        return s
    }

    private func applySuggestedDueDate(_ date: Date) {
        note.dueDate = date
        note.modifiedDate = .now
        try? context.save()
        suggestedDueDate = nil
    }

    private func dismissSuggestedDueDate() {
        dismissedSuggestion = suggestedDueDate
    }

    private func scheduleDateDetect() {
        detectTask?.cancel()
        detectTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            runDateDetect()
        }
    }

    private func runDateDetect() {
        let combined = note.title + " " + note.bodyMarkdown
        suggestedDueDate = DateDetectionService.detect(in: combined)
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
    @Previewable @State var focus: Bool = false
    let container = PersistenceController.preview
    let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.title == "Ship v1 to TestFlight" })
    let note = try! container.mainContext.fetch(descriptor).first!
    return NavigationStack {
        NoteEditorView(
            noteID: note.id,
            focusModeEnabled: $focus,
            intelligenceAvailable: false,
            onQuickCapture: {},
            onAINote: {},
            onSettings: {}
        )
    }
    .modelContainer(container)
}

#Preview("Empty") {
    @Previewable @State var focus: Bool = false
    NavigationStack {
        NoteEditorView(
            noteID: nil,
            focusModeEnabled: $focus,
            intelligenceAvailable: false,
            onQuickCapture: {},
            onAINote: {},
            onSettings: {}
        )
    }
    .modelContainer(PersistenceController.preview)
}
