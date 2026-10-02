import Foundation

public struct ImportResult: Sendable, Equatable {
    public var items: [String]
    /// Entries that were present but empty after cleaning (blank lines in txt are not counted).
    public var skippedEmpty: Int
    public var truncated: Int
    public var duplicatesRemoved: Int

    public init(items: [String], skippedEmpty: Int = 0, truncated: Int = 0, duplicatesRemoved: Int = 0) {
        self.items = items
        self.skippedEmpty = skippedEmpty
        self.truncated = truncated
        self.duplicatesRemoved = duplicatesRemoved
    }
}

public enum ImportError: Error, Equatable, LocalizedError {
    case emptyFile
    case noValidItems
    case malformedJSON
    case invalidJSONStructure
    case notUTF8

    public var errorDescription: String? {
        switch self {
        case .emptyFile: String(localized: "import.error.emptyFile", bundle: .module)
        case .noValidItems: String(localized: "import.error.noValidItems", bundle: .module)
        case .malformedJSON: String(localized: "import.error.malformedJSON", bundle: .module)
        case .invalidJSONStructure: String(localized: "import.error.invalidJSONStructure", bundle: .module)
        case .notUTF8: String(localized: "import.error.notUTF8", bundle: .module)
        }
    }
}
