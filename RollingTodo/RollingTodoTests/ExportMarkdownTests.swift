import Testing
import Foundation
@testable import RollingTodo

@MainActor
@Suite("ExportService.markdown(for:)")
struct ExportMarkdownTests {
    @Test func minimalNoteHasYAMLFrontMatterWithRequiredFields() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "Hello", folder: nil, sortOrder: 0)
        note.bodyMarkdown = "Body text."
        context.insert(note)

        let md = ExportService.markdown(for: note)

        #expect(md.hasPrefix("---\n"))
        #expect(md.contains("title: Hello"))
        #expect(md.contains("created:"))
        #expect(md.contains("modified:"))
        #expect(md.contains("\n---\n\nBody text."))
    }

    @Test func todoMetadataIsIncludedOnlyForTodos() {
        let context = TestSupport.makeInMemoryContext()
        let plain = Note(title: "Reference", folder: nil, sortOrder: 0)
        let todo = Note(title: "Task", folder: nil, sortOrder: 1)
        todo.todoEnabled = true
        todo.priority = .urgent
        todo.status = .inProgress
        context.insert(plain)
        context.insert(todo)

        let plainMd = ExportService.markdown(for: plain)
        let todoMd = ExportService.markdown(for: todo)

        #expect(!plainMd.contains("todoEnabled"))
        #expect(!plainMd.contains("priority"))
        #expect(todoMd.contains("todoEnabled: true"))
        #expect(todoMd.contains("priority: 4"))
        #expect(todoMd.contains("status: 4"))
    }

    @Test func todoItemsAreEmittedAsCheckboxList() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "Plan", folder: nil, sortOrder: 0)
        note.todoEnabled = true
        let item1 = TodoItem(text: "first", sortOrder: 0)
        item1.isDone = true
        item1.note = note
        let item2 = TodoItem(text: "second", sortOrder: 1)
        item2.isDone = false
        item2.note = note
        note.todoItems = [item1, item2]
        context.insert(note)

        let md = ExportService.markdown(for: note)

        #expect(md.contains("- [x] first"))
        #expect(md.contains("- [ ] second"))
    }

    @Test func titlesWithSpecialCharactersAreYAMLQuoted() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "1:1 with #boss", folder: nil, sortOrder: 0)
        context.insert(note)

        let md = ExportService.markdown(for: note)

        // ":" and "#" both trigger quoting in yamlValue
        #expect(md.contains("title: \"1:1 with #boss\""))
    }

    @Test func tagsAreSerialisedAsArray() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "tagged", folder: nil, sortOrder: 0)
        note.tags = ["alpha", "beta"]
        context.insert(note)

        let md = ExportService.markdown(for: note)

        #expect(md.contains("tags: [alpha, beta]"))
    }

    @Test func archivedAndLockedFlagsAreIncludedWhenSet() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "secret", folder: nil, sortOrder: 0)
        note.archivedDate = .now
        note.isLocked = true
        context.insert(note)

        let md = ExportService.markdown(for: note)

        #expect(md.contains("archived:"))
        #expect(md.contains("locked: true"))
    }

    /// Identical input should produce identical output. Catches regressions
    /// where, e.g., a `Set` swap into the YAML emit path would shuffle order.
    @Test func outputIsDeterministic() {
        let context = TestSupport.makeInMemoryContext()
        let fixed = TestSupport.date(2026, 5, 10)
        let note = Note(title: "Stable", folder: nil, sortOrder: 0)
        note.bodyMarkdown = "body"
        note.createdDate = fixed
        note.modifiedDate = fixed
        note.tags = ["a", "b", "c"]
        context.insert(note)

        let first = ExportService.markdown(for: note)
        let second = ExportService.markdown(for: note)

        #expect(first == second)
    }
}
