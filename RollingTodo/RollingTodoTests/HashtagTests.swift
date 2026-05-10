import Testing
@testable import RollingTodo

@Suite("String.extractedHashtags")
struct HashtagTests {
    @Test func plainHashtag() {
        #expect("#work".extractedHashtags() == ["work"])
    }

    @Test func multipleHashtagsAreCollected() {
        let tags = "today #urgent and #later".extractedHashtags()
        #expect(tags == ["urgent", "later"])
    }

    @Test func duplicatesAreDeduplicated() {
        let tags = "#work and more #work".extractedHashtags()
        #expect(tags == ["work"])
    }

    @Test func tagsAreLowercased() {
        let tags = "#URGENT vs #urgent".extractedHashtags()
        #expect(tags == ["urgent"])
    }

    @Test func tagsAcceptLettersDigitsHyphensUnderscores() {
        let tags = "#work-2026 #project_alpha #q3".extractedHashtags()
        #expect(tags == ["work-2026", "project_alpha", "q3"])
    }

    @Test func unicodeTagsAreSupported() {
        let tags = "#café #日本語".extractedHashtags()
        #expect(tags == ["café", "日本語"])
    }

    /// "##" and bare "#" should produce nothing — there's no tag content.
    @Test func emptyOrDoubleHashYieldsNothing() {
        #expect("# alone".extractedHashtags() == [])
        #expect("##".extractedHashtags() == [])
    }

    /// "#" must be preceded by whitespace or start-of-string. URL fragments
    /// like "https://example.com#anchor" should not register as tags.
    @Test func hashesInsideURLsAreIgnored() {
        let tags = "see https://example.com#anchor".extractedHashtags()
        #expect(tags == [])
    }

    @Test func tagAtStartOfStringIsRecognised() {
        #expect("#first".extractedHashtags() == ["first"])
    }

    @Test func emptyStringReturnsEmpty() {
        #expect("".extractedHashtags() == [])
    }
}
