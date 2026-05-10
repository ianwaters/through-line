import Testing
import Foundation
import SwiftData
@testable import RollingTodo

/// Tests `MaintenanceService.rescheduleOverdue` and `archiveInactive` against
/// an in-memory SwiftData context. These maintenance jobs run unattended so a
/// regression here would silently corrupt user notebooks.
@MainActor
@Suite("MaintenanceService")
struct MaintenanceServiceTests {
    private var calendar: Calendar { Calendar.current }

    // MARK: - rescheduleOverdue

    @Test func reschedulesOverdueTodoNoteToToday() {
        let context = TestSupport.makeInMemoryContext()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let note = Note(title: "Overdue", folder: nil, sortOrder: 0)
        note.todoEnabled = true
        note.status = .inProgress
        note.dueDate = yesterday
        context.insert(note)

        MaintenanceService.shared.rescheduleOverdue(context: context)

        let startOfToday = calendar.startOfDay(for: .now)
        #expect(note.dueDate == startOfToday)
    }

    @Test func leavesNonTodoNotesAlone() {
        let context = TestSupport.makeInMemoryContext()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let note = Note(title: "Reference", folder: nil, sortOrder: 0)
        note.todoEnabled = false
        note.dueDate = yesterday
        context.insert(note)

        MaintenanceService.shared.rescheduleOverdue(context: context)

        #expect(note.dueDate == yesterday)
    }

    @Test func leavesDoneAndCancelledNotesAlone() {
        let context = TestSupport.makeInMemoryContext()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!

        let done = Note(title: "Done", folder: nil, sortOrder: 0)
        done.todoEnabled = true
        done.status = .done
        done.dueDate = yesterday

        let cancelled = Note(title: "Cancelled", folder: nil, sortOrder: 1)
        cancelled.todoEnabled = true
        cancelled.status = .cancelled
        cancelled.dueDate = yesterday

        context.insert(done)
        context.insert(cancelled)

        MaintenanceService.shared.rescheduleOverdue(context: context)

        #expect(done.dueDate == yesterday)
        #expect(cancelled.dueDate == yesterday)
    }

    @Test func leavesFutureDueDatesAlone() {
        let context = TestSupport.makeInMemoryContext()
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: .now)!
        let note = Note(title: "Future", folder: nil, sortOrder: 0)
        note.todoEnabled = true
        note.status = .readyToStart
        note.dueDate = nextWeek
        context.insert(note)

        MaintenanceService.shared.rescheduleOverdue(context: context)

        #expect(note.dueDate == nextWeek)
    }

    // MARK: - archiveInactive

    @Test func archivesInactiveTodoNotesOlderThanCutoff() {
        let context = TestSupport.makeInMemoryContext()
        let oldDate = calendar.date(byAdding: .day, value: -45, to: .now)!
        let note = Note(title: "Stale", folder: nil, sortOrder: 0)
        note.todoEnabled = true
        note.modifiedDate = oldDate
        context.insert(note)

        MaintenanceService.shared.archiveInactive(context: context, age: .month)

        #expect(note.archivedDate != nil)
    }

    @Test func leavesInactiveNonTodoNotesAlone() {
        let context = TestSupport.makeInMemoryContext()
        let oldDate = calendar.date(byAdding: .day, value: -90, to: .now)!
        let note = Note(title: "Old reference note", folder: nil, sortOrder: 0)
        note.todoEnabled = false
        note.modifiedDate = oldDate
        context.insert(note)

        MaintenanceService.shared.archiveInactive(context: context, age: .month)

        #expect(note.archivedDate == nil)
    }

    @Test func leavesAlreadyArchivedNotesAlone() {
        let context = TestSupport.makeInMemoryContext()
        let oldDate = calendar.date(byAdding: .day, value: -90, to: .now)!
        let archivedAt = calendar.date(byAdding: .day, value: -10, to: .now)!
        let note = Note(title: "Was archived", folder: nil, sortOrder: 0)
        note.todoEnabled = true
        note.modifiedDate = oldDate
        note.archivedDate = archivedAt
        context.insert(note)

        MaintenanceService.shared.archiveInactive(context: context, age: .month)

        // Should keep its original archive timestamp, not be re-archived.
        #expect(note.archivedDate == archivedAt)
    }

    @Test func leavesRecentlyModifiedNotesAlone() {
        let context = TestSupport.makeInMemoryContext()
        let recent = calendar.date(byAdding: .day, value: -3, to: .now)!
        let note = Note(title: "Active", folder: nil, sortOrder: 0)
        note.todoEnabled = true
        note.modifiedDate = recent
        context.insert(note)

        MaintenanceService.shared.archiveInactive(context: context, age: .month)

        #expect(note.archivedDate == nil)
    }
}
