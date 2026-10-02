import Foundation

/// Atomic JSON persistence for one value. A missing or corrupt file yields the default instead of an error.
struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    let fileURL: URL
    let defaultValue: @Sendable () -> Value

    func load() -> Value {
        guard let data = try? Data(contentsOf: fileURL),
              let value = try? JSONDecoder().decode(Value.self, from: data) else {
            return defaultValue()
        }
        return value
    }

    func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum LockRotateDirectory {
    /// ~/Library/Application Support/LockRotate
    public static func defaultURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LockRotate", isDirectory: true)
    }
}
