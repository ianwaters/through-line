import SwiftUI
import SwiftData

struct TodoInspector: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(UnlockSession.self) private var unlockSession

    var body: some View {
        Form {
            Section {
                Toggle("Todo Enabled", isOn: $note.todoEnabled)
                    .onChange(of: note.todoEnabled) { _, _ in
                        note.modifiedDate = .now
                        try? context.save()
                    }

                Toggle("Pin to top", isOn: pinnedBinding)

                Button {
                    Task { await toggleLock() }
                } label: {
                    Label(note.isLocked ? "Remove lock" : "Lock note",
                          systemImage: note.isLocked ? "lock.open" : "lock")
                }
            }

            if note.todoEnabled {
                Section("Status") {
                    Picker("Status", selection: statusBinding) {
                        ForEach(Status.allCases) { s in
                            Label(s.displayName, systemImage: s.sfSymbol)
                                .tag(s)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    if note.recurrence != .none {
                        Label(note.recurrenceMode.explanation, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Recurrence") {
                    Picker("Repeat", selection: recurrenceBinding) {
                        ForEach(Recurrence.allCases) { r in
                            Label(r.displayName, systemImage: r.sfSymbol).tag(r)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    if note.recurrence != .none {
                        Picker("On completion", selection: recurrenceModeBinding) {
                            ForEach(RecurrenceMode.allCases) { mode in
                                Label(mode.displayName, systemImage: mode.sfSymbol).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: priorityBinding) {
                        ForEach(Priority.allCases) { p in
                            Label(p.displayName, systemImage: p.sfSymbol)
                                .tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Section("Label Colour") {
                    LabelColorPicker(selection: labelColorBinding)
                }

                Section("Due Date") {
                    DueDatePresets(setDate: { setDue($0) })

                    if let due = note.dueDate {
                        DatePicker("Pick", selection: Binding(
                            get: { due },
                            set: { setDue($0) }
                        ), displayedComponents: [.date])

                        Button("Clear due date", role: .destructive) {
                            note.dueDate = nil
                            note.modifiedDate = .now
                            try? context.save()
                        }
                    }
                }

                Section("Dates") {
                    LabeledContent("Created", value: note.createdDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Modified", value: note.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                }

                Section {
                    Button {
                        note.archivedDate = note.isArchived ? nil : .now
                        try? context.save()
                    } label: {
                        Label(note.isArchived ? "Unarchive" : "Archive", systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func toggleLock() async {
        let reason = note.isLocked
            ? "Remove lock from \"\(note.title.isEmpty ? "this note" : note.title)\""
            : "Lock \"\(note.title.isEmpty ? "this note" : note.title)\""
        let ok = await unlockSession.authenticate(reason: reason)
        guard ok else { return }
        note.isLocked.toggle()
        if !note.isLocked {
            unlockSession.unlock(note.id)
        }
        note.modifiedDate = .now
        try? context.save()
    }

    private var pinnedBinding: Binding<Bool> {
        Binding(
            get: { note.isPinned },
            set: { newValue in
                note.pinnedDate = newValue ? .now : nil
                try? context.save()
            }
        )
    }

    private func setDue(_ date: Date) {
        note.dueDate = Calendar.current.startOfDay(for: date)
        note.modifiedDate = .now
        try? context.save()
    }

    private var statusBinding: Binding<Status> {
        Binding(
            get: { note.status },
            set: { newStatus in
                if newStatus == .done && note.recurrence != .none {
                    handleDoneWithRecurrence()
                } else {
                    note.status = newStatus
                }
                note.modifiedDate = .now
                try? context.save()
            }
        )
    }

    private var recurrenceBinding: Binding<Recurrence> {
        Binding(
            get: { note.recurrence },
            set: {
                note.recurrence = $0
                note.modifiedDate = .now
                try? context.save()
            }
        )
    }

    private var recurrenceModeBinding: Binding<RecurrenceMode> {
        Binding(
            get: { note.recurrenceMode },
            set: {
                note.recurrenceMode = $0
                note.modifiedDate = .now
                try? context.save()
            }
        )
    }

    private func handleDoneWithRecurrence() {
        switch note.recurrenceMode {
        case .reset:
            note.advanceRecurrence()
            note.status = .notStarted
        case .duplicate:
            duplicateForNextOccurrence()
            note.status = .done
        }
    }

    private func duplicateForNextOccurrence() {
        let copy = Note(title: note.title, folder: note.folder, sortOrder: note.sortOrder)
        copy.bodyMarkdown = note.bodyMarkdown
        copy.todoEnabled = note.todoEnabled
        copy.priority = note.priority
        copy.status = .notStarted
        copy.labelColor = note.labelColor
        copy.recurrence = note.recurrence
        copy.recurrenceMode = note.recurrenceMode

        let base = note.dueDate ?? .now
        copy.dueDate = note.recurrence.next(after: base)

        for item in note.todoItems ?? [] {
            let newItem = TodoItem(text: item.text, sortOrder: item.sortOrder)
            newItem.isDone = false
            context.insert(newItem)
            newItem.note = copy
        }

        copy.refreshTags()
        context.insert(copy)

        // Original becomes history — clear recurrence so it doesn't loop again.
        note.recurrence = .none
    }

    private var priorityBinding: Binding<Priority> {
        Binding(
            get: { note.priority },
            set: {
                note.priority = $0
                note.modifiedDate = .now
                try? context.save()
            }
        )
    }

    private var labelColorBinding: Binding<LabelColor> {
        Binding(
            get: { note.labelColor },
            set: {
                note.labelColor = $0
                note.modifiedDate = .now
                try? context.save()
            }
        )
    }
}

private struct DueDatePresets: View {
    let setDate: (Date) -> Void

    private var calendar: Calendar { .current }

    private var presets: [(title: String, date: Date)] {
        let today = calendar.startOfDay(for: .now)
        return [
            ("Today", today),
            ("Tomorrow", calendar.date(byAdding: .day, value: 1, to: today) ?? today),
            ("Next week", calendar.date(byAdding: .weekOfYear, value: 1, to: today) ?? today)
        ]
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.title) { preset in
                Button(preset.title) { setDate(preset.date) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct LabelColorPicker: View {
    @Binding var selection: LabelColor

    private let columns = [GridItem(.adaptive(minimum: 32, maximum: 36), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(LabelColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    ZStack {
                        Circle()
                            .fill(color.swatch ?? Color.clear)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .strokeBorder(color == .none ? Color.secondary : Color.clear, lineWidth: 1)
                            )
                        if color == .none {
                            Image(systemName: "slash.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        if selection == color {
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .help(color.displayName)
            }
        }
        .padding(.vertical, 4)
    }
}
