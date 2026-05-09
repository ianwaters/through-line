import Foundation
import SwiftData

@Model
final class HomepageNote {
    var id: UUID = UUID()
    var body: String = ""
    var modifiedDate: Date = Date.now

    init(body: String = "") {
        self.id = UUID()
        self.body = body
        self.modifiedDate = .now
    }
}
