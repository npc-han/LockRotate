import Foundation
@testable import LockRotateSystem

struct RecordedCall: Sendable, Equatable {
    var executable: String
    var arguments: [String]
    var stdin: Data?
    var timeout: TimeInterval
}

/// Records calls and returns a canned result (or throws); never runs anything.
final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [RecordedCall] = []
    private let outcome: Result<CommandResult, SystemError>

    init(_ result: CommandResult) { outcome = .success(result) }
    init(throwing error: SystemError) { outcome = .failure(error) }

    var calls: [RecordedCall] {
        lock.withLock { _calls }
    }

    private func record(_ call: RecordedCall) {
        lock.withLock { _calls.append(call) }
    }

    func run(executable: URL, arguments: [String], stdin: Data?, timeout: TimeInterval) async throws -> CommandResult {
        record(RecordedCall(executable: executable.path, arguments: arguments, stdin: stdin, timeout: timeout))
        return try outcome.get()
    }
}

/// The scripts as they exist in the source tree, read independently of Bundle.module.
func sourceResource(_ name: String, file: StaticString = #filePath) throws -> Data {
    let root = URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("Sources/LockRotateSystem/Resources/\(name)"))
}

func makeManager(
    _ runner: FakeRunner,
    user: String = "alice",
    installed: Bool = true
) -> HelperManager {
    HelperManager(
        runner: runner,
        userName: { user },
        fileExists: { _ in installed },
        loadResource: { try sourceResource($0) }
    )
}
