import SwiftUI

struct NoteRow: View {
    let note: Note
    var isSelected: Bool = false

    private var calendar: Calendar { .current }

    private var isOverdue: Bool {
        guard !note.isArchived, let due = note.dueDate else { return false }
        guard note.status != .done && note.status != .cancelled else { return false }
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
        guard note.status != .done && note.status != .cancelled else { return false }
        return calendar.isDateInToday(due)
    }

    private var isUrgent: Bool { note.priority == .urgent }

    private var isSnoozed: Bool { note.isSnoozed() }

    private var snoozeWakeText: String? {
        guard let until = note.snoozedUntil, until > .now else { return nil }
        let cal = Calendar.current
        let interval = until.timeIntervalSinceNow
        if interval < 60 * 60 * 12 {
            // Less than 12 hours away — friendlier as a relative duration.
            let hours = Int((interval / 3600).rounded())
            if hours <= 1 { return "Wakes in 1h" }
            return "Wakes in \(hours)h"
        }
        if cal.isDateInTomorrow(until) {
            return "Wakes tomorrow " + until.formatted(.dateTime.hour().minute())
        }
        let comps = cal.dateComponents([.day], from: .now, to: until)
        if let d = comps.day, d < 7 {
            return "Wakes " + until.formatted(.dateTime.weekday(.wide).hour().minute())
        }
        return "Wakes " + until.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var bodyPreview: String {
        let firstLine = note.bodyMarkdown
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
        return firstLine
            .replacingOccurrences(of: #"^[#>\-\*]+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "`", with: "")
    }

    // MARK: - Selection-aware colours

    private var titleColor: Color {
        isSelected ? .white : .ink
    }

    private var subtleColor: Color {
        isSelected ? .white.opacity(0.85) : .inkMuted
    }

    private var statusColor: Color {
        isSelected ? .white : note.status.tint
    }

    private var dangerColor: Color {
        isSelected ? .white : .editorialRed
    }

    private var warningColor: Color {
        isSelected ? .white : .editorialAmber
    }

    private var pinLockColor: Color {
        isSelected ? .white : .accentColor
    }

    private var labelBarColor: Color {
        // Brighten the label colour ribbon when selected so it stays visible
        guard let swatch = note.labelColor.swatch else { return .clear }
        return isSelected ? .white : swatch
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1)
                .fill(labelBarColor)
                .frame(width: 2)
                .frame(maxHeight: 32)
                .opacity(note.labelColor == .none ? 0 : 1)

            // Always reserve the status-icon slot so titles align across rows
            if note.todoEnabled {
                Image(systemName: note.status.sfSymbol)
                    .foregroundStyle(statusColor)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 18, height: 18)
            } else {
                Color.clear.frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isSnoozed {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundStyle(pinLockColor)
                            .font(.system(size: 10))
                    } else if note.isLocked {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(pinLockColor)
                            .font(.system(size: 10))
                    } else if note.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(pinLockColor)
                            .font(.system(size: 10))
                            .rotationEffect(.degrees(45))
                    }

                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isUrgent && !note.isLocked && !isSnoozed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(dangerColor)
                            .font(.system(size: 10))
                    }
                }

                if !note.isLocked {
                    subline
                }
            }
        }
        .padding(.vertical, 4)
        // Make the entire row hit-testable for List selection. Without this,
        // on macOS the Text view absorbs clicks for cursor placement and the
        // HStack's default hit area is just the union of its children — so
        // clicks land in dead space between text and icons. Result: tapping
        // the title/icon doesn't select the row, only the empty trailing area.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var subline: some View {
        if let wakeText = snoozeWakeText {
            Text(wakeText)
                .font(.system(size: 11, weight: .semibold).smallCaps())
                .tracking(0.5)
                .foregroundStyle(subtleColor)
        } else if isOverdue {
            Text(daysOverdue == 1 ? "1 day overdue" : "\(daysOverdue) days overdue")
                .font(.system(size: 11, weight: .semibold).smallCaps())
                .tracking(0.5)
                .foregroundStyle(dangerColor)
        } else if isDueToday {
            Text("Due today")
                .font(.system(size: 11, weight: .semibold).smallCaps())
                .tracking(0.5)
                .foregroundStyle(warningColor)
        } else if !bodyPreview.isEmpty {
            Text(bodyPreview)
                .font(.editorialItalic(12))
                .foregroundStyle(subtleColor)
                .lineLimit(1)
        }
    }
}
