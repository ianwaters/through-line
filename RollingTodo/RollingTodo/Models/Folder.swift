import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    var createdDate: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Note.folder)
    var notes: [Note]? = []

    init(name: String = "", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.createdDate = .now
        self.notes = []
    }
}
