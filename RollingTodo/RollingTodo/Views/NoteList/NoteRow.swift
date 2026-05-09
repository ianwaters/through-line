import SwiftUI

struct NoteRow: View {
    let note: Note

    private var calendar: Calendar { .current }

    private var isOverdue: Bool {
        guard !note.isArchived, let due = note.dueDate else { return false }
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: .now)
    }

    private var daysOverdue: Int {
        guard isOverdue, let due = note.dueDate else { return 0 }
        let comps = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: due),
            to: calendar.startOfDay(for: .now)
        )
        return comps.day ?? 0
    }

    private var isDueToday: Bool {
        guard let due = note.dueDate, !note.isArchived else { return false }
        return calendar.isDateInToday(due)
    }

    private var isUrgent: Bool {
        note.priority == .urgent
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(note.labelColor.swatch ?? Color.clear)
                .frame(width: 3)
                .clipShape(.rect(cornerRadius: 1.5))
                .opacity(note.labelColor == .none ? 0 : 1)

            if note.todoEnabled {
                Image(systemName: note.status.sfSymbol)
                    .foregroundStyle(note.status.tint)
                    .font(.body)
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isUrgent {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if isOverdue {
                    Text(daysOverdue == 1 ? "1 day overdue" : "\(daysOverdue) days overdue")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if isDueToday {
                    Text("Due today")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
