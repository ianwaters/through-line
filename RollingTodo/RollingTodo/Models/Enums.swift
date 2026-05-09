import SwiftUI

enum Priority: Int, CaseIterable, Identifiable, Codable {
    case none = 0
    case low = 1
    case normal = 2
    case high = 3
    case urgent = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    var sfSymbol: String {
        switch self {
        case .none: "flag"
        case .low: "flag"
        case .normal: "flag.fill"
        case .high: "flag.2.crossed.fill"
        case .urgent: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .none: .inkMuted
        case .low: .inkMuted
        case .normal: .editorialNavy
        case .high: .editorialAmber
        case .urgent: .editorialRed
        }
    }
}

enum Status: Int, CaseIterable, Identifiable, Codable {
    case notStarted = 0
    case cancelled = 1
    case triage = 2
    case readyToStart = 3
    case inProgress = 4
    case done = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .notStarted: "Not Started"
        case .cancelled: "Cancelled"
        case .triage: "Triage"
        case .readyToStart: "Ready to Start"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }

    var sfSymbol: String {
        switch self {
        case .notStarted: "circle"
        case .cancelled: "xmark.circle"
        case .triage: "questionmark.circle"
        case .readyToStart: "arrow.right.circle"
        case .inProgress: "arrow.triangle.2.circlepath.circle"
        case .done: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notStarted: .inkMuted
        case .cancelled: .inkMuted
        case .triage: .editorialMustard
        case .readyToStart: .editorialNavy
        case .inProgress: .editorialPlum
        case .done: .editorialSage
        }
    }
}

enum LabelColor: String, CaseIterable, Identifiable, Codable {
    case none
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case blue
    case purple
    case pink
    case gray

    var id: String { rawValue }

    var displayName: String {
        rawValue == "none" ? "No Colour" : rawValue.capitalized
    }

    var swatch: Color? {
        switch self {
        case .none: nil
        case .red: .editorialRed
        case .orange: .editorialAmber
        case .yellow: .editorialMustard
        case .green: .editorialSage
        case .mint: Color(red: 0.451, green: 0.722, blue: 0.616)
        case .teal: Color(red: 0.318, green: 0.557, blue: 0.604)
        case .blue: .editorialNavy
        case .purple: .editorialPlum
        case .pink: Color(red: 0.804, green: 0.475, blue: 0.557)
        case .gray: .inkMuted
        }
    }
}

enum ArchiveAge: String, CaseIterable, Identifiable, Codable {
    case week
    case month
    case sixMonths
    case year

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .sixMonths: "6 Months"
        case .year: "Year"
        }
    }

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .sixMonths: 182
        case .year: 365
        }
    }
}

enum Recurrence: String, CaseIterable, Identifiable, Codable {
    case none
    case daily
    case weekdays
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "Doesn't repeat"
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .yearly: "Every year"
        }
    }

    var sfSymbol: String {
        switch self {
        case .none: "arrow.clockwise"
        case .daily, .weekdays: "calendar"
        case .weekly: "calendar.badge.clock"
        case .monthly, .yearly: "calendar.circle"
        }
    }

    func next(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            var candidate = calendar.date(byAdding: .day, value: 1, to: date)
            while let c = candidate {
                let weekday = calendar.component(.weekday, from: c)
                if weekday != 1 && weekday != 7 { return c }
                candidate = calendar.date(byAdding: .day, value: 1, to: c)
            }
            return nil
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

enum RecurrenceMode: String, CaseIterable, Identifiable, Codable {
    case reset
    case duplicate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reset: "Reset this note"
        case .duplicate: "Duplicate (keep history)"
        }
    }

    var sfSymbol: String {
        switch self {
        case .reset: "arrow.counterclockwise"
        case .duplicate: "doc.on.doc"
        }
    }

    var explanation: String {
        switch self {
        case .reset:
            "Marking done resets this note and advances its due date for the next occurrence."
        case .duplicate:
            "Marking done creates a fresh copy for the next occurrence and keeps this one as history."
        }
    }
}

enum EditorMode: String, CaseIterable, Identifiable, Codable {
    case edit
    case preview
    case split

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .edit: "Edit"
        case .preview: "Preview"
        case .split: "Split"
        }
    }

    var sfSymbol: String {
        switch self {
        case .edit: "pencil"
        case .preview: "eye"
        case .split: "rectangle.split.2x1"
        }
    }
}

enum FocusDueWindow: String, CaseIterable, Identifiable, Codable {
    case today
    case tomorrow
    case thisWeek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: "Today (or overdue)"
        case .tomorrow: "Today or tomorrow"
        case .thisWeek: "Within 7 days"
        }
    }

    func includes(_ date: Date, calendar: Calendar = .current) -> Bool {
        let startOfToday = calendar.startOfDay(for: .now)
        let endOfWindow: Date
        switch self {
        case .today:
            endOfWindow = startOfToday
        case .tomorrow:
            endOfWindow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        case .thisWeek:
            endOfWindow = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday
        }
        return calendar.startOfDay(for: date) <= endOfWindow
    }
}

enum FocusPriorityFloor: String, CaseIterable, Identifiable, Codable {
    case highOrUrgent
    case urgent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .highOrUrgent: "High or Urgent"
        case .urgent: "Urgent only"
        }
    }

    func passes(_ priority: Priority) -> Bool {
        switch self {
        case .highOrUrgent: return priority == .high || priority == .urgent
        case .urgent: return priority == .urgent
        }
    }
}

enum NoteSortOrder: String, CaseIterable, Identifiable, Codable {
    case manual
    case alphabetical
    case priority
    case dueDate
    case modifiedDate
    case createdDate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .alphabetical: "Alphabetical"
        case .priority: "Priority"
        case .dueDate: "Due Date"
        case .modifiedDate: "Modified"
        case .createdDate: "Created"
        }
    }
}
