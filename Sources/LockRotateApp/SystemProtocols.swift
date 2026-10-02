import LockRotateSystem

/// The slice of `HelperManager` the app model needs, so tests can inject a fake.
protocol HelperControlling: Sendable {
    func status() async -> HelperStatus
    func setLockText(_ text: String) async throws
    func install() async throws
    func uninstall() async throws
}

extension HelperManager: HelperControlling {
    func uninstall() async throws {
        try await uninstall(keepText: false)
    }
}

protocol LockTextReading: Sendable {
    func current() -> String?
}

extension LockTextReader: LockTextReading {}
