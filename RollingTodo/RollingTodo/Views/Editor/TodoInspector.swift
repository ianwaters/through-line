import SwiftUI
import SwiftData

struct TodoInspector: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Toggle("Todo Enabled", isOn: $note.todoEnabled)
                    .onChange(of: note.todoEnabled) { _, _ in
                        note.modifiedDate = .now
                        try? context.save()
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
                    if let due = note.dueDate {
                        DatePicker("Due", selection: Binding(
                            get: { due },
                            set: { newValue in
                                note.dueDate = newValue
                                note.modifiedDate = .now
                                try? context.save()
                            }
                        ), displayedComponents: [.date])
                        .labelsHidden()

                        Button("Clear due date", role: .destructive) {
                            note.dueDate = nil
                            note.modifiedDate = .now
                            try? context.save()
                        }
                    } else {
                        Button {
                            note.dueDate = Calendar.current.startOfDay(for: .now)
                            note.modifiedDate = .now
                            try? context.save()
                        } label: {
                            Label("Add due date", systemImage: "calendar.badge.plus")
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

    private var statusBinding: Binding<Status> {
        Binding(
            get: { note.status },
            set: {
                note.status = $0
                note.modifiedDate = .now
                try? context.save()
            }
        )
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
