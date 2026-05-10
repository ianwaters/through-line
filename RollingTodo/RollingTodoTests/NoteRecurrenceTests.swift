import Testing
import Foundation
import SwiftData
@testable import RollingTodo

/// Exercises `Note.advanceRecurrence()` end-to-end through an in-memory
/// SwiftData container. These are the highest-risk regression paths —
/// recurrence drives data mutation that the user can't easily detect if it
/// silently goes wrong.
@MainActor
@Suite("Note.advanceRecurrence")
struct NoteRecurrenceTests {
    @Test func nonRecurringReturnsFalseAndDoesNotMutate() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "Once", folder: nil, sortOrder: 0)
        note.recurrence = .none
        note.dueDate = TestSupport.date(2026, 5, 10)
        context.insert(note)

        let originalDue = note.dueDate
        let advanced = note.advanceRecurrence()

        #expect(advanced == false)
        #expect(note.dueDate == originalDue)
    }

    @Test func dailyAdvancesAndUnchecksTodos() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "Daily", folder: nil, sortOrder: 0)
        note.recurrence = .daily
        note.dueDate = TestSupport.date(2026, 5, 10)
        let item = TodoItem(text: "do thing", sortOrder: 0)
        item.isDone = true
        item.note = note
        note.todoItems = [item]
        context.insert(note)

        let advanced = note.advanceRecurrence()

        #expect(advanced == true)
        #expect(item.isDone == false)
        // Daily advances by 1 day in the user's calendar; just check it moved.
        #expect((note.dueDate ?? .distantPast) > TestSupport.date(2026, 5, 10))
    }

    /// When `dueDate` is nil, `advanceRecurrence()` falls back to `.now`.
    /// The result should still be a date in the future.
    @Test func usesNowWhenDueDateIsNil() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "No due", folder: nil, sortOrder: 0)
        note.recurrence = .weekly
        note.dueDate = nil
        context.insert(note)

        let before = Date.now
        let advanced = note.advanceRecurrence()

        #expect(advanced == true)
        #expect((note.dueDate ?? .distantPast) > before)
    }

    @Test func unchecksMultipleTodoItems() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "Many", folder: nil, sortOrder: 0)
        note.recurrence = .daily
        note.dueDate = TestSupport.date(2026, 5, 10)
        let items = (0..<3).map { i -> TodoItem in
            let it = TodoItem(text: "step \(i)", sortOrder: i)
            it.isDone = true
            it.note = note
            return it
        }
        note.todoItems = items
        context.insert(note)

        _ = note.advanceRecurrence()

        for it in items {
            #expect(it.isDone == false)
        }
    }
}
