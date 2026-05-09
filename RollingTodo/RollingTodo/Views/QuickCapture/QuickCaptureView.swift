import SwiftUI
import SwiftData

struct QuickCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Folder.sortOrder)]) private var folders: [Folder]
    @AppStorage("quickCaptureFolderID") private var quickCaptureFolderID: String = ""

    @State private var title: String = ""
    @State private var noteBody: String = ""
    @State private var asTodo: Bool = false
    @FocusState private var titleFocus: Bool

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.tint)
                Text("Quick Capture")
                    .font(.headline)
                Spacer()
                if !folders.isEmpty {
                    Picker("Folder", selection: $quickCaptureFolderID) {
                        Text("Unfiled").tag("")
                        ForEach(folders) { folder in
                            Text(folder.name.isEmpty ? "Untitled" : folder.name)
                                .tag(folder.id.uuidString)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
            }

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocus)
                .onSubmit(save)

            TextEditor(text: $noteBody)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80, maxHeight: 160)
                .padding(6)
                .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.2))
                )

            HStack {
                Toggle("Todo", isOn: $asTodo)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(minWidth: 360, idealWidth: 380)
        .onAppear { titleFocus = true }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let folder: Folder?
        if !quickCaptureFolderID.isEmpty,
           let uuid = UUID(uuidString: quickCaptureFolderID) {
            folder = folders.first(where: { $0.id == uuid })
        } else {
            folder = nil
        }

        let nextSort: Int = {
            let descriptor = FetchDescriptor<Note>()
            let all = (try? context.fetch(descriptor)) ?? []
            return (all.map(\.sortOrder).max() ?? -1) + 1
        }()

        let n = Note(title: trimmedTitle, folder: folder, sortOrder: nextSort)
        n.bodyMarkdown = noteBody
        n.todoEnabled = asTodo
        if asTodo { n.status = .notStarted }
        n.refreshTags()
        context.insert(n)
        try? context.save()

        title = ""
        noteBody = ""
        asTodo = false
        dismiss()
    }
}

#Preview {
    QuickCaptureView()
        .modelContainer(PersistenceController.preview)
}
