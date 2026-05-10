#if DEBUG
import Foundation
import SwiftData

/// Writes one record of every `@Model` type, with every optional field set to a
/// non-nil value and every relationship populated, so the CloudKit *Development*
/// environment registers every `CD_*` record type and field. After running this
/// and waiting for sync, deploy schema Dev → Prod once and every entity exists
/// — no more "I forgot to create a TodoItem in Debug" surprises in Production.
///
/// Seeds are tagged with `Self.seedMarker` in their title/name so they're easy
/// to find and delete from the UI after the schema has been promoted.
@MainActor
enum SchemaSeeder {
    static let seedMarker = "🛠 Schema Seed"

    /// Inserts one of every `@Model` type with all optional fields populated and
    /// all relationships wired both ways, then **waits for the CloudKit export
    /// to confirm** before returning. The wait matters: `context.save()` only
    /// queues the export; the actual upload happens asynchronously inside
    /// `NSPersistentCloudKitContainer`. If the user clicks Deploy in the
    /// CloudKit Console before that export lands, fields registered by the seed
    /// (especially relationship fields like `CD_Note.CD_folder`) won't be in
    /// Dev at deploy time and won't be promoted to Prod.
    static func seed(into context: ModelContext) async -> String {
        let monitor = CloudSyncMonitor.shared
        let initialExportCount = monitor.exportSuccessCount
        let initialExportFailures = monitor.exportFailureCount

        let folder = Folder(name: seedMarker, sortOrder: 9_999)
        context.insert(folder)

        let note = Note(title: seedMarker, folder: folder, sortOrder: 9_999)
        note.bodyMarkdown = "Schema seed — safe to delete after CloudKit deploy. #seed"
        note.todoEnabled = true
        note.priority = .urgent
        note.status = .inProgress
        note.labelColor = .red
        note.dueDate = .now
        note.pinnedDate = .now
        note.archivedDate = .now
        note.recurrence = .daily
        note.recurrenceMode = .duplicate
        note.isLocked = true
        note.tags = ["seed"]
        context.insert(note)

        let item = TodoItem(text: "Schema seed item", sortOrder: 0)
        item.isDone = true
        item.note = note
        context.insert(item)

        let homepageDescriptor = FetchDescriptor<HomepageNote>()
        let existingHomepage = (try? context.fetch(homepageDescriptor)) ?? []
        let didCreateHomepage = existingHomepage.isEmpty
        if didCreateHomepage {
            let homepage = HomepageNote(body: "Schema seed homepage — safe to delete.")
            context.insert(homepage)
        }

        do {
            try context.save()
        } catch {
            return "Seed save failed: \(error.localizedDescription)"
        }

        let extras = didCreateHomepage ? " + HomepageNote" : ""
        let saveSummary = "Saved seed records (Folder + Note + TodoItem\(extras))."

        // Poll the CloudSyncMonitor for export confirmation. We can't observe
        // an `@Observable` from a non-View context, so polling is the simplest
        // robust option. 120s is generous; cloudd typically batches exports
        // within 5–10s but can stall longer on the first export of a session.
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(500))
            if monitor.exportSuccessCount > initialExportCount {
                return saveSummary + "\n\nExport CONFIRMED on CloudKit Development. Safe to deploy schema Dev → Prod now."
            }
            if monitor.exportFailureCount > initialExportFailures {
                return saveSummary + "\n\nExport FAILED — \(monitor.statusNote) Do NOT deploy yet; fix the failure first. Copy diagnostics from Settings → iCloud Sync."
            }
        }
        return saveSummary + "\n\nNo export event in 120s. Don't deploy yet — open Settings → iCloud Sync, hit Test iCloud connection, and confirm CD_Folder/CD_Note/CD_TodoItem all appear in Server records before deploying."
    }

    /// Removes all seed records previously inserted by `seed(into:)`. Matches by
    /// the `seedMarker` string in `Folder.name` and `Note.title`. Children are
    /// removed explicitly because cascade-on-CloudKit-backed to-many is unsafe
    /// here (see feedback_swiftdata_cascade_delete in repo memory).
    @discardableResult
    static func cleanup(from context: ModelContext) -> String {
        let marker = seedMarker
        let folderDescriptor = FetchDescriptor<Folder>(
            predicate: #Predicate { $0.name == marker }
        )
        let noteDescriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.title == marker }
        )

        let folders = (try? context.fetch(folderDescriptor)) ?? []
        let notes = (try? context.fetch(noteDescriptor)) ?? []

        var deletedNotes = 0
        var deletedItems = 0
        var deletedFolders = 0

        for note in notes {
            for item in note.todoItems ?? [] {
                context.delete(item)
                deletedItems += 1
            }
            context.delete(note)
            deletedNotes += 1
        }
        for folder in folders {
            for note in folder.notes ?? [] where note.title != marker {
                // shouldn't happen, but don't orphan unrelated notes
                note.folder = nil
            }
            context.delete(folder)
            deletedFolders += 1
        }

        do {
            try context.save()
            return "Removed \(deletedFolders) folder(s), \(deletedNotes) note(s), \(deletedItems) todo item(s)."
        } catch {
            return "Cleanup save failed: \(error.localizedDescription)"
        }
    }
}
#endif
