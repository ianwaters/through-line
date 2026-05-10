import Foundation
import SwiftData

/// Single source of truth for creating new `Note` records. Used by Quick
/// Capture, AI Composer, the toolbar "New Note" button, and the iOS Share
/// Extension's outbox drainer — keeping the side effects (sort order,
/// `refreshTags`, `notStarted` status seeding) consistent across every entry
/// point.
@MainActor
enum NoteCreator {
    @discardableResult
    static func create(
        in context: ModelContext,
        title: String,
        body: String = "",
        folder: Folder? = nil,
        asTodo: Bool = false
    ) -> Note {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.archivedDate == nil })
        let existing = (try? context.fetch(descriptor)) ?? []
        let nextSort = (existing.map(\.sortOrder).max() ?? -1) + 1

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? "New Note" : trimmedTitle

        let note = Note(title: resolvedTitle, folder: folder, sortOrder: nextSort)
        note.bodyMarkdown = body
        note.todoEnabled = asTodo
        if asTodo { note.status = .notStarted }
        note.refreshTags()
        context.insert(note)
        try? context.save()
        return note
    }
}
