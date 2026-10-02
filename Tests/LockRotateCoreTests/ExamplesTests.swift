import Foundation
import Testing
@testable import LockRotateCore

/// The files in examples/ are shown in the README, so they must import cleanly with the default limits.
struct ExamplesTests {
    private static let examplesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // LockRotateCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("examples", isDirectory: true)

    private func load(_ name: String) throws -> ImportResult {
        let data = try Data(contentsOf: Self.examplesDirectory.appendingPathComponent(name))
        return try QuoteImporter().importData(data, filename: name)
    }

    private func expectCleanImport(_ result: ImportResult) {
        #expect(result.items.count == 12)
        #expect(result.skippedEmpty == 0)
        #expect(result.truncated == 0)
        #expect(result.duplicatesRemoved == 0)

        let sanitizer = TextSanitizer(maxLength: 120, maxLines: 3)
        for item in result.items {
            #expect(item.count <= 120, "too long: \(item)")
            #expect(item.split(separator: "\n", omittingEmptySubsequences: false).count <= 3, "too many lines: \(item)")
            // Cleaning an already-clean entry must not change it.
            #expect(sanitizer.clean(item)?.text == item, "changed by cleaning: \(item)")
        }
        let multiLine = result.items.filter { $0.contains("\n") }
        #expect((1...2).contains(multiLine.count))
    }

    @Test func txtExampleImportsCleanly() throws {
        expectCleanImport(try load("quotes.txt"))
    }

    @Test func jsonExampleImportsCleanly() throws {
        expectCleanImport(try load("quotes.json"))
    }

    @Test func bothExamplesHaveTheSameEntries() throws {
        #expect(try load("quotes.txt").items == load("quotes.json").items)
    }
}
