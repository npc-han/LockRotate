import Foundation
import LockRotateCore
import LockRotateSystem
@testable import LockRotateApp

/// A fake lock screen: one object plays both helper and reader, like the real preference does.
final class FakeSystem: HelperControlling, LockTextReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _text: String?
    private var _writes: [String] = []
    private var _status: HelperStatus
    private var _setError: SystemError?
    private var _installError: SystemError?
    private var _installCalls = 0
    private var _uninstallCalls = 0

    init(text: String? = nil, status: HelperStatus = .installed) {
        _text = text
        _status = status
    }

    var text: String? { lock.withLock { _text } }
    var writes: [String] { lock.withLock { _writes } }
    var installCalls: Int { lock.withLock { _installCalls } }
    var uninstallCalls: Int { lock.withLock { _uninstallCalls } }

    func failSetText(with error: SystemError?) { lock.withLock { _setError = error } }
    func failInstall(with error: SystemError?) { lock.withLock { _installError = error } }

    func status() async -> HelperStatus { lock.withLock { _status } }

    func setLockText(_ text: String) async throws {
        try lock.withLock {
            if let error = _setError { throw error }
            _text = text
            _writes.append(text)
        }
    }

    func install() async throws {
        try lock.withLock {
            _installCalls += 1
            if let error = _installError { throw error }
            _status = .installed
        }
    }

    func uninstall() async throws {
        lock.withLock {
            _uninstallCalls += 1
            _status = .notInstalled
        }
    }

    func current() -> String? { lock.withLock { _text } }
}

/// A login item whose state and failures the test controls, like `SMAppService.mainApp`.
final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    private let lock = NSLock()
    private var _status: LoginItemStatus
    private var _registerResult: LoginItemStatus?
    private var _failRegister = false
    private var _failUnregister = false
    private var _registerCalls = 0
    private var _unregisterCalls = 0
    private var _openedSettings = 0

    init(status: LoginItemStatus = .notRegistered) { _status = status }

    var status: LoginItemStatus { lock.withLock { _status } }
    var registerCalls: Int { lock.withLock { _registerCalls } }
    var unregisterCalls: Int { lock.withLock { _unregisterCalls } }
    var openedSettings: Int { lock.withLock { _openedSettings } }

    func setStatus(_ status: LoginItemStatus) { lock.withLock { _status = status } }
    func failRegister(_ fail: Bool) { lock.withLock { _failRegister = fail } }
    func failUnregister(_ fail: Bool) { lock.withLock { _failUnregister = fail } }
    /// What the status becomes after a successful `register()` (default `.enabled`).
    func registerLeaves(_ status: LoginItemStatus) { lock.withLock { _registerResult = status } }

    func register() throws {
        try lock.withLock {
            _registerCalls += 1
            if _failRegister { throw Failure() }
            _status = _registerResult ?? .enabled
        }
    }

    func unregister() throws {
        try lock.withLock {
            _unregisterCalls += 1
            if _failUnregister { throw Failure() }
            _status = .notRegistered
        }
    }

    func openSystemSettings() { lock.withLock { _openedSettings += 1 } }
}

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("LockRotateAppTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
struct Harness {
    let directory: URL
    let system: FakeSystem
    let loginItem: FakeLoginItem
    let model: AppModel

    init(
        items: [String] = [],
        mode: PlaybackMode = .sequential,
        system: FakeSystem = FakeSystem(),
        settings: AppSettings? = nil,
        loginItem: FakeLoginItem = FakeLoginItem()
    ) throws {
        directory = try makeTempDirectory()
        if let settings {
            try SettingsStore(directory: directory).save(settings)
        } else if !items.isEmpty || mode != .sequential {
            try SettingsStore(directory: directory).save(AppSettings(items: items, mode: mode))
        }
        self.system = system
        self.loginItem = loginItem
        model = AppModel(
            settingsStore: SettingsStore(directory: directory),
            stateStore: StateStore(directory: directory),
            helper: system,
            reader: system,
            loginItem: loginItem
        )
    }

    var savedSettings: AppSettings { SettingsStore(directory: directory).load() }
    var savedState: RotationState { StateStore(directory: directory).load() }
}
