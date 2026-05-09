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

    var isArchived: Bool { archivedDate != nil }
}
