import Foundation

/// Normalizes one lock-screen text entry; limits are parameters because the real
/// display limits are only known after measuring on a device.
public struct TextSanitizer: Sendable, Equatable {
    public static let ellipsis: Character = "…"

    public var maxLength: Int
    public var maxLines: Int

    public init(maxLength: Int = 500, maxLines: Int = 3) {
        self.maxLength = max(1, maxLength)
        self.maxLines = max(1, maxLines)
    }

    public struct Cleaned: Sendable, Equatable {
        public var text: String
        public var wasTruncated: Bool
    }

    public struct ListResult: Sendable, Equatable {
        public var items: [String]
        public var skippedEmpty: Int
        public var truncated: Int
        public var duplicatesRemoved: Int
    }

    /// Returns nil when nothing is left after cleaning.
    public func clean(_ raw: String) -> Cleaned? {
        // "\r\n" is a single Character in Swift, so line endings are normalized on scalars first.
        var scalars = String.UnicodeScalarView()
        var previousWasCR = false
        for scalar in raw.unicodeScalars {
            switch scalar {
            case "\r":
                scalars.append("\n")
                previousWasCR = true
                continue
            case "\n" where previousWasCR:
                break
            case "\n":
                scalars.append(scalar)
            case "\t":
                // Dropping a tab would glue words together.
                scalars.append(" ")
            default:
                if scalar.properties.generalCategory != .control { scalars.append(scalar) }
            }
            previousWasCR = false
        }

        // Trimming each line makes whitespace-only lines count as blank for the collapse below.
        var lines: [String] = []
        var blankRun = 0
        for line in String(scalars).split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blankRun += 1
                // Three or more newlines in a row become two (one blank line).
                if lines.isEmpty || blankRun > 1 { continue }
            } else {
                blankRun = 0
            }
            lines.append(trimmed)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return nil }

        var truncated = false
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            while lines.last?.isEmpty == true { lines.removeLast() }
            truncated = true
        }

        var text = lines.joined(separator: "\n")
        if text.count > maxLength {
            let head = String(text.prefix(maxLength - 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            text = head + String(Self.ellipsis)
            truncated = true
        }
        return Cleaned(text: text, wasTruncated: truncated)
    }

    /// Cleans every entry, drops empties, and removes exact duplicates keeping first occurrences.
    public func sanitize(_ rawItems: [String]) -> ListResult {
        var items: [String] = []
        var seen = Set<String>()
        var skippedEmpty = 0, truncated = 0, duplicates = 0
        for raw in rawItems {
            guard let cleaned = clean(raw) else {
                skippedEmpty += 1
                continue
            }
            guard seen.insert(cleaned.text).inserted else {
                duplicates += 1
                continue
            }
            if cleaned.wasTruncated { truncated += 1 }
            items.append(cleaned.text)
        }
        return ListResult(items: items, skippedEmpty: skippedEmpty, truncated: truncated, duplicatesRemoved: duplicates)
    }
}
