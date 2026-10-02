import Foundation
import Testing
@testable import LockRotateSystem

struct ProcessRunnerTests {
    let runner = ProcessRunner()

    @Test func capturesStdout() async throws {
        let r = try await runner.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["hello", "world"], stdin: nil, timeout: 10)
        #expect(r == CommandResult(exitCode: 0, stdout: "hello world\n", stderr: ""))
    }

    @Test func echoesStdin() async throws {
        let r = try await runner.run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], stdin: Data("你好\nline2".utf8), timeout: 10)
        #expect(r.exitCode == 0)
        #expect(r.stdout == "你好\nline2")
    }

    @Test func largeStdinAndStdoutDoNotDeadlock() async throws {
        let big = Data(repeating: UInt8(ascii: "a"), count: 4 * 1024 * 1024)
        let r = try await runner.run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], stdin: big, timeout: 20)
        #expect(r.exitCode == 0)
        #expect(r.stdout.utf8.count == big.count)
    }

    @Test func nonZeroExitAndStderrAreReturnedNotThrown() async throws {
        let r = try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo oops >&2; exit 7"], stdin: nil, timeout: 10)
        #expect(r.exitCode == 7)
        #expect(r.stderr == "oops\n")
        #expect(r.stdout.isEmpty)
    }

    @Test func childThatIgnoresStdinStillFinishes() async throws {
        let big = Data(repeating: 0x41, count: 2 * 1024 * 1024)
        let r = try await runner.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["hi"], stdin: big, timeout: 10)
        #expect(r.exitCode == 0)
        #expect(r.stdout == "hi\n")
    }

    @Test func timeoutTerminatesTheProcess() async throws {
        let start = Date()
        await #expect(throws: SystemError.timedOut) {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], stdin: nil, timeout: 0.5)
        }
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func missingExecutableThrowsFailed() async {
        await #expect(throws: SystemError.self) {
            try await runner.run(executable: URL(fileURLWithPath: "/nonexistent/binary"), arguments: [], stdin: nil, timeout: 5)
        }
    }

    @Test func cancellationStopsTheProcess() async throws {
        let start = Date()
        let task = Task {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], stdin: nil, timeout: 60)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        _ = try? await task.value
        #expect(Date().timeIntervalSince(start) < 10)
    }
}
