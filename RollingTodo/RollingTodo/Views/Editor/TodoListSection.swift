import SwiftUI
import SwiftData

struct TodoListSection: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var context

    @FocusState private var focusedTodoID: UUID?
    @State private var pendingFocusID: UUID?
    @State private var saveTask: Task<Void, Never>?

    private var items: [TodoItem] {
        (note.todoItems ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        // LazyVStack instead of List so the section sizes to its actual content
        // — multiline rows expand naturally, the Add row always sits at the
        // measured bottom, and the parent ScrollView in NoteEditorView absorbs
        // any overflow. Drag-to-reorder via `.onMove` is List-only and is the
        // tradeoff: re-add via custom `.draggable` + `.dropDestination` if
        // needed. iOS swipe-to-delete is replaced by the existing context menu.
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                TodoItemRow(
                    item: item,
                    focus: $focusedTodoID,
                    onDelete: { delete(item) },
                    onTextChanged: { scheduleSave() },
                    onReturnPressed: { handleReturnPressed(after: item) }
                )
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(item)
                    }
                }
            }

            Button(action: { _ = add() }) {
                Label("Add task", systemImage: "plus.circle")
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .onChange(of: focusedTodoID) { oldValue, _ in
            if oldValue != nil { flushSave() }
        }
        .onChange(of: pendingFocusID) { _, newValue in
            guard let id = newValue else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                focusedTodoID = id
                pendingFocusID = nil
            }
        }
        .onDisappear {
            saveTask?.cancel()
            flushSave()
        }
    }

    @discardableResult
    private func add() -> TodoItem {
        let next = (items.last?.sortOrder ?? -1) + 1
        let item = TodoItem(text: "", sortOrder: next)
        context.insert(item)
        item.note = note
        note.modifiedDate = .now
        try? context.save()
        return item
    }

    /// Hard-Return handler: insert a new TodoItem immediately below the current
    /// one, re-numbering trailing rows so the new item slots in the right place.
    private func handleReturnPressed(after current: TodoItem) {
        flushSave()
        let insertAfter = current.sortOrder
        for item in items where item.sortOrder > insertAfter {
            item.sortOrder += 1
        }
        let newItem = TodoItem(text: "", sortOrder: insertAfter + 1)
        context.insert(newItem)
        newItem.note = note
        note.modifiedDate = .now
        try? context.save()
        pendingFocusID = newItem.id
    }

    private func delete(_ item: TodoItem) {
        context.delete(item)
        note.modifiedDate = .now
        try? context.save()
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
        saveTask?.cancel()
        saveTask = nil
        note.modifiedDate = .now
        try? context.save()
    }
}

private struct TodoItemRow: View {
    @Bindable var item: TodoItem
    var focus: FocusState<UUID?>.Binding
    let onDelete: () -> Void
    let onTextChanged: () -> Void
    let onReturnPressed: () -> Void

    @Environment(\.modelContext) private var context
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                item.isDone.toggle()
                item.note?.modifiedDate = .now
                try? context.save()
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            TextField("Task", text: $item.text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .strikethrough(item.isDone, color: .secondary)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .focused(focus, equals: item.id)
                .onChange(of: item.text) { _, _ in onTextChanged() }
                .onKeyPress(keys: [.return], phases: .down) { keyPress in
                    // Hardware keyboard only: SwiftUI doesn't deliver `.return`
                    // through `.onKeyPress` from soft keyboards, so iOS soft-kb
                    // Return falls through to TextField default (newline) — the
                    // intended behaviour. Mac & iPad with kb hit this branch.
                    if keyPress.modifiers.contains(EventModifiers.shift) {
                        return .ignored
                    }
                    onReturnPressed()
                    return .handled
                }

            #if os(macOS)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Delete task")
            .padding(.top, 4)
            #endif
        }
        .contentShape(.rect)
        #if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        #endif
    }
}
