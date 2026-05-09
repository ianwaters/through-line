import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var bodyMarkdown: String = ""
    var sortOrder: Int = 0
    var createdDate: Date = Date.now
    var modifiedDate: Date = Date.now
    var archivedDate: Date?
    var todoEnabled: Bool = false
    var priorityRaw: Int = 0
    var statusRaw: Int = 0
    var labelColorRaw: String = "none"
    var dueDate: Date?
    var pinnedDate: Date?
    var recurrenceRaw: String = "none"
    var recurrenceModeRaw: String = "reset"
    var isLocked: Bool = false
    var tags: [String]? = []

    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \TodoItem.note)
    var todoItems: [TodoItem]? = []

    init(
        title: String = "New Note",
        folder: Folder? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.bodyMarkdown = ""
        self.sortOrder = sortOrder
        self.createdDate = .now
        self.modifiedDate = .now
        self.folder = folder
        self.todoItems = []
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    var labelColor: LabelColor {
        get { LabelColor(rawValue: labelColorRaw) ?? .none }
        set { labelColorRaw = newValue.rawValue }
    }

    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    var recurrenceMode: RecurrenceMode {
        get { RecurrenceMode(rawValue: recurrenceModeRaw) ?? .reset }
        set { recurrenceModeRaw = newValue.rawValue }
    }

    /// Advances the note's dueDate to the next recurrence and unchecks all todo items.
    /// Returns true if the note recurred, false if recurrence is none.
    @discardableResult
    func advanceRecurrence() -> Bool {
        guard recurrence != .none else { return false }
        let base = dueDate ?? .now
        guard let next = recurrence.next(after: base) else { return false }
        dueDate = next
        for item in todoItems ?? [] {
            item.isDone = false
        }
        return true
    }

    var isArchived: Bool { archivedDate != nil }
    var isPinned: Bool { pinnedDate != nil }

    func refreshTags() {
        let combined = title + " " + bodyMarkdown
        let parsed = combined.extractedHashtags()
        let next = parsed.sorted()
        if (tags ?? []) != next {
            tags = next
        }
    }
}

extension String {
    /// Extracts hashtags (#word) from the string, lowercased and de-duplicated.
    /// A tag is a `#` followed by 1+ unicode letter/number/underscore/hyphen.
    func extractedHashtags() -> Set<String> {
        let pattern = #"(?:^|\s)#([\p{L}\p{N}_\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        var found = Set<String>()
        regex.enumerateMatches(in: self, range: nsRange) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: self) else { return }
            found.insert(String(self[r]).lowercased())
        }
        return found
    }
}
