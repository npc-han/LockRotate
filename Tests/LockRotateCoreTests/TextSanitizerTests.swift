import Testing
@testable import LockRotateCore

struct TextSanitizerTests {
    let sanitizer = TextSanitizer()

    @Test func trimsSurroundingWhitespace() {
        #expect(sanitizer.clean("  \t hello \n ")?.text == "hello")
    }

    @Test func emptyAndWhitespaceOnlyBecomeNil() {
        #expect(sanitizer.clean("") == nil)
        #expect(sanitizer.clean(" \n\t  \n") == nil)
        #expect(sanitizer.clean("\u{0}\u{7}\u{1B}") == nil)
    }

    @Test func stripsControlCharactersButKeepsNewline() {
        #expect(sanitizer.clean("a\u{0}b\u{7}c\u{1B}[0m\nd")?.text == "abc[0m\nd")
    }

    @Test func tabBecomesSpaceInsteadOfGluingWords() {
        #expect(sanitizer.clean("a\tb")?.text == "a b")
    }

    @Test func normalizesCRLFAndCR() {
        #expect(sanitizer.clean("a\r\nb\rc")?.text == "a\nb\nc")
    }

    @Test func collapsesThreeOrMoreNewlinesToTwo() {
        #expect(sanitizer.clean("a\n\n\n\nb")?.text == "a\n\nb")
        #expect(sanitizer.clean("a\n\nb")?.text == "a\n\nb")
        #expect(sanitizer.clean("a\n \t \n\nb")?.text == "a\n\nb")
    }

    @Test func limitsLinesAndFlagsTruncation() throws {
        let result = try #require(sanitizer.clean("1\n2\n3\n4\n5"))
        #expect(result.text == "1\n2\n3")
        #expect(result.wasTruncated)
    }

    @Test func linesLimitCountsBlankLines() throws {
        let result = try #require(sanitizer.clean("a\n\nb\n\nc"))
        #expect(result.text == "a\n\nb")
    }

    @Test func customMaxLines() {
        let s = TextSanitizer(maxLines: 1)
        #expect(s.clean("a\nb")?.text == "a")
    }

    @Test func truncatesToMaxLengthWithEllipsis() throws {
        let s = TextSanitizer(maxLength: 10)
        let result = try #require(s.clean(String(repeating: "x", count: 50)))
        #expect(result.text == String(repeating: "x", count: 9) + "…")
        #expect(result.text.count == 10)
        #expect(result.wasTruncated)
    }

    @Test func exactlyMaxLengthIsNotTruncated() throws {
        let s = TextSanitizer(maxLength: 5)
        let result = try #require(s.clean("12345"))
        #expect(result.text == "12345")
        #expect(!result.wasTruncated)
    }

    @Test func lengthCountsCharactersNotBytes() throws {
        let s = TextSanitizer(maxLength: 5)
        #expect(s.clean("你好世界啊")?.text == "你好世界啊")
        let cut = try #require(s.clean("你好世界啊呀"))
        #expect(cut.text == "你好世界…")
        // Each emoji (including a ZWJ family sequence) is one Character.
        #expect(s.clean("😀😀😀😀😀")?.text == "😀😀😀😀😀")
        #expect(s.clean("👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦")?.wasTruncated == false)
        #expect(s.clean("😀😀😀😀😀😀")?.text == "😀😀😀😀…")
    }

    @Test func ellipsisDoesNotFollowTrailingSpace() {
        let s = TextSanitizer(maxLength: 6)
        #expect(s.clean("abcde fghij")?.text == "abcde…")
    }

    @Test func sanitizeListCountsEmptiesDuplicatesTruncations() {
        let s = TextSanitizer(maxLength: 5)
        let result = s.sanitize(["a", " a ", "", "  ", "b", "toolongtext", "a"])
        #expect(result.items == ["a", "b", "tool…"])
        #expect(result.skippedEmpty == 2)
        #expect(result.duplicatesRemoved == 2)
        #expect(result.truncated == 1)
    }

    @Test func dedupKeepsFirstOccurrenceOrder() {
        #expect(sanitizer.sanitize(["c", "a", "c", "b", "a"]).items == ["c", "a", "b"])
    }
}
