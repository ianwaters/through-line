import Testing
@testable import RollingTodo

@MainActor
@Suite("Note.refreshTags")
struct NoteTagsTests {
    @Test func parsesHashtagsFromTitleAndBody() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "Daily standup #work", folder: nil, sortOrder: 0)
        note.bodyMarkdown = "follow up on #standup-notes #work"
        context.insert(note)

        note.refreshTags()

        #expect(note.tags == ["standup-notes", "work"])
    }

    @Test func returnsEmptyArrayWhenNoHashtags() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "Plain text", folder: nil, sortOrder: 0)
        note.bodyMarkdown = "no tags here"
        context.insert(note)

        note.refreshTags()

        #expect(note.tags == [])
    }

    @Test func clearsTagsWhenAllHashtagsRemoved() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "#work", folder: nil, sortOrder: 0)
        context.insert(note)
        note.refreshTags()
        #expect(note.tags == ["work"])

        note.title = "no longer tagged"
        note.refreshTags()
        #expect(note.tags == [])
    }

    @Test func sortsTagsAlphabetically() {
        let context = TestSupport.makeInMemoryContext()
        let note = Note(title: "#zeta #alpha #mu", folder: nil, sortOrder: 0)
        context.insert(note)

        note.refreshTags()

        #expect(note.tags == ["alpha", "mu", "zeta"])
    }
}
