import Foundation

public struct StateStore: Sendable {
    private let store: JSONFileStore<RotationState>

    public init(directory: URL = LockRotateDirectory.defaultURL()) {
        store = JSONFileStore(
            fileURL: directory.appendingPathComponent("state.json"),
            defaultValue: { RotationState() }
        )
    }

    public func load() -> RotationState { store.load() }
    public func save(_ state: RotationState) throws { try store.save(state) }
}

public struct SettingsStore: Sendable {
    private let store: JSONFileStore<AppSettings>

    public init(directory: URL = LockRotateDirectory.defaultURL()) {
        store = JSONFileStore(
            fileURL: directory.appendingPathComponent("settings.json"),
            defaultValue: { AppSettings() }
        )
    }

    public func load() -> AppSettings { store.load() }
    public func save(_ settings: AppSettings) throws { try store.save(settings) }
}
