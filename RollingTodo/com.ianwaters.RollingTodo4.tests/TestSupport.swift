import Foundation
import SwiftData
@testable import RollingTodo

/// Shared helpers for the test suite.
enum TestSupport {
    /// A single in-memory `ModelContainer` reused by every test, lazily built.
    ///
    /// Why shared: creating a fresh `ModelContainer` per test races with
    /// SwiftData's internal type-metadata registration when Swift Testing runs
    /// suites in parallel, surfacing as `swift_weakLoadStrong` crashes. Sharing
    /// one container across the bundle sidesteps the race entirely.
    ///
    /// Tests that need a clean slate call `freshContext()`, which gives them a
    /// new `ModelContext` and wipes existing rows so cross-test interference
    /// (especially in MaintenanceService tests that fetch all notes) is avoided.
    @MainActor
    static let sharedContainer: ModelContainer = {
        let schema = Schema([Folder.self, Note.self, TodoItem.self, HomepageNote.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: config)
    }()

    /// Returns a context with no pre-existing rows. Caller-friendly default for
    /// every SwiftData-touching test.
    @MainActor
    static func freshContext() -> ModelContext {
        let context = ModelContext(sharedContainer)
        try? context.delete(model: Note.self)
        try? context.delete(model: Folder.self)
        try? context.delete(model: TodoItem.self)
        try? context.delete(model: HomepageNote.self)
        try? context.save()
        return context
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
