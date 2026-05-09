import Foundation
import SwiftData

@Model
final class TodoItem {
    var id: UUID = UUID()
    var text: String = ""
    var isDone: Bool = false
    var sortOrder: Int = 0
    var note: Note?

    init(text: String = "", sortOrder: Int = 0) {
        self.id = UUID()
        self.text = text
        self.sortOrder = sortOrder
    }
}
