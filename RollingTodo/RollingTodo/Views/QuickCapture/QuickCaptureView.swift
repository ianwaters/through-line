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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("A quick thought")
                    .font(.editorialDisplay(20, weight: .semibold))
                    .foregroundStyle(Color.ink)
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

            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $title)
                    .font(.editorialDisplay(20, weight: .medium))
                    .textFieldStyle(.plain)
                    .focused($titleFocus)
                    .onSubmit(save)

                Rectangle()
                    .fill(Color.inkHairline)
                    .frame(height: 0.5)

                TextEditor(text: $noteBody)
                    .font(.system(size: 14, design: .serif))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90, maxHeight: 180)

                if noteBody.isEmpty {
                    Text("A short note, link, or markdown.")
                        .font(.editorialItalic(13))
                        .foregroundStyle(Color.inkMuted)
                        .padding(.top, -8)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Toggle(isOn: $asTodo) {
                    Label("Todo", systemImage: "checkmark.circle")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.inkSoft)
                    .keyboardShortcut(.cancelAction)

                Button {
                    save()
                } label: {
                    Text("Capture")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 400)
        #endif
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
