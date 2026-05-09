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
        case .none: .secondary
        case .low: .gray
        case .normal: .blue
        case .high: .orange
        case .urgent: .red
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
        case .notStarted: .secondary
        case .cancelled: .gray
        case .triage: .orange
        case .readyToStart: .blue
        case .inProgress: .purple
        case .done: .green
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
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
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
