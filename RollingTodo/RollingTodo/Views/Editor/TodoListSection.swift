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

    private var dynamicHeight: CGFloat {
        // Each row is now ~36pt minimum but can grow up to ~8 lines tall via
        // axis: .vertical wrap. Use a heuristic average of 44pt per row so the
        // List's frame still bounds the section without clipping mid-row text;
        // overflow scrolls inside the inner List.
        let estPerRow: CGFloat = 44
        let addRowHeight: CGFloat = 36
        let count = items.count
        let calc = CGFloat(count) * estPerRow + addRowHeight + 8
        return min(max(calc, 80), 480)
    }

    var body: some View {
        List {
            ForEach(items) { item in
                TodoItemRow(
                    item: item,
                    focus: $focusedTodoID,
                    onDelete: { delete(item) },
                    onTextChanged: { scheduleSave() },
                    onReturnPressed: { handleReturnPressed(after: item) }
                )
                .listRowInsets(.init(top: 4, leading: 12, bottom: 4, trailing: 12))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(item)
                    }
                }
            }
            .onMove(perform: move)

            Button(action: { _ = add() }) {
                Label("Add task", systemImage: "plus.circle")
                    .foregroundStyle(.tint)
            }
            .listRowInsets(.init(top: 4, leading: 12, bottom: 4, trailing: 12))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: dynamicHeight)
        .onChange(of: focusedTodoID) { oldValue, _ in
            // Flush any pending save the moment the user leaves a row, so we
            // never lose keystrokes if the row is destroyed (delete, reorder).
            if oldValue != nil { flushSave() }
        }
        .onChange(of: pendingFocusID) { _, newValue in
            guard let id = newValue else { return }
            // Defer focus assignment by one runloop turn so SwiftUI has time to
            // insert the new row before we try to focus into it.
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
        // Bump every trailing item's sortOrder by 1.
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

    private func move(from offsets: IndexSet, to target: Int) {
        var reordered = items
        reordered.move(fromOffsets: offsets, toOffset: target)
        for (i, item) in reordered.enumerated() {
            item.sortOrder = i
        }
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
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 12)
                .padding(.top, 8)
                #if os(macOS)
                .opacity(isHovered ? 0.7 : 0.3)
                #else
                .opacity(0.4)
                #endif
                .help("Drag to reorder")

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
