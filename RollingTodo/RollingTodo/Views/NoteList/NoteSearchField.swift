import SwiftUI

/// Reusable search field that sits at the top of a notes list column.
struct NoteSearchField: View {
    @Binding var text: String
    var prompt: String = "Search notes"

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .medium))
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Button("Find") { focused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}
