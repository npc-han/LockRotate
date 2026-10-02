import Foundation
import Testing
@testable import LockRotateCore

struct QuoteImporterTests {
    let importer = QuoteImporter()

    // MARK: txt

    @Test func txtOneLinePerItem() throws {
        let r = try importer.importString("one\ntwo\nthree", filename: "q.txt")
        #expect(r.items == ["one", "two", "three"])
        #expect(r.skippedEmpty == 0)
    }

    @Test func txtIgnoresBlankLinesAndComments() throws {
        let r = try importer.importString("# header\n\none\n   \n  # indented comment\ntwo\n", filename: "q.txt")
        #expect(r.items == ["one", "two"])
    }

    @Test func txtHashInsideLineIsKept() throws {
        let r = try importer.importString("issue #12 fixed", filename: "q.txt")
        #expect(r.items == ["issue #12 fixed"])
    }

    @Test func txtLiteralBackslashNBecomesNewline() throws {
        let r = try importer.importString("line1\\nline2\nsingle", filename: "q.txt")
        #expect(r.items == ["line1\nline2", "single"])
    }

    @Test func txtHandlesCRLF() throws {
        let r = try importer.importString("a\r\nb\r\n\r\nc\r\n", filename: "q.txt")
        #expect(r.items == ["a", "b", "c"])
    }

    @Test func dataStripsUTF8BOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("# c\nhello\n".utf8))
        let r = try importer.importData(data, filename: "q.txt")
        #expect(r.items == ["hello"])
    }

    @Test func bomBeforeCommentDoesNotHideIt() throws {
        let r = try importer.importString("\u{FEFF}# comment\nx", filename: "q.txt")
        #expect(r.items == ["x"])
    }

    @Test func txtDedupTruncateCounts() throws {
        let small = QuoteImporter(sanitizer: TextSanitizer(maxLength: 5))
        let r = try small.importString("a\na\nlongerthan5\n\\n\nb", filename: "q.txt")
        #expect(r.items == ["a", "long…", "b"])
        #expect(r.duplicatesRemoved == 1)
        #expect(r.truncated == 1)
        #expect(r.skippedEmpty == 1)
    }

    @Test func txtMultilineLimitedToMaxLines() throws {
        let r = try importer.importString("a\\nb\\nc\\nd", filename: "q.txt")
        #expect(r.items == ["a\nb\nc"])
        #expect(r.truncated == 1)
    }

    @Test func chineseAndEmojiPreserved() throws {
        let r = try importer.importString("你好，世界 🌏\nこんにちは", filename: "q.txt")
        #expect(r.items == ["你好，世界 🌏", "こんにちは"])
    }

    // MARK: JSON

    @Test func jsonArray() throws {
        let r = try importer.importString(#"["a","b\nc"]"#, filename: "q.json")
        #expect(r.items == ["a", "b\nc"])
    }

    @Test func jsonObjectWithQuotes() throws {
        let r = try importer.importString(#"{"quotes":["a","b"]}"#, filename: "q.json")
        #expect(r.items == ["a", "b"])
    }

    @Test func jsonEmptyStringsAndDuplicatesCounted() throws {
        let r = try importer.importString(#"["a","","  ","a","b"]"#, filename: "q.json")
        #expect(r.items == ["a", "b"])
        #expect(r.skippedEmpty == 2)
        #expect(r.duplicatesRemoved == 1)
    }

    @Test func jsonWithBOMAndData() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(#"["x"]"#.utf8))
        #expect(try importer.importData(data, filename: "q.json").items == ["x"])
    }

    @Test func jsonMalformedThrows() {
        #expect(throws: ImportError.malformedJSON) {
            try importer.importString(#"["a", "b""#, filename: "q.json")
        }
    }

    @Test(arguments: [#"{"items":["a"]}"#, #"["a", 1]"#, #"[["a"]]"#, #""just a string""#, "42", #"{"quotes":"a"}"#])
    func jsonWrongStructureThrows(json: String) {
        #expect(throws: ImportError.invalidJSONStructure) {
            try importer.importString(json, filename: "q.json")
        }
    }

    @Test func jsonWithNoUsableEntriesThrows() {
        #expect(throws: ImportError.noValidItems) {
            try importer.importString(#"["", "  "]"#, filename: "q.json")
        }
        #expect(throws: ImportError.noValidItems) {
            try importer.importString("[]", filename: "q.json")
        }
    }

    // MARK: format detection

    @Test func jsonExtensionIsStrictEvenIfContentLooksLikeText() {
        #expect(throws: ImportError.malformedJSON) {
            try importer.importString("just text", filename: "q.json")
        }
    }

    @Test func txtExtensionNeverParsesJSON() throws {
        let r = try importer.importString(#"["a","b"]"#, filename: "q.txt")
        #expect(r.items == [#"["a","b"]"#])
    }

    @Test func extensionIsCaseInsensitive() throws {
        #expect(try importer.importString(#"["a"]"#, filename: "Q.JSON").items == ["a"])
    }

    @Test func noFilenameSniffsJSON() throws {
        #expect(try importer.importString(#"  ["a","b"]"#).items == ["a", "b"])
        #expect(try importer.importString(#"{"quotes":["a"]}"#).items == ["a"])
    }

    @Test func noFilenameFallsBackToTxtWhenNotJSON() throws {
        #expect(try importer.importString("[note] hello\nworld").items == ["[note] hello", "world"])
        #expect(try importer.importString("plain\ntext").items == ["plain", "text"])
    }

    @Test func unknownExtensionSniffs() throws {
        #expect(try importer.importString(#"["a"]"#, filename: "q.dat").items == ["a"])
        #expect(try importer.importString("a\nb", filename: "q").items == ["a", "b"])
    }

    // MARK: errors

    @Test func emptyInputsThrowEmptyFile() {
        #expect(throws: ImportError.emptyFile) { try importer.importData(Data(), filename: "q.txt") }
        #expect(throws: ImportError.emptyFile) { try importer.importString("  \n\r\n ", filename: "q.txt") }
        #expect(throws: ImportError.emptyFile) { try importer.importData(Data([0xEF, 0xBB, 0xBF]), filename: "q.txt") }
    }

    @Test func onlyCommentsThrowNoValidItems() {
        #expect(throws: ImportError.noValidItems) {
            try importer.importString("# a\n# b\n\n", filename: "q.txt")
        }
    }

    @Test func nonUTF8Throws() {
        let latin1 = Data([0x68, 0xE9, 0xFF, 0xFE, 0x6C])
        #expect(throws: ImportError.notUTF8) { try importer.importData(latin1, filename: "q.txt") }
    }

    @Test func errorDescriptionsAreLocalizedAndNonEmpty() {
        let all: [ImportError] = [.emptyFile, .noValidItems, .malformedJSON, .invalidJSONStructure, .notUTF8]
        for error in all {
            let text = error.localizedDescription
            #expect(!text.isEmpty)
            #expect(!text.hasPrefix("import.error."), "missing localization for \(error)")
        }
    }
}
