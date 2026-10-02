import Foundation

public struct QuoteImporter: Sendable {
    public enum Format: Sendable, Equatable {
        case txt, json
    }

    public var sanitizer: TextSanitizer

    public init(sanitizer: TextSanitizer = TextSanitizer()) {
        self.sanitizer = sanitizer
    }

    public func importData(_ data: Data, filename: String? = nil) throws -> ImportResult {
        guard !data.isEmpty else { throw ImportError.emptyFile }
        guard let text = String(data: data, encoding: .utf8) else { throw ImportError.notUTF8 }
        return try importString(text, filename: filename)
    }

    public func importString(_ string: String, filename: String? = nil) throws -> ImportResult {
        // Editors add a BOM that String(data:) may keep as U+FEFF.
        let text = string.hasPrefix("\u{FEFF}") ? String(string.dropFirst()) : string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyFile
        }

        let raw: [String]
        switch Self.declaredFormat(filename: filename) {
        case .json?:
            raw = try Self.parseJSON(text)
        case .txt?:
            raw = Self.parseTxt(text)
        case nil:
            // Content sniffing: a text line that merely starts with "[" must still import as txt.
            if Self.looksLikeJSON(text), let parsed = try? Self.parseJSON(text) {
                raw = parsed
            } else {
                raw = Self.parseTxt(text)
            }
        }

        let result = sanitizer.sanitize(raw)
        guard !result.items.isEmpty else { throw ImportError.noValidItems }
        return ImportResult(
            items: result.items,
            skippedEmpty: result.skippedEmpty,
            truncated: result.truncated,
            duplicatesRemoved: result.duplicatesRemoved
        )
    }

    private static func declaredFormat(filename: String?) -> Format? {
        guard let filename else { return nil }
        switch (filename as NSString).pathExtension.lowercased() {
        case "json": return .json
        case "txt", "text", "md": return .txt
        default: return nil
        }
    }

    private static func looksLikeJSON(_ text: String) -> Bool {
        guard let first = text.first(where: { !$0.isWhitespace }) else { return false }
        return first == "[" || first == "{"
    }

    private static func parseTxt(_ text: String) -> [String] {
        // "\r\n" is one Character in Swift, so split on newline-class characters instead of "\n" only.
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            return trimmed.replacingOccurrences(of: "\\n", with: "\n")
        }
    }

    private static func parseJSON(_ text: String) throws -> [String] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        } catch {
            throw ImportError.malformedJSON
        }
        let array: [Any]
        if let direct = object as? [Any] {
            array = direct
        } else if let dict = object as? [String: Any], let quotes = dict["quotes"] as? [Any] {
            array = quotes
        } else {
            throw ImportError.invalidJSONStructure
        }
        var strings: [String] = []
        for element in array {
            guard let string = element as? String else { throw ImportError.invalidJSONStructure }
            strings.append(string)
        }
        return strings
    }
}
