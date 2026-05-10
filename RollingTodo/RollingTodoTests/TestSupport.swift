import Foundation
import SwiftData
@testable import RollingTodo

/// Shared helpers for the test suite.
enum TestSupport {
    /// Builds an in-memory `ModelContainer` over the same schema the production
    /// container uses, so SwiftData-bound logic can be tested without touching
    /// disk or CloudKit.
    @MainActor
    static func makeInMemoryContext() -> ModelContext {
        let schema = Schema([Folder.self, Note.self, TodoItem.self, HomepageNote.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        return container.mainContext
    }

    /// A Gregorian calendar pinned to UTC. Tests that reason about specific
    /// calendar dates use this so they don't drift with the runner's locale.
    static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Helper to construct a deterministic date in `utcCalendar`.
    static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 12,
        minute: Int = 0,
        calendar: Calendar = utcCalendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
