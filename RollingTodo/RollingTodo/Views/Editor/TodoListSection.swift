import SwiftUI
import SwiftData

struct TodoListSection: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var context

    private var items: [TodoItem] {
        (note.todoItems ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var dynamicHeight: CGFloat {
        let rowHeight: CGFloat = 36
        let addRowHeight: CGFloat = 36
        let count = items.count
        let calc = CGFloat(count) * rowHeight + addRowHeight + 8
        return min(max(calc, 80), 260)
    }

    var body: some View {
        List {
            ForEach(items) { item in
                TodoItemRow(item: item)
                    .listRowInsets(.init(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .onMove(perform: move)
            .onDelete(perform: delete)

            Button(action: add) {
                Label("Add task", systemImage: "plus.circle")
                    .foregroundStyle(.tint)
            }
            .listRowInsets(.init(top: 4, leading: 12, bottom: 4, trailing: 12))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: dynamicHeight)
    }

    private func add() {
        let next = (items.last?.sortOrder ?? -1) + 1
        let item = TodoItem(text: "", sortOrder: next)
        context.insert(item)
        item.note = note
        note.modifiedDate = .now
        try? context.save()
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(items[i]) }
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
}

private struct TodoItemRow: View {
    @Bindable var item: TodoItem
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 10) {
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

            TextField("Task", text: $item.text, axis: .horizontal)
                .textFieldStyle(.plain)
                .strikethrough(item.isDone, color: .secondary)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .onSubmit {
                    item.note?.modifiedDate = .now
                    try? context.save()
                }
        }
        .contentShape(.rect)
    }
}
