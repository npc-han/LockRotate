import Foundation

public enum HelperStatus: Sendable, Equatable {
    case installed
    case notInstalled
}

public struct HelperManager: Sendable {
    private let runner: any CommandRunning
    private let userName: @Sendable () -> String
    private let fileExists: @Sendable (String) -> Bool
    private let loadResource: @Sendable (String) throws -> Data

    public init(runner: any CommandRunning = ProcessRunner()) {
        self.init(
            runner: runner,
            userName: { NSUserName() },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            loadResource: HelperManager.bundledResource
        )
    }

    init(
        runner: any CommandRunning,
        userName: @escaping @Sendable () -> String,
        fileExists: @escaping @Sendable (String) -> Bool,
        loadResource: @escaping @Sendable (String) throws -> Data
    ) {
        self.runner = runner
        self.userName = userName
        self.fileExists = fileExists
        self.loadResource = loadResource
    }

    public func status() async -> HelperStatus {
        await isInstalled() ? .installed : .notInstalled
    }

    /// Both the file and a working sudoers rule must exist; either alone is unusable.
    public func isInstalled() async -> Bool {
        guard fileExists(HelperPaths.helper) else { return false }
        let result = try? await runner.run(
            executable: HelperPaths.sudo,
            arguments: ["-n", "-l", HelperPaths.helper],
            stdin: nil,
            timeout: 10
        )
        return result?.exitCode == 0
    }

    public func setLockText(_ text: String) async throws {
        // No arguments: the sudoers rule only matches the bare path, and text stays out of argv.
        let result = try await runner.run(
            executable: HelperPaths.sudo,
            arguments: ["-n", HelperPaths.helper],
            stdin: Data(text.utf8),
            timeout: 10
        )
        switch result.exitCode {
        case 0:
            return
        case 65:
            throw SystemError.rejected(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        case 1 where result.stderr.contains("password is required") || result.stderr.contains("command not found"):
            throw SystemError.helperNotInstalled
        default:
            throw SystemError.failed(result.exitCode, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func install() async throws {
        let command = try HelperCommands.install(
            userName: userName(),
            installScript: loadResource(HelperCommands.installScriptName),
            helper: loadResource(HelperCommands.helperName)
        )
        try await runPrivileged(command)
    }

    public func uninstall(keepText: Bool = false) async throws {
        let command = try HelperCommands.uninstall(
            uninstallScript: loadResource(HelperCommands.uninstallScriptName),
            keepText: keepText
        )
        try await runPrivileged(command)
    }

    private func runPrivileged(_ shellCommand: String) async throws {
        let result = try await runner.run(
            executable: HelperPaths.osascript,
            arguments: ["-e", HelperCommands.appleScript(for: shellCommand)],
            stdin: nil,
            timeout: 120 // includes the time the user takes to type a password
        )
        guard result.exitCode != 0 else { return }
        if result.stderr.contains("-128") || result.stderr.contains("User canceled") {
            throw SystemError.userCancelled
        }
        throw SystemError.failed(result.exitCode, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func bundledResource(_ name: String) throws -> Data {
        // .copy may keep the Resources/ subdirectory depending on how the bundle is laid out.
        let url = Bundle.module.url(forResource: name, withExtension: nil)
            ?? Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources")
        guard let url, let data = try? Data(contentsOf: url) else { throw SystemError.resourceMissing(name) }
        return data
    }
}
