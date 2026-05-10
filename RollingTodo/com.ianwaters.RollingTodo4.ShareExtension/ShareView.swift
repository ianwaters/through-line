import SwiftUI

/// Compact form rendered inside the Share Extension. Mirrors Quick Capture's
/// shape (title, body, todo toggle) without the folder picker — folders need
/// the SwiftData container which the extension doesn't open. The host app
/// drops new shares into Unfiled and the user can move them later.
struct ShareView: View {
    let initial: SharePayload
    let onSave: (PendingShare) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var noteBody: String = ""
    @State private var asTodo: Bool = false
    @FocusState private var titleFocus: Bool

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($titleFocus)
                    TextField("Body", text: $noteBody, axis: .vertical)
                        .lineLimit(3...10)
                }
                Section {
                    Toggle("Save as a todo", isOn: $asTodo)
                }
            }
            .navigationTitle("Save to RollingTodo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(PendingShare(
                            id: UUID(),
                            title: title,
                            body: noteBody,
                            asTodo: asTodo,
                            createdAt: .now
                        ))
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            title = initial.suggestedTitle
            noteBody = initial.suggestedBody
            titleFocus = title.isEmpty
        }
    }
}
